import 'package:get/get.dart';

import '../../../../core/services/api_client.dart';
import '../../../../core/values/api_endpoints.dart';
import '../../../routes/app_routes.dart';
import '../../../../shared/models/category_model.dart';
import '../../../../shared/models/concept_model.dart';

class ConceptsController extends GetxController {
  final ApiClient _apiClient = ApiClient();

  final isLoading = false.obs;
  final concepts = <Concept>[].obs;
  final filteredConcepts = <Concept>[].obs;
  final categories = <ConceptCategory>[].obs;
  final selectedCategory = '全部'.obs;
  final sortBy = 'newest'.obs;
  final searchQuery = ''.obs;

  @override
  void onInit() {
    super.onInit();
    loadConceptHub();
  }

  Future<void> loadConceptHub() async {
    isLoading.value = true;
    try {
      await Future.wait([
        loadCategories(),
        loadConcepts(),
      ]);
      _applyFilters();
    } catch (e) {
      print('加载概念失败: $e');
      concepts.value = _getMockConcepts();
      filteredConcepts.value = concepts;
    } finally {
      isLoading.value = false;
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

  void sortConcepts(String sortType) {
    sortBy.value = sortType;
    loadConcepts().then((_) => _applyFilters());
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
    final counts = tagUsage;
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final countCompare = b.value.compareTo(a.value);
        return countCompare != 0 ? countCompare : a.key.compareTo(b.key);
      });
    return entries.map((entry) => entry.key).toList();
  }

  Concept? findConceptByTitle(String title) {
    final normalized = title.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final concept in concepts) {
      if (concept.title.trim().toLowerCase() == normalized) {
        return concept;
      }
    }
    return null;
  }

  Future<Concept?> loadConceptByTitle(String title) async {
    final cleanTitle = _normalizeConceptLinkTitle(title);
    final localConcept = findConceptByTitle(cleanTitle);
    if (localConcept != null) return localConcept;

    final response = await _apiClient.get(
      '/concepts/by-title/${Uri.encodeComponent(cleanTitle)}',
    );
    if (response.statusCode == 200) {
      final concept = Concept.fromJson(response.data);
      final index = concepts.indexWhere((item) => item.id == concept.id);
      if (index >= 0) {
        concepts[index] = concept;
      } else {
        concepts.add(concept);
      }
      _applyFilters();
      return concept;
    }
    return null;
  }

  Future<void> openConceptLink(String? href) async {
    if (href == null || !href.startsWith('concept:')) return;
    final rawTitle = href.substring('concept:'.length);
    await openConceptByTitle(rawTitle);
  }

  Future<void> openConceptByTitle(String title) async {
    final cleanTitle = _normalizeConceptLinkTitle(title);
    if (cleanTitle.isEmpty) return;
    try {
      final concept = await loadConceptByTitle(cleanTitle);
      if (concept == null) {
        Get.snackbar('未找到概念', cleanTitle);
        return;
      }
      Get.toNamed(
        AppRoutes.conceptDetail,
        arguments: concept,
        preventDuplicates: false,
      );
    } catch (_) {
      Get.snackbar('未找到概念', cleanTitle);
    }
  }

  String _normalizeConceptLinkTitle(String value) {
    var title = value.trim();
    if (title.startsWith('//')) {
      title = title.substring(2);
    }
    try {
      title = Uri.decodeComponent(title);
    } catch (_) {
      title = title.replaceAll('%20', ' ');
    }
    return title.trim();
  }

  Future<List<Concept>> loadRelatedConcepts(int conceptId) async {
    final response = await _apiClient.get('/concepts/$conceptId/related');
    if (response.statusCode == 200) {
      final List<dynamic> data = response.data;
      return data.map((json) => Concept.fromJson(json)).toList();
    }
    return [];
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

    filteredConcepts.value = items;
  }

  List<Concept> _getMockConcepts() {
    return [
      Concept(
        id: 1,
        title: 'P值',
        category: '假设检验与估计',
        content: 'P值是在原假设为真的情况下，观察到当前或更极端结果的概率。',
        summary: 'P值不是原假设为真的概率，也不是效应大小。',
        tags: const ['P值', '假设检验', '统计推断'],
        updatedAt: DateTime.now().subtract(const Duration(hours: 5)),
        readCount: 0,
      ),
      Concept(
        id: 2,
        title: 'CDASH、SDTM与ADaM关系',
        category: 'CDISC与提交',
        content: 'CDASH面向采集，SDTM面向标准化提交，ADaM面向统计分析。',
        summary: '三层标准共同支持采集、提交、分析和审评追溯。',
        tags: const ['CDISC', 'SDTM', 'ADaM'],
        updatedAt: DateTime.now().subtract(const Duration(hours: 10)),
        readCount: 0,
      ),
    ];
  }
}
