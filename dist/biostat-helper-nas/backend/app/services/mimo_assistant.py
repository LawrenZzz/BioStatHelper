import json
import httpx
import logging
import re
import time
import uuid
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse
from zoneinfo import ZoneInfo

from app.core.config import settings
from app.core.project_types import (
    PROJECT_TYPE_DESCRIPTIONS,
    PROJECT_TYPE_LABELS,
    normalize_project_type,
    project_type_label,
)
from app.crud.project import (
    STANDARD_WORKFLOW,
    _parse_due_at,
    normalize_parse_result,
    parse_text_fallback,
    safe_json_loads,
)
from app.services.project_workflow import (
    build_workflow_blueprint,
    normalize_workflow_blueprint,
)
from app.services.timeline_parser import parse_text_rows, rows_to_jsonable

logger = logging.getLogger(__name__)


def _mimo_debug_context(operation: str) -> dict:
    """Return copy/paste-safe diagnostics; never include API keys or user text."""
    base_url = (settings.MIMO_API_BASE_URL or "").strip()
    return {
        "operation": operation,
        "endpoint_configured": bool(base_url),
        "endpoint_host": (urlparse(base_url).hostname if base_url else None),
        "api_key_configured": bool(settings.MIMO_API_KEY),
        "model": settings.MIMO_MODEL,
        "timeout_seconds": settings.MIMO_PROJECT_TIMEOUT_SECONDS,
    }


def _log_mimo_fallback(operation: str, reason: str, exc: Exception | None = None, **extra) -> None:
    context = {**_mimo_debug_context(operation), "fallback": True, "reason": reason, **extra}
    if exc:
        context.update({"exception_type": type(exc).__name__, "exception": str(exc)[:500]})
    logger.warning("MIMO_DEBUG %s", json.dumps(context, ensure_ascii=False, default=str))


MEMBER_TYPE_VALUES = {
    "sponsor": "sponsor",
    "申办方": "sponsor",
    "申办单位": "sponsor",
    "sponsor team": "sponsor",
    "statistical_partner": "statistical_partner",
    "statistical partner": "statistical_partner",
    "合作统计方": "statistical_partner",
    "外部统计": "statistical_partner",
    "internal": "internal",
    "internal team": "internal",
    "内部团队": "internal",
    "统计团队": "internal",
    "other": "other",
    "其他": "other",
}


def _normalize_member_type(value) -> str:
    key = str(value or "").strip().lower().replace("：", "")
    if key in MEMBER_TYPE_VALUES:
        return MEMBER_TYPE_VALUES[key]
    # MiMo may add a short qualifier such as "合作统计方/CRO" or return the
    # Chinese label with surrounding punctuation. Preserve the intended group
    # instead of silently placing it in "other".
    if any(token in key for token in ("合作统计", "外部统计", "cro", "statistical partner")):
        return "statistical_partner"
    if any(token in key for token in ("申办", "sponsor")):
        return "sponsor"
    if any(token in key for token in ("内部", "统计团队", "internal")):
        return "internal"
    return "other"


def _normalize_member(item: dict, source_text: str = "") -> dict | None:
    if not isinstance(item, dict):
        return None
    name = str(item.get("name") or item.get("person") or item.get("姓名") or "").strip()
    organization = str(
        item.get("organization") or item.get("company") or item.get("组织") or item.get("公司") or ""
    ).strip() or None
    role = str(item.get("role") or item.get("position") or item.get("职责") or "").strip() or None
    if not name and organization:
        name = organization
        organization = None
    if not name:
        return None
    return {
        "member_type": _normalize_member_type(item.get("member_type") or item.get("type")),
        "name": name[:200],
        "organization": organization[:300] if organization else None,
        "role": role[:200] if role else None,
        "email": str(item.get("email") or "").strip()[:200] or None,
        "phone": str(item.get("phone") or "").strip()[:80] or None,
        "notes": str(item.get("notes") or "").strip()[:2000] or None,
        "source_text": source_text[:12000] if source_text else None,
    }


def parse_project_members_fallback(text: str) -> list[dict]:
    members = []
    # Each labeled clause may contain multiple people separated by comma or
    # semicolon. We preserve the clause as notes when its structure is fuzzy.
    pattern = re.compile(
        r"(申办方|申办单位|sponsor|合作统计方|外部统计|内部团队|统计团队|其他)\s*[:：]?\s*"
        r"(.+?)(?=(?:申办方|申办单位|sponsor|合作统计方|外部统计|内部团队|统计团队|其他)\s*[:：]?|$)",
        re.I,
    )
    matches = list(pattern.finditer(text))
    if not matches:
        matches = [re.match(r"(.+)", text)] if text.strip() else []
    for match in matches:
        if not match:
            continue
        label = match.group(1) if match.lastindex and match.lastindex >= 2 else "其他"
        value = match.group(2) if match.lastindex and match.lastindex >= 2 else match.group(1)
        member_type = _normalize_member_type(label)
        for part in re.split(r"[,，;；\n]+", value):
            part = part.strip(" \t-—")
            if not part:
                continue
            email = re.search(r"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}", part)
            phone = re.search(r"(?:1[3-9]\d{9}|\+?\d[\d -]{7,})", part)
            role_match = re.search(r"[（(]([^()（）]+)[）)]$", part)
            role = role_match.group(1).strip() if role_match else None
            person = re.sub(r"[（(][^()（）]+[）)]$", "", part).strip()
            organization = None
            org_match = re.match(r"(.+?)(?:[-—/]|\s+)([^-—/\s]+)$", person)
            if org_match and any(token in org_match.group(1) for token in ("公司", "中心", "医院", "大学", "研究所", "团队")):
                organization, person = org_match.groups()
            normalized = _normalize_member({
                "member_type": member_type,
                "name": person,
                "organization": organization,
                "role": role,
                "email": email.group(0) if email else None,
                "phone": phone.group(0) if phone else None,
                "notes": part,
            }, text)
            if normalized:
                members.append(normalized)
    return members


async def parse_project_members(text: str) -> tuple[list[dict], str, bool, dict | None]:
    endpoint = _endpoint()
    fallback = parse_project_members_fallback(text)
    if not endpoint or not settings.MIMO_API_KEY:
        return fallback, "local-rule", True, None
    prompt = """
你是临床试验项目管理助手。请从输入中提取项目成员，按以下四类归类：
sponsor=申办方，statistical_partner=合作统计方，internal=内部团队，other=其他。
每个人或团队一条记录。不要编造人员；组织名称可单独作为name。只返回JSON：
{"members":[{"member_type":"sponsor|statistical_partner|internal|other","name":"姓名或团队","organization":"组织或null","role":"职责或null","email":"邮箱或null","phone":"电话或null","notes":"备注或null"}]}
""".strip()
    payload = {
        "model": settings.MIMO_MODEL,
        "messages": [{"role": "system", "content": prompt}, {"role": "user", "content": text}],
        "temperature": 0.1,
        "response_format": {"type": "json_object"},
    }
    headers = {"Authorization": f"Bearer {settings.MIMO_API_KEY}", "Content-Type": "application/json"}
    try:
        async with httpx.AsyncClient(timeout=settings.MIMO_PROJECT_TIMEOUT_SECONDS) as client:
            response = await client.post(endpoint, json=payload, headers=headers)
            if response.status_code == 400:
                retry_payload = dict(payload)
                retry_payload.pop("response_format", None)
                response = await client.post(endpoint, json=retry_payload, headers=headers)
            response.raise_for_status()
            data = response.json()
        parsed = safe_json_loads(data["choices"][0]["message"]["content"]) or {}
        members = [item for item in (_normalize_member(value, text) for value in parsed.get("members", [])) if item]
        return members or fallback, settings.MIMO_MODEL, not bool(members), data
    except Exception as exc:
        logger.warning("MiMo member parsing failed; using local fallback: %s", exc)
        return fallback, "local-rule", True, None


