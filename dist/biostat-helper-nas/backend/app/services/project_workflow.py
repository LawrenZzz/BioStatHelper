from __future__ import annotations

from copy import deepcopy
from typing import Any

from app.core.project_types import normalize_project_type


def _todo(title: str, checklist: list[str], description: str | None = None) -> dict[str, Any]:
    return {
        "title": title,
        "description": description,
        "priority": "normal",
        "checklist_items": checklist,
    }


def _phase(name: str, *todos: dict[str, Any]) -> dict[str, Any]:
    return {"name": name, "todos": list(todos)}


def _base_workflow(is_cdisc: bool) -> list[dict[str, Any]]:
    workflow = [
        _phase(
            "项目启动",
            _todo(
                "确认研究设计、统计职责与关键里程碑",
                [
                    "确认当前方案版本、研究目的和主要里程碑",
                    "确认统计、编程、DM、医学和运营责任人",
                    "确认盲态、数据传输、锁库和交付边界",
                ],
            ),
            _todo(
                "建立项目目录、版本控制与QC约定",
                [
                    "建立目录结构、命名规范和程序模板",
                    "明确双编程或独立QC范围",
                    "建立决策、问题和版本追踪记录",
                ],
            ),
        ),
        _phase(
            "SAP与TFL",
            _todo(
                "方案统计审阅与估计目标确认",
                [
                    "核对主要/次要终点、时间点和 estimand",
                    "核对分析集、协变量、分层因素和多重性",
                    "核对缺失数据、伴发事件和敏感性分析策略",
                ],
            ),
            _todo(
                "SAP/TFL撰写",
                [
                    "分别起草SAP正文、分析规则和统计方法",
                    "分别起草TFL目录、shell、标题、脚注和分母规则",
                    "核对SAP方法与每个TFL输出的对应关系",
                ],
            ),
            _todo(
                "SAP/TFL联合审阅",
                [
                    "单独完成SAP统计、医学和申办方审阅",
                    "单独完成TFL shell的统计、医学和编程审阅",
                    "联合关闭SAP与TFL之间的不一致及全部审阅意见",
                ],
            ),
            _todo(
                "SAP/TFL定稿",
                [
                    "单独确认SAP定稿、签批、版本号和生效日期",
                    "单独确认TFL目录与shell定稿、版本号和脚注",
                    "记录SAP/TFL与方案的差异并冻结可追溯映射",
                ],
            ),
        ),
        _phase(
            "数据管理DM",
            _todo(
                "CRF/EDC与数据采集统计审阅",
                [
                    "确认关键终点、协变量和分层因素可分析",
                    "核对单位、访视窗口、缺失编码和重复测量结构",
                    "确认重要方案偏离和分析集判定所需字段",
                ],
            ),
            _todo(
                "数据清理与外部数据跟踪",
                [
                    "审阅Edit Check、Query和数据清理计划",
                    "确认外部数据传输规范、对账和版本",
                    "跟踪SAE一致性、医学编码和关键Query关闭",
                ],
            ),
        ),
    ]

    if is_cdisc:
        workflow.append(
            _phase(
                "CDISC与数据集",
                _todo(
                    "SDTM策略、映射与验证",
                    [
                        "确认SDTMIG、受控术语和业务规则版本",
                        "确认Trial Design域、SUPP和外部数据映射",
                        "关闭验证问题并维护SDRG解释",
                    ],
                ),
                _todo(
                    "ADaM规格、编程与可追溯性",
                    [
                        "确认ADSL、BDS/OCCDS结构和关键变量",
                        "确认PARAM/PARAMCD、分析标志、访视窗口和派生规则",
                        "完成ADaM主程序、独立QC及SDTM-ADaM-TFL追溯",
                    ],
                ),
                _todo(
                    "Define与审评资料准备",
                    [
                        "维护define.xml、value-level metadata和注释CRF",
                        "准备ADRG/SDRG及验证Issue解释",
                        "确认数据集、元数据、程序和结果版本一致",
                    ],
                ),
            )
        )
    else:
        workflow.append(
            _phase(
                "分析数据集与编程",
                _todo(
                    "分析数据集规格、派生与QC",
                    [
                        "确认分析数据集结构、变量和数据字典",
                        "确认分析标志、参数、访视窗口和派生规则",
                        "完成主程序、独立QC和源数据到结果的可追溯检查",
                    ],
                ),
            )
        )

    workflow.extend(
        [
            _phase(
                "统计编程与输出",
                _todo(
                    "TFL程序开发与独立QC",
                    [
                        "按定稿shell编写表、图、列表程序",
                        "核对格式、小数位、排序、脚注和分母",
                        "完成独立QC并关闭差异",
                    ],
                ),
                _todo(
                    "关键结果一致性与可追溯性核对",
                    [
                        "核对主要终点、安全性和敏感性分析关键数字",
                        "核对分析集、数据截点和输出版本",
                        "确认关键结果可追溯到分析数据和程序",
                    ],
                ),
            ),
            _phase(
                "盲态审阅",
                _todo(
                    "盲态数据审阅与分析集确认",
                    [
                        "确认重要方案偏离和分析集归属",
                        "确认异常值、缺失数据和伴发事件处理",
                        "记录盲态决策、理由和审批",
                    ],
                ),
            ),
            _phase(
                "锁库与揭盲",
                _todo(
                    "锁库、数据快照与揭盲准备",
                    [
                        "确认关键Query、外部数据和对账关闭",
                        "确认最终数据快照、随机化和揭盲权限",
                        "冻结最终分析输入、程序和运行环境",
                    ],
                ),
            ),
            _phase(
                "SAR统计分析报告",
                _todo(
                    "SAR撰写与结果解释",
                    [
                        "起草研究设计、分析集、终点和统计方法",
                        "汇总有效性、安全性和敏感性分析结果",
                        "核对SAR数字、表图出处和SAP/TFL一致性",
                    ],
                ),
                _todo(
                    "SAR审阅、定稿与签发",
                    [
                        "完成SAR独立QC和交叉审阅",
                        "关闭审阅意见并确认结论措辞",
                        "完成版本定稿、签发和归档",
                    ],
                ),
            ),
            _phase(
                "CSR与提交",
                _todo(
                    "CSR统计支持与提交归档",
                    [
                        "核对CSR统计文本、关键结论与TFL一致",
                        "确认探索性结果和敏感性分析措辞恰当",
                        "归档数据、程序、输出、QC和决策记录",
                    ],
                ),
            ),
        ]
    )
    return workflow


