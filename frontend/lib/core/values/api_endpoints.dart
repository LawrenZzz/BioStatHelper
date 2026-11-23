class ApiEndpoints {
  // 视频相关
  static const String videos = '/videos';
  static const String videoCategories = '/videos/categories';
  static const String videoNasCategories = '/videos/nas-categories';
  static const String videoDetail = '/videos/{id}';
  static const String videoProgress = '/videos/{id}/progress';
  static const String videoSearch = '/videos/search';

  // 概念相关
  static const String concepts = '/concepts';
  static const String conceptCategories = '/concepts/categories';
  static const String conceptDetail = '/concepts/{id}';
  static const String conceptSearch = '/concepts/search';

  // 快速参考相关
  static const String references = '/references';
  static const String referenceCategories = '/references/categories';
  static const String referenceDetail = '/references/{id}';

  // 用户相关
  static const String login = '/auth/login';
  static const String session = '/auth/session';
  static const String register = '/auth/register';
  static const String profile = '/auth/profile';
  static const String settings = '/auth/settings';

  // 收藏相关
  static const String favorites = '/auth/favorites';
  static const String addFavorite = '/auth/favorites';
  static const String removeFavorite = '/auth/favorites';

  // 笔记相关
  static const String notes = '/notes';
  static const String noteDetail = '/notes/{id}';

  // 搜索
  static const String search = '/search';
  static const String searchSuggestions = '/search/suggestions';

  // 统计
  static const String statistics = '/statistics';
  static const String learningProgress = '/statistics/progress';

  // 项目工作台
  static const String projects = '/projects';
  static const String projectDetail = '/projects/{id}';
  static const String projectStandardWorkflow =
      '/projects/{id}/standard-workflow';
  static const String projectPhases = '/projects/{id}/phases';
  static const String projectPhaseReorder = '/projects/{id}/phases/reorder';
  static const String projectPhaseDetail = '/projects/phases/{phaseId}';
  static const String projectTodos = '/projects/{id}/todos';
  static const String projectTodoReorder = '/projects/{id}/todos/reorder';
  static const String projectMeetings = '/projects/{id}/meetings';
  static const String projectAssistantParse = '/projects/{id}/assistant/parse';
  static const String projectIntakeDraft = '/projects/assistant/project-intake/draft';
  static const String projectIntakeCreate = '/projects/assistant/project-intake';
  static const String projectAgent = '/projects/{id}/agent';
  static const String projectAgentMessages = '/projects/{id}/agent/messages';
  static const String projectMembers = '/projects/{id}/members';
  static const String projectMemberDetail = '/projects/members/{memberId}';
  static const String projectMemberParse = '/projects/{id}/members/parse';
  static const String projectTimeline = '/projects/{id}/timeline';
  static const String projectTimelineText = '/projects/{id}/timeline/text';
  static const String projectTimelineFile = '/projects/{id}/timeline/file';
  static const String projectTimelineItem = '/projects/timeline/items/{itemId}';
  static const String projectTimelineDetail = '/projects/timeline/{timelineId}';
  static const String projectTodoChecklist =
      '/projects/todos/{todoId}/checklist';
  static const String projectChecklistItem =
      '/projects/todos/checklist/{itemId}';

  // 今日工作台 (GTD)
  static const String gtdInbox = '/gtd/inbox';
  static const String gtdInboxProcess = '/gtd/inbox/{todoId}/process';
  static const String gtdFocus = '/gtd/focus';
  static const String gtdFocusToggle = '/gtd/focus/toggle';
  static const String gtdNextActions = '/gtd/next-actions';
  static const String gtdWaiting = '/gtd/waiting';
  static const String gtdSomeday = '/gtd/someday';
  static const String gtdReviewStatus = '/gtd/review/status';
  static const String gtdReviewWeekly = '/gtd/review/weekly';
  static const String gtdTasks = '/gtd/tasks';
  static const String gtdCalendar = '/gtd/calendar';
  static const String gtdContexts = '/gtd/contexts';
  static const String gtdFilters = '/gtd/filters';
  static const String gtdFilterDetail = '/gtd/filters/{filterId}';

  // 任务参考笔记 + 附件 (Phase 3)
  static const String gtdTaskNotes = '/gtd/tasks/{todoId}/notes';
  static const String gtdNoteDetail = '/gtd/notes/{noteId}';
  static const String gtdTaskAttachments = '/gtd/tasks/{todoId}/attachments';
  static const String gtdAttachmentDownload = '/gtd/attachments/{attachmentId}/download';
  static const String gtdAttachmentDetail = '/gtd/attachments/{attachmentId}';
}