def _normalize_timeline_item(item: dict, index: int) -> dict | None:
    if not isinstance(item, dict):
        return None
    title = str(item.get("title") or item.get("task") or item.get("name") or "").strip()
    if not title:
        return None
    from app.services.timeline_parser import parse_datetime

    target_type = str(item.get("target_type") or "none").strip().lower()
    if target_type not in {"none", "todo", "checklist"}:
        target_type = "none"
    try:
        matched_todo_id = int(item["matched_todo_id"]) if item.get("matched_todo_id") is not None else None
    except (TypeError, ValueError):
        matched_todo_id = None
    try:
        matched_checklist_item_id = (
            int(item["matched_checklist_item_id"])
            if item.get("matched_checklist_item_id") is not None
            else None
        )
    except (TypeError, ValueError):
        matched_checklist_item_id = None

    try:
        row_number = int(item.get("row_number") or index)
    except (TypeError, ValueError):
        row_number = index
    try:
        confidence = float(item["confidence"]) if item.get("confidence") is not None else None
    except (TypeError, ValueError):
        confidence = None

    return {
        "row_number": row_number,
        "external_id": str(item.get("external_id") or item.get("id") or "").strip() or None,
        "title": title[:300],
        "description": str(item.get("description") or item.get("detail") or "").strip()[:2000] or None,
        "phase": str(item.get("phase") or item.get("stage") or "").strip()[:100] or None,
        "start_at": parse_datetime(item.get("start_at") or item.get("start") or item.get("开始日期")),
        "due_at": parse_datetime(item.get("due_at") or item.get("end_at") or item.get("due") or item.get("结束日期")) or parse_datetime(item.get("start_at") or item.get("start") or item.get("开始日期")),
        "status": str(item.get("status") or "").strip()[:30] or None,
        "target_type": target_type,
        "matched_todo_id": matched_todo_id,
        "matched_checklist_item_id": matched_checklist_item_id,
        "confidence": confidence,
        "warning": str(item.get("warning") or "").strip()[:1000] or None,
    }


def timeline_fallback(rows: list[dict]) -> list[dict]:
    return [item for item in (_normalize_timeline_item(row, index) for index, row in enumerate(rows, start=1)) if item]


async def parse_timeline_rows(
    rows: list[dict],
    context: dict | None = None,
) -> tuple[list[dict], str, bool, dict | None]:
    fallback = timeline_fallback(rows)
    endpoint = _endpoint()
    if not endpoint or not settings.MIMO_API_KEY:
        return fallback, "local-rule", True, None
    prompt = """
你是临床试验项目计划管理助手。把表格或文本行转换成项目时间线事项，并尽量匹配现有项目任务。
下面的项目上下文包含真实存在的阶段、待办和清单及其ID。匹配时只能使用上下文中的ID：
- 先按事项标题、原始编号、阶段和描述匹配；精确或明确同义匹配才绑定。
- 任务绑定填写 target_type=todo 和 matched_todo_id；清单绑定填写 target_type=checklist 和 matched_checklist_item_id。
- 不确定时填写 target_type=none，不要猜测ID；应用会保留记录并允许人工绑定。
保留每一行一个事项，不要编造日期；日期必须是带+08:00的ISO 8601格式。只有一个日期的里程碑可将start_at和due_at设为同一天。
只返回JSON：
{"items":[{"row_number":1,"external_id":"编号或null","title":"对应项目待办或清单标题","description":"说明或null","phase":"流程阶段或null","start_at":"ISO或null","due_at":"ISO或null","status":"状态或null","target_type":"none|todo|checklist","matched_todo_id":null,"matched_checklist_item_id":null,"confidence":0.0}]}
""".strip()
    project_context = context or {"phases": [], "todos": []}
    payload = {
        "model": settings.MIMO_MODEL,
        "messages": [
            {"role": "system", "content": prompt},
            {
                "role": "user",
                "content": json.dumps(
                    {
                        "project_context": project_context,
                        "timeline_rows": rows_to_jsonable(rows[:300]),
                    },
                    ensure_ascii=False,
                    default=str,
                ),
            },
        ],
        "temperature": 0.1,
        "response_format": {"type": "json_object"},
    }
    headers = {"Authorization": f"Bearer {settings.MIMO_API_KEY}", "Content-Type": "application/json"}
    try:
        async with httpx.AsyncClient(timeout=settings.MIMO_PROJECT_TIMEOUT_SECONDS) as client:
            response = await client.post(endpoint, json=payload, headers=headers)
            if response.status_code == 400:
                retry_payload = dict(payload)
                retry_payload.pop("response_format", None)
                response = await client.post(endpoint, json=retry_payload, headers=headers)
            response.raise_for_status()
            data = response.json()
        parsed = safe_json_loads(data["choices"][0]["message"]["content"]) or {}
        normalized = [item for item in (_normalize_timeline_item(value, index) for index, value in enumerate(parsed.get("items", []), start=1)) if item]
        # Keep rows the model omitted. This prevents a partial AI response from
        # silently losing spreadsheet activities.
        if len(normalized) < len(fallback):
            by_row = {item["row_number"]: item for item in normalized}
            normalized.extend(item for item in fallback if item["row_number"] not in by_row)
            normalized.sort(key=lambda item: item["row_number"])
        return normalized, settings.MIMO_MODEL, False, data
    except Exception as exc:
        logger.warning("MiMo timeline parsing failed; using local fallback: %s", exc)
        return fallback, "local-rule", True, None


SYSTEM_PROMPT_TEMPLATE = """
你是生物统计师和统计程序员项目助手。请把用户输入判断为以下两类之一：
1. meeting：用户粘贴了会议通知、会议链接、会议纪要或需要生成会议记录。
2. todo：用户表达了某个时间需要做某事，需要生成项目待办。

当前时间：{now_iso}
当前日期：{today}
时区：Asia/Shanghai，所有解析出的时间都请返回带 +08:00 时区的 ISO 8601。

时间解析要求：
- 识别中文自然语言时间，例如：今天、明天、后天、本周五、下周三、7月12日、2026/7/12、下午3点、晚上8点、9:30-10:30。
- 如果会议内容包含时间段，请填 starts_at 和 ends_at；如果只有开始时间，ends_at 可以按会议默认1小时推断。
- 如果待办只给了日期没有具体时间，due_at 设为当天 23:59:00+08:00。
- 如果没有年份，按当前日期推断最近的未来日期。
- 如果用户输入“XX时间需要做XX事情”，intent 应为 todo，并把XX时间写入 due_at。
- 如果用户输入包含开始日期/开始时间，例如“从周一开始，下周五前完成”，请把开始时间写入 start_at，截止时间写入 due_at。

只返回JSON，不要Markdown，不要解释。格式：
{
  "intent": "meeting" 或 "todo",
  "meetings": [
    {
      "title": "会议标题",
      "agenda": "会议议程或原文摘要",
      "meeting_url": "可跳转链接或null",
      "location": "地点或null",
      "starts_at": "ISO 8601时间或null",
      "ends_at": "ISO 8601时间或null",
      "attendees": "参会人或null",
      "notes": "备注或null"
    }
  ],
  "todos": [
      {
       "title": "待办标题",
       "description": "待办说明",
       "todo_type": "extra",
       "phase": "所属阶段或null",
       "status": "open",
       "priority": "low|normal|high|urgent",
       "start_at": "ISO 8601时间或null",
       "due_at": "ISO 8601时间或null"
      }
  ]
}
""".strip()

