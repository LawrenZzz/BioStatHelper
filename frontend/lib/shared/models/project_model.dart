import 'dart:convert';

class ProjectTypeOption {
  final String value;
  final String label;

  const ProjectTypeOption(this.value, this.label);
}

const projectTypeOptions = <ProjectTypeOption>[
  ProjectTypeOption('drug', '药物临床研究'),
  ProjectTypeOption('vaccine', '疫苗临床研究'),
  ProjectTypeOption('medical_device', '医疗器械临床研究'),
  ProjectTypeOption('diagnostic', '诊断试剂/伴随诊断研究'),
  ProjectTypeOption('radiopharmaceutical', '核药/放射性药物研究'),
  ProjectTypeOption('biologic', '生物制品临床研究'),
  ProjectTypeOption('cell_gene', '细胞与基因治疗研究'),
  ProjectTypeOption('tcm', '中药/天然药物研究'),
  ProjectTypeOption('rws', '真实世界研究 RWS'),
  ProjectTypeOption('iit', '研究者发起研究 IIT'),
  ProjectTypeOption('observational', '观察性研究'),
  ProjectTypeOption('be_pk', '生物等效性/PK研究'),
  ProjectTypeOption('other', '其他临床研究'),
];

String projectTypeLabel(String value) {
  for (final option in projectTypeOptions) {
    if (option.value == value) return option.label;
  }
  return projectTypeOptions.last.label;
}

bool isKnownProjectType(String value) =>
    projectTypeOptions.any((option) => option.value == value);

class BiostatProject {
  final int id;
  final String name;
  final String sponsor;
  final String protocolNo;
  final String phase;
  final String currentWorkflowPhase;
  final String projectType;
  final bool isCdisc;
  final String indication;
  final String description;
  final String status;
  final bool isInbox;
  final DateTime? reviewAt;
  final int todoCount;
  final int openTodoCount;
  final int inProgressTodoCount;
  final int doneTodoCount;
  final int meetingCount;
  final double progressPercent;
  final DateTime createdAt;
  final DateTime updatedAt;

