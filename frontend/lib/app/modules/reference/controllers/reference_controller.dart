import 'package:get/get.dart';
import '../../../../shared/models/reference_model.dart';
import '../../../../core/services/api_client.dart';
import '../../../../core/values/api_endpoints.dart';

class ReferenceController extends GetxController {
  final ApiClient _apiClient = ApiClient();

  // 可观察变量
  final isLoading = false.obs;
  final references = <QuickReference>[].obs;
  final filteredReferences = <QuickReference>[].obs;
  final selectedCategory = '全部'.obs;

  @override
  void onInit() {
    super.onInit();
    loadReferences();
  }

  Future<void> loadReferences() async {
    isLoading.value = true;

    try {
      final response = await _apiClient.get(ApiEndpoints.references);

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'];
        references.value =
            data.map((json) => QuickReference.fromJson(json)).toList();
        filteredReferences.value = references;
      }
    } catch (e) {
      print('加载参考失败: $e');
      // 使用模拟数据
      references.value = _getMockReferences();
      filteredReferences.value = references;
    } finally {
      isLoading.value = false;
    }
  }

  void filterByCategory(String category) {
    selectedCategory.value = category;

    if (category == '全部') {
      filteredReferences.value = references;
    } else {
      filteredReferences.value =
          references.where((r) => r.category == category).toList();
    }
  }

  void togglePin(QuickReference reference) {
    final index = references.indexWhere((r) => r.id == reference.id);
    if (index != -1) {
      references[index] = QuickReference(
        id: reference.id,
        title: reference.title,
        category: reference.category,
        content: reference.content,
        type: reference.type,
        tags: reference.tags,
        isPinned: !reference.isPinned,
      );

      // 更新筛选列表
      final filteredIndex =
          filteredReferences.indexWhere((r) => r.id == reference.id);
      if (filteredIndex != -1) {
        filteredReferences[filteredIndex] = references[index];
      }

      // 调用API更新置顶状态
      _updatePinStatus(reference.id, references[index].isPinned);
    }
  }

  Future<void> _updatePinStatus(int referenceId, bool isPinned) async {
    try {
      await _apiClient.put(
        '${ApiEndpoints.referenceDetail.replaceAll('{id}', referenceId.toString())}/pin',
        data: {'is_pinned': isPinned},
      );
    } catch (e) {
      print('更新置顶状态失败: $e');
    }
  }

  List<QuickReference> _getMockReferences() {
    return [
      QuickReference(
        id: 1,
        title: 't分布临界值表',
        category: '临界值表',
        content: '''t分布临界值表（双侧）

| 自由度 | α=0.10 | α=0.05 | α=0.02 | α=0.01 |
|--------|--------|--------|--------|--------|
| 1      | 6.314  | 12.706 | 31.821 | 63.657 |
| 5      | 2.015  | 2.571  | 3.365  | 4.032  |
| 10     | 1.812  | 2.228  | 2.764  | 3.169  |
| 20     | 1.725  | 2.086  | 2.528  | 2.845  |
| 30     | 1.697  | 2.042  | 2.457  | 2.750  |
| 60     | 1.671  | 2.000  | 2.390  | 2.660  |
| 120    | 1.658  | 1.980  | 2.358  | 2.617  |
| ∞      | 1.645  | 1.960  | 2.326  | 2.576  |

使用说明：
- 自由度 = n - 1（单样本）或 n₁ + n₂ - 2（两样本）
- α = 显著性水平
- 双侧检验：比较 |t| 与临界值
- 单侧检验：使用 α/2 列的值''',
        type: ReferenceType.table,
        tags: ['t分布', '临界值', '假设检验'],
        isPinned: true,
      ),
      QuickReference(
        id: 2,
        title: '样本量公式速查',
        category: '常用公式',
        content: '''常用样本量计算公式

1. 单样本均值比较
   n = (z_(α/2) + z_β)² × σ² / δ²

2. 两样本均值比较
   n = 2 × (z_(α/2) + z_β)² × σ² / δ²

3. 单样本比例比较
   n = (z_(α/2) + z_β)² × p(1-p) / (p-p₀)²

4. 两样本比例比较
   n = [(z_(α/2) + z_β)² × (p₁(1-p₁) + p₂(1-p₂))] / (p₁-p₂)²

5. 非劣效检验样本量
   n = 2 × (z_(α) + z_β)² × σ² / (δ-Δ)²

其中：
- z_(α/2)：显著性水平对应的临界值
- z_β：功效对应的临界值
- σ：标准差
- δ：预期差异或效应量
- p：比例
- Δ：非劣效界值''',
        type: ReferenceType.formula,
        tags: ['样本量', '功效分析', '公式'],
        isPinned: true,
      ),
      QuickReference(
        id: 3,
        title: '统计分析前检查清单',
        category: '检验清单',
        content: '''统计分析前检查清单

□ 数据质量检查
  - 缺失值比例和模式
  - 异常值检测
  - 数据录入错误

□ 数据分布检验
  - 正态性检验（Shapiro-Wilk, Kolmogorov-Smirnov）
  - 方差齐性检验（Levene检验）
  - 直方图和Q-Q图

□ 分析方法选择
  - 研究设计类型
  - 变量类型（连续/分类）
  - 数据分布假设
  - 样本量大小

□ 假设检验前提
  - 独立性假设
  - 正态性假设
  - 方差齐性假设

□ 模型诊断
  - 残差分析
  - 多重共线性检查
  - 影响点诊断

□ 结果解释
  - 效应量报告
  - 置信区间
  - 实际意义讨论''',
        type: ReferenceType.checklist,
        tags: ['检查清单', '数据分析', '质量控制'],
        isPinned: true,
      ),
      QuickReference(
        id: 4,
        title: 'ICH E9指南摘要',
        category: 'ICH指南',
        content: '''ICH E9 临床试验统计学指导原则摘要

1. 试验设计
   - 主要目的和次要目的
   - 主要终点和次要终点
   - 样本量确定依据

2. 分析人群
   - 意向性治疗（ITT）原则
   - 符合方案（PP）人群
   - 安全性分析人群

3. 缺失数据处理
   - 缺失数据原因分析
   - 敏感性分析
   - 多重填补方法

4. 多重性问题
   - 主要终点的多重性校正
   - 次要终点的解释
   - 亚组分析的限制

5. 期中分析
   - α消耗函数
   - 独立数据监查委员会
   - 提前终止标准

6. 统计方法
   - 主要分析方法
   - 敏感性分析
   - 亚组分析''',
        type: ReferenceType.guideline,
        tags: ['ICH指南', '临床试验', '监管要求'],
        isPinned: false,
      ),
      QuickReference(
        id: 5,
        title: '常用统计检验选择速查',
        category: '速查表',
        content: '''统计检验选择速查表

连续变量比较：
- 单样本t检验：单组均值与已知值比较
- 独立样本t检验：两独立组均值比较
- 配对t检验：配对数据均值比较
- 单因素方差分析：多组均值比较
- 重复测量方差分析：重复测量数据

分类变量比较：
- 卡方检验：两组或多组比例比较
- Fisher精确检验：小样本比例比较
- McNemar检验：配对比例比较

相关分析：
- Pearson相关：连续变量线性相关
- Spearman相关：有序变量或非线性相关
- Kendall相关：有序变量相关

回归分析：
- 线性回归：连续因变量
- 逻辑回归：二分类因变量
- Cox回归：生存时间数据
- Poisson回归：计数数据

非参数检验：
- Mann-Whitney U检验：两组比较
- Wilcoxon符号秩检验：配对比较
- Kruskal-Wallis检验：多组比较
- Friedman检验：重复测量多组比较''',
        type: ReferenceType.cheatSheet,
        tags: ['统计检验', '方法选择', '速查表'],
        isPinned: false,
      ),
    ];
  }
}