PROJECT_AGENT_SYSTEM_PROMPT = """
你是生物统计项目工作台 Agent。你只能根据当前项目上下文提出结构化更新，不要编造当前项目不存在的待办、清单或阶段 ID。
用户会用自然语言告诉你项目已经完成了什么、接下来要做什么、什么时候做，或粘贴会议通知。

你的工作：
1. 从 completed_todo_ids / completed_checklist_item_ids 标记用户明确表示已完成的已有事项。
2. 判断当前进行到哪个阶段，填 current_phase。只有上下文中已有阶段名才能使用。
3. 将新待办放进最合适的已有阶段；如果确实需要新阶段才创建一个新阶段名。新待办使用 action=create，已有待办调整使用 action=update。
4. 用户说“接下来/目前/正在做”时，将相应已有待办设为 in_progress；不要把未明确完成的事项标记 done。
5. 会议必须创建或更新，并可用 todo_id、todo_ref 或 checklist_item_id 绑定到当前项目内的事项。
6. 识别开始时间、截止时间和会议时间段。会议是 starts_at/ends_at 时间段，待办是 start_at/due_at 截止时间。
7. 如果信息不足以安全判断已有事项，优先创建一个清晰的新待办；只有无法判断标题或目标时才填写 clarification。

只返回 JSON，不要 Markdown，不要解释。格式：
{
  "intent": "update|create_todo|complete|meeting|mixed",
  "summary": "一句话说明本次将做什么",
  "clarification": null,
  "current_phase": "上下文中的阶段名或null",
  "completed_todo_ids": [],
  "completed_checklist_item_ids": [],
  "todos": [
    {
      "ref": "todo-1",
      "id": null,
      "action": "create|update",
      "title": "待办标题",
      "description": "说明或null",
      "todo_type": "standard|extra|meeting",
      "phase": "阶段名或null",
      "status": "open|in_progress|done|blocked|cancelled",
      "priority": "low|normal|high|urgent",
      "start_at": "带+08:00的ISO时间或null",
      "due_at": "带+08:00的ISO时间或null",
      "checklist_items": [{"id": null, "title": "清单项", "is_done": false, "due_at": null}]
    }
  ],
  "meetings": [
    {
      "ref": "meeting-1",
      "id": null,
      "action": "create|update",
      "title": "会议标题",
      "agenda": "议程或null",
      "meeting_url": "链接或null",
      "location": "地点或null",
      "starts_at": "带+08:00的ISO时间或null",
      "ends_at": "带+08:00的ISO时间或null",
      "attendees": "参会人或null",
      "notes": "备注或null",
      "todo_id": null,
      "todo_ref": "todo-1或null",
      "checklist_item_id": null
    }
  ]
}
""".strip()

PROJECT_INTAKE_SYSTEM_PROMPT = """
你是生物统计项目建档助手。用户会粘贴一段项目介绍、会议纪要、邮件或当前进展。
请从中提取项目基本信息，并判断当前临床试验/生物统计项目进度。

可用标准阶段（current_phase 尽量使用以下名称）：
项目启动、SAP与TFL、数据管理DM、CDISC与数据集、分析数据集与编程、统计编程与输出、盲态审阅、锁库与揭盲、SAR统计分析报告、CSR与提交。

项目主类型只能返回以下代码之一：
{project_type_descriptions}

规则：
1. 只根据输入内容判断，不确定的字段返回null，不要编造申办方、方案编号或日期。
2. 明确说“已完成/完成/已定稿/已关闭”的事项放入 completed_todo_titles；明确“正在/目前/进行中”的事项放入 in_progress_todo_titles。
   当输入提供了充分的流程证据时，可以把当前事项之前必然已经完成的标准流程事项标为已完成。例如“SAP已提交审核”表示项目启动及方案审阅已经完成，SAP起草/审阅仍在进行；不要把当前事项或后续事项提前标为完成。
3. 用户明确提出但尚未完成的事情放入 todos，并给出最合适的阶段。没有明确截止日期时 due_at 返回null。
4. 已有标准流程可以承载的事项，优先使用标准阶段和标准流程标题；确实不是标准流程的才作为 extra 待办。
   completed_todo_titles 和 in_progress_todo_titles 中，如果事项对应标准流程，必须原样使用下面清单中的标准待办标题：
{standard_todo_titles}
5. SAP与TFL是同一个协同阶段：撰写、审阅、定稿都一起推进；可在事项或清单中分别描述SAP与TFL，不要拆成两个流程阶段。
6. project_type 根据研究对象或研究场景返回上述主类型代码；肿瘤、心血管等是适应症/治疗领域，不是主类型。
7. is_cdisc 仅在文本明确提到CDISC、SDTM、ADaM、define.xml或明确说是/不是CDISC项目时判断；没有证据返回null。
8. indication 只填写疾病/适应症，不要把项目类型、临床分期或CDISC状态混入。
9. current_phase 是当前正在进行或最后明确完成的阶段；没有证据时返回null。
10. 项目名称应简短清晰；description 保留项目背景、设计、样本量、主要终点等有价值信息，但不要重复整段原文。
11. 所有日期时间返回带 +08:00 的 ISO 8601；没有日期不要猜日期。
12. 识别项目成员时只按 sponsor（申办方）、statistical_partner（合作统计方）、internal（内部团队）、other（其他）四类归类；不要编造人员。

只返回JSON，不要Markdown，不要解释：
{
  "name": "项目名称",
  "sponsor": "申办方或null",
  "protocol_no": "方案编号或null",
  "phase": "分期或null",
  "project_type": "项目主类型代码",
  "is_cdisc": true或false或null,
  "indication": "适应症或null",
  "description": "项目摘要或null",
  "status": "active|completed",
  "current_phase": "标准阶段名或null",
  "completed_todo_titles": ["已完成事项"],
  "in_progress_todo_titles": ["正在进行事项"],
  "members": [
    {"member_type":"sponsor|statistical_partner|internal|other","name":"姓名或团队","organization":"组织或null","role":"职责或null","email":"邮箱或null","phone":"电话或null","notes":"备注或null"}
  ],
  "todos": [
    {
      "title": "待办标题",
      "description": "说明或null",
      "todo_type": "standard|extra|meeting",
      "phase": "标准阶段名或null",
      "status": "open|in_progress|done|blocked|cancelled",
      "priority": "low|normal|high|urgent",
      "start_at": "ISO时间或null",
      "due_at": "ISO时间或null"
    }
  ]
}
""".strip()


def _project_intake_system_prompt() -> str:
    titles = "\n".join(f"- {title}" for _, title in STANDARD_WORKFLOW)
    type_descriptions = "\n".join(
        f"- {code}: {PROJECT_TYPE_LABELS[code]}；{description}"
        for code, description in PROJECT_TYPE_DESCRIPTIONS.items()
    )
    return (
        PROJECT_INTAKE_SYSTEM_PROMPT
        .replace("{standard_todo_titles}", titles)
        .replace("{project_type_descriptions}", type_descriptions)
    )