  BiostatProject({
    required this.id,
    required this.name,
    this.sponsor = '',
    this.protocolNo = '',
    this.phase = '',
    this.currentWorkflowPhase = '',
    this.projectType = 'other',
    this.isCdisc = false,
    this.indication = '',
    this.description = '',
    this.status = 'active',
    this.isInbox = false,
    this.reviewAt,
    this.todoCount = 0,
    this.openTodoCount = 0,
    this.inProgressTodoCount = 0,
    this.doneTodoCount = 0,
    this.meetingCount = 0,
    this.progressPercent = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BiostatProject.fromJson(Map<String, dynamic> json) {
    return BiostatProject(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      sponsor: json['sponsor'] ?? '',
      protocolNo: json['protocol_no'] ?? '',
      phase: json['phase'] ?? '',
      currentWorkflowPhase: json['current_workflow_phase'] ?? '',
      projectType: json['project_type'] ?? 'other',
      isCdisc: json['is_cdisc'] == true,
      indication: json['indication'] ?? '',
      description: json['description'] ?? '',
      status: json['status'] ?? 'active',
      isInbox: json['is_inbox'] == true,
      reviewAt: DateTime.tryParse(json['review_at'] ?? ''),
      todoCount: json['todo_count'] ?? 0,
      openTodoCount: json['open_todo_count'] ?? 0,
      inProgressTodoCount: json['in_progress_todo_count'] ?? 0,
      doneTodoCount: json['done_todo_count'] ?? 0,
      meetingCount: json['meeting_count'] ?? 0,
      progressPercent: (json['progress_percent'] ?? 0).toDouble(),
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
    );
  }

  bool get isCompleted => status == 'completed';
  int get notStartedTodoCount =>
      (todoCount - doneTodoCount - inProgressTodoCount).clamp(0, todoCount);

  String get snapshotCurrentState {
    const prefix = '当前阶段（原文）：';
    for (final line in const LineSplitter().convert(description)) {
      if (line.startsWith(prefix)) return line.substring(prefix.length).trim();
    }
    return '';
  }

  bool get isCdiscUnconfirmed =>
      !isCdisc && description.contains('[snapshot:cdisc-unconfirmed]');
  String get displayDescription =>
      description.replaceAll('[snapshot:cdisc-unconfirmed]', '').trim();
  String get cdiscLabel => isCdiscUnconfirmed
      ? 'CDISC 待确认'
      : isCdisc
          ? 'CDISC'
          : '非CDISC';
}

class ProjectTodoFocus {
  final BiostatProject project;
  final int todoId;

  const ProjectTodoFocus({
    required this.project,
    required this.todoId,
  });
}

class ProjectChecklistItem {
  final int id;
  final int todoId;
  final String title;
  final bool isDone;
  final DateTime? dueAt;
  final int? meetingId;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProjectChecklistItem({
    required this.id,
    required this.todoId,
    required this.title,
    this.isDone = false,
    this.dueAt,
    this.meetingId,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProjectChecklistItem.fromJson(Map<String, dynamic> json) {
    return ProjectChecklistItem(
      id: json['id'] ?? 0,
      todoId: json['todo_id'] ?? 0,
      title: json['title'] ?? '',
      isDone: json['is_done'] ?? false,
      dueAt: DateTime.tryParse(json['due_at'] ?? ''),
      meetingId: json['meeting_id'],
      sortOrder: json['sort_order'] ?? 0,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
    );
  }
}

class ProjectPhase {
  final int id;
  final int projectId;
  final String name;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProjectPhase({
    required this.id,
    required this.projectId,
    required this.name,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProjectPhase.fromJson(Map<String, dynamic> json) {
    return ProjectPhase(
      id: json['id'] ?? 0,
      projectId: json['project_id'] ?? 0,
      name: json['name'] ?? '',
      sortOrder: json['sort_order'] ?? 0,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
    );
  }
}

class ProjectTodo {
  final int id;
  final int projectId;
  final String title;
  final String description;
  final String todoType;
  final String phase;
  final String status;
  final String priority;
  final DateTime? startAt;
  final DateTime? dueAt;
  final int sortOrder;
  final List<ProjectChecklistItem> checklistItems;
  // GTD fields
  final List<String> contexts;
  final List<String> tags;
  final String area;
  final String energyLevel;
  final int? timeEstimate;
  final bool isFocusedToday;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String recurrence;
  // Calendar view: the specific due date of this expanded occurrence, which
  // differs from dueAt for recurring tasks whose base date is in the past.
  final DateTime? occurrenceDueAt;
  // Denormalized project label carried by GTD task DTOs.
  final String projectName;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProjectTodo({
    required this.id,
    required this.projectId,
    required this.title,
    this.description = '',
    this.todoType = 'extra',
    this.phase = '',
    this.status = 'next',
    this.priority = 'normal',
    this.startAt,
    this.dueAt,
    this.sortOrder = 0,
    this.checklistItems = const [],
    this.contexts = const [],
    this.tags = const [],
    this.area = '',
    this.energyLevel = '',
    this.timeEstimate,
    this.isFocusedToday = false,
    this.completedAt,
    this.cancelledAt,
    this.recurrence = '',
    this.occurrenceDueAt,
    this.projectName = '',
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProjectTodo.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) {
      final value = json[key];
      if (value is List) {
        return value.whereType<String>().toList();
      }
      if (value is String && value.isNotEmpty) {
        try {
          final parsed = _decodeJson(value);
          if (parsed is List) return parsed.whereType<String>().toList();
        } catch (_) {}
      }
      return const [];
    }

    return ProjectTodo(
      // GTD task DTOs expose the id as `todo_id`.
      id: json['todo_id'] ?? json['id'] ?? 0,
      projectId: json['project_id'] ?? 0,
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      todoType: json['todo_type'] ?? 'extra',
      phase: json['phase'] ?? '',
      status: json['status'] ?? 'next',
      priority: json['priority'] ?? 'normal',
      startAt: DateTime.tryParse(json['start_at'] ?? ''),
      dueAt: DateTime.tryParse(json['due_at'] ?? ''),
      sortOrder: json['sort_order'] ?? 0,
      checklistItems: (json['checklist_items'] as List?)
              ?.map((item) => ProjectChecklistItem.fromJson(item))
              .toList() ??
          [],
      contexts: strings('contexts'),
      tags: strings('tags'),
      area: json['area'] ?? '',
      energyLevel: json['energy_level'] ?? '',
      timeEstimate: (json['time_estimate'] as num?)?.toInt(),
      isFocusedToday: json['is_focused_today'] == true,
      completedAt: DateTime.tryParse(json['completed_at'] ?? ''),
      cancelledAt: DateTime.tryParse(json['cancelled_at'] ?? ''),
      recurrence: json['recurrence'] ?? '',
      occurrenceDueAt: DateTime.tryParse(json['occurrence_due_at'] ?? ''),
      projectName: json['project_name'] ?? '',
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
    );
  }

  bool get isDone => status == 'done';
  bool get isWorkflowInferred => tags.contains('workflow-inferred');

  bool get isActive =>
      status == 'next' ||
      status == 'open' ||
      status == 'in_progress' ||
      status == 'blocked' ||
      status == 'waiting';

  bool get isNext => status == 'next' || status == 'open';
  bool get isInbox => status == 'inbox';
  bool get isWaiting => status == 'waiting';
  bool get isSomeday => status == 'someday' || status == 'reference';
  bool get isArchived => status == 'archived';

  int get doneChecklistCount =>
      checklistItems.where((item) => item.isDone).length;
}

dynamic _decodeJson(String value) => jsonDecode(value);

class ProjectMeeting {
  final int id;
  final int projectId;
  final String title;
  final String agenda;
  final String meetingUrl;
  final String location;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String attendees;
  final String notes;

  ProjectMeeting({
    required this.id,
    required this.projectId,
    required this.title,
    this.agenda = '',
    this.meetingUrl = '',
    this.location = '',
    this.startsAt,
    this.endsAt,
    this.attendees = '',
    this.notes = '',
  });

  factory ProjectMeeting.fromJson(Map<String, dynamic> json) {
    return ProjectMeeting(
      id: json['id'] ?? 0,
      projectId: json['project_id'] ?? 0,
      title: json['title'] ?? '',
      agenda: json['agenda'] ?? '',
      meetingUrl: json['meeting_url'] ?? '',
      location: json['location'] ?? '',
      startsAt: DateTime.tryParse(json['starts_at'] ?? ''),
      endsAt: DateTime.tryParse(json['ends_at'] ?? ''),
      attendees: json['attendees'] ?? '',
      notes: json['notes'] ?? '',
    );
  }
}

class ProjectAgentResult {
  final String intent;
  final String summary;
  final String? clarification;
  final String modelUsed;
  final bool fallbackUsed;
  final String? currentPhase;
  final int completedTodoCount;
  final int completedChecklistCount;
  final List<ProjectTodo> createdTodos;
  final List<ProjectTodo> updatedTodos;
  final List<ProjectMeeting> createdMeetings;
  final List<ProjectMeeting> updatedMeetings;

  const ProjectAgentResult({
    required this.intent,
    required this.summary,
    this.clarification,
    this.modelUsed = '',
    this.fallbackUsed = false,
    this.currentPhase,
    this.completedTodoCount = 0,
    this.completedChecklistCount = 0,
    this.createdTodos = const [],
    this.updatedTodos = const [],
    this.createdMeetings = const [],
    this.updatedMeetings = const [],
  });

  factory ProjectAgentResult.fromJson(Map<String, dynamic> json) {
    List<ProjectTodo> todos(String key) =>
        (json[key] as List?)
            ?.whereType<Map>()
            .map((item) => ProjectTodo.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList() ??
        const [];
    List<ProjectMeeting> meetings(String key) =>
        (json[key] as List?)
            ?.whereType<Map>()
            .map((item) => ProjectMeeting.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList() ??
        const [];

    return ProjectAgentResult(
      intent: json['intent'] ?? 'update',
      summary: json['summary'] ?? '已更新项目安排',
      clarification: json['clarification'],
      modelUsed: json['model_used'] ?? '',
      fallbackUsed: json['fallback_used'] ?? false,
      currentPhase: json['current_phase'],
      completedTodoCount: json['completed_todo_count'] ?? 0,
      completedChecklistCount: json['completed_checklist_count'] ?? 0,
      createdTodos: todos('created_todos'),
      updatedTodos: todos('updated_todos'),
      createdMeetings: meetings('created_meetings'),
      updatedMeetings: meetings('updated_meetings'),
    );
  }
}

class ProjectAgentMessage {
  final int id;
  final int projectId;
  final String role;
  final String content;
  final String modelUsed;
  final bool fallbackUsed;
  final DateTime createdAt;
  final bool isPending;

  const ProjectAgentMessage({
    required this.id,
    required this.projectId,
    required this.role,
    required this.content,
    this.modelUsed = '',
    this.fallbackUsed = false,
    required this.createdAt,
    this.isPending = false,
  });

  factory ProjectAgentMessage.fromJson(Map<String, dynamic> json) {
    return ProjectAgentMessage(
      id: json['id'] ?? 0,
      projectId: json['project_id'] ?? 0,
      role: json['role'] ?? 'assistant',
      content: json['content'] ?? '',
      modelUsed: json['model_used'] ?? '',
      fallbackUsed: json['fallback_used'] ?? false,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }

  bool get isUser => role == 'user';
}

class ProjectMember {
  final int id;
  final int projectId;
  final String memberType;
  final String name;
  final String organization;
  final String role;
  final String email;
  final String phone;
  final String notes;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProjectMember({
    required this.id,
    required this.projectId,
    required this.memberType,
    required this.name,
    this.organization = '',
    this.role = '',
    this.email = '',
    this.phone = '',
    this.notes = '',
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProjectMember.fromJson(Map<String, dynamic> json) {
    return ProjectMember(
      id: json['id'] ?? 0,
      projectId: json['project_id'] ?? 0,
      memberType: json['member_type'] ?? 'other',
      name: json['name'] ?? '',
      organization: json['organization'] ?? '',
      role: json['role'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      notes: json['notes'] ?? '',
      sortOrder: json['sort_order'] ?? 0,
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
    );
  }
}

String projectMemberTypeLabel(String value) {
  switch (value) {
    case 'sponsor':
      return '申办方';
    case 'statistical_partner':
      return '合作统计方';
    case 'internal':
      return '内部团队';
    default:
      return '其他';
  }
}

class ProjectTimelineItem {
  final int id;
  final int timelineImportId;
  final int projectId;
  final int rowNumber;
  final String externalId;
  final String title;
  final String description;
  final String phase;
  final DateTime? startAt;
  final DateTime? dueAt;
  final String status;
  final String targetType;
  final int? matchedTodoId;
  final int? matchedChecklistItemId;
  final double? confidence;
  final String warning;
  final dynamic rawJson;

  const ProjectTimelineItem({
    required this.id,
    required this.timelineImportId,
    required this.projectId,
    required this.rowNumber,
    required this.title,
    this.externalId = '',
    this.description = '',
    this.phase = '',
    this.startAt,
    this.dueAt,
    this.status = '',
    this.targetType = 'none',
    this.matchedTodoId,
    this.matchedChecklistItemId,
    this.confidence,
    this.warning = '',
    this.rawJson,
  });

  factory ProjectTimelineItem.fromJson(Map<String, dynamic> json) {
    return ProjectTimelineItem(
      id: json['id'] ?? 0,
      timelineImportId: json['timeline_import_id'] ?? 0,
      projectId: json['project_id'] ?? 0,
      rowNumber: json['row_number'] ?? 0,
      externalId: json['external_id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      phase: json['phase'] ?? '',
      startAt: DateTime.tryParse(json['start_at'] ?? ''),
      dueAt: DateTime.tryParse(json['due_at'] ?? ''),
      status: json['status'] ?? '',
      targetType: json['target_type'] ?? 'none',
      matchedTodoId: json['matched_todo_id'],
      matchedChecklistItemId: json['matched_checklist_item_id'],
      confidence: (json['confidence'] as num?)?.toDouble(),
      warning: json['warning'] ?? '',
      rawJson: json['raw_json'],
    );
  }

  bool get isMatched => targetType != 'none';
}

class ProjectTimelineImport {
  final int id;
  final int projectId;
  final String fileName;
  final String sourceType;
  final String modelUsed;
  final bool fallbackUsed;
  final String status;
  final String errorMessage;
  final List<ProjectTimelineItem> items;
  final DateTime createdAt;

  const ProjectTimelineImport({
    required this.id,
    required this.projectId,
    this.fileName = '',
    this.sourceType = 'text',
    this.modelUsed = '',
    this.fallbackUsed = false,
    this.status = 'parsed',
    this.errorMessage = '',
    this.items = const [],
    required this.createdAt,
  });

  factory ProjectTimelineImport.fromJson(Map<String, dynamic> json) {
    return ProjectTimelineImport(
      id: json['id'] ?? 0,
      projectId: json['project_id'] ?? 0,
      fileName: json['file_name'] ?? '',
      sourceType: json['source_type'] ?? 'text',
      modelUsed: json['model_used'] ?? '',
      fallbackUsed: json['fallback_used'] == true,
      status: json['status'] ?? 'parsed',
      errorMessage: json['error_message'] ?? '',
      items: (json['items'] as List?)
              ?.whereType<Map>()
              .map((item) => ProjectTimelineItem.fromJson(
                    Map<String, dynamic>.from(item),
                  ))
              .toList() ??
          const [],
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}
