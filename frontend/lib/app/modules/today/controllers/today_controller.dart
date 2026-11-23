import 'dart:typed_data';

import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../../core/services/api_client.dart';
import '../../../../core/values/api_endpoints.dart';
import '../../../../shared/models/project_model.dart';
import '../../projects/controllers/projects_controller.dart';
import '../../shell/controllers/shell_controller.dart';
import '../today_workspace.dart';

class TodayReviewCounts {
  const TodayReviewCounts({
    this.completedTodos = 0,
    this.completedChecklistItems = 0,
    this.inbox = 0,
    this.next = 0,
    this.waiting = 0,
    this.someday = 0,
  });

  final int completedTodos;
  final int completedChecklistItems;
  final int inbox;
  final int next;
  final int waiting;
  final int someday;
}

class TodayReviewStale {
  final int todoId;
  final String title;
  final int projectId;
  final String? projectName;
  final String reason;
  final DateTime? dueAt;

  const TodayReviewStale({
    required this.todoId,
    required this.title,
    required this.projectId,
    this.projectName,
    required this.reason,
    this.dueAt,
  });

  factory TodayReviewStale.fromJson(Map<String, dynamic> json) =>
      TodayReviewStale(
        todoId: json['todo_id'] ?? 0,
        title: json['title'] ?? '',
        projectId: json['project_id'] ?? 0,
        projectName: json['project_name'],
        reason: json['reason'] ?? '',
        dueAt: DateTime.tryParse(json['due_at'] ?? ''),
      );

  bool get isChecklist => reason == 'checklist_done';
}

class TodayReviewInfo {
  final TodayReviewCounts counts;
  final List<TodayReviewStale> staleOpen;
  final List<int> needsReviewProjectIds;
  final DateTime? lastReviewAt;

  const TodayReviewInfo({
    required this.counts,
    required this.staleOpen,
    required this.needsReviewProjectIds,
    this.lastReviewAt,
  });
}

class SavedFilter {
  final int id;
  final String name;
  final Map<String, dynamic> criteria;

  const SavedFilter({required this.id, required this.name, this.criteria = const {}});