VIDEO_SYSTEM_PROMPT = """
你是生物统计课程视频资料管理员，熟悉临床试验、生物统计、DM数据管理、CDISC、SAS程序和统计编程课程。
请根据NAS视频的相对路径、文件名、已有分类和已有元数据，整理课程视频信息。

只返回JSON，不要Markdown，不要解释。格式：
{
  "category_path": "建议分类路径，使用/分隔，可多层级，例如 生物统计/生存分析 或 SAS程序/宏",
  "course_name": "课程名称",
  "course_title": "课程完整标题",
  "lesson_title": "本集标题",
  "title": "App列表显示标题，通常为 第01集 xxx 或 lesson_title",
  "episode_number": 1,
  "sort_order": 1,
  "instructor": null,
  "tags": "逗号分隔标签",
  "description": "一两句话说明本集内容"
}

要求：
- 如果文件名或标题中有数字，把它作为episode_number和sort_order。
- 需要识别两种目录情况：
  1. 单集资源包文件夹：一个文件夹里通常只有一个视频，同时有.ass/.srt/.vtt/.xml弹幕字幕或同名资源文件。这时该文件夹多半是本集标题/资源包，不应作为课程分类末级；category_path应使用它的父层级，lesson_title可使用该单集文件夹名或视频标题。
  2. 课程多层目录：如果文件夹下有多个视频或明显是章节/模块目录，应保留为课程子分类，例如 生物统计/实验设计/样本量。
- payload.file_context 中的 standalone_video_folder、sidecar_files、sibling_video_count、suggested_category_path 可作为判断依据。standalone_video_folder=true 时优先使用 suggested_category_path 作为分类。
- 需要识别文档目录式编号：如 1、1.1、1.1.1、2.3.4。通常最高层和中间层是课程章节分类，最末层是本集视频。若 1.1.1 文件名为“1.1.1 Cox比例风险模型”，则 category_path 应包含课程/1 .../1.1 ...，lesson_title 为“Cox比例风险模型”，episode_number 可取末级编号1，sort_order 使用 payload.file_context.outline_sort_order。
- 编号不一定在文件名开头。若文件名是“平台前缀 1.1.1 Cox比例风险模型 1080p”，请忽略平台前缀和清晰度，按 1.1.1 识别层级。
- category_path 只写到本集的父级章节，不要把 1.1.1 这一集本身追加为分类末级；1.1.1 的标题放在 lesson_title/title。例如“课程/1 生存分析/1.1 Cox模型/1.1.1 PH假设检验”是错的，应为“课程/1 生存分析/1.1 Cox模型”。
- 如果某层只有编号没有标题，请优先参考 payload.file_context.outline_ancestor_context 中每个层级的 sample_titles/sample_files/direct_child_titles，为该层概括一个合适的中文章节名；其次参考 outline_siblings；无法判断时才使用“第1章”“第1.1节”这类稳定名称。
- 如果 payload.file_context.outline_sort_order 存在，sort_order 使用这个整数；不要返回“1.1.1”这类带点字符串。
- 去除无意义前缀，例如编号、EP、P、课时、音视频、视频、课程视频、【已下载】、清晰度、平台水印等，不要把这些写入 lesson_title。
- category_path优先沿用课程/章节文件夹层级，但可把杂乱文件夹名归并为清晰课程分类。
- 不要编造讲师；不确定时返回null。
- 字段不知道时返回null，不要返回空字符串。
""".strip()

NOISE_LEADING_PREFIX_WORDS = sorted(
    [
        "课程音视频",
        "课程视频",
        "课件视频",
        "课堂视频",
        "直播回放",
        "音视频",
        "视频",
        "音频",
        "录屏",
        "回放",
        "正课",
        "主课",
        "课件",
        "讲义",
        "资料",
        "素材",
        "附件",
    ],
    key=len,
    reverse=True,
)

NOISE_LEADING_PREFIX_RE = re.compile(
    rf"^\s*(?:[（(【\[]\s*)?(?:{'|'.join(re.escape(word) for word in NOISE_LEADING_PREFIX_WORDS)})(?:\s*[）)】\]])?\s*(?:[\s.、:：/\\|_-])*(?=(?:\d|第|EP\b|P\b|Part\b|Lesson\b|Lecture\b|$))",
    re.IGNORECASE,
)


def _endpoint() -> str:
    base = (settings.MIMO_API_BASE_URL or "").rstrip("/")
    if not base:
        return ""
    if base.endswith("/chat/completions"):
        return base
    return f"{base}/chat/completions"


def _project_system_prompt() -> str:
    now = datetime.now(ZoneInfo("Asia/Shanghai"))
    weekday_names = ["星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"]
    return (
        SYSTEM_PROMPT_TEMPLATE
        .replace("{now_iso}", now.isoformat(timespec="seconds"))
        .replace("{today}", f"{now.date().isoformat()} {weekday_names[now.weekday()]}")
    )


def _extract_episode_number(text: str) -> int | None:
    outline = _extract_outline_code(text)
    if outline:
        try:
            return int(outline.split(".")[-1])
        except ValueError:
            pass
    clean_text = _strip_noise_tokens(text)
    patterns = [
        r"(?:第\s*)?(\d{1,4})(?:\s*[集讲课节])",
        r"(?:EP|Ep|ep|P|p)\s*0*(\d{1,4})",
    ]
    for pattern in patterns:
        match = re.search(pattern, clean_text or "")
        if match:
            try:
                return int(match.group(1))
            except ValueError:
                return None
    for match in re.finditer(r"(?<![\d.])0*(\d{1,4})(?![\d.])", clean_text or ""):
        try:
            number = int(match.group(1))
        except ValueError:
            continue
        if number not in {4, 720, 1080, 2160}:
            return number
    return None


def _strip_noise_tokens(text: str) -> str:
    value = Path(text or "").stem
    value = value.replace("_", " ").replace("-", " ").strip()
    value = re.sub(r"【[^】]*(?:已下载|高清|超清|字幕|弹幕|水印|1080|720|4k)[^】]*】", " ", value, flags=re.IGNORECASE)
    value = re.sub(r"\[[^\]]*(?:已下载|高清|超清|字幕|弹幕|水印|1080|720|4k)[^\]]*\]", " ", value, flags=re.IGNORECASE)
    value = re.sub(r"(?i)\b(?:1080p?|720p?|4k|x264|h264|h265|hevc|aac)\b", " ", value)
    value = re.sub(r"\s+", " ", value)
    for _ in range(5):
        clean_value = NOISE_LEADING_PREFIX_RE.sub("", value).strip()
        if clean_value == value:
            break
        value = clean_value
    return value.strip(" .、_-")


def _extract_outline_code(text: str) -> str | None:
    value = _strip_noise_tokens(text)
    match = re.search(r"(?<![\d.])(\d+(?:\.\d+){1,5})(?![\d.])", value)
    if match:
        return match.group(1)
    match = re.match(r"^\s*(\d{1,4})(?!\.\d)(?:[\s\.、:：_-]+|$)", value)
    if match and match.group(1) not in {"720", "1080", "2160"}:
        return match.group(1)
    return None


def _clean_title(text: str) -> str:
    value = _strip_noise_tokens(text)
    outline_match = re.search(r"(?<![\d.])\d+(?:\.\d+){1,5}(?![\d.])", value)
    if outline_match:
        tail = value[outline_match.end():].strip(" .、:：_-")
        head = value[:outline_match.start()].strip(" .、:：_-")
        value = tail or head or value
    value = re.sub(r"^\s*\d+(?:\.\d+){0,5}[\s\.、_-]*", "", value)
    value = re.sub(r"^\s*(?:EP|Ep|ep|P|p|课时|第\s*\d+\s*[集讲课节])\s*\d*[\s\.、_-]*", "", value)
    value = re.sub(r"\s+", " ", value)
    return value.strip() or Path(text or "").stem.strip()


