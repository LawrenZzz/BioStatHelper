"""Dependency-aware workflow estimates. Inference is labelled, never dated."""

import re

from app.services.project_workflow import build_workflow_blueprint


def infer_milestones(text: str) -> dict:
    clauses = [s.strip() for s in re.split(r'[，；。\n]', text) if s.strip()]

    def evidence(pattern, *, final=False):
        for clause in clauses:
            if final and re.search(r'期中|中期|首轮|阶段性|TAV0|Part\s*1|待确认|待更新|是否|准备|预计|计划|尚未|未完成|未锁|未定稿|未签署', clause, re.I):
                continue
            match = re.search(pattern, clause, re.I)
            if match:
                # Reject negated/anticipated milestones even when the verb is after SAP.
                prefix = clause[max(0, match.start() - 6):match.start()]
                if not re.search(r'尚未|没有|未能|计划|预计|等待|待', prefix):
                    return clause
        return ''

    return {
        'sap_final': evidence(r'SAP(?:/TFL)?(?:\s*V[\d.]+)?(?:已有|已经|已)(?:完成)?(?:审核定稿|定稿|签署|签批)|SAP/SAR已有签署版', final=True),
        'sap_review': evidence(r'SAP(?:/TFL)?.*(?:审核|审阅|修订|反馈|已提交|已发审核|提交.*审核)'),
        'sap_draft': evidence(r'SAP(?:/TFL)?.*(?:撰写|编写|起草|工作稿)'),
        'dm': evidence(r'CRF|aCRF|EDC|建库|数据清理|传输协议|外部.*协议|IWRS'),
        'dry_run': evidence(r'dry\s*run.*(?:已发出|结果|收尾|反馈|准备)|dry\s*run后'),
        'locked': evidence(r'(?:已经|已)(?:完成)?(?:正式)?锁库|(?:数据库|数据)(?:已经|已)锁定|(?:正式)?锁库(?:已经|已)完成', final=True),
        'formal_outputs': evidence(r'正式递交资料.*(?:已形成|已有)|已有正式递交资料|(?:终末|最终|正式)分析(?:输出)?已完成', final=True),
        'sar_review': evidence(r'(?:SAR|CSR)(?:/SAR|/CSR|/TFL)?.*(?:反馈|修订|复核|已发出|等待)|报告反馈|统计QC问题待关闭'),
        'sar_final': evidence(r'(?:SAR|SAP/SAR)(?:已有|已经|已)(?:完成)?(?:签署版|签署|定稿|签发)', final=True),
        'sar_sent': evidence(r'SAR(?:/TFL)?已发出', final=True),
        'interim': evidence(r'期中|中期|阶段性|Part\s*1|首轮', final=False),
        'analysis_delivery': evidence(r'阶段性分析已交付|期中SAP已签署|期中SAP已有定稿存档|已有BTD分析输出'),
        'working_outputs': evidence(r'已有SAP/TFL\s*V|Part1分析输出'),
        'unblinding_plan': evidence(r'揭盲流程已定稿'),
        'design': evidence(r'方案.*(?:设计|统计|修订|讨论)|随机化方案.*(?:编写|确认)|技术标.*沟通'),
    }


