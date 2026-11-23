import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../../../core/services/api_client.dart';
import '../../../../core/services/device_integration_service.dart';
import '../../../../core/values/api_endpoints.dart';
import '../../../routes/app_routes.dart';
import '../../../../shared/models/project_model.dart';

class ProjectsController extends GetxController {
  final ApiClient _apiClient = ApiClient();

  static const List<String> _workflowPhaseOrder = [
    '项目启动',
    'SAP与TFL',
    '数据管理DM',
    'CDISC与数据集',
    '分析数据集与编程',
    '统计编程与输出',
    '盲态审阅',
    '锁库与揭盲',
    'SAR统计分析报告',
    'CSR与提交',
  ];

  final isLoading = false.obs;
  final projects = <BiostatProject>[].obs;
  final searchQuery = ''.obs;

  List<BiostatProject> get filteredProjects {
    final query = searchQuery.value.trim().toLowerCase();
    if (query.isEmpty) return projects.toList();
    return projects.where((project) {
      final haystack = [
        project.name,
        project.protocolNo,
        project.sponsor,
        project.phase,
        project.indication,
        project.description,
        projectTypeLabel(project.projectType),
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }
  final allTodos = <ProjectTodo>[].obs;
  final selectedProject = Rxn<BiostatProject>();
  final phases = <ProjectPhase>[].obs;
  final todos = <ProjectTodo>[].obs;
  final meetings = <ProjectMeeting>[].obs;
  final members = <ProjectMember>[].obs;
  final timelineImports = <ProjectTimelineImport>[].obs;
  final agentMessages = <ProjectAgentMessage>[].obs;
  final activeTab = 'standard'.obs;

  @override
  void onInit() {
    super.onInit();
    loadProjects();
  }

  Future<void> loadProjects() async {
    isLoading.value = true;
    try {
      final response = await _apiClient.get(ApiEndpoints.projects);
      final List<dynamic> data = response.data['data'];
      projects.value =
          data.map((json) => BiostatProject.fromJson(json)).toList();

      if (selectedProject.value != null) {
        final refreshed = projects.firstWhereOrNull(
          (project) => project.id == selectedProject.value!.id,
        );
        if (refreshed != null) {
          selectedProject.value = refreshed;
        }
      }

      await loadSummaryTodos();
    } catch (e) {
      print('加载项目失败: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> loadSummaryTodos() async {
    final summary = <ProjectTodo>[];
    for (final project in projects) {
      try {
        final endpoint =
            ApiEndpoints.projectTodos.replaceAll('{id}', project.id.toString());
        final response = await _apiClient.get(endpoint);
        final List<dynamic> data = response.data['data'];
        summary.addAll(data.map((json) => ProjectTodo.fromJson(json)));
      } catch (_) {}
    }
    allTodos.value = summary;
  }

  Future<void> openProject(BiostatProject project) async {
    Get.toNamed(AppRoutes.projectDetail, arguments: project);
  }

  Future<void> openProjectAtTodo(
    BiostatProject project,
    ProjectTodo todo,
  ) async {
    activeTab.value = 'standard';
    Get.toNamed(
      AppRoutes.projectDetail,
      arguments: ProjectTodoFocus(
        project: project,
        todoId: todo.id,
      ),
    );
  }

  Future<void> selectProject(BiostatProject project) async {
    selectedProject.value = project;
    agentMessages.clear();
    await Future.wait([
      loadPhases(),
      loadTodos(),
      loadMeetings(),
      loadMembers(),
      loadTimelineImports(),
      loadAgentMessages(),
    ]);
  }

  Future<void> loadPhases() async {
    final projectId = selectedProject.value?.id;
    if (projectId == null) return;
    final endpoint = ApiEndpoints.projectPhases.replaceAll(
        '{id}', projectId.toString());
    final response = await _apiClient.get(endpoint);
    if (selectedProject.value?.id != projectId) return; // 已切走，丢弃过期响应
    final List<dynamic> data = response.data['data'];
    phases.value = data.map((json) => ProjectPhase.fromJson(json)).toList();
  }

  Future<BiostatProject> createProject(
    String name, {
    String protocolNo = '',
    String phase = '',
    String sponsor = '',
    String projectType = 'other',
    bool isCdisc = false,
    String indication = '',
    String description = '',
  }) async {
    debugPrint('[createProject] 开始创建项目 name=$name '
        'protocolNo=$protocolNo phase=$phase sponsor=$sponsor '
        'projectType=$projectType isCdisc=$isCdisc');
    try {
      final response = await _apiClient.post(
        ApiEndpoints.projects,
        data: {
          'name': name,
          'protocol_no': protocolNo.isEmpty ? null : protocolNo,
          'phase': phase.isEmpty ? null : phase,
          'sponsor': sponsor.isEmpty ? null : sponsor,
          'project_type': projectType,
          'is_cdisc': isCdisc,
          'indication': indication.isEmpty ? null : indication,
          'description': description.isEmpty ? null : description,
          'create_standard_workflow': true,
        },
        timeout: const Duration(seconds: 45),
      );
      debugPrint('[createProject] 服务端返回 status=${response.statusCode} data=${response.data}');
      final project = BiostatProject.fromJson(response.data);
      debugPrint('[createProject] 解析成功 projectId=${project.id} name=${project.name}');
      await loadProjects();
      return project;
    } on ApiException catch (error) {
      debugPrint('[createProject] 请求异常 message=$error status=${error.statusCode} '
          'type=${error.type} uri=${error.requestUri}');
      if (!error.isTimeout) rethrow;
      await loadProjects();
      final existing = projects.firstWhereOrNull((item) => item.name == name);
      if (existing != null) {
        debugPrint('[createProject] 请求超时但服务端已创建 projectId=${existing.id}');
        return existing;
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> draftProjectIntake(String text) async {
    final requestId = DateTime.now().toIso8601String();
    debugPrint('[AI][intake][$requestId] request length=${text.trim().length} '
        'endpoint=${ApiEndpoints.projectIntakeDraft}');
    try {
      final response = await _apiClient.post(
        ApiEndpoints.projectIntakeDraft,
        data: {'text': text.trim(), 'create_standard_workflow': true},
        timeout: const Duration(seconds: 45),
      );
      final result = Map<String, dynamic>.from(response.data as Map);
      debugPrint('[AI][intake][$requestId] response status=${response.statusCode} '
          'model=${result['model_used']} fallback=${result['fallback_used']} '
          'error=${result['error']} debugId=${result['debug_id']} '
          'rawType=${result['raw']?.runtimeType} rawKeys='
          '${result['raw'] is Map ? (result['raw'] as Map).keys.toList() : []} '
          'name=${result['name']} todos=${(result['todos'] as List?)?.length ?? 0}');
      return result;
    } on ApiException catch (error) {
      debugPrint('[AI][intake][$requestId] error status=${error.statusCode} '
          'type=${error.type} timeout=${error.isTimeout} uri=${error.requestUri} '
          'message=$error');
      rethrow;
    } catch (error, stack) {
      debugPrint('[AI][intake][$requestId] unexpected error=$error\\n$stack');
      rethrow;
    }
  }

  Future<BiostatProject> createProjectFromIntake({
    required String text,
    required Map<String, dynamic> draft,
  }) async {
    debugPrint('[createProjectFromIntake] 开始创建 textLength=${text.length} draftKeys=${draft.keys.toList()}');
    try {
      final response = await _apiClient.post(
        ApiEndpoints.projectIntakeCreate,
        data: {
          ...draft,
          'text': text.trim(),
          'create_standard_workflow': true,
        },
        timeout: const Duration(seconds: 45),
      );
      final responseData = Map<String, dynamic>.from(response.data as Map);
      debugPrint('[AI][intakeCreate] status=${response.statusCode} '
          'model=${responseData['model_used']} fallback=${responseData['fallback_used']} '
          'error=${responseData['error']} debugId=${responseData['debug_id']} '
          'createdTodoCount=${responseData['created_todo_count']}');
      final project = BiostatProject.fromJson(
        Map<String, dynamic>.from(responseData['project'] as Map),
      );
      await loadProjects();
      return project;
    } on ApiException catch (error) {
      debugPrint('[createProjectFromIntake] 请求异常 message=$error '
          'status=${error.statusCode} type=${error.type} uri=${error.requestUri}');
      if (!error.isTimeout) rethrow;
      await loadProjects();
      final name = (draft['name'] ?? '').toString().trim();
      final existing = name.isEmpty
          ? null
          : projects.firstWhereOrNull((item) => item.name == name);
      if (existing != null) {
        debugPrint('[createProjectFromIntake] 请求超时但服务端已创建 projectId=${existing.id}');
        return existing;
      }
      rethrow;
    }
  }

  Future<BiostatProject?> updateProject(
    BiostatProject project, {
    required String name,
    String protocolNo = '',
    String phase = '',
    String sponsor = '',
    String projectType = 'other',
    bool isCdisc = false,
    String indication = '',
    String description = '',
    String status = 'active',
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return null;
    final endpoint =
        ApiEndpoints.projectDetail.replaceAll('{id}', project.id.toString());
    final response = await _apiClient.put(
      endpoint,
      data: {
        'name': trimmedName,
        'protocol_no': protocolNo.trim().isEmpty ? null : protocolNo.trim(),
        'phase': phase.trim().isEmpty ? null : phase.trim(),
        'sponsor': sponsor.trim().isEmpty ? null : sponsor.trim(),
        'project_type': projectType,
        'is_cdisc': isCdisc,
        'indication': indication.trim().isEmpty ? null : indication.trim(),
        'description': description.trim().isEmpty ? null : description.trim(),
        'status': status,
      },
    );
    final updated = BiostatProject.fromJson(response.data);
    final index = projects.indexWhere((item) => item.id == updated.id);
    if (index >= 0) {
      projects[index] = updated;
      projects.refresh();
    }
    selectedProject.value = updated;
    await refreshWorkspace();
    return selectedProject.value ?? updated;
  }

  Future<void> deleteProject(BiostatProject project) async {
    final endpoint =
        ApiEndpoints.projectDetail.replaceAll('{id}', project.id.toString());
    await _apiClient.delete(
      endpoint,
      queryParameters: {'confirm_name': project.name},
    );
    projects.removeWhere((item) => item.id == project.id);
    allTodos.removeWhere((item) => item.projectId == project.id);
    if (selectedProject.value?.id == project.id) {
      selectedProject.value = null;
      phases.clear();
      todos.clear();
      meetings.clear();
      agentMessages.clear();
      activeTab.value = 'standard';
    }
    await loadProjects();
  }

  Future<void> loadTodos() async {
    final projectId = selectedProject.value?.id;
    if (projectId == null) return;
    final endpoint =
        ApiEndpoints.projectTodos.replaceAll('{id}', projectId.toString());
    final response = await _apiClient.get(endpoint);
    if (selectedProject.value?.id != projectId) return; // 已切走，丢弃过期响应
    final List<dynamic> data = response.data['data'];
    todos.value = data.map((json) => ProjectTodo.fromJson(json)).toList();
  }

  Future<void> loadMeetings() async {
    final projectId = selectedProject.value?.id;
    if (projectId == null) return;
    final endpoint =
        ApiEndpoints.projectMeetings.replaceAll('{id}', projectId.toString());
    final response = await _apiClient.get(endpoint);
    if (selectedProject.value?.id != projectId) return; // 已切走，丢弃过期响应
    final List<dynamic> data = response.data['data'];
    meetings.value = data.map((json) => ProjectMeeting.fromJson(json)).toList();
  }

  Future<void> loadMembers() async {
    final projectId = selectedProject.value?.id;
    if (projectId == null) return;
    final endpoint =
        ApiEndpoints.projectMembers.replaceAll('{id}', projectId.toString());
    final response = await _apiClient.get(endpoint);
    if (selectedProject.value?.id != projectId) return; // 已切走，丢弃过期响应
    final List<dynamic> data = response.data['data'];
    members.value = data
        .map((json) => ProjectMember.fromJson(
              Map<String, dynamic>.from(json as Map),
            ))
        .toList();
  }

  Future<void> loadTimelineImports() async {
    final projectId = selectedProject.value?.id;
    if (projectId == null) return;
    final endpoint =
        ApiEndpoints.projectTimeline.replaceAll('{id}', projectId.toString());
    final response = await _apiClient.get(endpoint);
    if (selectedProject.value?.id != projectId) return; // 已切走，丢弃过期响应
    final List<dynamic> data = response.data['data'];
    timelineImports.value = data
        .map((json) => ProjectTimelineImport.fromJson(
              Map<String, dynamic>.from(json as Map),
            ))
        .toList();
  }

  Future<void> createMember({
    required String memberType,
    required String name,
    String organization = '',
    String role = '',
    String email = '',
    String phone = '',
    String notes = '',
  }) async {
    final project = selectedProject.value;
    if (project == null || name.trim().isEmpty) return;
    final endpoint =
        ApiEndpoints.projectMembers.replaceAll('{id}', project.id.toString());
    await _apiClient.post(endpoint, data: {
      'member_type': memberType,
      'name': name.trim(),
      'organization': organization.trim().isEmpty ? null : organization.trim(),
      'role': role.trim().isEmpty ? null : role.trim(),
      'email': email.trim().isEmpty ? null : email.trim(),
      'phone': phone.trim().isEmpty ? null : phone.trim(),
      'notes': notes.trim().isEmpty ? null : notes.trim(),
    });
    await loadMembers();
  }

  Future<void> updateMember(
    ProjectMember member, {
    required String memberType,
    required String name,
    String organization = '',
    String role = '',
    String email = '',
    String phone = '',
    String notes = '',
  }) async {
    await _apiClient.put(
      ApiEndpoints.projectMemberDetail
          .replaceAll('{memberId}', member.id.toString()),
      data: {
        'member_type': memberType,
        'name': name.trim(),
        'organization':
            organization.trim().isEmpty ? null : organization.trim(),
        'role': role.trim().isEmpty ? null : role.trim(),
        'email': email.trim().isEmpty ? null : email.trim(),
        'phone': phone.trim().isEmpty ? null : phone.trim(),
        'notes': notes.trim().isEmpty ? null : notes.trim(),
      },
    );
    await loadMembers();
  }

  Future<void> deleteMember(ProjectMember member) async {
    await _apiClient.delete(
      ApiEndpoints.projectMemberDetail
          .replaceAll('{memberId}', member.id.toString()),
    );
    members.removeWhere((item) => item.id == member.id);
  }

  Future<void> parseMembers(String text) async {
    final project = selectedProject.value;
    if (project == null || text.trim().isEmpty) return;
    final endpoint = ApiEndpoints.projectMemberParse
        .replaceAll('{id}', project.id.toString());
    final response = await _apiClient.post(endpoint,
        data: {
          'text': text.trim(),
          'create_records': true,
        },
        timeout: const Duration(seconds: 45));
    await loadMembers();
    final count =
        response.data is Map ? response.data['created_count'] ?? 0 : 0;
    Get.snackbar('项目成员', '已识别并保存 $count 条成员信息');
  }

  Future<ProjectTimelineImport?> importTimelineText(String text) async {
    final project = selectedProject.value;
    if (project == null || text.trim().isEmpty) return null;
    final endpoint = ApiEndpoints.projectTimelineText
        .replaceAll('{id}', project.id.toString());
    final response = await _apiClient.post(
      endpoint,
      data: {'source_text': text.trim()},
      timeout: const Duration(seconds: 90),
    );
    final imported = ProjectTimelineImport.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
    await refreshWorkspace();
    return imported;
  }

  Future<ProjectTimelineImport?> importTimelineFile(
    List<int> bytes,
    String filename,
  ) async {
    final project = selectedProject.value;
    if (project == null || bytes.isEmpty) return null;
    final endpoint = ApiEndpoints.projectTimelineFile
        .replaceAll('{id}', project.id.toString());
    final response = await _apiClient.upload(
      endpoint,
      bytes: bytes,
      filename: filename,
      timeout: const Duration(seconds: 90),
    );
    final imported = ProjectTimelineImport.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
    await refreshWorkspace();
    return imported;
  }

  Future<void> updateTimelineItem(
    ProjectTimelineItem item, {
    String? targetType,
    int? todoId,
    int? checklistItemId,
    DateTime? startAt,
    DateTime? dueAt,
    bool clearStartAt = false,
    bool clearDueAt = false,
  }) async {
    final endpoint = ApiEndpoints.projectTimelineItem
        .replaceAll('{itemId}', item.id.toString());
    final data = <String, dynamic>{
      'start_at':
          clearStartAt ? null : (startAt ?? item.startAt)?.toIso8601String(),
      'due_at': clearDueAt ? null : (dueAt ?? item.dueAt)?.toIso8601String(),
    };
    if (targetType != null || todoId != null || checklistItemId != null) {
      data.addAll({
        'target_type': targetType ?? item.targetType,
        'matched_todo_id': targetType == 'todo' ? todoId : null,
        'matched_checklist_item_id':
            targetType == 'checklist' ? checklistItemId : null,
      });
    }
    await _apiClient.put(endpoint, data: data);
    await refreshWorkspace();
  }

  Future<void> deleteTimelineImport(ProjectTimelineImport timeline) async {
    await _apiClient.delete(ApiEndpoints.projectTimelineDetail
        .replaceAll('{timelineId}', timeline.id.toString()));
    timelineImports.removeWhere((item) => item.id == timeline.id);
  }

  Future<void> loadAgentMessages() async {
    final projectId = selectedProject.value?.id;
    if (projectId == null) return;
    final endpoint = ApiEndpoints.projectAgentMessages
        .replaceAll('{id}', projectId.toString());
    try {
      final response = await _apiClient.get(endpoint);
      if (selectedProject.value?.id != projectId) return; // 已切走，丢弃过期响应
      final List<dynamic> data = response.data['data'];
      agentMessages.value = data
          .map((json) => ProjectAgentMessage.fromJson(
                Map<String, dynamic>.from(json as Map),
              ))
          .toList();
    } on ApiException catch (error) {
      if (error.statusCode != 404) rethrow;
      agentMessages.clear();
    }
  }

  Future<ProjectTodo?> createTodo(
    String title, {
    String description = '',
    String todoType = 'extra',
    String phase = '',
    DateTime? startAt,
    DateTime? dueAt,
    List<String> checklistItems = const [],
    String status = 'next',
    String priority = 'normal',
    List<String> contexts = const [],
    List<String> tags = const [],
    String area = '',
    String energyLevel = '',
    int? timeEstimate,
    bool isFocusedToday = false,
  }) async {
    final project = selectedProject.value;
    if (project == null) return null;
    final endpoint =
        ApiEndpoints.projectTodos.replaceAll('{id}', project.id.toString());
    final response = await _apiClient.post(
      endpoint,
      data: {
        'title': title,
        'description': description.isEmpty ? null : description,
        'todo_type': todoType,
        'phase': phase.isEmpty ? null : phase,
        'status': status,
        'priority': priority,
        'start_at': startAt?.toIso8601String(),
        'due_at': dueAt?.toIso8601String(),
        'contexts': contexts.isEmpty ? null : contexts,
        'tags': tags.isEmpty ? null : tags,
        'area': area.isEmpty ? null : area,
        'energy_level': energyLevel.isEmpty ? null : energyLevel,
        'time_estimate': timeEstimate,
        'is_focused_today': isFocusedToday,
        'checklist_items': checklistItems
            .where((item) => item.trim().isNotEmpty)
            .map((item) => {'title': item.trim()})
            .toList(),
      },
    );
    final created = ProjectTodo.fromJson(response.data);
    await refreshWorkspace();
    return created;
  }

  Future<ProjectTodo?> updateTodo(
    ProjectTodo todo, {
    String? title,
    String? description,
    String? status,
    String? phase,
    String? priority,
    DateTime? startAt,
    DateTime? dueAt,
    List<String>? contexts,
    String? area,
    String? energyLevel,
    int? timeEstimate,
    bool? isFocusedToday,
    bool clearStartAt = false,
    bool clearDueAt = false,
  }) async {
    final data = <String, dynamic>{};
    if (title != null) data['title'] = title;
    if (description != null) data['description'] = description;
    if (status != null) data['status'] = status;
    if (phase != null) data['phase'] = phase.isEmpty ? null : phase;
    if (priority != null) data['priority'] = priority;
    if (contexts != null) data['contexts'] = contexts;
    if (area != null) data['area'] = area.isEmpty ? null : area;
    if (energyLevel != null) {
      data['energy_level'] = energyLevel.isEmpty ? null : energyLevel;
    }
    if (timeEstimate != null) data['time_estimate'] = timeEstimate;
    if (isFocusedToday != null) data['is_focused_today'] = isFocusedToday;
    if (clearStartAt) {
      data['start_at'] = null;
    } else if (startAt != null) {
      data['start_at'] = startAt.toIso8601String();
    }
    if (clearDueAt) {
      data['due_at'] = null;
    } else if (dueAt != null) {
      data['due_at'] = dueAt.toIso8601String();
    }
    final response =
        await _apiClient.put('/projects/todos/${todo.id}', data: data);
    final updated = ProjectTodo.fromJson(response.data);
    await refreshWorkspace();
    return updated;
  }

  /// Toggle whether a task sits on today's Focus list.
  Future<void> toggleFocusToday(ProjectTodo todo) async {
    await updateTodo(todo, isFocusedToday: !todo.isFocusedToday);
  }

  /// One-tap compact status change from a task card / project detail.
  Future<void> setTodoStatus(ProjectTodo todo, String status) async {
    await updateTodo(todo, status: status);
  }

  /// Quick-add a task into a project's 流程待办 bucket without opening a dialog.
  Future<ProjectTodo?> quickAddTodo(
    BiostatProject project,
    String title,
  ) async {
    if (title.trim().isEmpty) return null;
    final currentProject = selectedProject.value;
    // quickAdd targets a specific project regardless of the selected one.
    selectedProject.value = project;
    try {
      return await createTodo(
        title.trim(),
        phase: '流程待办',
        status: 'next',
      );
    } finally {
      // restore whatever was selected
      if (currentProject != null) selectedProject.value = currentProject;
    }
  }

  Future<void> toggleTodo(ProjectTodo todo) async {
    await updateTodo(todo, status: todo.isDone ? 'next' : 'done');
  }

  Future<void> deleteTodo(ProjectTodo todo) async {
    await _apiClient.delete('/projects/todos/${todo.id}');
    await refreshWorkspace();
  }

  Future<void> addChecklistItem(
    ProjectTodo todo,
    String title, {
    DateTime? dueAt,
    int? meetingId,
  }) async {
    if (title.trim().isEmpty) return;
    final endpoint = ApiEndpoints.projectTodoChecklist
        .replaceAll('{todoId}', todo.id.toString());
    await _apiClient.post(
      endpoint,
      data: {
        'title': title.trim(),
        'due_at': dueAt?.toIso8601String(),
        'meeting_id': meetingId,
      },
    );
    await refreshWorkspace();
  }

  Future<void> updateChecklistItem(
    ProjectChecklistItem item, {
    String? title,
    bool? isDone,
    DateTime? dueAt,
    int? meetingId,
    bool clearDueAt = false,
    bool clearMeeting = false,
  }) async {
    final endpoint = ApiEndpoints.projectChecklistItem
        .replaceAll('{itemId}', item.id.toString());
    final data = <String, dynamic>{};
    if (title != null) data['title'] = title;
    if (isDone != null) data['is_done'] = isDone;
    if (clearDueAt) {
      data['due_at'] = null;
    } else if (dueAt != null) {
      data['due_at'] = dueAt.toIso8601String();
    }
    if (clearMeeting) {
      data['meeting_id'] = null;
    } else if (meetingId != null) {
      data['meeting_id'] = meetingId;
    }
    await _apiClient.put(endpoint, data: data);
    await refreshWorkspace();
  }

  Future<void> toggleChecklistItem(ProjectChecklistItem item) async {
    await updateChecklistItem(item, isDone: !item.isDone);
  }

  Future<void> deleteChecklistItem(ProjectChecklistItem item) async {
    final endpoint = ApiEndpoints.projectChecklistItem
        .replaceAll('{itemId}', item.id.toString());
    await _apiClient.delete(endpoint);
    await refreshWorkspace();
  }

  Future<ProjectMeeting?> createMeeting(
    String title, {
    String url = '',
    String agenda = '',
    DateTime? startsAt,
    DateTime? endsAt,
    int? bindChecklistItemId,
  }) async {
    final project = selectedProject.value;
    if (project == null) return null;
    final endpoint =
        ApiEndpoints.projectMeetings.replaceAll('{id}', project.id.toString());
    final response = await _apiClient.post(
      endpoint,
      data: {
        'title': title,
        'meeting_url': url.isEmpty ? null : url,
        'agenda': agenda.isEmpty ? null : agenda,
        'starts_at': startsAt?.toIso8601String(),
        'ends_at': endsAt?.toIso8601String(),
      },
    );
    final meeting = ProjectMeeting.fromJson(response.data);
    if (bindChecklistItemId != null) {
      final item = checklistItems.firstWhereOrNull(
        (entry) => entry.id == bindChecklistItemId,
      );
      if (item != null) {
        await updateChecklistItem(item, meetingId: meeting.id);
      }
    }
    await refreshWorkspace();
    return meeting;
  }

  Future<void> parseAssistantText(String text) async {
    final project = selectedProject.value;
    if (project == null || text.trim().isEmpty) return;
    final endpoint = ApiEndpoints.projectAssistantParse
        .replaceAll('{id}', project.id.toString());
    await _apiClient.post(
      endpoint,
      data: {
        'text': text,
        'create_records': true,
      },
    );
    await refreshWorkspace();
  }

  Future<ProjectAgentResult?> runProjectAgent(String text) async {
    final project = selectedProject.value;
    final normalized = text.trim();
    if (project == null || normalized.isEmpty) return null;
    agentMessages.add(
      ProjectAgentMessage(
        id: -DateTime.now().microsecondsSinceEpoch,
        projectId: project.id,
        role: 'user',
        content: normalized,
        createdAt: DateTime.now(),
        isPending: true,
      ),
    );
    final endpoint =
        ApiEndpoints.projectAgent.replaceAll('{id}', project.id.toString());
    final response = await _apiClient.post(
      endpoint,
      data: {'text': normalized},
      timeout: const Duration(seconds: 30),
    );
    final result = ProjectAgentResult.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
    await refreshWorkspace();
    await loadAgentMessages();
    return result;
  }

  void addLocalAgentError(String message) {
    final project = selectedProject.value;
    if (project == null) return;
    // Remove the optimistic bubble so a failed request can be retried cleanly.
    agentMessages.removeWhere((item) => item.isPending);
    agentMessages.add(
      ProjectAgentMessage(
        id: -DateTime.now().microsecondsSinceEpoch,
        projectId: project.id,
        role: 'assistant',
        content: message,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> refreshWorkspace() async {
    await Future.wait([
      loadProjects(),
      loadPhases(),
      loadTodos(),
      loadMeetings(),
      loadMembers(),
      loadTimelineImports()
    ]);
  }

  Future<void> seedStandardWorkflow() async {
    final project = selectedProject.value;
    if (project == null) return;
    final endpoint = ApiEndpoints.projectStandardWorkflow
        .replaceAll('{id}', project.id.toString());
    final response = await _apiClient.post(endpoint);
    final created = response.data is Map ? response.data['created'] ?? 0 : 0;
    Get.snackbar('标准流程', '已补齐标准流程，新增 $created 条待办');
    await refreshWorkspace();
  }

  Future<void> createPhase(String name) async {
    final project = selectedProject.value;
    if (project == null || name.trim().isEmpty) return;
    final endpoint =
        ApiEndpoints.projectPhases.replaceAll('{id}', project.id.toString());
    await _apiClient.post(
      endpoint,
      data: {'name': name.trim()},
    );
    await refreshWorkspace();
  }

  Future<void> updatePhase(ProjectPhase phase, String name) async {
    if (name.trim().isEmpty) return;
    final endpoint = ApiEndpoints.projectPhaseDetail
        .replaceAll('{phaseId}', phase.id.toString());
    await _apiClient.put(
      endpoint,
      data: {'name': name.trim()},
    );
    await refreshWorkspace();
  }

  Future<void> deletePhase(ProjectPhase phase) async {
    final endpoint = ApiEndpoints.projectPhaseDetail
        .replaceAll('{phaseId}', phase.id.toString());
    await _apiClient.delete(endpoint);
    await refreshWorkspace();
  }

  Future<void> reorderPhases(List<int> phaseIds) async {
    final project = selectedProject.value;
    if (project == null || phaseIds.isEmpty) return;
    final endpoint = ApiEndpoints.projectPhaseReorder
        .replaceAll('{id}', project.id.toString());
    await _apiClient.post(
      endpoint,
      data: {'phase_ids': phaseIds},
    );
    await refreshWorkspace();
  }

  Future<void> movePhase(ProjectPhase phase, int offset) async {
    if (phase.id <= 0 || offset == 0) return;
    final ordered = orderedWorkflowPhases
        .where((item) => item.id > 0)
        .toList(growable: true);
    final index = ordered.indexWhere((item) => item.id == phase.id);
    final targetIndex = index + offset;
    if (index < 0 || targetIndex < 0 || targetIndex >= ordered.length) return;
    final moved = ordered.removeAt(index);
    ordered.insert(targetIndex, moved);
    await reorderPhases(ordered.map((item) => item.id).toList());
  }

  Future<void> reorderTodosInPhase(String phase, List<int> todoIds) async {
    final project = selectedProject.value;
    if (project == null) return;
    final endpoint = ApiEndpoints.projectTodoReorder
        .replaceAll('{id}', project.id.toString());
    await _apiClient.post(
      endpoint,
      data: {
        'phase': phase,
        'todo_ids': todoIds,
      },
    );
    await refreshWorkspace();
  }

  Future<bool> syncTodoReminder(ProjectTodo todo) async {
    if (todo.dueAt == null) {
      Get.snackbar('提醒事项', '请先为待办设置截止时间');
      return false;
    }
    final projectName = projectNameForTodo(todo);
    final ok = await DeviceIntegrationService.syncTodoReminder(
      todo,
      projectName: projectName,
    );
    Get.snackbar(
      '提醒事项',
      ok ? '已写入手机日历，并设置 1小时/30分钟/10分钟提醒' : '写入失败，请检查日历和通知权限',
    );
    return ok;
  }

  List<ProjectTodo> get standardTodos =>
      todos.where((todo) => todo.todoType == 'standard').toList();

  List<BiostatProject> get ongoingProjects =>
      projects.where((project) => !project.isCompleted).toList();

  List<BiostatProject> get completedProjects =>
      projects.where((project) => project.isCompleted).toList();

  List<ProjectTodo> get upcomingTodos {
    final items = allTodos
        .where((todo) => todo.isActive && todo.dueAt != null)
        .toList()
      ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
    return items.take(5).toList();
  }

  String projectNameForTodo(ProjectTodo todo) {
    return projects
            .firstWhereOrNull((project) => project.id == todo.projectId)
            ?.name ??
        '项目';
  }

  List<ProjectChecklistItem> get checklistItems =>
      todos.expand((todo) => todo.checklistItems).toList();

  ProjectMeeting? meetingForChecklist(ProjectChecklistItem item) {
    final meetingId = item.meetingId;
    if (meetingId == null) return null;
    return meetings.firstWhereOrNull((meeting) => meeting.id == meetingId);
  }

  Map<String, List<ProjectTodo>> get workflowTodosByPhase {
    final grouped = <String, List<ProjectTodo>>{
      for (final phase in orderedWorkflowPhases) phase.name: <ProjectTodo>[],
    };
    final orderedTodos = [...todos]..sort(_compareWorkflowTodos);
    for (final todo in orderedTodos) {
      final phase = _displayWorkflowPhase(todo.phase);
      grouped.putIfAbsent(phase, () => []).add(todo);
    }
    final entries = grouped.entries.toList()
      ..sort((a, b) => _compareWorkflowPhases(a.key, b.key));
    return {for (final entry in entries) entry.key: entry.value};
  }

  Map<String, List<ProjectTodo>> get standardTodosByPhase =>
      workflowTodosByPhase;

  List<ProjectPhase> get orderedWorkflowPhases {
    final items = [...phases]..sort((a, b) {
        final orderCompare =
            _effectivePhaseSortOrder(a).compareTo(_effectivePhaseSortOrder(b));
        if (orderCompare != 0) return orderCompare;
        return _compareWorkflowPhases(a.name, b.name);
      });
    if (items.isEmpty && todos.isNotEmpty) {
      final names =
          todos.map((todo) => _displayWorkflowPhase(todo.phase)).toSet();
      return names
          .map(
            (name) => ProjectPhase(
              id: 0,
              projectId: selectedProject.value?.id ?? 0,
              name: name,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          )
          .toList()
        ..sort((a, b) => _compareWorkflowPhases(a.name, b.name));
    }
    return items;
  }

  String _displayWorkflowPhase(String phase) {
    if (phase.isEmpty || phase == '额外待办') return '流程待办';
    if (phase == '方案与SAP' || phase == 'TFL与统计输出') {
      return 'SAP与TFL';
    }
    return phase;
  }

  int _workflowPhaseRank(String phase) {
    final index = _workflowPhaseOrder.indexOf(phase);
    if (index >= 0) return index;
    if (phase == '流程待办') return _workflowPhaseOrder.length;
    return _workflowPhaseOrder.length + 1;
  }

  int _effectivePhaseSortOrder(ProjectPhase phase) {
    if (phase.sortOrder > 0) return phase.sortOrder;
    return 100000 + _workflowPhaseRank(phase.name);
  }

  int _compareWorkflowPhases(String a, String b) {
    final rankCompare = _workflowPhaseRank(a).compareTo(_workflowPhaseRank(b));
    if (rankCompare != 0) return rankCompare;
    return a.compareTo(b);
  }

  int _effectiveSortOrder(ProjectTodo todo) {
    return todo.sortOrder > 0 ? todo.sortOrder : 100000;
  }

  int _compareWorkflowTodos(ProjectTodo a, ProjectTodo b) {
    final phaseCompare = _compareWorkflowPhases(
      _displayWorkflowPhase(a.phase),
      _displayWorkflowPhase(b.phase),
    );
    if (phaseCompare != 0) return phaseCompare;

    final sortCompare =
        _effectiveSortOrder(a).compareTo(_effectiveSortOrder(b));
    if (sortCompare != 0) return sortCompare;

    final dueCompare = _compareNullableDate(a.dueAt, b.dueAt);
    if (dueCompare != 0) return dueCompare;

    return a.id.compareTo(b.id);
  }

  int _compareNullableDate(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }
}