def _normalize_video_suggestion(raw: dict, payload: dict) -> dict:
    relative_path = payload.get("relative_path") or ""
    file_name = payload.get("file_name") or relative_path
    file_context = payload.get("file_context") or {}
    folder_parts = [part for part in relative_path.split("/")[:-1] if part]
    folder_path = file_context.get("suggested_category_path") or "/".join(folder_parts) or "未分类"
    title = _clean_title(file_name)
    outline_code = file_context.get("outline_code") or _extract_outline_code(file_name)
    outline_episode = None
    if outline_code:
        try:
            outline_episode = int(str(outline_code).split(".")[-1])
        except ValueError:
            outline_episode = None
    episode_number = raw.get("episode_number") or outline_episode or _extract_episode_number(file_name) or _extract_episode_number(title)

    def clean(value):
        if value is None:
            return None
        value = str(value).strip()
        return value or None

    def as_int(value):
        if value in (None, ""):
            return None
        if isinstance(value, str) and re.fullmatch(r"\d+(?:\.\d+)+", value.strip()):
            value = value.strip().split(".")[-1]
        try:
            return int(value)
        except (TypeError, ValueError):
            return None

    def strip_leaf_from_category_path(value, lesson):
        value = clean(value)
        if not value:
            return value
        parts = [part.strip() for part in value.split("/") if part.strip()]
        if not parts:
            return None
        last = parts[-1]
        leaf_code = clean(file_context.get("outline_code")) or outline_code
        leaf_title = clean(file_context.get("outline_leaf_title")) or clean(file_context.get("clean_lesson_title")) or clean(lesson)
        looks_like_leaf = False
        if leaf_code and (last == leaf_code or last.startswith(f"{leaf_code} ") or last.startswith(f"{leaf_code}.") or last.startswith(f"{leaf_code}、")):
            looks_like_leaf = True
        if leaf_title and leaf_title in last and (leaf_code or last == leaf_title):
            looks_like_leaf = True
        if not looks_like_leaf:
            return value
        parent = "/".join(parts[:-1])
        return parent or suggested_category_path or "未分类"

    suggested_category_path = clean(file_context.get("suggested_category_path"))
    category_path = clean(raw.get("category_path")) or clean(payload.get("category_path")) or folder_path
    if file_context.get("standalone_video_folder") and suggested_category_path:
        lesson_folder = clean(file_context.get("lesson_folder_name"))
        if category_path == lesson_folder or category_path.endswith(f"/{lesson_folder}"):
            category_path = suggested_category_path
    course_name = clean(raw.get("course_name")) or clean(file_context.get("course_name")) or (folder_parts[0] if folder_parts else None)
    lesson_title = clean(raw.get("lesson_title")) or clean(file_context.get("clean_lesson_title")) or clean(file_context.get("outline_leaf_title")) or clean(file_context.get("lesson_folder_name")) or title
    category_path = strip_leaf_from_category_path(category_path, lesson_title)
    sort_order_value = file_context.get("outline_sort_order") if outline_code else None
    sort_order_value = sort_order_value or raw.get("sort_order") or episode_number

    return {
        "category_path": category_path,
        "course_name": course_name,
        "course_title": clean(raw.get("course_title")) or course_name,
        "lesson_title": lesson_title,
        "title": clean(raw.get("title")) or lesson_title,
        "episode_number": as_int(episode_number),
        "sort_order": as_int(sort_order_value) or 0,
        "instructor": clean(raw.get("instructor")),
        "tags": clean(raw.get("tags")),
        "description": clean(raw.get("description")),
    }


def parse_video_metadata_fallback(payload: dict) -> dict:
    relative_path = payload.get("relative_path") or ""
    file_name = payload.get("file_name") or relative_path
    file_context = payload.get("file_context") or {}
    folder_parts = [part for part in relative_path.split("/")[:-1] if part]
    title = _clean_title(file_name)
    outline_code = file_context.get("outline_code") or _extract_outline_code(file_name)
    outline_episode = None
    if outline_code:
        try:
            outline_episode = int(str(outline_code).split(".")[-1])
        except ValueError:
            outline_episode = None
    episode_number = outline_episode or _extract_episode_number(file_name) or _extract_episode_number(title)
    category_path = file_context.get("suggested_category_path") or ("/".join(folder_parts) if folder_parts else "未分类")
    course_name = file_context.get("course_name") or (folder_parts[0] if folder_parts else None)
    lesson_title = file_context.get("clean_lesson_title") or file_context.get("outline_leaf_title") or file_context.get("lesson_folder_name") or title
    tags = []
    lowered = f"{relative_path} {title}".lower()
    for keyword in ["SAS", "CDISC", "ADaM", "SDTM", "TFL", "DM", "生存分析", "临床试验", "样本量", "统计编程"]:
        if keyword.lower() in lowered:
            tags.append(keyword)

    return _normalize_video_suggestion(
        {
            "category_path": category_path,
            "course_name": course_name,
            "course_title": course_name,
            "lesson_title": lesson_title,
            "title": lesson_title,
            "episode_number": episode_number,
            "sort_order": file_context.get("outline_sort_order") or episode_number or 0,
            "tags": ", ".join(dict.fromkeys(tags)) if tags else None,
            "description": f"来自NAS课程目录：{category_path}" if category_path else None,
        },
        payload,
    )


async def organize_video_metadata(payload: dict, category_paths: list[str] | None = None) -> tuple[dict, str, bool, dict | None]:
    endpoint = _endpoint()
    if not endpoint or not settings.MIMO_API_KEY:
        return parse_video_metadata_fallback(payload), "local-rule", True, None

    user_content = {
        "video": payload,
        "existing_category_paths": category_paths or [],
    }
    request_payload = {
        "model": settings.MIMO_MODEL,
        "messages": [
            {"role": "system", "content": VIDEO_SYSTEM_PROMPT},
            {"role": "user", "content": str(user_content)},
        ],
        "temperature": 0.1,
        "response_format": {"type": "json_object"},
    }
    headers = {
        "Authorization": f"Bearer {settings.MIMO_API_KEY}",
        "Content-Type": "application/json",
    }

    try:
        async with httpx.AsyncClient(timeout=settings.MIMO_TIMEOUT_SECONDS) as client:
            response = await client.post(endpoint, json=request_payload, headers=headers)
            response.raise_for_status()
            data = response.json()
        content = data["choices"][0]["message"]["content"]
        parsed = safe_json_loads(content)
        if not parsed:
            raise ValueError("MiMo返回内容不是可解析JSON")
        return _normalize_video_suggestion(parsed, payload), settings.MIMO_MODEL, False, data
    except Exception as exc:
        fallback = parse_video_metadata_fallback(payload)
        fallback["error"] = str(exc)
        return fallback, "local-rule", True, None


async def parse_project_text(text: str) -> tuple[dict, str, bool, dict | None]:
    endpoint = _endpoint()
    if not endpoint or not settings.MIMO_API_KEY:
        fallback = parse_text_fallback(text)
        return fallback, "local-rule", True, None

    payload = {
        "model": settings.MIMO_MODEL,
        "messages": [
            {"role": "system", "content": _project_system_prompt()},
            {"role": "user", "content": text},
        ],
        "temperature": 0.1,
        "response_format": {"type": "json_object"},
    }
    headers = {
        "Authorization": f"Bearer {settings.MIMO_API_KEY}",
        "Content-Type": "application/json",
    }
    try:
        async with httpx.AsyncClient(timeout=settings.MIMO_TIMEOUT_SECONDS) as client:
            response = await client.post(endpoint, json=payload, headers=headers)
            response.raise_for_status()
            data = response.json()
        content = data["choices"][0]["message"]["content"]
        parsed = safe_json_loads(content)
        if not parsed:
            raise ValueError("MiMo返回内容不是可解析JSON")
        return normalize_parse_result(parsed, text), settings.MIMO_MODEL, False, data
    except Exception as exc:
        fallback = parse_text_fallback(text)
        fallback["error"] = str(exc)
        return fallback, "local-rule", True, None