  factory SavedFilter.fromJson(Map<String, dynamic> json) => SavedFilter(
        id: json['id'] ?? 0,
        name: json['name'] ?? '',
        criteria: (json['criteria'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

/// 任务参考笔记（复用 Note 表 + task_id）。
class TaskNote {
  final int id;
  final String title;
  final String content;
  final DateTime? createdAt;

  const TaskNote({
    required this.id,
    this.title = '',
    this.content = '',
    this.createdAt,
  });

  factory TaskNote.fromJson(Map<String, dynamic> json) => TaskNote(
        id: json['id'] ?? 0,
        title: json['title'] ?? '',
        content: json['content'] ?? '',
        createdAt: DateTime.tryParse(json['created_at'] ?? ''),
      );
}

/// 任务文件附件（BLOB 存储）。
class TaskAttachment {
  final int id;
  final String filename;
  final String? contentType;
  final int sizeBytes;
  final DateTime? createdAt;

  const TaskAttachment({
    required this.id,
    required this.filename,
    this.contentType,
    this.sizeBytes = 0,
    this.createdAt,
  });

  factory TaskAttachment.fromJson(Map<String, dynamic> json) => TaskAttachment(
        id: json['id'] ?? 0,
        filename: json['filename'] ?? '',
        contentType: json['content_type'],
        sizeBytes: json['size_bytes'] ?? 0,
        createdAt: DateTime.tryParse(json['created_at'] ?? ''),
      );

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

class TodayController extends GetxController {
  final _apiClient = ApiClient();
  final _projectsController = Get.find<ProjectsController>();

  final RxList<ProjectTodo> inbox = <ProjectTodo>[].obs;
  final RxList<ProjectTodo> focusTasks = <ProjectTodo>[].obs;
  final RxList<ProjectTodo> nextActions = <ProjectTodo>[].obs;
  final RxList<ProjectTodo> waiting = <ProjectTodo>[].obs;
  final RxList<ProjectTodo> calendarTasks = <ProjectTodo>[].obs;

  final RxBool loading = false.obs;
  final RxBool reviewDue = false.obs;
  final RxBool reviewLoading = false.obs;
  final RxBool capturingToInbox = false.obs;
  final RxBool mobileDrawerOpen = false.obs;

  final Rx<TodayReviewInfo?> review = Rx<TodayReviewInfo?>(null);

  // Calendar month view state.
  final Rx<DateTime> visibleMonth = Rx<DateTime>(
    DateTime(DateTime.now().year, DateTime.now().month, 1),
  );

  // Context directory (@人 / @地点).
  final RxList<String> contextPeople = <String>[].obs;
  final RxList<String> contextPlaces = <String>[].obs;

  // Global search + saved filters.
  final RxString searchQuery = ''.obs;
  final RxList<ProjectTodo> searchResults = <ProjectTodo>[].obs;
  final RxBool searching = false.obs;
  final RxList<SavedFilter> savedFilters = <SavedFilter>[].obs;

  // 当前按上下文(工作情境)筛选的标签，如 @DM / @home。
  final RxString activeContext = ''.obs;

  // Body layout: 0=列表, 1=日历, 2=看板.
  final RxInt bodyMode = 0.obs;

  // 当前选中的工作区（宽屏左栏导航）
  final Rx<TodayWorkspace> currentWorkspace = TodayWorkspace.focus.obs;

  void setBodyMode(int mode) {
    if (bodyMode.value != mode) {
      bodyMode.value = mode;
      if (mode == 1) loadCalendar();
    }
  }

  @override
  void onInit() {
    super.onInit();
    loadAll();
  }

  String get todayLabel {
    final now = DateTime.now();
    final dateStr = DateFormat('M月d日 EEEE', 'zh_CN').format(now);
    return dateStr;
  }

  List<BiostatProject> get realProjects =>
      _projectsController.projects
          .where((project) => !project.isInbox)
          .toList();

  Future<void> loadAll() async {
    loading.value = true;
    try {
      unawaitedSilent([
        loadInbox(),
        loadFocus(),
        loadNextActions(),
        loadWaiting(),
        loadReviewStatus(),
        loadCalendar(),
        loadContexts(),
        loadSavedFilters(),
      ]);
    } finally {
      loading.value = false;
    }
  }

  // ---------- inbox ----------

  Future<void> loadInbox() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.gtdInbox);
      final List<dynamic> data = response.data is List ? response.data : [];
      inbox.assignAll(data.map((json) => ProjectTodo.fromJson(json)));
    } catch (e) {
      print('加载收件箱失败: $e');
    }
  }

  Future<void> createInbox(String title, {String? description}) async {
    if (title.trim().isEmpty) return;
    capturingToInbox.value = true;
    try {
      await _apiClient.post(
        ApiEndpoints.gtdInbox,
        data: {
          'title': title.trim(),
          'description': (description == null || description.isEmpty)
              ? null
              : description,
        },
      );
      await loadInbox();
    } catch (e) {
      print('捕获失败: $e');
    } finally {
      capturingToInbox.value = false;
    }
  }

  /// GTD 处理流程：把收件箱事项移动到一个状态（并可选归入真实项目）。
  Future<void> processInbox(
    ProjectTodo todo, {
    required String action,
    int? projectId,
    String? phase,
    String? title,
    bool? isFocusedToday,
  }) async {
    final endpoint =
        ApiEndpoints.gtdInboxProcess.replaceAll('{todoId}', todo.id.toString());
    try {
      await _apiClient.post(endpoint, data: {
        'action': action,
        'project_id': projectId,
        'phase': phase,
        'title': title,
        'is_focused_today': isFocusedToday,
      });
      await loadAll();
    } catch (e) {
      print('处理收件箱失败: $e');
    }
  }

  // ---------- focus / next / waiting ----------

  Future<void> loadFocus() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.gtdFocus);
      final List<dynamic> data = response.data is List ? response.data : [];
      focusTasks.assignAll(data.map((json) => ProjectTodo.fromJson(json)));
    } catch (e) {
      print('加载专注失败: $e');
    }
  }

  Future<void> toggleFocus(ProjectTodo todo) async {
    try {
      await _apiClient.post(ApiEndpoints.gtdFocusToggle, data: {
        'todo_id': todo.id,
      });
      await loadFocus();
    } catch (e) {
      print('切换专注失败: $e');
    }
  }

  Future<void> loadNextActions() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.gtdNextActions);
      final List<dynamic> data = response.data is List ? response.data : [];
      nextActions.assignAll(data.map((json) => ProjectTodo.fromJson(json)));
    } catch (e) {
      print('加载下一步失败: $e');
    }
  }

  Future<void> loadWaiting() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.gtdWaiting);
      final List<dynamic> data = response.data is List ? response.data : [];
      waiting.assignAll(data.map((json) => ProjectTodo.fromJson(json)));
    } catch (e) {
      print('加载等待失败: $e');
    }
  }

  // ---------- calendar ----------

  /// 加载当前可见月的任务日历（含循环任务展开），并补齐当月前 6 天的空窗。
  Future<void> loadCalendar() async {
    final month = visibleMonth.value;
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0);
    final startQuery = _dateQuery(start);
    final endQuery = _dateQuery(end);
    try {
      final response = await _apiClient.get(
        ApiEndpoints.gtdCalendar,
        queryParameters: {'start': startQuery, 'end': endQuery},
      );
      final List<dynamic> data = response.data is List ? response.data : [];
      calendarTasks.assignAll(data.map((json) => ProjectTodo.fromJson(json)));
    } catch (e) {
      print('加载日历失败: $e');
    }
  }

  void shiftMonth(int delta) {
    final next = DateTime(
      visibleMonth.value.year,
      visibleMonth.value.month + delta,
      1,
    );
    visibleMonth.value = next;
    loadCalendar();
  }

  // ---------- contexts ----------

  Future<void> loadContexts() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.gtdContexts);
      final data = response.data as Map? ?? const {};
      contextPeople.assignAll((data['people'] as List? ?? const [])
          .whereType<String>()
          .toList());
      contextPlaces.assignAll((data['places'] as List? ?? const [])
          .whereType<String>()
          .toList());
    } catch (e) {
      print('加载上下文失败: $e');
    }
  }

  String _dateQuery(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  // ---------- global search + saved filters ----------

  /// 跑到通用 /gtd/tasks 上执行一次搜索/筛选（build query params 而非 body）。
  Future<void> searchTasks({String? q, Map<String, dynamic>? criteria}) async {
    final effectiveQ = q ?? searchQuery.value;
    final params = <String, dynamic>{...?criteria};
    if (effectiveQ.trim().isNotEmpty) {
      params['q'] = effectiveQ.trim();
    }
    if (params.isEmpty) {
      searchResults.clear();
      return;
    }
    searching.value = true;
    try {
      final response = await _apiClient.get(
        ApiEndpoints.gtdTasks,
        queryParameters: params,
      );
      final List<dynamic> data = response.data is List ? response.data : [];
      searchResults.assignAll(data.map((json) => ProjectTodo.fromJson(json)));
    } catch (e) {
      print('搜索失败: $e');
    } finally {
      searching.value = false;
    }
  }

  void clearSearch() {
    searchQuery.value = '';
    searchResults.clear();
    activeContext.value = '';
  }

  /// 按 @上下文 筛选全部任务（GTD 按情境工作）。
  void searchByContext(String context) {
    activeContext.value = context;
    searchQuery.value = context;
    searchTasks(criteria: {'contexts': context});
  }

  /// 统计每个 @上下文 下处于活动/等待任务数（基于已加载列表，零额外请求）。
  Map<String, int> contextCounts() {
    final counts = <String, int>{};
    for (final task in [...focusTasks, ...nextActions, ...waiting]) {
      for (final c in task.contexts) {
        counts[c] = (counts[c] ?? 0) + 1;
      }
    }
    return counts;
  }

  Future<void> loadSavedFilters() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.gtdFilters);
      final List<dynamic> data = response.data is List ? response.data : [];
      savedFilters.assignAll(
          data.map((json) => SavedFilter.fromJson(Map<String, dynamic>.from(json))));
    } catch (e) {
      print('加载筛选失败: $e');
    }
  }

  Future<void> applySavedFilter(SavedFilter filter) async {
    await searchTasks(criteria: Map<String, dynamic>.from(filter.criteria));
  }

  Future<void> saveCurrentFilter(String name) async {
    final criteria = <String, dynamic>{};
    final q = searchQuery.value.trim();
    if (q.isNotEmpty) criteria['q'] = q;
    if (criteria.isEmpty) return;
    try {
      await _apiClient.post(
        ApiEndpoints.gtdFilters,
        data: {'name': name, 'criteria': criteria},
      );
      await loadSavedFilters();
    } catch (e) {
      print('保存筛选失败: $e');
    }
  }

  Future<void> deleteSavedFilter(SavedFilter filter) async {
    try {
      await _apiClient.delete(
        ApiEndpoints.gtdFilterDetail.replaceAll(
            '{filterId}', filter.id.toString()));
      savedFilters.removeWhere((f) => f.id == filter.id);
    } catch (e) {
      print('删除筛选失败: $e');
    }
  }

  // ---------- weekly review ----------

  Future<void> loadReviewStatus() async {
    try {
      final response = await _apiClient.get(ApiEndpoints.gtdReviewStatus);
      reviewDue.value = response.data['due'] == true;
    } catch (e) {
      print('检查回顾状态失败: $e');
    }
  }

  Future<void> runWeeklyReview() async {
    reviewLoading.value = true;
    try {
      final response = await _apiClient.get(ApiEndpoints.gtdReviewWeekly);
      final data = response.data;
      final countsJson =
          (data['counts'] as Map?)?.cast<String, dynamic>() ?? const {};
      final staleJson =
          (data['stale_open'] as List?)?.cast<Map>() ?? const <Map>[];
      final needsJson =
          (data['needs_review'] as List?)?.cast<Map>() ?? const <Map>[];
      review.value = TodayReviewInfo(
        counts: TodayReviewCounts(
          completedTodos: countsJson['completed_todos'] ?? 0,
          completedChecklistItems: countsJson['completed_checklist_items'] ?? 0,
          inbox: countsJson['inbox'] ?? 0,
          next: countsJson['next'] ?? 0,
          waiting: countsJson['waiting'] ?? 0,
          someday: countsJson['someday'] ?? 0,
        ),
        staleOpen: staleJson
            .map((json) => TodayReviewStale.fromJson(
                Map<String, dynamic>.from(json)))
            .toList(),
        needsReviewProjectIds: needsJson
            .map((json) => json['project_id'] is int ? json['project_id'] as int : 0)
            .toList(),
      );
      reviewDue.value = false;
    } catch (e) {
      print('每周回顾失败: $e');
    } finally {
      reviewLoading.value = false;
    }
  }

  // ---------- task notes + attachments (参考笔记 / 文件附件) ----------

  /// 拉取任务参考笔记，结果以 (notes, ok) 返回。
  Future<List<TaskNote>> loadTaskNotes(int todoId) async {
    try {
      final endpoint =
          ApiEndpoints.gtdTaskNotes.replaceAll('{todoId}', todoId.toString());
      final response = await _apiClient.get(endpoint);
      final List<dynamic> data = response.data is List ? response.data : [];
      return data.map((json) => TaskNote.fromJson(Map<String, dynamic>.from(json))).toList();
    } catch (e) {
      print('加载任务笔记失败: $e');
      return const [];
    }
  }

  Future<void> addTaskNote(int todoId, {String title = '', String content = ''}) async {
    if (content.trim().isEmpty && title.trim().isEmpty) return;
    try {
      final endpoint =
          ApiEndpoints.gtdTaskNotes.replaceAll('{todoId}', todoId.toString());
      await _apiClient.post(endpoint, data: {
        'title': title.trim(),
        'content': content.trim(),
      });
    } catch (e) {
      print('添加任务笔记失败: $e');
    }
  }

  Future<bool> deleteTaskNote(int noteId) async {
    try {
      final endpoint =
          ApiEndpoints.gtdNoteDetail.replaceAll('{noteId}', noteId.toString());
      await _apiClient.delete(endpoint);
      return true;
    } catch (e) {
      print('删除任务笔记失败: $e');
      return false;
    }
  }

  /// 拉取任务附件列表。
  Future<List<TaskAttachment>> loadTaskAttachments(int todoId) async {
    try {
      final endpoint = ApiEndpoints.gtdTaskAttachments
          .replaceAll('{todoId}', todoId.toString());
      final response = await _apiClient.get(endpoint);
      final List<dynamic> data = response.data is List ? response.data : [];
      return data
          .map((json) => TaskAttachment.fromJson(Map<String, dynamic>.from(json)))
          .toList();
    } catch (e) {
      print('加载任务附件失败: $e');
      return const [];
    }
  }

  Future<bool> uploadTaskAttachment(int todoId,
      {required List<int> bytes, required String filename}) async {
    if (bytes.isEmpty) return false;
    try {
      final endpoint = ApiEndpoints.gtdTaskAttachments
          .replaceAll('{todoId}', todoId.toString());
      await _apiClient.upload(endpoint, bytes: bytes, filename: filename);
      return true;
    } catch (e) {
      print('上传附件失败: $e');
      return false;
    }
  }

  /// 下载附件原始字节，供保存到本地。filename 用于落盘命名。
  Future<Uint8List?> downloadTaskAttachment(int attachmentId) async {
    try {
      final endpoint = ApiEndpoints.gtdAttachmentDownload
          .replaceAll('{attachmentId}', attachmentId.toString());
      final bytes = await _apiClient.downloadBytes(endpoint);
      return Uint8List.fromList(bytes);
    } catch (e) {
      print('下载附件失败: $e');
      return null;
    }
  }

  Future<bool> deleteTaskAttachment(int attachmentId) async {
    try {
      final endpoint = ApiEndpoints.gtdAttachmentDetail
          .replaceAll('{attachmentId}', attachmentId.toString());
      await _apiClient.delete(endpoint);
      return true;
    } catch (e) {
      print('删除附件失败: $e');
      return false;
    }
  }

  // ---------- task actions (delegated to projects) ----------

  /// 在 GTD 里完成/改状态，复用统一的 updateTodo。
  Future<void> updateTaskStatus(ProjectTodo todo, String status) async {
    await _projectsController.updateTodo(todo, status: status);
    await loadAll();
  }

  /// 在 GTD 里勾选/取消清单项，清单自动派生状态，然后刷新。
  Future<void> toggleChecklistItem(ProjectChecklistItem item) async {
    await _projectsController.toggleChecklistItem(item);
    await loadAll();
  }

  Future<void> toggleFocusedToday(ProjectTodo todo) async {
    await _projectsController.updateTodo(todo, isFocusedToday: !todo.isFocusedToday);
    await loadAll();
  }

  void openTask(ProjectTodo todo) {
    if (todo.projectId == 0) return;
    // 打开真实项目详情，并切到项目库 Tab。
    Get.find<ShellController>().switchTab(1);
    _projectsController.openProjectAtTodo(
      BiostatProject(
        id: todo.projectId,
        name: todo.projectName.isEmpty ? '项目' : todo.projectName,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      todo,
    );
  }

  void unawaitedSilent(List<Future<void>> futures) {
    for (final future in futures) {
      future.catchError((_) {});
    }
  }
}