def _find_phase(workflow: list[dict[str, Any]], name: str) -> dict[str, Any] | None:
    return next((phase for phase in workflow if phase["name"] == name), None)


def _append_todo(
    workflow: list[dict[str, Any]],
    phase_name: str,
    title: str,
    checklist: list[str],
    description: str | None = None,
) -> None:
    phase = _find_phase(workflow, phase_name)
    if phase is not None:
        phase["todos"].append(_todo(title, checklist, description))


def _rename_phase(workflow: list[dict[str, Any]], old: str, new: str) -> None:
    phase = _find_phase(workflow, old)
    if phase is not None:
        phase["name"] = new


def build_workflow_blueprint(project_type: str, is_cdisc: bool) -> list[dict[str, Any]]:
    project_type = normalize_project_type(project_type)
    workflow = _base_workflow(bool(is_cdisc))
    data_phase = "CDISC与数据集" if is_cdisc else "分析数据集与编程"

    if project_type == "vaccine":
        _append_todo(workflow, "SAP与TFL", "疫苗免疫原性与保护效力策略", [
            "确认血清阳转/血清学应答、GMT/GMC及倍数升高定义",
            "确认保护效力、病例定义、监测期和人时计算",
            "确认反应原性、安全性和亚组分析窗口",
        ])
        _append_todo(workflow, data_phase, "免疫原性与病例数据派生", [
            "确认检测下限、低于定量限和基线血清状态处理",
            "确认免疫原性分析集、采血窗口和缺失规则",
            "确认病例裁定、暴露时间和批间一致性变量",
        ])
    elif project_type == "medical_device":
        _append_todo(workflow, "SAP与TFL", "器械性能与操作者效应分析设计", [
            "确认主要性能终点、成功标准和非劣/优效界值",
            "评估中心、操作者、器械批次和学习曲线效应",
            "明确器械缺陷、转换治疗和重复测量处理",
        ])
    elif project_type == "diagnostic":
        _append_todo(workflow, "SAP与TFL", "诊断准确性统计设计", [
            "确认目标使用人群、参考标准和盲法判读",
            "确认灵敏度、特异度、PPV/NPV、ROC及置信区间方法",
            "确认无效/不确定结果、多阅片者和多中心处理",
        ])
        _append_todo(workflow, data_phase, "样本与判读数据一致性检查", [
            "核对样本流转、检测批次、设备和操作者信息",
            "核对参考标准、指数试验和判读时间顺序",
            "确认重复样本、缺失参考标准和无效结果标志",
        ])
    elif project_type == "radiopharmaceutical":
        _append_todo(workflow, "SAP与TFL", "核药剂量学与影像终点策略", [
            "确认给药活度、衰变校正、采集窗口和成像设备因素",
            "确认器官/肿瘤吸收剂量、生物分布和剂量限制",
            "确认阅片、病灶层级、患者层级和影像终点规则",
        ])
        _append_todo(workflow, "数据管理DM", "核药与影像数据对账", [
            "核对给药时间、活度、残留活度和校准信息",
            "核对影像采集、重建、中心判读和病灶匹配",
            "核对辐射安全事件和剂量学源数据完整性",
        ])
    elif project_type == "biologic":
        _append_todo(workflow, "SAP与TFL", "PK/PD与免疫原性策略", [
            "确认PK/PD参数、采样窗口和低于定量限处理",
            "确认ADA/NAb阳性、基线增强和滴度定义",
            "确认免疫原性对PK、有效性和安全性的影响分析",
        ])
    elif project_type == "cell_gene":
        _append_todo(workflow, "SAP与TFL", "细胞/基因治疗特定终点策略", [
            "确认细胞持久性、载体拷贝数和载体脱落分析",
            "确认长期随访、延迟不良事件和竞争风险处理",
            "确认CRS、神经毒性等特定风险分级和时间窗",
        ])
        _append_todo(workflow, "CSR与提交", "长期随访统计更新", [
            "确认年度长期随访数据截点和累积暴露",
            "更新持久性、迟发安全性和生存结局",
            "维护跨年度数据、程序和报告版本一致性",
        ])
    elif project_type == "tcm":
        _append_todo(workflow, "SAP与TFL", "中药证候与复合终点策略", [
            "确认疾病终点与证候终点的层级和多重性",
            "确认证候量表、疗效判定和缺失条目计分",
            "确认基础治疗、合并用药和产品批次影响",
        ])
    elif project_type in {"rws", "observational"}:
        _rename_phase(workflow, "数据管理DM", "研究数据治理")
        _rename_phase(workflow, "盲态审阅", "偏倚与混杂控制")
        _rename_phase(workflow, "锁库与揭盲", "数据冻结与最终分析")
        _append_todo(workflow, "SAP与TFL", "目标人群、暴露与结局操作化定义", [
            "明确索引日、基线期、随访期和删失规则",
            "明确纳排标准、暴露、对照和结局算法",
            "预先定义负对照、亚组和敏感性分析",
        ])
        _append_todo(workflow, "研究数据治理", "数据适用性与来源评估", [
            "评估覆盖度、完整性、准确性、时效性和可追溯性",
            "核对编码体系、跨库链接、重复记录和数据漂移",
            "记录变量可用性与研究问题的适配证据",
        ])
        _append_todo(workflow, "偏倚与混杂控制", "混杂控制与稳健性分析", [
            "明确因果图或协变量选择依据并避免调整中介变量",
            "实施倾向评分、加权/匹配/分层或结局模型",
            "检查平衡性、阳性、未测量混杂和模型设定敏感性",
        ])
    elif project_type == "iit":
        _append_todo(workflow, "项目启动", "IIT治理与统计交付边界确认", [
            "确认研究者、机构、数据所有权和统计责任",
            "确认经费、合同、数据访问和发表计划",
            "确认方案偏离、SAE、监查和归档责任",
        ])
    elif project_type == "be_pk":
        _append_todo(workflow, "SAP与TFL", "BE/PK统计分析策略", [
            "确认主要PK参数、对数转换和BE界值",
            "确认序列、周期、制剂、受试者效应和异常值规则",
            "确认BLQ、缺失采样、呕吐和重测样本处理",
        ])
        _append_todo(workflow, "统计编程与输出", "NCA与生物等效性分析", [
            "核对实际采样时间和NCA参数计算",
            "计算几何均值比及90%置信区间",
            "检查周期、序列、残留效应和敏感性分析",
        ])
    elif project_type == "drug":
        _append_todo(workflow, "SAP与TFL", "药物有效性与安全性分析策略", [
            "确认剂量组、治疗策略、暴露定义和估计目标",
            "确认AE/SAE、实验室、生命体征和特殊关注风险分析",
            "确认剂量反应、亚组、获益风险和敏感性分析",
        ])

    return workflow