def _normalize_project_intake(raw: dict, source_text: str) -> dict:
    allowed_statuses = {"active", "completed"}
    allowed_todo_statuses = {"open", "in_progress", "done", "blocked", "cancelled"}
    allowed_priorities = {"low", "normal", "high", "urgent"}
    def clean(value, limit=500):
        if value is None:
            return None
        value = str(value).strip()
        return value[:limit] or None

    def clean_datetime(value):
        if not value:
            return None
        try:
            parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        except ValueError:
            return None
        return parsed.isoformat()

    result = {
        "name": clean(raw.get("name"), 300) or "未命名项目",
        "sponsor": clean(raw.get("sponsor")),
        "protocol_no": clean(raw.get("protocol_no")),
        "phase": clean(raw.get("phase")),
        "project_type": normalize_project_type(raw.get("project_type")),
        "is_cdisc": raw.get("is_cdisc") if isinstance(raw.get("is_cdisc"), bool) else None,
        "indication": clean(raw.get("indication")),
        # Keep the project overview concise. The original intake text is kept
        # on generated task records, but must not become the project summary.
        "description": clean(raw.get("description"), 4000),
        "status": raw.get("status") if raw.get("status") in allowed_statuses else "active",
        "current_phase": clean(raw.get("current_phase"), 80),
        "completed_todo_titles": [clean(item, 300) for item in (raw.get("completed_todo_titles") or []) if clean(item, 300)],
        "in_progress_todo_titles": [clean(item, 300) for item in (raw.get("in_progress_todo_titles") or []) if clean(item, 300)],
        "todos": [],
        "members": [],
    }
    for item in raw.get("members") or []:
        member = _normalize_member(item, source_text)
        if member:
            result["members"].append(member)
    for item in raw.get("todos") or []:
        if not isinstance(item, dict) or not str(item.get("title") or "").strip():
            continue
        todo = {
            "title": str(item["title"]).strip()[:300],
            "description": clean(item.get("description"), 2000),
            "todo_type": item.get("todo_type") if item.get("todo_type") in {"standard", "extra", "meeting"} else "extra",
            "phase": clean(item.get("phase"), 80),
            "status": item.get("status") if item.get("status") in allowed_todo_statuses else "open",
            "priority": item.get("priority") if item.get("priority") in allowed_priorities else "normal",
            "start_at": clean_datetime(item.get("start_at")),
            "due_at": clean_datetime(item.get("due_at")),
            "checklist_items": [],
        }
        result["todos"].append(todo)
    return result


def _project_intake_fallback(text: str) -> dict:
    from app.crud.project import STANDARD_PHASE_ORDER, STANDARD_WORKFLOW

    lines = [line.strip(" -•\t") for line in text.splitlines() if line.strip()]
    source = " ".join(lines) if lines else text.strip()

    def clean_field(value: str | None) -> str | None:
        if not value:
            return None
        return re.sub(r"\s+", " ", value).strip(" ，,。；;\t") or None

    def labeled_field(labels: str) -> str | None:
        # Labels are deliberately terminated by punctuation or the next known
        # label, so inline text such as "申办单位甲公司，III期" is supported.
        match = re.search(
            rf"(?:{labels})\s*[:：]?\s*(.+?)(?=\s*[,，;；。\n]|\s+(?:方案编号|方案号|申办单位|申办方|sponsor|临床分期|分期|适应症|项目类型|疾病)\s*[:：]?|$)",
            source,
            re.I,
        )
        return clean_field(match.group(1)) if match else None

    first_clause = re.split(r"[,，;；。\n]", source, maxsplit=1)[0].strip()
    name_match = re.search(r"^\s*(.+?项目)(?:$|\s*(?:方案编号|方案号))", first_clause)
    name = clean_field(name_match.group(1) if name_match else first_clause)
    if not name or len(name) > 100 or any(token in name for token in ("已完成", "目前", "接下来", "申办方")):
        name = "未命名项目"

    sponsor = labeled_field(r"申办单位|申办方|sponsor")
    protocol_no = labeled_field(r"方案编号|方案号|protocol(?:\s*no\.?)?")
    phase = labeled_field(r"临床分期|分期|phase")
    if not phase:
        phase_match = re.search(r"(?<![A-Za-z0-9])((?:I{1,4}|V|VI|[1-4])期)", source, re.I)
        phase = clean_field(phase_match.group(1) if phase_match else None)

    project_type = normalize_project_type(source)
    indication = labeled_field(r"适应症|疾病|治疗领域")

    is_cdisc = None
    if re.search(r"(?:非CDISC|不是CDISC|无需CDISC|不需要CDISC)", source, re.I):
        is_cdisc = False
    elif re.search(
        r"(?:CDISC项目|是CDISC|需要CDISC|采用CDISC|SDTM|ADaM|define\.xml)",
        source,
        re.I,
    ):
        is_cdisc = True

    completed_inline = []
    for keyword in ("初步分析", "阶段性分析", "期中分析", "最终分析"):
        if keyword in source and re.search(rf"{re.escape(keyword)}[^，,。；;\n]*?(?:已完成|完成|已定稿)", source):
            completed_inline.append(keyword)

    current_phase = next((phase_name for phase_name in STANDARD_PHASE_ORDER if phase_name in source), None)
    if not current_phase and re.search(r"SAP|TFLs?|统计分析计划", source, re.I):
        current_phase = "SAP与TFL"

    completed = []
    in_progress = []
    sap_active_title = "SAP/TFL联合审阅"
    sap_progress_evidence = re.search(
        r"(?:SAP|统计分析计划)[^，,。；;\n]{0,50}(?:已提交|正在|目前|进行中|审核)",
        source,
        re.I,
    )
    if sap_progress_evidence:
        in_progress.append(sap_active_title)
        active_index = next(
            (index for index, (_, title) in enumerate(STANDARD_WORKFLOW) if title == sap_active_title),
            None,
        )
        if active_index is not None:
            completed.extend(title for _, title in STANDARD_WORKFLOW[:active_index])

    todos = []
    due_at = _parse_due_at(source)
    if re.search(r"提交\s*(?:给)?\s*申办方\s*审核|申办方\s*审核", source):
        todos.append({
            "title": "提交SAP至申办方审核",
            "description": "尚老师审核完成后，提交申办方审核。",
            "todo_type": "standard",
            "phase": "SAP与TFL",
            "status": "open",
            "priority": "high",
            "due_at": due_at.isoformat() if due_at else None,
            "checklist_items": [],
        })

    progress_parts = []
    if re.search(r"SAP[^，,。；;\n]*已提交[^，,。；;\n]*审核", source, re.I):
        progress_parts.append("SAP已提交内部审核")
    elif in_progress:
        progress_parts.append("SAP处于审阅阶段")
    if todos:
        progress_parts.append("下一步提交申办方审核")
    description_parts = []
    if sponsor:
        description_parts.append(f"申办单位：{sponsor}")
    if protocol_no:
        description_parts.append(f"方案编号：{protocol_no}")
    if phase:
        description_parts.append(f"临床分期：{phase}")
    if project_type != "other":
        description_parts.append(f"项目类型：{project_type_label(project_type)}")
    if is_cdisc is not None:
        description_parts.append(f"CDISC项目：{'是' if is_cdisc else '否'}")
    if progress_parts:
        description_parts.append("当前进度：" + "；".join(progress_parts))
    description = "；".join(description_parts) + "。" if description_parts else None

    return _normalize_project_intake({
        "name": name,
        "sponsor": sponsor,
        "protocol_no": protocol_no,
        "phase": phase,
        "project_type": project_type,
        "is_cdisc": is_cdisc,
        "indication": indication,
        "description": description,
        "current_phase": current_phase,
        "completed_todo_titles": list(dict.fromkeys([*completed, *completed_inline])),
        "in_progress_todo_titles": list(dict.fromkeys(in_progress)),
        "todos": todos,
        "members": parse_project_members_fallback(source),
    }, text)


