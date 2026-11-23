from __future__ import annotations


PROJECT_TYPE_OPTIONS = (
    ("drug", "药物临床研究"),
    ("vaccine", "疫苗临床研究"),
    ("medical_device", "医疗器械临床研究"),
    ("diagnostic", "诊断试剂/伴随诊断研究"),
    ("radiopharmaceutical", "核药/放射性药物研究"),
    ("biologic", "生物制品临床研究"),
    ("cell_gene", "细胞与基因治疗研究"),
    ("tcm", "中药/天然药物研究"),
    ("rws", "真实世界研究 RWS"),
    ("iit", "研究者发起研究 IIT"),
    ("observational", "观察性研究"),
    ("be_pk", "生物等效性/PK研究"),
    ("other", "其他临床研究"),
)

PROJECT_TYPE_LABELS = dict(PROJECT_TYPE_OPTIONS)

PROJECT_TYPE_DESCRIPTIONS = {
    "drug": "药物干预性试验，关注有效性、安全性、剂量、估计目标及获益风险。",
    "vaccine": "疫苗试验，重点覆盖免疫原性、保护效力、反应原性和批间一致性。",
    "medical_device": "医疗器械试验，关注器械性能、操作者/中心效应、学习曲线和器械缺陷。",
    "diagnostic": "诊断准确性或伴随诊断研究，关注参考标准、灵敏度、特异度、ROC及无效结果。",
    "radiopharmaceutical": "核药或放射性药物研究，关注剂量学、生物分布、衰变校正、影像终点和辐射安全。",
    "biologic": "生物制品研究，除有效性和安全性外通常需关注PK/PD、ADA和中和抗体。",
    "cell_gene": "细胞或基因治疗研究，关注持久性、长期随访、载体脱落和特定急性风险。",
    "tcm": "中药或天然药物研究，关注证候、复合终点、质量批次和中西医并行定义。",
    "rws": "真实世界研究，重点是数据适用性、目标试验模拟、混杂控制、缺失和敏感性分析。",
    "iit": "研究者发起研究，需明确研究治理、数据责任、统计交付边界和发表计划。",
    "observational": "队列、病例对照或横断面等观察性研究，重点是选择偏倚、混杂和测量误差。",
    "be_pk": "生物等效性或药代动力学研究，重点是NCA、对数转换、几何均值比和90%置信区间。",
    "other": "未归入其他主类型的临床或生物统计研究。",
}

_PROJECT_TYPE_ALIASES = (
    ("diagnostic", ("诊断试剂", "体外诊断", "伴随诊断", "诊断准确性", "ivd")),
    ("radiopharmaceutical", ("放射性药物", "放射性诊断", "放射性治疗", "核药")),
    ("cell_gene", ("细胞治疗", "基因治疗", "car-t", "cart")),
    ("be_pk", ("生物等效性", "生物等效", "be试验", "be研究", "pk研究", "pk试验", "药代动力学")),
    ("medical_device", ("医疗器械", "器械临床", "器械")),
    ("vaccine", ("预防性疫苗", "治疗性疫苗", "疫苗")),
    ("biologic", ("生物制品", "单克隆抗体", "单抗", "抗体药物", "蛋白药")),
    ("tcm", ("天然药物", "中药")),
    ("rws", ("真实世界研究", "真实世界数据", "真实世界证据", "rws", "rwe")),
    ("iit", ("研究者发起研究", "研究者发起", "iit")),
    ("observational", ("观察性研究", "队列研究", "病例对照", "横断面研究", "横断面")),
    ("drug", ("化学药", "小分子药", "药物临床", "药物研究", "药品临床", "药物")),
)


def normalize_project_type(value: object, default: str = "other") -> str:
    if value is None:
        return default
    normalized = str(value).strip().lower()
    if not normalized:
        return default
    if normalized in PROJECT_TYPE_LABELS:
        return normalized
    for code, label in PROJECT_TYPE_OPTIONS:
        if normalized == label.lower():
            return code
    for code, aliases in _PROJECT_TYPE_ALIASES:
        if any(alias.lower() in normalized for alias in aliases):
            return code
    return default


def project_type_label(value: object) -> str:
    code = normalize_project_type(value)
    return PROJECT_TYPE_LABELS.get(code, PROJECT_TYPE_LABELS["other"])