def flatten_workflow(workflow: list[dict[str, Any]]) -> list[tuple[str, str]]:
    return [
        (phase["name"], todo["title"])
        for phase in workflow
        for todo in phase.get("todos", [])
    ]


def normalize_workflow_blueprint(
    raw: object,
    fallback: list[dict[str, Any]],
    *,
    is_cdisc: bool | None = None,
) -> list[dict[str, Any]]:
    if isinstance(raw, dict):
        raw = raw.get("phases") or raw.get("workflow_phases")
    if not isinstance(raw, list):
        return deepcopy(fallback)

    phases: list[dict[str, Any]] = []
    phase_names: set[str] = set()
    for phase_raw in raw[:20]:
        if not isinstance(phase_raw, dict):
            continue
        name = str(phase_raw.get("name") or "").strip()[:100]
        if not name or name in phase_names:
            continue
        todos: list[dict[str, Any]] = []
        todo_titles: set[str] = set()
        for todo_raw in (phase_raw.get("todos") or [])[:30]:
            if not isinstance(todo_raw, dict):
                continue
            title = str(todo_raw.get("title") or "").strip()[:300]
            if not title or title in todo_titles:
                continue
            checklist = []
            for item in (todo_raw.get("checklist_items") or [])[:15]:
                item_title = str(item.get("title") if isinstance(item, dict) else item).strip()[:300]
                if item_title and item_title not in checklist:
                    checklist.append(item_title)
            todos.append({
                "title": title,
                "description": str(todo_raw.get("description") or "").strip()[:2000] or None,
                "priority": todo_raw.get("priority") if todo_raw.get("priority") in {"low", "normal", "high", "urgent"} else "normal",
                "checklist_items": checklist,
            })
            todo_titles.add(title)
        if todos:
            phases.append({"name": name, "todos": todos})
            phase_names.add(name)

    # A tiny or malformed model response must never replace the reliable local
    # workflow. Valid tailored workflows still have a meaningful lifecycle.
    if len(phases) < 5 or sum(len(item["todos"]) for item in phases) < 10:
        return deepcopy(fallback)
    return enforce_workflow_contract(
        phases,
        fallback,
        is_cdisc=(
            is_cdisc
            if is_cdisc is not None
            else any(phase["name"] == "CDISC与数据集" for phase in fallback)
        ),
    )