async def parse_project_intake(text: str) -> tuple[dict, str, bool, dict | None]:
    request_id = uuid.uuid4().hex[:12]
    endpoint = _endpoint()
    if not endpoint or not settings.MIMO_API_KEY:
        _log_mimo_fallback(
            "project_intake",
            "missing_endpoint_or_api_key",
            request_id=request_id,
            endpoint_configured=bool(endpoint),
            api_key_configured=bool(settings.MIMO_API_KEY),
            input_length=len(text),
        )
        fallback = _project_intake_fallback(text)
        missing = []
        if not endpoint:
            missing.append("MIMO_API_BASE_URL")
        if not settings.MIMO_API_KEY:
            missing.append("MIMO_API_KEY")
        fallback["error"] = f"MIMO 未配置：缺少 {' 和 '.join(missing)}"
        fallback["debug_id"] = request_id
        return fallback, "local-rule", True, None
    payload = {
        "model": settings.MIMO_MODEL,
        "messages": [
            {"role": "system", "content": _project_intake_system_prompt() + "\n当前时间：" + datetime.now(ZoneInfo("Asia/Shanghai")).isoformat(timespec="seconds")},
            {"role": "user", "content": text},
        ],
        "temperature": 0.1,
        "response_format": {"type": "json_object"},
    }
    headers = {"Authorization": f"Bearer {settings.MIMO_API_KEY}", "Content-Type": "application/json"}
    try:
        logger.info("MIMO_DEBUG %s", json.dumps({
            **_mimo_debug_context("project_intake"),
            "request_id": request_id,
            "event": "request",
            "input_length": len(text),
            "timeout_seconds": settings.MIMO_PROJECT_TIMEOUT_SECONDS,
        }, ensure_ascii=False, default=str))
        async with httpx.AsyncClient(timeout=settings.MIMO_PROJECT_TIMEOUT_SECONDS) as client:
            response = await client.post(endpoint, json=payload, headers=headers)
            logger.info("MIMO_DEBUG %s", json.dumps({
                **_mimo_debug_context("project_intake"),
                "request_id": request_id,
                "event": "response",
                "status": response.status_code,
                "content_type": response.headers.get("content-type"),
                "body_length": len(response.content),
                "provider_request_id": response.headers.get("x-request-id") or response.headers.get("request-id"),
            }, ensure_ascii=False, default=str))
            # Some OpenAI-compatible MiMo gateways reject response_format even
            # though they support chat completions. Retry once without it so a
            # gateway capability difference does not force local fallback.
            if response.status_code == 400:
                logger.warning("MIMO_DEBUG %s", json.dumps({
                    **_mimo_debug_context("project_intake"),
                    "request_id": request_id,
                    "event": "retry_without_response_format",
                }, ensure_ascii=False, default=str))
                retry_payload = dict(payload)
                retry_payload.pop("response_format", None)
                response = await client.post(endpoint, json=retry_payload, headers=headers)
            if response.is_error:
                body = response.text.replace("\n", " ")[:500]
                logger.warning(
                    "MiMo project intake HTTP error: status=%s model=%s body=%s",
                    response.status_code,
                    settings.MIMO_MODEL,
                    body,
                )
            response.raise_for_status()
            data = response.json()
        parsed = safe_json_loads(data["choices"][0]["message"]["content"])
        if not parsed:
            raise ValueError("MiMo返回内容不是可解析JSON")
        # Explicit values present in the source text take precedence over a
        # model omission or hallucination, while the model remains responsible
        # for the richer summary and task interpretation.
        normalized = _normalize_project_intake(parsed, text)
        deterministic = _project_intake_fallback(text)
        for field in (
            "name",
            "sponsor",
            "protocol_no",
            "phase",
            "project_type",
            "is_cdisc",
            "indication",
            "current_phase",
        ):
            value = deterministic.get(field)
            has_explicit_value = value is not None and value != ""
            if field == "name" and value == "未命名项目":
                has_explicit_value = False
            if field == "project_type" and value == "other":
                has_explicit_value = False
            if has_explicit_value:
                normalized[field] = value
        if not normalized.get("description") or normalized["description"].strip() == text.strip():
            normalized["description"] = deterministic.get("description")
        normalized["completed_todo_titles"] = list(dict.fromkeys([
            *deterministic.get("completed_todo_titles", []),
            *normalized.get("completed_todo_titles", []),
        ]))
        normalized["in_progress_todo_titles"] = list(dict.fromkeys([
            *deterministic.get("in_progress_todo_titles", []),
            *normalized.get("in_progress_todo_titles", []),
        ]))
        existing_todo_keys = {
            re.sub(r"\s+", "", str(item.get("title") or "")).lower()
            for item in normalized.get("todos", [])
        }
        for item in deterministic.get("todos", []):
            key = re.sub(r"\s+", "", str(item.get("title") or "")).lower()
            if key and key not in existing_todo_keys:
                normalized["todos"].append(item)
                existing_todo_keys.add(key)
        return normalized, settings.MIMO_MODEL, False, data
    except Exception as exc:
        _log_mimo_fallback(
            "project_intake",
            "request_or_response_error",
            exc,
            request_id=request_id,
            text_length=len(text),
        )
        fallback = _project_intake_fallback(text)
        fallback["error"] = f"{type(exc).__name__}: {str(exc)[:500]}"
        fallback["debug_id"] = request_id
        return fallback, "local-rule", True, None


WORKFLOW_TAILOR_SYSTEM_PROMPT = """
你是资深临床试验生物统计师、统计程序员和数据标准专家。
请根据项目主类型、是否CDISC项目和项目描述，定制给定的基础项目流程。

规则：
1. 输入中的全部阶段、任务和checklist已经提供给你。可以按项目类型调整名称、增删任务和细化checklist，但必须保留完整生命周期和必要质量控制。
2. SAP与TFL的文档规划必须在同一个“SAP与TFL”阶段协同推进，包含SAP/TFL撰写、联合审阅和定稿；在各任务checklist中分别列出SAP和TFL工作，不得拆成两个阶段。
3. 最终数据上的TFL程序生产放在“统计编程与输出”，不要与前期TFL shell撰写混淆。
4. is_cdisc=true时必须覆盖SDTM、ADaM、define.xml、验证和reviewer guides；is_cdisc=false时不要强制生成这些监管数据标准交付物，但要保留分析数据集、编程QC和可追溯性。
5. RWS/观察性研究应强调数据适用性、目标人群/暴露/结局操作化、偏倚与混杂、缺失和敏感性分析，不得生搬随机化揭盲流程。
6. 不要编造项目已完成状态、人员或日期。每个任务提供2至6条可执行checklist。阶段5至15个，总任务至少10个。
7. 只返回JSON，不要Markdown或解释：
{
  "phases": [
    {
      "name": "阶段名称",
      "todos": [
        {
          "title": "任务标题",
          "description": "执行说明或null",
          "priority": "low|normal|high|urgent",
          "checklist_items": ["清单项"]
        }
      ]
    }
  ]
}
""".strip()