def build_progress_workflow(entry: dict, *, project_type: str, is_cdisc: bool) -> dict:
    workflow = build_workflow_blueprint(project_type, is_cdisc)
    observational = project_type in {'rws', 'observational'}
    if observational:
        for phase in workflow:
            for todo in phase['todos']:
                if todo['title'] == '盲态数据审阅与分析集确认':
                    todo.update(title='数据审阅与分析人群确认', checklist_items=[
                        '核对纳排、索引日、暴露、结局及分析人群',
                        '确认异常值、缺失数据、失访和数据质量处理',
                        '记录分析决策、偏倚评估及审阅结论',
                    ])
                elif todo['title'] == '锁库、数据快照与揭盲准备':
                    todo.update(title='数据截点、冻结与分析输入确认', checklist_items=[
                        '确认本次分析的数据截点、质疑及外部数据对账',
                        '确认冻结数据快照、来源版本和访问权限',
                        '确认纳入人群、数据输入及可追溯记录',
                    ])
                else:
                    todo['checklist_items'] = [
                        item.replace('盲态、数据传输、锁库', '数据权限、传输、冻结')
                        for item in todo['checklist_items']
                    ]
    design_name = '研究设计与统计策略' if observational else '方案设计与随机化'
    design_todos = [{
        'title': '研究设计、终点与样本量确认',
        'checklist_items': ['确认研究设计、主要终点与估计目标', '核对样本量参数、假设及计算依据', '确认方案统计章节及评审结论'],
    }]
    if not observational and '随机' in entry['study_design']:
        design_todos.append({
            'title': '随机化方案、系统与UAT确认',
            'checklist_items': ['确认随机化、分层与盲法参数', '审阅随机系统及UAT结论', '确认批准版本、权限与盲底传输安排'],
        })
    workflow.insert(1, {'name': design_name, 'todos': design_todos})
    dm_name = '研究数据治理' if observational else '数据管理DM'
    execution_name = '临床执行与数据截点'
    dm_index = next(i for i, p in enumerate(workflow) if p['name'] == dm_name)
    workflow.insert(dm_index + 1, {'name': execution_name, 'todos': [{
        'title': '本次分析范围的入组、随访与数据截点确认',
        'checklist_items': ['核对本次分析纳入人群与数据截点', '确认本次分析所需访视、终点与随访数据', '核对偏离、退出及尚在随访受试者的处理'],
    }]})
    milestones = infer_milestones(entry['current_state'])
    for phase in workflow:
        for todo in phase['todos']:
            todo.update(status='next', origin='unstarted', basis='文档未显示本项已开始或完成。')

    def mark(phase_name, status, basis):
        for phase in workflow:
            if phase['name'] == phase_name:
                for todo in phase['todos']:
                    todo.update(status=status, origin='inferred', basis=basis)

    def task(phase_name, title, status, basis):
        for phase in workflow:
            if phase['name'] == phase_name:
                for todo in phase['todos']:
                    if todo['title'] == title:
                        todo.update(status=status, origin='inferred', basis=basis)

    sap = milestones['sap_review'] or milestones['sap_draft']
    if sap:
        mark('项目启动', 'done', f'已进入SAP/TFL工作，推断项目启动已完成。依据：{sap}')
        task(design_name, '研究设计、终点与样本量确认', 'done',
             f'SAP工作已开展，推断本次方案设计已形成可用基线；不代表随机系统已上线。依据：{sap}')
        task('SAP与TFL', '方案统计审阅与估计目标确认', 'done', sap)
        task('SAP与TFL', 'SAP/TFL撰写', 'done' if milestones['sap_review'] else 'in_progress', sap)
        if milestones['sap_review']:
            task('SAP与TFL', 'SAP/TFL联合审阅', 'in_progress', sap)

    if milestones['design'] and not sap:
        mark('项目启动', 'in_progress', milestones['design'])
        mark(design_name, 'in_progress', milestones['design'])
    if milestones['dm']:
        mark('项目启动', 'done', milestones['dm'])
        mark(dm_name, 'in_progress', milestones['dm'])
    data_name = 'CDISC与数据集' if is_cdisc else '分析数据集与编程'
    if milestones['dry_run']:
        mark('项目启动', 'done', milestones['dry_run'])
        mark(dm_name, 'in_progress', milestones['dry_run'])
        mark(data_name, 'in_progress', milestones['dry_run'])
        mark('统计编程与输出', 'in_progress', milestones['dry_run'])
    if milestones['analysis_delivery']:
        basis = f'已有阶段性工作记录，推断启动与设计已完成；不代表终末分析完成。依据：{milestones["analysis_delivery"]}'
        mark('项目启动', 'done', basis)
        mark(design_name, 'done', basis)
        mark(data_name, 'in_progress', basis)
        mark('统计编程与输出', 'in_progress', basis)
    if milestones['working_outputs']:
        basis = milestones['working_outputs']
        mark('项目启动', 'done', basis)
        task(design_name, '研究设计、终点与样本量确认', 'done',
             f'已有SAP/TFL工作版本及分析输出，推断本次设计基线已形成。依据：{basis}')
        task('SAP与TFL', 'SAP/TFL撰写', 'done', basis)
        task('SAP与TFL', 'SAP/TFL联合审阅', 'in_progress', f'已有工作版本，最终接受状态尚待确认。依据：{basis}')
        mark(data_name, 'in_progress', basis)
        mark('统计编程与输出', 'in_progress', basis)
    if milestones['unblinding_plan']:
        mark('项目启动', 'done', milestones['unblinding_plan'])

    final_basis = milestones['formal_outputs'] or milestones['sar_final'] or milestones['locked'] or milestones['sar_sent']
    sap_final = milestones['sap_final'] or final_basis
    if sap_final:
        basis = f'根据本次分析里程碑推断启动、设计及SAP/TFL基线已完成。依据：{sap_final}'
        for phase in ['项目启动', 'SAP与TFL']:
            mark(phase, 'done', basis)
        task(design_name, '研究设计、终点与样本量确认', 'done', basis)
    lock_name = '数据冻结与最终分析' if observational else '锁库与揭盲'
    blind_name = '偏倚与混杂控制' if observational else '盲态审阅'
    if final_basis:
        basis = f'按本次分析数据范围推断已完成数据核对、截点确认及冻结；不代表后续长期随访结束。依据：{final_basis}'
        for phase in [dm_name, execution_name, blind_name, lock_name]:
            mark(phase, 'done', basis)
        mark(design_name, 'done', basis)
        mark(data_name, 'in_progress', f'正式分析所需数据集编程与验证。依据：{final_basis}')
        mark('统计编程与输出', 'in_progress', final_basis)
    if milestones['formal_outputs'] or milestones['sar_final'] or milestones['sar_sent']:
        basis = milestones['formal_outputs'] or milestones['sar_final'] or milestones['sar_sent']
        mark(data_name, 'done', f'正式输出/签署报告已形成，推断分析输入与派生已具备。依据：{basis}')
        mark('统计编程与输出', 'done', f'正式分析资料已形成，推断首版分析输出已完成。依据：{basis}')
        task('SAR统计分析报告', 'SAR撰写与结果解释', 'done', basis)
        task('SAR统计分析报告', 'SAR审阅、定稿与签发', 'in_progress', basis)
    if milestones['sar_review']:
        basis = milestones['sar_review']
        task('SAR统计分析报告', 'SAR撰写与结果解释', 'done', basis)
        task('SAR统计分析报告', 'SAR审阅、定稿与签发', 'in_progress', basis)
        if re.search(r'QC|复核|TFL|输出', basis, re.I):
            mark('统计编程与输出', 'in_progress', f'已有结果仍需复核或反馈修订。依据：{basis}')
    if milestones['sar_final']:
        mark('SAR统计分析报告', 'done', milestones['sar_final'])
        mark('CSR与提交', 'in_progress', milestones['sar_final'])

    # Current phase follows active work, not simply the furthest mention.
    active = [p['name'] for p in workflow if any(t['status'] == 'in_progress' for t in p['todos'])]
    current = ('统计编程与输出' if '统计QC问题待关闭' in milestones['sar_review'] else
               'SAR统计分析报告' if milestones['sar_review'] else
               '统计编程与输出' if milestones['dry_run'] else
               'SAP与TFL' if sap and not sap_final else
               active[-1] if active else entry['workflow_phase'])
    return {'phases': workflow, 'current_phase': current, 'milestones': milestones}


