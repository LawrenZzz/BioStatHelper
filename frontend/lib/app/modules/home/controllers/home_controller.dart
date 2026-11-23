import 'package:get/get.dart';

import '../../../../core/services/api_client.dart';
import '../../../../core/values/api_endpoints.dart';
import '../../../../shared/models/category_model.dart';
import '../../../../shared/models/concept_model.dart';

class HomeController extends GetxController {
  final ApiClient _apiClient = ApiClient();

  final isLoading = false.obs;
  final concepts = <Concept>[].obs;
  final visibleConcepts = <Concept>[].obs;
  final categories = <ConceptCategory>[].obs;
  final selectedCategory = '全部'.obs;
  final searchQuery = ''.obs;
  final sortBy = 'popular'.obs;
  final conceptTotal = 0.obs;

  // 学习进度（接 /statistics/progress）
  final completedVideos = 0.obs;
  final totalVideos = 0.obs;
  final completedConcepts = 0.obs;
  final totalConcepts = 0.obs;
  final studyHours = 0.0.obs;
  final streakDays = 0.obs;
  final hasProgress = false.obs;

  @override
  void onInit() {
    super.onInit();
    loadKnowledgeHome();
  }

  Future<void> loadKnowledgeHome() async {
    isLoading.value = true;
    try {
      await Future.wait([
        loadCategories(),
        loadConcepts(),
        loadLearningProgress(),
      ]);
      _applyFilters();
    } catch (e) {
      print('加载知识库首页失败: $e');
      concepts.value = _getFallbackConcepts();
      visibleConcepts.value = concepts;
      conceptTotal.value = concepts.length;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadLearningProgress() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.learningProgress);
      final data = response.data;
      completedVideos.value = data['completed_videos'] ?? 0;
      totalVideos.value = data['total_videos'] ?? 0;
      completedConcepts.value = data['completed_concepts'] ?? 0;
      totalConcepts.value = data['total_concepts'] ?? 0;
      studyHours.value = (data['study_hours'] as num?)?.toDouble() ?? 0;
      streakDays.value = data['streak_days'] ?? 0;
      hasProgress.value = true;
    } catch (e) {
      hasProgress.value = false;
    }
  }

  Future<void> loadCategories() async {
    final response = await _apiClient.get(ApiEndpoints.conceptCategories);
    if (response.statusCode == 200) {
      final List<dynamic> data = response.data;
      categories.value =
          data.map((json) => ConceptCategory.fromJson(json)).toList();
    }
  }

  Future<void> loadConcepts() async {
    final response = await _apiClient.get(
      ApiEndpoints.concepts,
      queryParameters: {
        'limit': 1000,
        'sort': sortBy.value,
      },
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = response.data['data'];
      concepts.value = data.map((json) => Concept.fromJson(json)).toList();
      conceptTotal.value = response.data['total'] ?? concepts.length;
    }
  }

  void updateSearchQuery(String query) {
    searchQuery.value = query;
    _applyFilters();
  }

  void filterByCategory(String category) {
    selectedCategory.value = category;
    _applyFilters();
  }

  void changeSort(String sort) {
    sortBy.value = sort;
    loadConcepts().then((_) => _applyFilters());
  }

  int get totalConceptCount =>
      conceptTotal.value == 0 ? concepts.length : conceptTotal.value;

  int get categoryCount => categories.length;

  int get tagCount => concepts
      .expand((concept) => concept.tags)
      .where((tag) => tag.trim().isNotEmpty)
      .toSet()
      .length;

  List<String> get hotTags {
    final entries = tagUsage.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(10).map((entry) => entry.key).toList();
  }

  Map<String, int> get tagUsage {
    final counts = <String, int>{};
    for (final concept in concepts) {
      for (final rawTag in concept.tags) {
        final tag = rawTag.trim();
        if (tag.isNotEmpty) {
          counts[tag] = (counts[tag] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  List<String> get allTags {
    final entries = tagUsage.entries.toList()
      ..sort((a, b) {
        final countCompare = b.value.compareTo(a.value);
        return countCompare != 0 ? countCompare : a.key.compareTo(b.key);
      });
    return entries.map((entry) => entry.key).toList();
  }

  void _applyFilters() {
    final query = searchQuery.value.trim().toLowerCase();
    final category = selectedCategory.value;
    var items = concepts.where((concept) {
      final matchesCategory = category == '全部' || concept.category == category;
      final matchesQuery = query.isEmpty ||
          concept.title.toLowerCase().contains(query) ||
          concept.summary.toLowerCase().contains(query) ||
          concept.content.toLowerCase().contains(query) ||
          concept.tags.any((tag) => tag.toLowerCase().contains(query));
      return matchesCategory && matchesQuery;
    }).toList();

    if (sortBy.value == 'newest') {
      items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } else {
      items.sort((a, b) => b.readCount.compareTo(a.readCount));
    }

    visibleConcepts.value = items;
  }

  List<Concept> _getFallbackConcepts() {
    return [
      Concept(
        id: 1,
        title: 'P值',
        category: '假设检验与估计',
        content: 'P值是在原假设成立时，观察到当前或更极端结果的概率。',
        summary: 'P值需要与效应量、置信区间和临床意义一起解释。',
        tags: const ['P值', '假设检验', '统计推断'],
        updatedAt: DateTime.now(),
        readCount: 0,
      ),
      Concept(
        id: 2,
        title: 'SAP统计分析计划',
        category: '临床试验统计',
        content: 'SAP把方案中的统计原则转化为可执行的分析规则和TFL输出规范。',
        summary: 'SAP应在揭盲或锁库前定稿，降低选择性分析风险。',
        tags: const ['SAP', 'TFL', '临床试验'],
        updatedAt: DateTime.now(),
        readCount: 0,
      ),
    ];
  }
}