def _insert_phase_after(
    workflow: list[dict[str, Any]],
    phase: dict[str, Any],
    after_names: set[str],
) -> None:
    index = next(
        (i + 1 for i, item in enumerate(workflow) if item["name"] in after_names),
        len(workflow),
    )
    workflow.insert(index, deepcopy(phase))


def _workflow_phase(fallback: list[dict[str, Any]], name: str) -> dict[str, Any]:
    return deepcopy(next(phase for phase in fallback if phase["name"] == name))


def _sap_tfl_task_kind(title: str) -> str | None:
    normalized = title.upper()
    if "SAP" not in normalized or "TFL" not in normalized:
        return None
    if any(token in title for token in ("撰写", "起草")):
        return "writing"
    if any(token in title for token in ("审阅", "审核", "评审")):
        return "review"
    if any(token in title for token in ("定稿", "签批", "签发")):
        return "final"
    return None


def enforce_workflow_contract(
    workflow: list[dict[str, Any]],
    fallback: list[dict[str, Any]],
    *,
    is_cdisc: bool,
) -> list[dict[str, Any]]:
    """Keep AI customization inside the project's non-negotiable rules."""
    result = deepcopy(workflow)

    legacy_sap_tfl_names = {"方案与SAP", "TFL与统计输出"}
    sap_tfl = next((phase for phase in result if phase["name"] == "SAP与TFL"), None)
    for phase in list(result):
        if phase["name"] not in legacy_sap_tfl_names:
            continue
        if sap_tfl is None:
            phase["name"] = "SAP与TFL"
            sap_tfl = phase
        else:
            existing = {todo["title"] for todo in sap_tfl["todos"]}
            sap_tfl["todos"].extend(
                todo for todo in phase["todos"] if todo["title"] not in existing
            )
            result.remove(phase)

    fallback_sap_tfl = _workflow_phase(fallback, "SAP与TFL")
    if sap_tfl is None:
        _insert_phase_after(result, fallback_sap_tfl, {"项目启动"})
        sap_tfl = next(phase for phase in result if phase["name"] == "SAP与TFL")

    required_tasks = {
        "writing": next(todo for todo in fallback_sap_tfl["todos"] if todo["title"] == "SAP/TFL撰写"),
        "review": next(todo for todo in fallback_sap_tfl["todos"] if todo["title"] == "SAP/TFL联合审阅"),
        "final": next(todo for todo in fallback_sap_tfl["todos"] if todo["title"] == "SAP/TFL定稿"),
    }
    for kind, required in required_tasks.items():
        candidate = next(
            (todo for todo in sap_tfl["todos"] if _sap_tfl_task_kind(todo["title"]) == kind),
            None,
        )
        if candidate is None:
            sap_tfl["todos"].append(deepcopy(required))
            continue
        candidate["title"] = required["title"]
        checklist = candidate.setdefault("checklist_items", [])
        checklist.extend(item for item in required["checklist_items"] if item not in checklist)

    cdisc_tokens = ("CDISC", "SDTM", "ADAM", "DEFINE.XML", "SDRG", "ADRG")

    def contains_cdisc(value: object) -> bool:
        upper = str(value or "").upper()
        return any(token in upper for token in cdisc_tokens)

    if is_cdisc:
        if not any(phase["name"] == "CDISC与数据集" for phase in result):
            _insert_phase_after(
                result,
                _workflow_phase(fallback, "CDISC与数据集"),
                {"数据管理DM", "研究数据治理"},
            )
    else:
        filtered: list[dict[str, Any]] = []
        for phase in result:
            if contains_cdisc(phase["name"]):
                continue
            phase["todos"] = [
                todo for todo in phase["todos"]
                if not contains_cdisc(todo["title"])
            ]
            if phase["todos"]:
                filtered.append(phase)
        result = filtered
        if not any(phase["name"] == "分析数据集与编程" for phase in result):
            _insert_phase_after(
                result,
                _workflow_phase(fallback, "分析数据集与编程"),
                {"数据管理DM", "研究数据治理"},
            )

    return result


DEFAULT_WORKFLOW_BLUEPRINT = build_workflow_blueprint("drug", True)
STANDARD_WORKFLOW = flatten_workflow(DEFAULT_WORKFLOW_BLUEPRINT)
STANDARD_PHASE_ORDER = [phase["name"] for phase in DEFAULT_WORKFLOW_BLUEPRINT]