async def tailor_project_workflow(
    project_type: str,
    is_cdisc: bool,
    project_text: str = "",
) -> tuple[list[dict], str, bool, dict | None]:
    normalized_type = normalize_project_type(project_type)
    fallback = build_workflow_blueprint(normalized_type, bool(is_cdisc))
    endpoint = _endpoint()
    if not endpoint or not settings.MIMO_API_KEY:
        _log_mimo_fallback(
            "workflow_tailoring",
            "missing_endpoint_or_api_key",
            endpoint_configured=bool(endpoint),
            input_length=len(project_text),
        )
        return fallback, "local-rule", True, None

    context = {
        "project_type": normalized_type,
        "project_type_label": project_type_label(normalized_type),
        "project_type_description": PROJECT_TYPE_DESCRIPTIONS[normalized_type],
        "is_cdisc": bool(is_cdisc),
        "project_description": project_text.strip()[:6000] or None,
        "base_workflow": fallback,
    }
    payload = {
        "model": settings.MIMO_MODEL,
        "messages": [
            {"role": "system", "content": WORKFLOW_TAILOR_SYSTEM_PROMPT},
            {"role": "user", "content": json.dumps(context, ensure_ascii=False)},
        ],
        "temperature": 0.1,
        "response_format": {"type": "json_object"},
    }
    headers = {
        "Authorization": f"Bearer {settings.MIMO_API_KEY}",
        "Content-Type": "application/json",
    }
    request_id = uuid.uuid4().hex[:12]
    started = time.monotonic()
    try:
        logger.info("MIMO_DEBUG %s", json.dumps({
            **_mimo_debug_context("workflow_tailoring"),
            "request_id": request_id,
            "event": "request",
            "input_length": len(project_text),
        }, ensure_ascii=False))
        async with httpx.AsyncClient(timeout=settings.MIMO_PROJECT_TIMEOUT_SECONDS) as client:
            response = await client.post(endpoint, json=payload, headers=headers)
            logger.info("MIMO_DEBUG %s", json.dumps({
                **_mimo_debug_context("workflow_tailoring"),
                "request_id": request_id,
                "event": "response",
                "status": response.status_code,
                "content_type": response.headers.get("content-type"),
                "body_length": len(response.content),
                "elapsed_ms": round((time.monotonic() - started) * 1000),
                "provider_request_id": response.headers.get("x-request-id") or response.headers.get("request-id"),
            }, ensure_ascii=False))
            if response.status_code == 400:
                retry_payload = dict(payload)
                retry_payload.pop("response_format", None)
                logger.info("MIMO_DEBUG %s", json.dumps({
                    **_mimo_debug_context("workflow_tailoring"),
                    "request_id": request_id,
                    "event": "retry_without_response_format",
                }, ensure_ascii=False))
                response = await client.post(endpoint, json=retry_payload, headers=headers)
            if response.is_error:
                logger.warning(
                    "MiMo workflow tailoring HTTP error: status=%s model=%s body=%s",
                    response.status_code,
                    settings.MIMO_MODEL,
                    response.text.replace("\n", " ")[:500],
                )
            response.raise_for_status()
            data = response.json()
        parsed = safe_json_loads(data["choices"][0]["message"]["content"])
        if not parsed:
            raise ValueError("MiMo返回的流程不是可解析JSON")
        tailored = normalize_workflow_blueprint(
            parsed,
            fallback,
            is_cdisc=bool(is_cdisc),
        )
        # normalize_workflow_blueprint deliberately returns a copy of fallback
        # for malformed responses; this is still a successful, safe creation.
        return tailored, settings.MIMO_MODEL, False, data
    except Exception as exc:
        _log_mimo_fallback(
            "workflow_tailoring",
            "request_or_response_error",
            exc,
            request_id=request_id,
            input_length=len(project_text),
        )
        return fallback, "local-rule", True, None


def _agent_fallback(text: str, context: dict) -> dict:
    """Keep the project agent usable when MiMo is unavailable."""
    from app.crud.project import parse_text_fallback

    normalized = text.strip()
    lower = normalized.lower()
    phases = context.get("phases") or []
    todos = context.get("todos") or []
    completed_markers = ("已完成", "完成了", "做完", "搞定", "已处理", "已经做了", "关闭")
    active_markers = ("正在", "目前", "接下来", "下一步", "开始做", "安排")

    completed_todo_ids = []
    referenced_todo_ids = []
    current_phase = None
    for phase in phases:
        name = str(phase.get("name") or "")
        if name and name in normalized:
            current_phase = name
    for todo in todos:
        title = str(todo.get("title") or "")
        if not title:
            continue
        if title in normalized:
            referenced_todo_ids.append(todo["id"])
            if any(marker in normalized for marker in completed_markers):
                completed_todo_ids.append(todo["id"])
            if any(marker in normalized for marker in active_markers):
                current_phase = current_phase or todo.get("phase")

    parsed = parse_text_fallback(normalized)
    if parsed.get("intent") == "meeting":
        for meeting in parsed.get("meetings", []):
            meeting["todo_id"] = (
                referenced_todo_ids[0]
                if referenced_todo_ids
                else completed_todo_ids[0]
                if completed_todo_ids
                else None
            )
        return {
            "intent": "meeting",
            "summary": "已识别会议内容并尝试关联当前项目事项。",
            "clarification": None,
            "current_phase": current_phase,
            "completed_todo_ids": completed_todo_ids,
            "completed_checklist_item_ids": [],
            "todos": [],
            "meetings": parsed.get("meetings", []),
        }

    todos_out = []
    for todo in parsed.get("todos", []):
        todo["action"] = "create"
        todo["phase"] = todo.get("phase") or current_phase
        todo["ref"] = "todo-1"
        todo["checklist_items"] = []
        todos_out.append(todo)
    return {
        "intent": "mixed" if completed_todo_ids else "create_todo",
        "summary": "已根据输入更新完成状态并整理下一步待办。",
        "clarification": None,
        "current_phase": current_phase,
        "completed_todo_ids": completed_todo_ids,
        "completed_checklist_item_ids": [],
        "todos": todos_out,
        "meetings": [],
    }


async def parse_project_agent(text: str, context: dict) -> tuple[dict, str, bool, dict | None]:
    endpoint = _endpoint()
    if not endpoint or not settings.MIMO_API_KEY:
        return _agent_fallback(text, context), "local-rule", True, None

    now = datetime.now(ZoneInfo("Asia/Shanghai"))
    system_prompt = (
        PROJECT_AGENT_SYSTEM_PROMPT
        + "\n\n当前时间："
        + now.isoformat(timespec="seconds")
        + "\n当前项目上下文（仅可引用其中的 ID）：\n"
        + json.dumps(context, ensure_ascii=False)
    )
    payload = {
        "model": settings.MIMO_MODEL,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": text},
        ],
        "temperature": 0.1,
        "response_format": {"type": "json_object"},
    }
    headers = {
        "Authorization": f"Bearer {settings.MIMO_API_KEY}",
        "Content-Type": "application/json",
    }
    try:
        async with httpx.AsyncClient(timeout=settings.MIMO_PROJECT_TIMEOUT_SECONDS) as client:
            response = await client.post(endpoint, json=payload, headers=headers)
            if response.status_code == 400:
                logger.warning(
                    "MiMo project agent returned 400; retrying without response_format (model=%s)",
                    settings.MIMO_MODEL,
                )
                retry_payload = dict(payload)
                retry_payload.pop("response_format", None)
                response = await client.post(endpoint, json=retry_payload, headers=headers)
            if response.is_error:
                logger.warning(
                    "MiMo project agent HTTP error: status=%s model=%s body=%s",
                    response.status_code,
                    settings.MIMO_MODEL,
                    response.text.replace("\n", " ")[:500],
                )
            response.raise_for_status()
            data = response.json()
        parsed = safe_json_loads(data["choices"][0]["message"]["content"])
        if not parsed:
            raise ValueError("MiMo返回内容不是可解析JSON")
        return parsed, settings.MIMO_MODEL, False, data
    except Exception as exc:
        logger.warning(
            "MiMo project agent failed; using local fallback (%s): %s",
            type(exc).__name__,
            exc,
        )
        fallback = _agent_fallback(text, context)
        fallback["error"] = str(exc)
        return fallback, "local-rule", True, None