def pending_task_phase(title: str, plan: dict) -> str:
    names = {p['name'] for p in plan['phases']}
    sap_done = all(t['status'] == 'done' for p in plan['phases'] if p['name'] == 'SAP与TFL' for t in p['todos'])
    if re.search(r'CSR|归档|递交包|m5|合同|服务范围|负责人|本人范围', title, re.I):
        return 'CSR与提交' if not re.search(r'合同|服务范围|负责人|本人范围', title) else '项目启动'
    if re.search(r'SAR|报告|论文', title, re.I):
        return 'SAR统计分析报告'
    if re.search(r'SAP|TFL.*(?:反馈|定稿|修订)|终点|样本量|量表|方案复审', title, re.I):
        return '统计编程与输出' if sap_done else 'SAP与TFL'
    if re.search(r'分析集|ADaM|SDTM|数据集|衍生|派生', title, re.I):
        return 'CDISC与数据集' if 'CDISC与数据集' in names else '分析数据集与编程'
    if re.search(r'随机|盲底|UAT', title, re.I):
        return '方案设计与随机化' if '方案设计与随机化' in names else '研究设计与统计策略'
    if re.search(r'外部数据|传输|采样|CRF|数据清理|影像.*标准|建库', title, re.I):
        return '研究数据治理' if '研究数据治理' in names else '数据管理DM'
    if re.search(r'锁库|揭盲', title):
        return '数据冻结与最终分析' if '数据冻结与最终分析' in names else '锁库与揭盲'
    return '统计编程与输出'
