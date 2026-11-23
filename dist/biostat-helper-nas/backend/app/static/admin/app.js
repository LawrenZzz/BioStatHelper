const state = {
  token: localStorage.getItem("bioStatAdminToken"),
  activeTab: "knowledge",
  activeProjectTab: "standard",
  videos: [],
  videoSidecarMatches: new Map(),
  concepts: [],
  categories: [],
  projects: [],
  activeProjectId: null,
  projectIntakeDraft: null,
  projectPhases: [],
  openProjectPhases: new Set(),
  draggingTodo: null,
  todos: [],
  meetings: [],
  members: [],
  timelineImports: [],
  activeTimelineItemId: null,
  videoCategories: [],
  collapsedVideoCategoryIds: new Set(),
  reorderVideos: [],
  draggingVideoId: null,
};

const ADMIN_UI_BUILD_ID = "20261020-learning-library-v1";
console.info(`BioStat admin UI build: ${ADMIN_UI_BUILD_ID}`);

const $ = (selector) => document.querySelector(selector);
const PROJECT_TYPE_LABELS = {
  drug: "药物临床研究",
  vaccine: "疫苗临床研究",
  medical_device: "医疗器械临床研究",
  diagnostic: "诊断试剂/伴随诊断研究",
  radiopharmaceutical: "核药/放射性药物研究",
  biologic: "生物制品临床研究",
  cell_gene: "细胞与基因治疗研究",
  tcm: "中药/天然药物研究",
  rws: "真实世界研究 RWS",
  iit: "研究者发起研究 IIT",
  observational: "观察性研究",
  be_pk: "生物等效性/PK研究",
  other: "其他临床研究",
};

const els = {
  appPanel: $("#appPanel"),
  loginPanel: $("#loginPanel"),
  loginForm: $("#loginForm"),
  loginMessageBox: $("#loginMessageBox"),
  logoutButton: $("#logoutButton"),
  messageBox: $("#messageBox"),
  sessionStatus: $("#sessionStatus"),
  statsGrid: $("#statsGrid"),
  tabs: document.querySelectorAll(".tab"),
  knowledgePanel: $("#knowledgePanel"),
  projectsPanel: $("#projectsPanel"),
  videosPanel: $("#videosPanel"),
  videoCategoryFilter: $("#videoCategoryFilter"),
  videoCategoryList: $("#videoCategoryList"),
  newVideoCategoryButton: $("#newVideoCategoryButton"),
  manualVideoButton: $("#manualVideoButton"),
  scanSidecarsButton: $("#scanSidecarsButton"),
  reorderVideosButton: $("#reorderVideosButton"),
  aiOrganizeVideosButton: $("#aiOrganizeVideosButton"),
  aiOrganizeAllVideosButton: $("#aiOrganizeAllVideosButton"),
  deleteAllVideoCategoriesButton: $("#deleteAllVideoCategoriesButton"),
  deleteVideoLibraryButton: $("#deleteVideoLibraryButton"),
  videoProgressPanel: $("#videoProgressPanel"),
  videoProgressTitle: $("#videoProgressTitle"),
  videoProgressText: $("#videoProgressText"),
  videoProgressBar: $("#videoProgressBar"),
  videoCategoryDialog: $("#videoCategoryDialog"),
  videoCategoryDialogTitle: $("#videoCategoryDialogTitle"),
  videoCategoryEditId: $("#videoCategoryEditId"),
  videoCategoryName: $("#videoCategoryName"),
  videoCategoryParent: $("#videoCategoryParent"),
  videoCategorySortOrder: $("#videoCategorySortOrder"),
  videoCategoryDescription: $("#videoCategoryDescription"),
  saveVideoCategoryButton: $("#saveVideoCategoryButton"),
  manualVideoDialog: $("#manualVideoDialog"),
  manualVideoPath: $("#manualVideoPath"),
  manualVideoCategory: $("#manualVideoCategory"),
  manualVideoEpisode: $("#manualVideoEpisode"),
  manualVideoTitle: $("#manualVideoTitle"),
  manualVideoCourseName: $("#manualVideoCourseName"),
  manualVideoDescription: $("#manualVideoDescription"),
  saveManualVideoButton: $("#saveManualVideoButton"),
  videoReorderDialog: $("#videoReorderDialog"),
  videoReorderList: $("#videoReorderList"),
  saveVideoReorderButton: $("#saveVideoReorderButton"),

  categoryList: $("#categoryList"),
  conceptCategory: $("#conceptCategory"),
  conceptCategoryFilter: $("#conceptCategoryFilter"),
  conceptContent: $("#conceptContent"),
  conceptDialog: $("#conceptDialog"),
  conceptDialogTitle: $("#conceptDialogTitle"),
  conceptEditId: $("#conceptEditId"),
  conceptExamples: $("#conceptExamples"),
  conceptFormulas: $("#conceptFormulas"),
  conceptList: $("#conceptList"),
  conceptPublished: $("#conceptPublished"),
  conceptPublishedFilter: $("#conceptPublishedFilter"),
  conceptSearchInput: $("#conceptSearchInput"),
  conceptSummary: $("#conceptSummary"),
  conceptTags: $("#conceptTags"),
  conceptTitle: $("#conceptTitle"),
  deleteConceptButton: $("#deleteConceptButton"),
  newConceptButton: $("#newConceptButton"),
  publishAllConceptsButton: $("#publishAllConceptsButton"),
  refreshKnowledgeButton: $("#refreshKnowledgeButton"),
  saveConceptButton: $("#saveConceptButton"),

  projectList: $("#projectList"),
  projectEmpty: $("#projectEmpty"),
  projectWorkspace: $("#projectWorkspace"),
  activeProjectName: $("#activeProjectName"),
  activeProjectMeta: $("#activeProjectMeta"),
  activeProjectDescription: $("#activeProjectDescription"),
  editProjectButton: $("#editProjectButton"),
  deleteProjectButton: $("#deleteProjectButton"),
  newProjectButton: $("#newProjectButton"),
  refreshProjectsButton: $("#refreshProjectsButton"),
  seedWorkflowButton: $("#seedWorkflowButton"),
  newProjectPhaseButton: $("#newProjectPhaseButton"),
  newTodoButton: $("#newTodoButton"),
  newMeetingButton: $("#newMeetingButton"),
  assistantInput: $("#assistantInput"),
  parseAssistantButton: $("#parseAssistantButton"),
  clearAssistantButton: $("#clearAssistantButton"),
  subtabs: document.querySelectorAll(".subtab"),
  standardTodos: $("#standardTodos"),
  meetingList: $("#meetingList"),
  memberList: $("#memberList"),
  timelineList: $("#timelineList"),

  projectDialog: $("#projectDialog"),
  projectDialogTitle: $("#projectDialogTitle"),
  projectEditId: $("#projectEditId"),
  projectName: $("#projectName"),
  projectProtocolNo: $("#projectProtocolNo"),
  projectSponsor: $("#projectSponsor"),
  projectPhase: $("#projectPhase"),
  projectType: $("#projectType"),
  projectIsCdisc: $("#projectIsCdisc"),
  projectIndication: $("#projectIndication"),
  projectDescription: $("#projectDescription"),
  projectStatus: $("#projectStatus"),
  projectCreateWorkflowRow: $("#projectCreateWorkflowRow"),
  projectCreateWorkflow: $("#projectCreateWorkflow"),
  projectIntakeRow: $("#projectIntakeRow"),
  projectIntakeText: $("#projectIntakeText"),
  parseProjectIntakeButton: $("#parseProjectIntakeButton"),
  projectIntakePreview: $("#projectIntakePreview"),
  saveProjectButton: $("#saveProjectButton"),

  todoDialog: $("#todoDialog"),
  todoDialogTitle: $("#todoDialogTitle"),
  todoEditId: $("#todoEditId"),
  todoTitle: $("#todoTitle"),
  todoType: $("#todoType"),
  todoPhase: $("#todoPhase"),
  todoStatus: $("#todoStatus"),
  todoPriority: $("#todoPriority"),
  todoStartAt: $("#todoStartAt"),
  todoDueAt: $("#todoDueAt"),
  todoDescription: $("#todoDescription"),
  projectPhaseOptions: $("#projectPhaseOptions"),
  parseTodoDraftButton: $("#parseTodoDraftButton"),
  saveTodoButton: $("#saveTodoButton"),
  deleteTodoButton: $("#deleteTodoButton"),
  projectPhaseDialog: $("#projectPhaseDialog"),
  projectPhaseDialogTitle: $("#projectPhaseDialogTitle"),
  projectPhaseEditId: $("#projectPhaseEditId"),
  projectPhaseName: $("#projectPhaseName"),
  saveProjectPhaseButton: $("#saveProjectPhaseButton"),
  deleteProjectPhaseButton: $("#deleteProjectPhaseButton"),
  checklistDialog: $("#checklistDialog"),
  checklistDialogTitle: $("#checklistDialogTitle"),
  checklistEditId: $("#checklistEditId"),
  checklistTodoId: $("#checklistTodoId"),
  checklistTitle: $("#checklistTitle"),
  checklistDueAt: $("#checklistDueAt"),
  checklistMeetingId: $("#checklistMeetingId"),
  checklistIsDone: $("#checklistIsDone"),
  saveChecklistButton: $("#saveChecklistButton"),
  deleteChecklistButton: $("#deleteChecklistButton"),

  meetingDialog: $("#meetingDialog"),
  meetingDialogTitle: $("#meetingDialogTitle"),
  meetingEditId: $("#meetingEditId"),
  meetingTitle: $("#meetingTitle"),
  meetingUrl: $("#meetingUrl"),
  meetingStartsAt: $("#meetingStartsAt"),
  meetingEndsAt: $("#meetingEndsAt"),
  meetingLocation: $("#meetingLocation"),
  meetingAttendees: $("#meetingAttendees"),
  meetingChecklistId: $("#meetingChecklistId"),
  meetingAgenda: $("#meetingAgenda"),
  meetingNotes: $("#meetingNotes"),
  parseMeetingDraftButton: $("#parseMeetingDraftButton"),
  saveMeetingButton: $("#saveMeetingButton"),
  deleteMeetingButton: $("#deleteMeetingButton"),

  memberDialog: $("#memberDialog"),
  memberDialogTitle: $("#memberDialogTitle"),
  memberEditId: $("#memberEditId"),
  memberType: $("#memberType"),
  memberName: $("#memberName"),
  memberOrganization: $("#memberOrganization"),
  memberRole: $("#memberRole"),
  memberEmail: $("#memberEmail"),
  memberPhone: $("#memberPhone"),
  memberNotes: $("#memberNotes"),
  parseMemberButton: $("#parseMemberButton"),
  saveMemberButton: $("#saveMemberButton"),
  deleteMemberButton: $("#deleteMemberButton"),
  memberTextDialog: $("#memberTextDialog"),
  memberText: $("#memberText"),
  parseMemberTextButton: $("#parseMemberTextButton"),
  timelineTextDialog: $("#timelineTextDialog"),
  timelineText: $("#timelineText"),
  importTimelineTextButton: $("#importTimelineTextButton"),
  timelineFileInput: $("#timelineFileInput"),
  timelineItemDialog: $("#timelineItemDialog"),
  timelineItemId: $("#timelineItemId"),
  timelineItemTitle: $("#timelineItemTitle"),
  timelineItemTarget: $("#timelineItemTarget"),
  timelineItemStartAt: $("#timelineItemStartAt"),
  timelineItemDueAt: $("#timelineItemDueAt"),
  saveTimelineItemButton: $("#saveTimelineItemButton"),

  editDialog: $("#editDialog"),
  publishedFilter: $("#publishedFilter"),
  refreshButton: $("#refreshButton"),
  saveButton: $("#saveButton"),
  scanButton: $("#scanButton"),
  searchInput: $("#searchInput"),
  tableBody: $("#videoTableBody"),
};

function api(path, options = {}) {
  const headers = {
    "Content-Type": "application/json",
    ...(options.headers || {}),
  };
  if (state.token) headers.Authorization = `Bearer ${state.token}`;

  return fetch(`/api/v1${path}`, { ...options, headers }).then(async (response) => {
    const text = await response.text();
    let data = null;
    try {
      data = text ? JSON.parse(text) : null;
    } catch {
      data = { detail: text };
    }
    if (!response.ok) {
      const detail = Array.isArray(data?.detail)
        ? data.detail.map((item) => item.msg || JSON.stringify(item)).join("；")
        : (typeof data?.detail === "object" ? JSON.stringify(data.detail) : data?.detail);
      const error = new Error(detail || `请求失败：HTTP ${response.status}`);
      error.status = response.status;
      throw error;
    }
    return data;
  });
}

function setMessage(text, isError = false, target = els.messageBox) {
  if (!target) return;
  target.textContent = text;
  target.classList.toggle("error", isError);
  target.classList.remove("hidden");
  window.setTimeout(() => target.classList.add("hidden"), 7000);
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function formatJson(value) {
  return JSON.stringify(value || [], null, 2);
}

function compactTags(tags) {
  if (!Array.isArray(tags)) return "";
  return tags.map((tag) => (typeof tag === "string" ? tag : tag.name)).filter(Boolean).join(", ");
}

function toLocalInputValue(value) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  const pad = (number) => String(number).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function fromLocalInputValue(value) {
  if (!value) return null;
  return value.length === 16 ? `${value}:00` : value;
}

function formatDateTime(value) {
  if (!value) return "-";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "-";
  return date.toLocaleString("zh-CN", { hour12: false });
}

function setVideoProgress(title, current, total, detail = "") {
  const percent = total > 0 ? Math.round((current / total) * 100) : 0;
  els.videoProgressPanel.classList.remove("hidden");
  els.videoProgressTitle.textContent = title;
  els.videoProgressText.textContent = detail || `${current}/${total} (${percent}%)`;
  els.videoProgressBar.style.width = `${Math.max(0, Math.min(100, percent))}%`;
}

function hideVideoProgressSoon() {
  window.clearTimeout(window.videoProgressTimer);
  window.videoProgressTimer = window.setTimeout(() => {
    els.videoProgressPanel.classList.add("hidden");
  }, 1800);
}

function updateSession() {
  const loggedIn = Boolean(state.token);
  els.loginPanel.classList.toggle("hidden", loggedIn);
  els.appPanel.classList.toggle("hidden", !loggedIn);
  els.logoutButton.classList.toggle("hidden", !loggedIn);
  els.sessionStatus.textContent = loggedIn ? "已登录" : "未登录";
}

function switchTab(tab) {
  state.activeTab = tab;
  els.tabs.forEach((button) => button.classList.toggle("active", button.dataset.tab === tab));
  els.knowledgePanel.classList.toggle("hidden", tab !== "knowledge");
  els.projectsPanel.classList.toggle("hidden", tab !== "projects");
  els.videosPanel.classList.toggle("hidden", tab !== "videos");
}

function switchProjectTab(tab) {
  if (tab === "extra") tab = "standard";
  state.activeProjectTab = tab;
  els.subtabs.forEach((button) => button.classList.toggle("active", button.dataset.projectTab === tab));
  els.standardTodos.classList.toggle("hidden", tab !== "standard");
  els.meetingList.classList.toggle("hidden", tab !== "meetings");
  els.memberList.classList.toggle("hidden", tab !== "members");
  els.timelineList.classList.toggle("hidden", tab !== "timeline");
}

function formatSize(bytes) {
  if (!bytes) return "-";
  const units = ["B", "KB", "MB", "GB", "TB"];
  let size = bytes;
  let unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex += 1;
  }
  return `${size.toFixed(unitIndex === 0 ? 0 : 1)} ${units[unitIndex]}`;
}

function renderStats(stats) {
  const entries = [
    ["用户", stats.users],
    ["App视频", stats.videos],
    ["概念", stats.concepts],
    ["参考", stats.references],
    ["NAS视频", stats.nas_videos],
    ["已发布", stats.published_nas_videos],
  ];
  els.statsGrid.innerHTML = entries
    .map(([label, value]) => `<article class="stat"><span>${label}</span><strong>${value}</strong></article>`)
    .join("");
}

async function loadStats() {
  const stats = await api("/admin/stats");
  renderStats(stats);
}

function renderCategoryOptions() {
  const options = state.categories
    .map((category) => `<option value="${category.id}">${escapeHtml(category.icon || "")} ${escapeHtml(category.name)}</option>`)
    .join("");
  els.conceptCategory.innerHTML = options;
  els.conceptCategoryFilter.innerHTML = `<option value="">全部分类</option>${options}`;
}

function renderCategories() {
  const selected = Number(els.conceptCategoryFilter.value || 0);
  const allCount = state.categories.reduce((sum, category) => sum + (category.concept_count || 0), 0);
  els.categoryList.innerHTML = [
    `<button class="category-item ${selected ? "" : "active"}" type="button" data-category-id=""><span>全部</span><strong>${allCount}</strong></button>`,
    ...state.categories.map((category) => `
      <button class="category-item ${selected === category.id ? "active" : ""}" type="button" data-category-id="${category.id}">
        <span>${escapeHtml(category.icon || "")} ${escapeHtml(category.name)}</span>
        <strong>${category.concept_count || 0}</strong>
      </button>
    `),
  ].join("");
}

function getFilteredConcepts() {
  const published = els.conceptPublishedFilter.value;
  return state.concepts.filter((concept) => {
    if (published === "true" && !concept.is_published) return false;
    if (published === "false" && concept.is_published) return false;
    return true;
  });
}

function renderConceptCards(concepts) {
  return concepts.map((concept) => {
    const tags = compactTags(concept.tags);
    const status = concept.is_published ? `<span class="pill ok">已发布</span>` : `<span class="pill pending">已隐藏</span>`;
    return `
      <article class="concept-row">
        <div>
          <div class="concept-meta">
            <span>${escapeHtml(concept.category?.icon || "")} ${escapeHtml(concept.category?.name || "未分类")}</span>
            ${status}
            <span>${concept.read_count || 0} 次阅读</span>
          </div>
          <h3>${escapeHtml(concept.title)}</h3>
          <p>${escapeHtml(concept.summary || "")}</p>
          ${tags ? `<div class="tag-line">${escapeHtml(tags)}</div>` : ""}
        </div>
        <div class="row-actions">
          <button class="ghost" type="button" data-action="toggle-concept" data-id="${concept.id}">${concept.is_published ? "隐藏" : "发布"}</button>
          <button type="button" data-action="edit-concept" data-id="${concept.id}">编辑</button>
        </div>
      </article>
    `;
  }).join("");
}

function renderConceptGroup(title, concepts, tone = "") {
  if (!concepts.length) return "";
  return `
    <section class="concept-status-group ${tone}">
      <div class="concept-group-heading">
        <h3>${escapeHtml(title)}</h3>
        <span>${concepts.length} 条</span>
      </div>
      ${renderConceptCards(concepts)}
    </section>
  `;
}

function renderConcepts() {
  const concepts = getFilteredConcepts();
  if (!concepts.length) {
    els.conceptList.innerHTML = `<div class="empty-state"><h3>暂无概念</h3><p>可以同步内置知识库，或手动新增一个概念。</p></div>`;
    return;
  }

  if (!els.conceptPublishedFilter.value) {
    const published = concepts.filter((concept) => concept.is_published);
    const hidden = concepts.filter((concept) => !concept.is_published);
    els.conceptList.innerHTML = [
      renderConceptGroup("已发布", published, "published"),
      renderConceptGroup("已隐藏", hidden, "hidden-group"),
    ].join("");
    return;
  }

  els.conceptList.innerHTML = renderConceptCards(concepts);
}

async function loadCategories() {
  state.categories = await api("/concepts/categories/");
  renderCategoryOptions();
  renderCategories();
}

async function loadConcepts() {
  const params = new URLSearchParams({ limit: "500", include_unpublished: "true", sort: "newest" });
  const search = els.conceptSearchInput.value.trim();
  const categoryId = els.conceptCategoryFilter.value;
  if (search) params.set("search", search);
  if (categoryId) params.set("category_id", categoryId);
  const data = await api(`/concepts?${params.toString()}`);
  state.concepts = data.data || [];
  renderConcepts();
}

async function loadKnowledge() {
  await Promise.all([loadCategories(), loadConcepts()]);
}

function renderProjects() {
  if (!state.projects.length) {
    els.projectList.innerHTML = `<div class="empty-state small"><h3>暂无项目</h3><p>先创建一个项目。</p></div>`;
    return;
  }
  els.projectList.innerHTML = state.projects.map((project) => `
    <button class="project-item ${state.activeProjectId === project.id ? "active" : ""}" type="button" data-project-id="${project.id}">
      <strong>${escapeHtml(project.name)}</strong>
      <span>${escapeHtml(project.protocol_no || project.phase || PROJECT_TYPE_LABELS[project.project_type] || "未填写方案信息")}</span>
      <em>${project.open_todo_count || 0} 个未完成 · ${project.meeting_count || 0} 个会议</em>
    </button>
  `).join("");
}

function renderProjectWorkspace() {
  const project = state.projects.find((item) => item.id === state.activeProjectId);
  els.projectEmpty.classList.toggle("hidden", Boolean(project));
  els.projectWorkspace.classList.toggle("hidden", !project);
  if (!project) return;

  els.activeProjectName.textContent = project.name;
  els.activeProjectMeta.textContent = [
    project.protocol_no,
    project.sponsor,
    project.phase,
    PROJECT_TYPE_LABELS[project.project_type] || PROJECT_TYPE_LABELS.other,
    !project.is_cdisc && project.description?.includes("[snapshot:cdisc-unconfirmed]") ? "CDISC 待确认" : project.is_cdisc ? "CDISC" : "非CDISC",
    project.current_workflow_phase ? `当前：${project.current_workflow_phase}` : "",
    project.indication,
  ].filter(Boolean).join(" · ") || "未填写项目元数据";
  const displayDescription = (project.description || "").replaceAll("[snapshot:cdisc-unconfirmed]", "").trim();
  els.activeProjectDescription.textContent = displayDescription;
  els.activeProjectDescription.classList.toggle("hidden", !displayDescription);

  renderTodos();
  renderMeetings();
  renderMembers();
  renderTimelineImports();
  switchProjectTab(state.activeProjectTab);
}

function todoStatusLabel(status) {
  return {
    open: "未开始",
    in_progress: "进行中",
    done: "已完成",
    blocked: "阻塞",
    cancelled: "取消",
  }[status] || status;
}

function normalizeTodoPhase(phase) {
  return !phase || phase === "额外待办" ? "流程待办" : phase;
}

function phaseSortOrder(phase) {
  const value = Number(phase?.sort_order || 0);
  return value > 0 ? value : 100000;
}

function todoSortOrder(todo) {
  const value = Number(todo?.sort_order || 0);
  return value > 0 ? value : 100000;
}

function compareTodos(a, b) {
  const orderDiff = todoSortOrder(a) - todoSortOrder(b);
  if (orderDiff) return orderDiff;
  const aDue = a.due_at ? new Date(a.due_at).getTime() : Number.MAX_SAFE_INTEGER;
  const bDue = b.due_at ? new Date(b.due_at).getTime() : Number.MAX_SAFE_INTEGER;
  if (aDue !== bDue) return aDue - bDue;
  return a.id - b.id;
}

function orderedProjectPhases() {
  const phases = [...state.projectPhases].sort((a, b) => {
    const orderDiff = phaseSortOrder(a) - phaseSortOrder(b);
    if (orderDiff) return orderDiff;
    return String(a.name || "").localeCompare(String(b.name || ""), "zh-Hans-CN");
  });
  const names = new Set(phases.map((phase) => phase.name));
  for (const todo of state.todos) {
    const name = normalizeTodoPhase(todo.phase);
    if (!names.has(name)) {
      names.add(name);
      phases.push({ id: 0, name, sort_order: phaseSortOrder(null) + names.size });
    }
  }
  return phases;
}

function groupedTodosByPhase() {
  const grouped = new Map();
  for (const phase of orderedProjectPhases()) {
    grouped.set(phase.name, []);
  }
  for (const todo of state.todos) {
    const name = normalizeTodoPhase(todo.phase);
    if (!grouped.has(name)) grouped.set(name, []);
    grouped.get(name).push(todo);
  }
  for (const list of grouped.values()) {
    list.sort(compareTodos);
  }
  return grouped;
}

function renderProjectPhaseOptions() {
  if (!els.projectPhaseOptions) return;
  els.projectPhaseOptions.innerHTML = orderedProjectPhases()
    .map((phase) => `<option value="${escapeHtml(phase.name)}"></option>`)
    .join("");
}

function formatTimeOnly(value) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleTimeString("zh-CN", { hour12: false, hour: "2-digit", minute: "2-digit" });
}

function formatMeetingRange(meeting) {
  if (!meeting?.starts_at && !meeting?.ends_at) return "未设置会议时间段";
  if (meeting.starts_at && meeting.ends_at) {
    const startsAt = new Date(meeting.starts_at);
    const endsAt = new Date(meeting.ends_at);
    const sameDay =
      !Number.isNaN(startsAt.getTime()) &&
      !Number.isNaN(endsAt.getTime()) &&
      startsAt.toDateString() === endsAt.toDateString();
    if (sameDay) return `${formatDateTime(meeting.starts_at)} - ${formatTimeOnly(meeting.ends_at)}`;
    return `${formatDateTime(meeting.starts_at)} - ${formatDateTime(meeting.ends_at)}`;
  }
  return meeting.starts_at ? `开始 ${formatDateTime(meeting.starts_at)}` : `结束 ${formatDateTime(meeting.ends_at)}`;
}

function findMeeting(id) {
  return state.meetings.find((meeting) => meeting.id === Number(id));
}

function allChecklistItems() {
  const items = [];
  for (const todo of state.todos) {
    for (const item of todo.checklist_items || []) {
      items.push({ todo, item });
    }
  }
  return items;
}

function checklistLabel(todo, item) {
  return `${todo?.title || "待办"} / ${item?.title || "清单项"}`;
}

function boundChecklistForMeeting(meetingId) {
  return allChecklistItems().find(({ item }) => Number(item.meeting_id) === Number(meetingId));
}

function renderChecklistMeetingOptions(selectedMeetingId = "") {
  if (!els.checklistMeetingId) return;
  els.checklistMeetingId.innerHTML = [
    `<option value="">不绑定会议</option>`,
    ...state.meetings.map((meeting) => (
      `<option value="${meeting.id}" ${Number(selectedMeetingId) === meeting.id ? "selected" : ""}>` +
      `${escapeHtml(meeting.title)} · ${escapeHtml(formatMeetingRange(meeting))}</option>`
    )),
  ].join("");
}

function renderMeetingChecklistOptions(selectedChecklistId = "") {
  if (!els.meetingChecklistId) return;
  els.meetingChecklistId.innerHTML = [
    `<option value="">不绑定清单</option>`,
    ...allChecklistItems().map(({ todo, item }) => (
      `<option value="${item.id}" ${Number(selectedChecklistId) === item.id ? "selected" : ""}>` +
      `${escapeHtml(checklistLabel(todo, item))}</option>`
    )),
  ].join("");
}

function renderChecklistItems(todo) {
  const items = todo.checklist_items || [];
  const itemRows = items.length ? items.map((item) => {
    const meeting = findMeeting(item.meeting_id);
    return `
    <li class="${item.is_done ? "done" : ""}">
      <button class="ghost tiny" type="button" data-action="toggle-checklist" data-id="${item.id}">
        ${item.is_done ? "已完成" : "完成"}
      </button>
      <span class="checklist-title">${escapeHtml(item.title)}</span>
      ${item.due_at ? `<em>清单截止 ${formatDateTime(item.due_at)}</em>` : ""}
      ${meeting ? `
        <button class="ghost tiny meeting-link" type="button" data-action="view-meeting" data-id="${meeting.id}">
          查看会议详情
        </button>
        <em>${escapeHtml(formatMeetingRange(meeting))}</em>
      ` : ""}
      <button class="ghost tiny" type="button" data-action="edit-checklist" data-id="${item.id}">编辑</button>
      <button class="ghost danger tiny" type="button" data-action="delete-checklist" data-id="${item.id}">删除</button>
    </li>
  `;
  }).join("") : `<li class="muted">暂无清单项</li>`;
  return `
    <details class="checklist-mini">
      <summary class="checklist-mini-head">
        <span>清单 ${items.filter((item) => item.is_done).length}/${items.length}</span>
        <em>展开查看截止时间和绑定会议</em>
        <button class="ghost tiny" type="button" data-action="add-checklist" data-id="${todo.id}">添加清单</button>
      </summary>
      <ul>${itemRows}</ul>
    </details>
  `;
}

function renderTodoRow(todo, phaseName) {
  return `
    <article class="todo-row ${todo.status === "done" ? "done" : ""}" draggable="true" data-todo-id="${todo.id}" data-phase="${escapeHtml(phaseName)}">
      <div>
        <div class="concept-meta">
          <span>${escapeHtml(phaseName)}</span>
          <span class="pill ${todo.status === "done" ? "ok" : "pending"}">${todoStatusLabel(todo.status)}</span>
          ${(todo.description || '').startsWith('[流程推断]') ? '<span class="pill">流程推断 · 可修改</span>' : ''}
          <span>${todo.priority || "normal"}</span>
          ${todo.start_at ? `<span>开始 ${formatDateTime(todo.start_at)}</span>` : ""}
          ${todo.due_at ? `<span>截止 ${formatDateTime(todo.due_at)}</span>` : ""}
        </div>
        <h3>${escapeHtml(todo.title)}</h3>
        ${todo.description ? `<p>${escapeHtml(todo.description)}</p>` : ""}
        ${renderChecklistItems(todo)}
      </div>
      <div class="row-actions">
        <span class="drag-handle" title="拖动调整顺序">☰</span>
        <button class="ghost" type="button" data-action="complete-todo" data-id="${todo.id}">${todo.status === "done" ? "重开" : "完成"}</button>
        <button type="button" data-action="edit-todo" data-id="${todo.id}">编辑</button>
      </div>
    </article>
  `;
}

function renderTodoContainer(container) {
  const phases = orderedProjectPhases();
  if (!phases.length) {
    container.innerHTML = `<div class="empty-state"><h3>暂无待办</h3><p>可以手动新增，或用智能解析创建。</p></div>`;
    return;
  }
  const grouped = groupedTodosByPhase();
  container.innerHTML = phases.map((phase, index) => {
    const todos = grouped.get(phase.name) || [];
    const done = todos.filter((todo) => todo.status === "done").length;
    const isOpen = state.openProjectPhases.has(phase.name);
    const canMoveUp = Boolean(phase.id) && index > 0;
    const canMoveDown = Boolean(phase.id) && index < phases.filter((item) => item.id).length - 1;
    return `
      <details class="phase-section" data-phase="${escapeHtml(phase.name)}" ${isOpen ? "open" : ""}>
        <summary>
          <div>
            <strong>${escapeHtml(phase.name)}</strong>
            <span>${done}/${todos.length} 完成</span>
          </div>
          <div class="phase-actions">
            <button class="ghost tiny" type="button" data-action="add-phase-todo" data-phase="${escapeHtml(phase.name)}">新增待办</button>
            ${phase.id ? `<button class="ghost tiny" type="button" data-action="edit-phase" data-id="${phase.id}">编辑</button>` : ""}
            ${canMoveUp ? `<button class="ghost tiny" type="button" data-action="move-phase-up" data-id="${phase.id}">上移</button>` : ""}
            ${canMoveDown ? `<button class="ghost tiny" type="button" data-action="move-phase-down" data-id="${phase.id}">下移</button>` : ""}
            ${phase.id ? `<button class="ghost danger tiny" type="button" data-action="delete-phase" data-id="${phase.id}">删除</button>` : ""}
          </div>
        </summary>
        <div class="phase-todo-dropzone" data-phase="${escapeHtml(phase.name)}">
          ${todos.length ? todos.map((todo) => renderTodoRow(todo, phase.name)).join("") : `<div class="empty-state small"><p>本阶段暂无待办。</p></div>`}
        </div>
      </details>
    `;
  }).join("");
}

function renderTodos() {
  renderProjectPhaseOptions();
  renderTodoContainer(els.standardTodos);
}

function renderMeetings() {
  if (!state.meetings.length) {
    els.meetingList.innerHTML = `<div class="empty-state"><h3>暂无会议</h3><p>可以快捷创建会议，或粘贴会议通知让助手解析。</p></div>`;
    return;
  }
  els.meetingList.innerHTML = state.meetings.map((meeting) => `
    <article class="todo-row">
        <div>
          <div class="concept-meta">
          <span>${escapeHtml(formatMeetingRange(meeting))}</span>
          ${meeting.location ? `<span>${escapeHtml(meeting.location)}</span>` : ""}
        </div>
        <h3>${escapeHtml(meeting.title)}</h3>
        ${meeting.agenda ? `<p>${escapeHtml(meeting.agenda)}</p>` : ""}
        ${meeting.meeting_url ? `<a href="${escapeHtml(meeting.meeting_url)}" target="_blank" rel="noreferrer">打开会议链接</a>` : ""}
      </div>
      <div class="row-actions">
        <button type="button" data-action="edit-meeting" data-id="${meeting.id}">编辑</button>
      </div>
    </article>
  `).join("");
}

function memberTypeLabel(value) {
  return {
    sponsor: "申办方",
    statistical_partner: "合作统计方",
    internal: "内部团队",
    other: "其他",
  }[value] || "其他";
}

function renderMembers() {
  const types = ["sponsor", "statistical_partner", "internal", "other"];
  const groups = types.map((type) => {
    const members = state.members.filter((item) => item.member_type === type);
    if (!members.length) return "";
    return `
      <section class="member-group">
        <div class="section-heading"><h3>${memberTypeLabel(type)}</h3><span>${members.length} 人</span></div>
        <div class="member-grid">
          ${members.map((member) => `
            <article class="member-card">
              <div>
                <h3>${escapeHtml(member.name)}</h3>
                <p>${escapeHtml([member.organization, member.role].filter(Boolean).join(" · ") || "未填写职责")}</p>
                <p class="muted">${escapeHtml([member.email, member.phone, member.notes].filter(Boolean).join(" · ") || "")}</p>
              </div>
              <div class="row-actions">
                <button class="ghost tiny" type="button" data-action="edit-member" data-id="${member.id}">编辑</button>
                <button class="ghost danger tiny" type="button" data-action="delete-member" data-id="${member.id}">删除</button>
              </div>
            </article>
          `).join("")}
        </div>
      </section>
    `;
  }).join("");
  els.memberList.innerHTML = `
    <div class="section-heading">
      <div><h3>项目相关成员</h3><span>按角色维护项目协作关系</span></div>
      <div class="button-row">
        <button class="ghost" type="button" data-action="parse-members">AI 识别成员</button>
        <button type="button" data-action="add-member">添加成员</button>
      </div>
    </div>
    ${groups || `<div class="empty-state"><h3>暂无成员</h3><p>可以手动添加，或粘贴成员信息交给 AI 分类。</p></div>`}
  `;
}

function checklistTargetLabel(todo, item) {
  return `清单 · ${todo?.title || "任务"} / ${item?.title || "清单事项"}`;
}

function timelineTargetValue(item) {
  if (item.target_type === "todo" && item.matched_todo_id) return `todo-${item.matched_todo_id}`;
  if (item.target_type === "checklist" && item.matched_checklist_item_id) return `checklist-${item.matched_checklist_item_id}`;
  return "none";
}

function timelineTargetLabel(item) {
  if (item.target_type === "todo" && item.matched_todo_id) {
    return state.todos.find((todo) => todo.id === item.matched_todo_id)?.title || "已绑定任务";
  }
  if (item.target_type === "checklist" && item.matched_checklist_item_id) {
    const found = allChecklistItems().find(({ item: checklist }) => checklist.id === item.matched_checklist_item_id);
    return found ? checklistTargetLabel(found.todo, found.item) : "已绑定清单";
  }
  return "未绑定";
}

function renderTimelineImports() {
  const imports = state.timelineImports || [];
  els.timelineList.innerHTML = `
    <div class="section-heading">
      <div><h3>项目 Timeline</h3><span>导入后自动识别日期并匹配到任务或清单，低置信度记录可人工修正</span></div>
      <div class="button-row">
        <button class="ghost" type="button" data-action="import-timeline-text">粘贴文字</button>
        <button type="button" data-action="pick-timeline-file">导入 Excel/CSV</button>
      </div>
    </div>
    ${imports.length ? imports.map((timeline) => `
      <details class="timeline-import" open>
        <summary>
          <div><strong>${escapeHtml(timeline.file_name || "文字 Timeline")}</strong><span>${timeline.items?.length || 0} 条 · ${escapeHtml(timeline.status || "parsed")}${timeline.fallback_used ? " · 本地规则" : ""}</span></div>
          <button class="ghost danger tiny" type="button" data-action="delete-timeline" data-id="${timeline.id}">删除记录</button>
        </summary>
        <div class="timeline-items">
          ${(timeline.items || []).map((item) => `
            <article class="timeline-item ${item.target_type === "none" ? "unmatched" : "matched"}">
              <div>
                <div class="concept-meta"><span>第 ${item.row_number} 行</span><span>${escapeHtml(item.phase || "未指定阶段")}</span><span>${item.target_type === "none" ? "未匹配" : "已匹配"}</span></div>
                <h3>${escapeHtml(item.title)}</h3>
                <p>${escapeHtml(item.description || "")}</p>
                <p class="muted">${escapeHtml(item.start_at ? `开始 ${formatDateTime(item.start_at)}` : "")}${item.due_at ? ` · 截止 ${formatDateTime(item.due_at)}` : ""}</p>
                <p class="muted">目标：${escapeHtml(timelineTargetLabel(item))}${item.confidence != null ? ` · 置信度 ${Math.round(item.confidence * 100)}%` : ""}</p>
                ${item.warning ? `<p class="warning-text">${escapeHtml(item.warning)}</p>` : ""}
              </div>
              <div class="row-actions"><button type="button" data-action="edit-timeline" data-id="${item.id}">编辑匹配/日期</button></div>
            </article>
          `).join("")}
        </div>
      </details>
    `).join("") : `<div class="empty-state"><h3>暂无 Timeline</h3><p>支持文字、CSV、TSV、XLS、XLSX、XLSM 和文本格式。</p></div>`}
  `;
}

function openMemberDialog(member = null) {
  els.memberDialogTitle.textContent = member ? "编辑项目成员" : "添加项目成员";
  els.memberEditId.value = member?.id || "";
  els.memberType.value = member?.member_type || "other";
  els.memberName.value = member?.name || "";
  els.memberOrganization.value = member?.organization || "";
  els.memberRole.value = member?.role || "";
  els.memberEmail.value = member?.email || "";
  els.memberPhone.value = member?.phone || "";
  els.memberNotes.value = member?.notes || "";
  els.deleteMemberButton.classList.toggle("hidden", !member);
  els.memberDialog.showModal();
}

function readMemberPayload() {
  return {
    member_type: els.memberType.value,
    name: els.memberName.value.trim(),
    organization: els.memberOrganization.value.trim() || null,
    role: els.memberRole.value.trim() || null,
    email: els.memberEmail.value.trim() || null,
    phone: els.memberPhone.value.trim() || null,
    notes: els.memberNotes.value.trim() || null,
  };
}

async function saveMember() {
  if (!state.activeProjectId) throw new Error("请先选择项目");
  const payload = readMemberPayload();
  if (!payload.name) throw new Error("成员姓名不能为空");
  const id = els.memberEditId.value;
  await api(id ? `/projects/members/${id}` : `/projects/${state.activeProjectId}/members`, {
    method: id ? "PUT" : "POST",
    body: JSON.stringify(payload),
  });
  els.memberDialog.close();
  setMessage("项目成员已保存");
  await loadActiveProjectData();
}

async function deleteMember(id = null) {
  const memberId = id || els.memberEditId.value;
  const member = state.members.find((item) => item.id === Number(memberId));
  if (!member || !window.confirm(`确定删除成员“${member.name}”吗？`)) return;
  await api(`/projects/members/${member.id}`, { method: "DELETE" });
  if (els.memberDialog.open) els.memberDialog.close();
  setMessage("项目成员已删除");
  await loadActiveProjectData();
}

function openMemberTextDialog() {
  els.memberText.value = "";
  els.memberTextDialog.showModal();
}

async function parseMemberText() {
  if (!state.activeProjectId || !els.memberText.value.trim()) throw new Error("请先粘贴成员信息");
  els.parseMemberTextButton.disabled = true;
  try {
    const result = await api(`/projects/${state.activeProjectId}/members/parse`, {
      method: "POST",
      body: JSON.stringify({ text: els.memberText.value.trim(), create_records: true }),
    });
    els.memberTextDialog.close();
    setMessage(`已识别并保存 ${result.created_count || 0} 位成员${result.fallback_used ? "（本地规则）" : ""}`);
    await loadActiveProjectData();
  } finally {
    els.parseMemberTextButton.disabled = false;
  }
}

function openTimelineTextDialog() {
  els.timelineText.value = "";
  els.timelineTextDialog.showModal();
}

async function importTimelineText() {
  const text = els.timelineText.value.trim();
  if (!state.activeProjectId || !text) throw new Error("请先粘贴 Timeline 内容");
  els.importTimelineTextButton.disabled = true;
  try {
    const result = await api(`/projects/${state.activeProjectId}/timeline/text`, {
      method: "POST",
      body: JSON.stringify({ source_text: text }),
    });
    els.timelineTextDialog.close();
    setMessage(`Timeline 已导入：${result.items?.length || 0} 条，已尝试自动匹配`);
    await loadActiveProjectData();
  } finally {
    els.importTimelineTextButton.disabled = false;
  }
}

async function importTimelineFile(file) {
  if (!state.activeProjectId || !file) return;
  const form = new FormData();
  form.append("file", file);
  const headers = state.token ? { Authorization: `Bearer ${state.token}` } : {};
  const response = await fetch(`/api/v1/projects/${state.activeProjectId}/timeline/file`, {
    method: "POST",
    headers,
    body: form,
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.detail || `HTTP ${response.status}`);
  setMessage(`Timeline 已导入：${data.items?.length || 0} 条，已尝试自动匹配`);
  await loadActiveProjectData();
}

function openTimelineItemDialog(item) {
  if (!item) return;
  els.timelineItemId.value = item.id;
  els.timelineItemTitle.value = item.title || "";
  els.timelineItemStartAt.value = toLocalInputValue(item.start_at);
  els.timelineItemDueAt.value = toLocalInputValue(item.due_at);
  const selected = timelineTargetValue(item);
  els.timelineItemTarget.innerHTML = [
    `<option value="none">未绑定项目事项</option>`,
    ...state.todos.map((todo) => `<option value="todo-${todo.id}">任务 · ${escapeHtml(todo.title)}</option>`),
    ...allChecklistItems().map(({ todo, item: checklist }) => `<option value="checklist-${checklist.id}">${escapeHtml(checklistTargetLabel(todo, checklist))}</option>`),
  ].join("");
  els.timelineItemTarget.value = [...els.timelineItemTarget.options].some((option) => option.value === selected) ? selected : "none";
  els.timelineItemDialog.showModal();
}

async function saveTimelineItem() {
  const id = Number(els.timelineItemId.value);
  const value = els.timelineItemTarget.value;
  const targetType = value.startsWith("todo-") ? "todo" : value.startsWith("checklist-") ? "checklist" : "none";
  const payload = {
    title: els.timelineItemTitle.value.trim(),
    target_type: targetType,
    matched_todo_id: targetType === "todo" ? Number(value.slice(5)) : null,
    matched_checklist_item_id: targetType === "checklist" ? Number(value.slice(10)) : null,
    start_at: fromLocalInputValue(els.timelineItemStartAt.value),
    due_at: fromLocalInputValue(els.timelineItemDueAt.value),
  };
  if (!payload.title) throw new Error("Timeline 事项标题不能为空");
  await api(`/projects/timeline/items/${id}`, { method: "PUT", body: JSON.stringify(payload) });
  els.timelineItemDialog.close();
  setMessage("Timeline 事项已保存，日期已同步到目标事项");
  await loadActiveProjectData();
}

async function deleteTimelineImport(id) {
  const timeline = state.timelineImports.find((item) => item.id === Number(id));
  if (!timeline || !window.confirm("确定删除这条 Timeline 导入记录吗？不会删除本地文件。")) return;
  await api(`/projects/timeline/${timeline.id}`, { method: "DELETE" });
  setMessage("Timeline 导入记录已删除");
  await loadActiveProjectData();
}

async function loadProjects() {
  const data = await api("/projects?limit=200");
  state.projects = data.data || [];
  if (!state.activeProjectId && state.projects.length) {
    state.activeProjectId = state.projects[0].id;
  }
  renderProjects();
  await loadActiveProjectData();
}

async function loadActiveProjectData() {
  if (!state.activeProjectId) {
    state.projectPhases = [];
    state.todos = [];
    state.meetings = [];
    state.members = [];
    state.timelineImports = [];
    renderProjectWorkspace();
    return;
  }
  const [phaseData, todoData, meetingData, memberData, timelineData] = await Promise.all([
    api(`/projects/${state.activeProjectId}/phases`),
    api(`/projects/${state.activeProjectId}/todos`),
    api(`/projects/${state.activeProjectId}/meetings`),
    api(`/projects/${state.activeProjectId}/members`),
    api(`/projects/${state.activeProjectId}/timeline`),
  ]);
  state.projectPhases = phaseData.data || [];
  state.todos = todoData.data || [];
  state.meetings = meetingData.data || [];
  state.members = memberData.data || [];
  state.timelineImports = timelineData.data || [];
  renderProjectWorkspace();
}

async function loadVideos() {
  await loadVideoCategories();
  const params = new URLSearchParams({ limit: "200" });
  const search = els.searchInput.value.trim();
  const published = els.publishedFilter.value;
  const categoryId = els.videoCategoryFilter.value;
  if (search) params.set("search", search);
  if (published) params.set("published", published);
  if (categoryId) params.set("category_id", categoryId);
  const data = await api(`/admin/nas-videos?${params.toString()}`);
  state.videos = data.data;
  renderVideos();
}

async function loadVideoCategories() {
  state.videoCategories = await api("/admin/nas-video-categories");
  renderVideoCategoryOptions();
  renderVideoCategoryList();
}

function renderVideoCategoryOptions() {
  const selectedFilter = els.videoCategoryFilter.value;
  const selectedParent = els.videoCategoryParent.value;
  const selectedManualCategory = els.manualVideoCategory.value;
  const editCategory = $("#editVideoCategory");
  const selectedEditCategory = editCategory?.value || "";
  const options = state.videoCategories.map((category) => {
    const depth = Math.max(0, category.path.split("/").length - 1);
    return `<option value="${category.id}">${" ".repeat(depth * 2)}${escapeHtml(category.path)}</option>`;
  }).join("");
  const fullOptions = `<option value="">全部分类</option>${options}`;
  els.videoCategoryFilter.innerHTML = fullOptions;
  els.videoCategoryParent.innerHTML = `<option value="">无父级</option>${options}`;
  els.manualVideoCategory.innerHTML = `<option value="">未分类</option>${options}`;
  if (editCategory) editCategory.innerHTML = `<option value="">未分类</option>${options}`;
  els.videoCategoryFilter.value = selectedFilter;
  els.videoCategoryParent.value = selectedParent;
  els.manualVideoCategory.value = selectedManualCategory;
  if (editCategory) editCategory.value = selectedEditCategory;
}

function renderVideoCategoryList() {
  if (!els.videoCategoryList) return;
  if (!state.videoCategories.length) {
    els.videoCategoryList.innerHTML = `<div class="empty-state small"><h3>暂无分类</h3><p>扫描视频目录后会按文件夹自动生成。</p></div>`;
    return;
  }
  const selectedId = Number(els.videoCategoryFilter.value || 0);
  const childrenByParent = new Map();
  state.videoCategories.forEach((category) => {
    const parentId = category.parent_id || 0;
    if (!childrenByParent.has(parentId)) childrenByParent.set(parentId, []);
    childrenByParent.get(parentId).push(category);
  });

  const renderNode = (category, depth) => {
    const active = selectedId === category.id ? "active" : "";
    const children = childrenByParent.get(category.id) || [];
    const hasChildren = children.length > 0;
    const collapsed = state.collapsedVideoCategoryIds.has(category.id);
    const childMarkup = hasChildren && !collapsed
      ? children.map((child) => renderNode(child, depth + 1)).join("")
      : "";
    return `
      <article class="video-category-item ${active}" style="--depth: ${depth}">
        <div class="category-main">
          <button class="tree-toggle ${hasChildren ? "" : "placeholder"}" type="button" data-action="toggle-video-category" data-id="${category.id}" aria-label="${collapsed ? "展开" : "折叠"}分类" ${hasChildren ? "" : "disabled"}>
            ${hasChildren ? (collapsed ? "▸" : "▾") : ""}
          </button>
          <button class="category-filter-button" type="button" data-action="filter-video-category" data-id="${category.id}">
            <strong>${escapeHtml(category.name)}</strong>
            <span>${escapeHtml(category.path)} · ${category.video_count || 0} 个视频 · ${category.children_count || 0} 个子分类</span>
          </button>
        </div>
        <div class="row-actions">
          <button class="ghost" type="button" data-action="add-child-category" data-id="${category.id}">子分类</button>
          <button type="button" data-action="edit-video-category" data-id="${category.id}">编辑</button>
          <button class="ghost" type="button" data-action="publish-video-category" data-id="${category.id}">发布课程</button>
          <button class="ghost danger" type="button" data-action="delete-video-category" data-id="${category.id}">删除</button>
        </div>
      </article>
      ${childMarkup}
    `;
  };

  els.videoCategoryList.innerHTML = (childrenByParent.get(0) || [])
    .map((category) => renderNode(category, 0))
    .join("");
}

function renderVideos() {
  if (!state.videos.length) {
    els.tableBody.innerHTML = `<tr><td colspan="8">暂无视频。请先扫描 NAS 视频目录。</td></tr>`;
    return;
  }
  els.tableBody.innerHTML = state.videos.map((video) => {
    const title = video.title || video.lesson_title || "-";
    const status = video.published_video_id ? `<span class="pill ok">已发布</span>` : `<span class="pill pending">未发布</span>`;
    const thumbnail = video.thumbnail_url
      ? `<img class="video-cover-thumb" src="${escapeHtml(video.thumbnail_url)}" alt="封面" loading="lazy" />`
      : `<span class="thumb-empty">无封面</span>`;
    const sidecarMatch = state.videoSidecarMatches.get(video.id);
    const sidecarStatus = sidecarMatch
      ? `<span class="pill ok">字幕 ${sidecarMatch.subtitle_count || 0} / 弹幕 ${sidecarMatch.danmaku_count || 0}</span>`
      : "";
    return `
      <tr>
        <td><div class="file-name">${escapeHtml(video.file_name)}</div><div class="file-path">${escapeHtml(video.relative_path)}</div></td>
        <td>${thumbnail}</td>
        <td>
          <div>${escapeHtml(video.category_path || "未分类")}</div>
          <div class="file-path">第 ${video.episode_number || "-"} 集 · 排序 ${video.sort_order || 0}</div>
        </td>
        <td>${escapeHtml(video.course_name || "-")}</td>
        <td>${escapeHtml(title)}</td>
        <td>${formatSize(video.file_size)}</td>
        <td><div class="status-stack">${status}${sidecarStatus}</div></td>
        <td><div class="row-actions"><button class="ghost" type="button" data-action="ai-organize" data-id="${video.id}">AI整理</button><button class="ghost" type="button" data-action="edit" data-id="${video.id}">编辑</button><button class="ghost danger" type="button" data-action="delete-record" data-id="${video.id}">删除记录</button><button type="button" data-action="publish" data-id="${video.id}">发布</button></div></td>
      </tr>
    `;
  }).join("");
}

function renderVideoReorderList() {
  if (!els.videoReorderList) return;
  els.videoReorderList.innerHTML = state.reorderVideos.map((video, index) => {
    const title = video.title || video.lesson_title || video.file_name || "未命名视频";
    const episode = video.episode_number ? `第 ${video.episode_number} 集` : "未设集数";
    return `
      <li class="video-reorder-item" draggable="true" data-video-id="${video.id}">
        <span class="video-reorder-handle" aria-hidden="true">⋮⋮</span>
        <strong>${index + 1}</strong>
        <div>
          <b>${escapeHtml(title)}</b>
          <span>${escapeHtml(video.category_path || "未分类")} · ${episode}</span>
        </div>
      </li>
    `;
  }).join("");
}

async function openVideoReorderDialog() {
  if (els.searchInput.value.trim()) {
    throw new Error("请先清空关键词搜索，再调整完整课程的顺序");
  }
  const params = new URLSearchParams({ limit: "1000" });
  const categoryId = els.videoCategoryFilter.value;
  if (categoryId) params.set("category_id", categoryId);
  const data = await api(`/admin/nas-videos?${params.toString()}`);
  state.reorderVideos = data.data || [];
  if (!state.reorderVideos.length) {
    throw new Error("当前分类没有可排序的视频");
  }
  renderVideoReorderList();
  els.videoReorderDialog.showModal();
}

function syncVideoReorderFromDom() {
  const ids = [...els.videoReorderList.querySelectorAll("[data-video-id]")]
    .map((item) => Number(item.dataset.videoId));
  const byId = new Map(state.reorderVideos.map((video) => [video.id, video]));
  state.reorderVideos = ids.map((id) => byId.get(id)).filter(Boolean);
}

async function saveVideoReorder() {
  const videoIds = state.reorderVideos.map((video) => video.id);
  await api("/admin/nas-videos/reorder", {
    method: "PUT",
    body: JSON.stringify({ video_ids: videoIds }),
  });
  els.videoReorderDialog.close();
  setMessage(`已保存 ${videoIds.length} 个视频的人工排序；后续扫描和 AI 整理不会覆盖该顺序。`);
  await loadVideos();
}

async function refreshAll() {
  if (!state.token) return;
  try {
    await Promise.all([loadStats(), loadKnowledge(), loadProjects(), loadVideos()]);
  } catch (error) {
    if (error.status === 401 || error.status === 403) logout();
    setMessage(error.message, true);
  }
}

function openConceptDialog(concept = null) {
  const isEdit = Boolean(concept);
  els.conceptDialogTitle.textContent = isEdit ? "编辑概念" : "新增概念";
  els.conceptEditId.value = concept?.id || "";
  els.conceptTitle.value = concept?.title || "";
  els.conceptCategory.value = concept?.category_id || concept?.category?.id || state.categories[0]?.id || "";
  els.conceptSummary.value = concept?.summary || "";
  els.conceptContent.value = concept?.content || "";
  els.conceptTags.value = compactTags(concept?.tags || []);
  els.conceptFormulas.value = formatJson((concept?.formulas || []).map((formula) => ({
    name: formula.name,
    expression: formula.expression,
    description: formula.description || "",
    variables: (formula.variables || []).map((variable) => ({
      symbol: variable.symbol,
      name: variable.name,
      description: variable.description || "",
    })),
  })));
  els.conceptExamples.value = formatJson((concept?.examples || []).map((example) => ({
    title: example.title,
    description: example.description || "",
    solution: example.solution || "",
    result: example.result || "",
  })));
  els.conceptPublished.checked = concept?.is_published ?? true;
  els.deleteConceptButton.classList.toggle("hidden", !isEdit);
  els.conceptDialog.showModal();
}

function readJsonArray(text, label) {
  const trimmed = text.trim();
  if (!trimmed) return [];
  const value = JSON.parse(trimmed);
  if (!Array.isArray(value)) throw new Error(`${label} 必须是 JSON 数组`);
  return value;
}

function readConceptPayload() {
  const categoryId = Number(els.conceptCategory.value);
  if (!categoryId) throw new Error("请选择分类");
  return {
    title: els.conceptTitle.value.trim(),
    category_id: categoryId,
    summary: els.conceptSummary.value.trim() || null,
    content: els.conceptContent.value.trim(),
    tags: els.conceptTags.value.split(/[，,]/).map((tag) => tag.trim()).filter(Boolean),
    formulas: readJsonArray(els.conceptFormulas.value, "公式 JSON"),
    examples: readJsonArray(els.conceptExamples.value, "示例 JSON"),
    is_published: els.conceptPublished.checked,
  };
}

async function saveCurrentConcept() {
  const id = els.conceptEditId.value;
  const payload = readConceptPayload();
  if (!payload.title || !payload.content) throw new Error("标题和正文不能为空");
  if (id) {
    await api(`/concepts/${id}`, { method: "PUT", body: JSON.stringify(payload) });
  } else {
    const { is_published: _isPublished, ...createPayload } = payload;
    const created = await api("/concepts", { method: "POST", body: JSON.stringify(createPayload) });
    if (!payload.is_published) {
      await api(`/concepts/${created.id}`, { method: "PUT", body: JSON.stringify({ is_published: false }) });
    }
  }
  els.conceptDialog.close();
  setMessage("概念已保存");
  await Promise.all([loadStats(), loadKnowledge()]);
}

async function deleteCurrentConcept() {
  const id = els.conceptEditId.value;
  if (!id || !window.confirm("确定删除这个概念吗？删除后不可恢复。")) return;
  await api(`/concepts/${id}`, { method: "DELETE" });
  els.conceptDialog.close();
  setMessage("概念已删除");
  await Promise.all([loadStats(), loadKnowledge()]);
}

async function toggleConceptPublish(id) {
  const concept = state.concepts.find((item) => item.id === id);
  if (!concept) return;
  await api(`/concepts/${id}`, { method: "PUT", body: JSON.stringify({ is_published: !concept.is_published }) });
  setMessage(concept.is_published ? "概念已隐藏" : "概念已发布");
  await Promise.all([loadStats(), loadKnowledge()]);
}

function openProjectDialog(project = null) {
  const isEdit = Boolean(project);
  state.projectIntakeDraft = null;
  els.projectDialogTitle.textContent = isEdit ? "编辑项目" : "新建项目";
  els.projectEditId.value = project?.id || "";
  els.projectName.value = project?.name || "";
  els.projectProtocolNo.value = project?.protocol_no || "";
  els.projectSponsor.value = project?.sponsor || "";
  els.projectPhase.value = project?.phase || "";
  els.projectType.value = project?.project_type || "other";
  els.projectIsCdisc.checked = project?.is_cdisc === true;
  els.projectIndication.value = project?.indication || "";
  els.projectDescription.value = project?.description || "";
  let cdiscResolution = document.getElementById("projectCdiscResolution");
  if (!cdiscResolution) {
    const label = document.createElement("label");
    label.id = "projectCdiscResolutionRow";
    label.textContent = "CDISC 状态确认";
    cdiscResolution = document.createElement("select");
    cdiscResolution.id = "projectCdiscResolution";
    for (const [value, text] of [["unknown", "待确认"], ["yes", "CDISC 项目"], ["no", "非 CDISC 项目"]]) {
      const option = document.createElement("option");
      option.value = value; option.textContent = text; cdiscResolution.append(option);
    }
    label.append(cdiscResolution);
    els.projectIsCdisc.closest("label").after(label);
    const confirmCdisc = (value) => {
      els.projectIsCdisc.checked = value === "yes";
      const description = els.projectDescription.value.replaceAll("[snapshot:cdisc-unconfirmed]", "").trim();
      els.projectDescription.value = value === "unknown" ? `${description}\n[snapshot:cdisc-unconfirmed]` : description;
    };
    cdiscResolution.addEventListener("change", () => confirmCdisc(cdiscResolution.value));
    els.projectIsCdisc.addEventListener("change", () => {
      cdiscResolution.value = els.projectIsCdisc.checked ? "yes" : "no";
      confirmCdisc(cdiscResolution.value);
    });
  }
  document.getElementById("projectCdiscResolutionRow").hidden = !project?.description?.includes("[snapshot:cdisc-unconfirmed]") || project?.is_cdisc === true;
  cdiscResolution.value = "unknown";
  els.projectStatus.value = project?.status || "active";
  els.projectCreateWorkflow.checked = !isEdit;
  els.projectCreateWorkflowRow.classList.toggle("hidden", isEdit);
  els.projectIntakeRow.classList.toggle("hidden", isEdit);
  els.projectIntakeText.value = "";
  els.projectIntakePreview.textContent = "";
  els.projectIntakePreview.classList.add("hidden");
  els.saveProjectButton.textContent = isEdit ? "保存项目" : "创建项目";
  els.projectDialog.showModal();
}

async function parseProjectIntake() {
  const text = els.projectIntakeText.value.trim();
  if (!text) throw new Error("请先粘贴项目介绍或当前进展");
  els.parseProjectIntakeButton.disabled = true;
  els.parseProjectIntakeButton.textContent = "识别中...";
  try {
    const result = await api("/projects/assistant/project-intake/draft", {
      method: "POST",
      body: JSON.stringify({ text, create_standard_workflow: true }),
    });
    state.projectIntakeDraft = result;
    els.projectName.value = result.name || "";
    els.projectProtocolNo.value = result.protocol_no || "";
    els.projectSponsor.value = result.sponsor || "";
    els.projectPhase.value = result.phase || "";
    els.projectType.value = result.project_type || "other";
    els.projectIsCdisc.checked = result.is_cdisc === true;
    els.projectIndication.value = result.indication || "";
    els.projectDescription.value = result.description || "";
    const completed = (result.completed_todo_titles || []).length;
    const inProgress = (result.in_progress_todo_titles || []).length;
    const todos = (result.todos || []).length;
    const current = result.current_phase ? `当前阶段：${result.current_phase} · ` : "";
    const type = PROJECT_TYPE_LABELS[result.project_type] || PROJECT_TYPE_LABELS.other;
    const cdisc = result.is_cdisc === true ? "CDISC" : "非CDISC";
    els.projectIntakePreview.textContent = `${current}${type} · ${cdisc} · 已完成 ${completed} 项 · 进行中 ${inProgress} 项 · 新增待办 ${todos} 项${result.fallback_used ? " · 使用本地规则兜底" : ` · ${result.model_used || "AI"}`}`;
    els.projectIntakePreview.classList.remove("hidden");
  } finally {
    els.parseProjectIntakeButton.disabled = false;
    els.parseProjectIntakeButton.textContent = "AI 识别项目与进度";
  }
}

async function saveProject() {
  const id = els.projectEditId.value;
  const name = els.projectName.value.trim();
  if (!name) throw new Error("项目名称不能为空");
  const payload = {
    name,
    protocol_no: els.projectProtocolNo.value.trim() || null,
    sponsor: els.projectSponsor.value.trim() || null,
    phase: els.projectPhase.value.trim() || null,
    project_type: els.projectType.value || "other",
    is_cdisc: els.projectIsCdisc.checked,
    indication: els.projectIndication.value.trim() || null,
    description: els.projectDescription.value.trim() || null,
    status: els.projectStatus.value || "active",
  };
  let project;
  if (id) {
    project = await api(`/projects/${id}`, {
      method: "PUT",
      body: JSON.stringify(payload),
    });
  } else if (state.projectIntakeDraft && els.projectIntakeText.value.trim()) {
    project = (await api("/projects/assistant/project-intake", {
      method: "POST",
      body: JSON.stringify({
        ...state.projectIntakeDraft,
        name: payload.name,
        protocol_no: payload.protocol_no,
        sponsor: payload.sponsor,
        phase: payload.phase,
        project_type: payload.project_type,
        is_cdisc: payload.is_cdisc,
        indication: payload.indication,
        description: payload.description,
        status: payload.status,
        text: els.projectIntakeText.value.trim(),
        create_standard_workflow: els.projectCreateWorkflow.checked,
      }),
    })).project;
  } else {
    project = await api("/projects", {
      method: "POST",
      body: JSON.stringify({
        ...payload,
        create_standard_workflow: els.projectCreateWorkflow.checked,
      }),
    });
  }
  state.activeProjectId = project.id;
  if (!id) state.openProjectPhases.clear();
  els.projectDialog.close();
  setMessage(id ? "项目详情已保存" : "项目已创建，并已生成标准流程待办");
  await loadProjects();
  await loadActiveProjectData();
}

async function deleteActiveProject() {
  const project = state.projects.find((item) => item.id === state.activeProjectId);
  if (!project) throw new Error("请先选择项目");
  const firstConfirm = window.confirm(
    `确定永久删除“${project.name}”吗？\n\n该项目的阶段、待办、清单、会议和项目对话记录都会一并删除，且无法恢复。`
  );
  if (!firstConfirm) return;
  const confirmName = window.prompt("请输入完整项目名称进行二次确认：", "");
  if (confirmName === null) return;
  if (confirmName.trim() !== project.name.trim()) {
    setMessage("项目名称不匹配，已取消删除。", true);
    return;
  }
  const params = new URLSearchParams({ confirm_name: confirmName.trim() });
  await api(`/projects/${project.id}?${params.toString()}`, { method: "DELETE" });
  state.activeProjectId = null;
  state.projectPhases = [];
  state.todos = [];
  state.meetings = [];
  state.openProjectPhases.clear();
  setMessage(`项目“${project.name}”及其关联记录已删除。`);
  await loadProjects();
}

function openTodoDialog(todo = null, phaseName = "流程待办") {
  const isEdit = Boolean(todo);
  els.todoDialogTitle.textContent = isEdit ? "编辑待办" : "新增待办";
  els.todoEditId.value = todo?.id || "";
  els.todoTitle.value = todo?.title || "";
  els.todoType.value = todo?.todo_type || "extra";
  els.todoPhase.value = todo?.phase || phaseName || "";
  els.todoStatus.value = todo?.status || "open";
  els.todoPriority.value = todo?.priority || "normal";
  els.todoStartAt.value = toLocalInputValue(todo?.start_at);
  els.todoDueAt.value = toLocalInputValue(todo?.due_at);
  els.todoDescription.value = todo?.description || "";
  els.deleteTodoButton.classList.toggle("hidden", !isEdit);
  els.todoDialog.showModal();
}

function openProjectPhaseDialog(phase = null) {
  const isEdit = Boolean(phase);
  els.projectPhaseDialogTitle.textContent = isEdit ? "编辑阶段" : "新增阶段";
  els.projectPhaseEditId.value = phase?.id || "";
  els.projectPhaseName.value = phase?.name || "";
  els.deleteProjectPhaseButton.classList.toggle("hidden", !isEdit);
  els.projectPhaseDialog.showModal();
}

async function saveProjectPhase() {
  if (!state.activeProjectId) throw new Error("请先选择项目");
  const id = els.projectPhaseEditId.value;
  const payload = { name: els.projectPhaseName.value.trim() };
  if (!payload.name) throw new Error("阶段名称不能为空");
  if (id) {
    await api(`/projects/phases/${id}`, { method: "PUT", body: JSON.stringify(payload) });
  } else {
    await api(`/projects/${state.activeProjectId}/phases`, { method: "POST", body: JSON.stringify(payload) });
  }
  els.projectPhaseDialog.close();
  setMessage("阶段已保存");
  await loadActiveProjectData();
}

async function deleteProjectPhase(id = null) {
  const phaseId = id || els.projectPhaseEditId.value;
  if (!phaseId) return;
  if (!window.confirm("确定删除这个阶段吗？该阶段下的待办会移动到“流程待办”，不会删除待办本身。")) return;
  await api(`/projects/phases/${phaseId}`, { method: "DELETE" });
  if (els.projectPhaseDialog.open) els.projectPhaseDialog.close();
  setMessage("阶段已删除");
  await loadActiveProjectData();
}

function readTodoPayload() {
  return {
    title: els.todoTitle.value.trim(),
    todo_type: els.todoType.value,
    phase: els.todoPhase.value.trim() || null,
    status: els.todoStatus.value,
    priority: els.todoPriority.value,
    start_at: fromLocalInputValue(els.todoStartAt.value),
    due_at: fromLocalInputValue(els.todoDueAt.value),
    description: els.todoDescription.value.trim() || null,
  };
}

function findChecklistItem(id) {
  for (const todo of state.todos) {
    const item = (todo.checklist_items || []).find((entry) => entry.id === id);
    if (item) return { todo, item };
  }
  return { todo: null, item: null };
}

function openChecklistDialog(todo, item = null) {
  const isEdit = Boolean(item);
  els.checklistDialogTitle.textContent = isEdit ? "编辑清单项" : "新增清单项";
  els.checklistEditId.value = item?.id || "";
  els.checklistTodoId.value = todo?.id || item?.todo_id || "";
  els.checklistTitle.value = item?.title || "";
  els.checklistDueAt.value = toLocalInputValue(item?.due_at);
  renderChecklistMeetingOptions(item?.meeting_id || "");
  els.checklistIsDone.checked = Boolean(item?.is_done);
  els.deleteChecklistButton.classList.toggle("hidden", !isEdit);
  els.checklistDialog.showModal();
}

function readChecklistPayload() {
  return {
    title: els.checklistTitle.value.trim(),
    due_at: fromLocalInputValue(els.checklistDueAt.value),
    meeting_id: els.checklistMeetingId.value ? Number(els.checklistMeetingId.value) : null,
    is_done: els.checklistIsDone.checked,
  };
}

async function saveChecklistItem() {
  const id = els.checklistEditId.value;
  const todoId = els.checklistTodoId.value;
  const payload = readChecklistPayload();
  if (!payload.title) throw new Error("清单内容不能为空");
  if (id) {
    await api(`/projects/todos/checklist/${id}`, { method: "PUT", body: JSON.stringify(payload) });
  } else {
    await api(`/projects/todos/${todoId}/checklist`, { method: "POST", body: JSON.stringify(payload) });
  }
  els.checklistDialog.close();
  setMessage("清单项已保存");
  await loadActiveProjectData();
}

async function deleteChecklistItem() {
  const id = els.checklistEditId.value;
  if (!id || !window.confirm("确定删除这个清单项吗？")) return;
  await api(`/projects/todos/checklist/${id}`, { method: "DELETE" });
  els.checklistDialog.close();
  setMessage("清单项已删除");
  await loadActiveProjectData();
}

function collectTodoDraftText() {
  return [els.todoTitle.value.trim(), els.todoDescription.value.trim()].filter(Boolean).join("\n");
}

function collectMeetingDraftText() {
  return [
    els.meetingTitle.value.trim(),
    els.meetingUrl.value.trim(),
    els.meetingAgenda.value.trim(),
    els.meetingNotes.value.trim(),
    els.meetingLocation.value.trim(),
    els.meetingAttendees.value.trim(),
  ].filter(Boolean).join("\n");
}

async function draftProjectText(text) {
  if (!state.activeProjectId) throw new Error("请先选择项目");
  if (!text.trim()) throw new Error("请先粘贴或输入需要解析的内容");
  return api(`/projects/${state.activeProjectId}/assistant/draft`, {
    method: "POST",
    body: JSON.stringify({ text, create_records: false }),
  });
}

function applyTodoDraftToForm(todo) {
  if (!todo) throw new Error("没有识别到待办内容");
  els.todoTitle.value = todo.title || els.todoTitle.value;
  els.todoType.value = todo.todo_type || "extra";
  els.todoPhase.value = todo.phase || els.todoPhase.value;
  els.todoStatus.value = todo.status || "open";
  els.todoPriority.value = todo.priority || "normal";
  els.todoStartAt.value = toLocalInputValue(todo.start_at) || els.todoStartAt.value;
  els.todoDueAt.value = toLocalInputValue(todo.due_at) || els.todoDueAt.value;
  els.todoDescription.value = todo.description || els.todoDescription.value;
}

function applyTodoDraftToPayload(payload, todo, sourceText) {
  if (!todo) return payload;
  return {
    ...payload,
    title: todo.title || payload.title,
    description: todo.description || payload.description,
    todo_type: todo.todo_type || payload.todo_type || "extra",
    phase: todo.phase || payload.phase,
    status: todo.status || payload.status || "open",
    priority: todo.priority || payload.priority || "normal",
    start_at: todo.start_at || payload.start_at,
    due_at: todo.due_at || payload.due_at,
    source_text: sourceText,
  };
}

async function parseTodoDraftToForm() {
  const text = collectTodoDraftText();
  const result = await draftProjectText(text);
  const todo = result.todos?.[0];
  applyTodoDraftToForm(todo);
  setMessage(`已解析待办时间。${result.fallback_used ? "当前使用本地规则解析。" : `模型：${result.model_used}`}`);
}

async function saveTodo() {
  if (!state.activeProjectId) throw new Error("请先选择项目");
  const id = els.todoEditId.value;
  let payload = readTodoPayload();
  const sourceText = collectTodoDraftText();
  if (!id && sourceText && (!payload.due_at || !payload.title)) {
    const result = await draftProjectText(sourceText);
    payload = applyTodoDraftToPayload(payload, result.todos?.[0], sourceText);
  }
  if (!payload.title) throw new Error("待办标题不能为空");
  if (id) {
    await api(`/projects/todos/${id}`, { method: "PUT", body: JSON.stringify(payload) });
  } else {
    await api(`/projects/${state.activeProjectId}/todos`, { method: "POST", body: JSON.stringify(payload) });
  }
  els.todoDialog.close();
  setMessage("待办已保存");
  await loadActiveProjectData();
}

async function deleteTodo() {
  const id = els.todoEditId.value;
  if (!id || !window.confirm("确定删除这个待办吗？")) return;
  await api(`/projects/todos/${id}`, { method: "DELETE" });
  els.todoDialog.close();
  setMessage("待办已删除");
  await loadActiveProjectData();
}

async function reorderProjectPhaseTodos(phaseName, todoIds) {
  if (!state.activeProjectId) throw new Error("请先选择项目");
  await api(`/projects/${state.activeProjectId}/todos/reorder`, {
    method: "POST",
    body: JSON.stringify({
      phase: phaseName,
      todo_ids: todoIds,
    }),
  });
  setMessage("待办顺序已更新");
  await loadActiveProjectData();
}

async function reorderProjectPhases(phaseIds) {
  if (!state.activeProjectId) throw new Error("请先选择项目");
  await api(`/projects/${state.activeProjectId}/phases/reorder`, {
    method: "POST",
    body: JSON.stringify({ phase_ids: phaseIds }),
  });
  setMessage("阶段顺序已更新");
  await loadActiveProjectData();
}

async function moveProjectPhase(phaseId, direction) {
  const phases = orderedProjectPhases().filter((phase) => phase.id);
  const index = phases.findIndex((phase) => phase.id === phaseId);
  const targetIndex = index + direction;
  if (index < 0 || targetIndex < 0 || targetIndex >= phases.length) return;
  const [moved] = phases.splice(index, 1);
  phases.splice(targetIndex, 0, moved);
  await reorderProjectPhases(phases.map((phase) => phase.id));
}

function collectPhaseTodoIdsFromDom(dropzone) {
  return [...dropzone.querySelectorAll(".todo-row[data-todo-id]")]
    .map((row) => Number(row.dataset.todoId))
    .filter(Boolean);
}

function insertDraggedTodo(dropzone, targetRow, event) {
  const dragged = document.querySelector(`.todo-row[data-todo-id="${state.draggingTodo?.id}"]`);
  if (!dragged) return;
  if (targetRow === dragged) return;
  if (!targetRow) {
    dropzone.appendChild(dragged);
    return;
  }
  const rect = targetRow.getBoundingClientRect();
  const insertAfter = event.clientY > rect.top + rect.height / 2;
  dropzone.insertBefore(dragged, insertAfter ? targetRow.nextSibling : targetRow);
}

function openMeetingDialog(meeting = null) {
  const isEdit = Boolean(meeting);
  els.meetingDialogTitle.textContent = isEdit ? "编辑会议" : "快捷创建会议";
  els.meetingEditId.value = meeting?.id || "";
  els.meetingTitle.value = meeting?.title || "";
  els.meetingUrl.value = meeting?.meeting_url || "";
  els.meetingStartsAt.value = toLocalInputValue(meeting?.starts_at);
  els.meetingEndsAt.value = toLocalInputValue(meeting?.ends_at);
  els.meetingLocation.value = meeting?.location || "";
  els.meetingAttendees.value = meeting?.attendees || "";
  els.meetingAgenda.value = meeting?.agenda || "";
  els.meetingNotes.value = meeting?.notes || "";
  renderMeetingChecklistOptions(isEdit ? boundChecklistForMeeting(meeting.id)?.item.id || "" : "");
  els.deleteMeetingButton.classList.toggle("hidden", !isEdit);
  els.meetingDialog.showModal();
}

function readMeetingPayload() {
  return {
    title: els.meetingTitle.value.trim(),
    meeting_url: els.meetingUrl.value.trim() || null,
    starts_at: fromLocalInputValue(els.meetingStartsAt.value),
    ends_at: fromLocalInputValue(els.meetingEndsAt.value),
    location: els.meetingLocation.value.trim() || null,
    attendees: els.meetingAttendees.value.trim() || null,
    agenda: els.meetingAgenda.value.trim() || null,
    notes: els.meetingNotes.value.trim() || null,
  };
}

function applyMeetingDraftToForm(meeting) {
  if (!meeting) throw new Error("没有识别到会议内容");
  els.meetingTitle.value = meeting.title || els.meetingTitle.value;
  els.meetingUrl.value = meeting.meeting_url || els.meetingUrl.value;
  els.meetingStartsAt.value = toLocalInputValue(meeting.starts_at) || els.meetingStartsAt.value;
  els.meetingEndsAt.value = toLocalInputValue(meeting.ends_at) || els.meetingEndsAt.value;
  els.meetingLocation.value = meeting.location || els.meetingLocation.value;
  els.meetingAttendees.value = meeting.attendees || els.meetingAttendees.value;
  els.meetingAgenda.value = meeting.agenda || els.meetingAgenda.value;
  els.meetingNotes.value = meeting.notes || els.meetingNotes.value;
}

function applyMeetingDraftToPayload(payload, meeting, sourceText) {
  if (!meeting) return payload;
  return {
    ...payload,
    title: meeting.title || payload.title,
    agenda: meeting.agenda || payload.agenda,
    meeting_url: meeting.meeting_url || payload.meeting_url,
    location: meeting.location || payload.location,
    starts_at: meeting.starts_at || payload.starts_at,
    ends_at: meeting.ends_at || payload.ends_at,
    attendees: meeting.attendees || payload.attendees,
    notes: meeting.notes || payload.notes,
    source_text: sourceText,
  };
}

async function parseMeetingDraftToForm() {
  const text = collectMeetingDraftText();
  const result = await draftProjectText(text);
  const meeting = result.meetings?.[0];
  applyMeetingDraftToForm(meeting);
  setMessage(`已解析会议时间。${result.fallback_used ? "当前使用本地规则解析。" : `模型：${result.model_used}`}`);
}

async function saveMeeting() {
  if (!state.activeProjectId) throw new Error("请先选择项目");
  const id = els.meetingEditId.value;
  const selectedChecklistId = els.meetingChecklistId.value ? Number(els.meetingChecklistId.value) : null;
  let payload = readMeetingPayload();
  const sourceText = collectMeetingDraftText();
  if (!id && sourceText && (!payload.starts_at || !payload.title)) {
    const result = await draftProjectText(sourceText);
    payload = applyMeetingDraftToPayload(payload, result.meetings?.[0], sourceText);
  }
  if (!payload.title) throw new Error("会议标题不能为空");
  let savedMeeting;
  if (id) {
    savedMeeting = await api(`/projects/meetings/${id}`, { method: "PUT", body: JSON.stringify(payload) });
  } else {
    savedMeeting = await api(`/projects/${state.activeProjectId}/meetings`, { method: "POST", body: JSON.stringify(payload) });
  }
  await syncMeetingChecklistBinding(savedMeeting.id, selectedChecklistId);
  els.meetingDialog.close();
  setMessage("会议已保存");
  await loadActiveProjectData();
}

async function syncMeetingChecklistBinding(meetingId, checklistId) {
  const currentBindings = allChecklistItems().filter(({ item }) => Number(item.meeting_id) === Number(meetingId));
  for (const { item } of currentBindings) {
    if (checklistId && item.id === checklistId) continue;
    await api(`/projects/todos/checklist/${item.id}`, {
      method: "PUT",
      body: JSON.stringify({ meeting_id: null }),
    });
  }
  if (checklistId) {
    await api(`/projects/todos/checklist/${checklistId}`, {
      method: "PUT",
      body: JSON.stringify({ meeting_id: meetingId }),
    });
  }
}

async function deleteMeeting() {
  const id = els.meetingEditId.value;
  if (!id || !window.confirm("确定删除这个会议吗？")) return;
  await api(`/projects/meetings/${id}`, { method: "DELETE" });
  els.meetingDialog.close();
  setMessage("会议已删除");
  await loadActiveProjectData();
}

async function parseAssistantText() {
  if (!state.activeProjectId) throw new Error("请先选择项目");
  const text = els.assistantInput.value.trim();
  if (!text) throw new Error("请先粘贴会议内容或输入待办");
  const result = await api(`/projects/${state.activeProjectId}/assistant/parse`, {
    method: "POST",
    body: JSON.stringify({ text, create_records: true }),
  });
  els.assistantInput.value = "";
  setMessage(`已创建：${result.meetings.length} 个会议，${result.todos.length} 个待办。${result.fallback_used ? "当前使用本地规则解析。" : `模型：${result.model_used}`}`);
  await loadActiveProjectData();
}

function openEditDialog(video) {
  $("#editId").value = video.id;
  $("#editTitle").value = video.title || "";
  $("#editCourseName").value = video.course_name || "";
  $("#editCourseTitle").value = video.course_title || "";
  $("#editLessonTitle").value = video.lesson_title || "";
  $("#editVideoCategory").value = video.category_id || "";
  $("#editEpisodeNumber").value = video.episode_number || "";
  $("#editSortOrder").value = video.sort_order ?? "";
  $("#editInstructor").value = video.instructor || "";
  $("#editTags").value = video.tags || "";
  $("#editDuration").value = video.duration_seconds || "";
  $("#editVisible").checked = video.is_visible;
  $("#editDescription").value = video.description || "";
  els.editDialog.showModal();
}

function readEditPayload() {
  const duration = $("#editDuration").value;
  const episodeNumber = $("#editEpisodeNumber").value;
  const sortOrder = $("#editSortOrder").value;
  const categoryId = $("#editVideoCategory").value;
  return {
    title: $("#editTitle").value.trim() || null,
    course_name: $("#editCourseName").value.trim() || null,
    course_title: $("#editCourseTitle").value.trim() || null,
    lesson_title: $("#editLessonTitle").value.trim() || null,
    category_id: categoryId ? Number(categoryId) : null,
    episode_number: episodeNumber ? Number(episodeNumber) : null,
    sort_order: sortOrder ? Number(sortOrder) : null,
    instructor: $("#editInstructor").value.trim() || null,
    tags: $("#editTags").value.trim() || null,
    duration_seconds: duration ? Number(duration) : null,
    is_visible: $("#editVisible").checked,
    description: $("#editDescription").value.trim() || null,
  };
}

async function saveCurrentVideo({ publish = false } = {}) {
  const id = $("#editId").value;
  const savedVideo = await api(`/admin/nas-videos/${id}`, { method: "PUT", body: JSON.stringify(readEditPayload()) });
  const index = state.videos.findIndex((video) => String(video.id) === String(id));
  if (index >= 0 && savedVideo) {
    state.videos[index] = savedVideo;
    renderVideos();
  }
  if (publish) {
    await api(`/admin/nas-videos/${id}/publish`, { method: "POST", body: JSON.stringify({ is_published: true }) });
  }
  els.editDialog.close();
  setMessage(publish ? "已保存并发布到 App 视频列表" : "已保存；如果已发布到 App，也已同步更新");
  await Promise.all([loadStats(), loadVideos()]);
}

async function publishVideo(id) {
  await api(`/admin/nas-videos/${id}/publish`, { method: "POST", body: JSON.stringify({ is_published: true }) });
  setMessage("已发布到 App 视频列表");
  await Promise.all([loadStats(), loadVideos()]);
}

async function publishVideoCategory(category) {
  const firstConfirm = window.confirm(
    `确定发布这个课程分类及其所有子分类下的视频吗？\n\n${category.path}\n\n` +
      `直接包含 ${category.video_count || 0} 个视频，${category.children_count || 0} 个子分类。已发布的视频会同步更新元数据。`
  );
  if (!firstConfirm) return;

  const result = await api(`/admin/nas-video-categories/${category.id}/publish`, {
    method: "POST",
    body: JSON.stringify({ is_published: true }),
  });
  setMessage(
    `课程发布完成：${result.category_path}，共 ${result.total} 个视频，成功发布/更新 ${result.published} 个，失败 ${result.failed || 0} 个。`,
    Boolean(result.failed)
  );
  await Promise.all([loadStats(), loadVideos()]);
}

async function deleteVideoRecord(video) {
  const label = video.title || video.lesson_title || video.file_name;
  const firstConfirm = window.confirm(
    `确定从视频库删除这条记录吗？\n\n${label}\n\n这只会删除数据库记录，不会删除NAS本地视频文件。若已发布到App，也会删除对应App视频记录。`
  );
  if (!firstConfirm) return;

  const confirmText = window.prompt("请输入“删除视频库记录”进行二次确认：");
  if (confirmText !== "删除视频库记录") {
    setMessage("确认文本不正确，已取消删除。", true);
    return;
  }

  const result = await api(`/admin/nas-videos/${video.id}`, {
    method: "DELETE",
    body: JSON.stringify({ confirm_text: confirmText }),
  });
  setMessage(`已删除视频库记录：${result.file_name}。NAS本地文件未删除。`);
  await Promise.all([loadStats(), loadVideos()]);
}

async function aiOrganizeVideo(id) {
  const result = await api(`/admin/nas-videos/${id}/ai-organize`, {
    method: "POST",
    body: JSON.stringify({ apply: true, overwrite_existing: true }),
  });
  const item = result.data?.[0];
  if (item?.error) {
    setMessage(`AI整理失败：${item.error}`, true);
    return;
  }
  setMessage(`AI整理完成：${item?.course_name || item?.category_path || "已更新"}。${item?.fallback_used ? "当前使用本地规则解析。" : `模型：${item?.model_used}`}`);
  await loadVideos();
}

async function fetchVideoIds({ all = false } = {}) {
  if (!all) return state.videos.map((video) => video.id);
  const ids = [];
  let skip = 0;
  const limit = 1000;
  while (true) {
    const data = await api(`/admin/nas-videos?skip=${skip}&limit=${limit}`);
    ids.push(...(data.data || []).map((video) => video.id));
    if (ids.length >= data.total || !data.data?.length) break;
    skip += limit;
  }
  return ids;
}

async function aiOrganizeVideoIds(videoIds, title = "AI整理视频库") {
  const ids = Array.from(new Set((videoIds || []).filter(Boolean)));
  if (!ids.length) {
    setMessage("没有需要整理的视频。");
    return { total: 0, applied: 0, fallback: 0 };
  }
  let applied = 0;
  let fallback = 0;
  let failed = 0;
  setVideoProgress(title, 0, ids.length);
  for (let index = 0; index < ids.length; index += 1) {
    const id = ids[index];
    setVideoProgress(title, index, ids.length, `正在整理 ${index + 1}/${ids.length}`);
    const result = await api(`/admin/nas-videos/${id}/ai-organize`, {
      method: "POST",
      body: JSON.stringify({ apply: true, overwrite_existing: true }),
    });
    const item = result.data?.[0];
    if (item?.error) failed += 1;
    if (item?.applied) applied += 1;
    if (item?.fallback_used) fallback += 1;
    setVideoProgress(title, index + 1, ids.length, `已完成 ${index + 1}/${ids.length}`);
  }
  setMessage(`AI整理完成：处理 ${ids.length} 个视频，写回 ${applied} 个，规则兜底 ${fallback} 个，失败 ${failed} 个。`, failed > 0);
  hideVideoProgressSoon();
  await Promise.all([loadStats(), loadVideos()]);
  return { total: ids.length, applied, fallback };
}

async function aiOrganizeCurrentVideos() {
  await aiOrganizeVideoIds(await fetchVideoIds(), "AI整理当前列表");
}

async function aiOrganizeAllVideos() {
  await aiOrganizeVideoIds(await fetchVideoIds({ all: true }), "AI整理全库");
}

async function scanVideoSidecars() {
  setVideoProgress("搜索字幕/弹幕", 0, 1, "正在检查已有视频同目录文件...");
  const result = await api("/admin/nas-videos/sidecars/scan", { method: "POST" });
  state.videoSidecarMatches = new Map(
    (result.data || []).map((item) => [item.video_id, item]),
  );
  setVideoProgress("搜索字幕/弹幕", 1, 1, "搜索完成");
  renderVideos();
  setMessage(
    `搜索完成：检查 ${result.total} 个视频，${result.matched_videos} 个视频匹配到字幕/弹幕，共 ${result.sidecar_files} 个文件（字幕 ${result.subtitle_files}，弹幕 ${result.danmaku_files}）。App 打开视频详情时会自动加载。`,
    result.matched_videos === 0,
  );
  hideVideoProgressSoon();
  return result;
}

async function deleteVideoLibraryRecords() {
  const firstConfirm = window.confirm("确定删除整个NAS视频库的数据库记录吗？\n\n不会删除NAS本地视频文件，但会删除对应App视频记录。");
  if (!firstConfirm) return;
  const confirmText = window.prompt("请输入“删除整个视频库记录”进行二次确认：");
  if (confirmText !== "删除整个视频库记录") {
    setMessage("确认文本不正确，已取消删除。", true);
    return;
  }
  const result = await api("/admin/nas-videos/library", {
    method: "DELETE",
    body: JSON.stringify({ confirm_text: confirmText }),
  });
  setMessage(`已删除 ${result.deleted} 条视频库记录。NAS本地文件未删除。`);
  await Promise.all([loadStats(), loadVideos()]);
}

function openVideoCategoryDialog(category = null, parentId = "") {
  els.videoCategoryDialogTitle.textContent = category ? "编辑视频分类" : "新增视频分类";
  els.videoCategoryEditId.value = category?.id || "";
  els.videoCategoryName.value = category?.name || "";
  els.videoCategoryParent.value = category?.parent_id || parentId || "";
  els.videoCategorySortOrder.value = category?.sort_order ?? 0;
  els.videoCategoryDescription.value = category?.description || "";
  els.videoCategoryDialog.showModal();
}

async function deleteVideoCategory(category) {
  const firstConfirm = window.confirm(
    `确定删除这个分类及其所有子分类吗？\n\n${category.path}\n\n` +
      `直接包含 ${category.video_count || 0} 个视频，${category.children_count || 0} 个子分类。\n` +
      "这只会删除分类记录，分类下的视频会变为未分类，不会删除NAS本地视频文件。"
  );
  if (!firstConfirm) return;

  const confirmText = window.prompt("请输入“删除分类”进行二次确认：");
  if (confirmText !== "删除分类") {
    setMessage("确认文本不正确，已取消删除。", true);
    return;
  }

  const result = await api(`/admin/nas-video-categories/${category.id}`, { method: "DELETE" });
  setMessage(
    `已删除分类：${result.category_path}。删除 ${result.deleted_categories} 个分类，${result.unassigned_videos} 个视频已改为未分类。NAS本地文件未删除。`
  );
  if (els.videoCategoryFilter.value === String(category.id)) {
    els.videoCategoryFilter.value = "";
  }
  await Promise.all([loadStats(), loadVideos()]);
}

async function deleteAllVideoCategories() {
  const totalCategories = state.videoCategories.length;
  const categorizedVideos = state.videoCategories.reduce(
    (sum, category) => sum + (category.video_count || 0),
    0
  );
  const firstConfirm = window.confirm(
    `确定删除全部 NAS 视频分类吗？\n\n` +
      `当前共有 ${totalCategories} 个分类，至少 ${categorizedVideos} 个视频直接挂在分类下。\n` +
      "这只会清空分类树，所有视频会变为未分类，不会删除NAS本地视频文件，也不会删除视频库记录。"
  );
  if (!firstConfirm) return;

  const confirmText = window.prompt("请输入“删除全部分类”进行二次确认：");
  if (confirmText !== "删除全部分类") {
    setMessage("确认文本不正确，已取消删除。", true);
    return;
  }

  const result = await api("/admin/nas-video-categories", { method: "DELETE" });
  els.videoCategoryFilter.value = "";
  setMessage(
    `已删除全部分类：删除 ${result.deleted_categories} 个分类，${result.unassigned_videos} 个视频已改为未分类。NAS本地文件未删除。`
  );
  await Promise.all([loadStats(), loadVideos()]);
}

function logout() {
  state.token = null;
  localStorage.removeItem("bioStatAdminToken");
  updateSession();
}

els.loginForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const username = $("#usernameInput").value.trim();
  const password = $("#passwordInput").value;
  setMessage("正在登录...", false, els.loginMessageBox);
  try {
    const data = await api("/auth/session", { method: "POST", body: JSON.stringify({ username, password }) });
    state.token = data.access_token;
    localStorage.setItem("bioStatAdminToken", state.token);
    updateSession();
    await refreshAll();
  } catch (error) {
    setMessage(`登录失败：${error.message}`, true, els.loginMessageBox);
  }
});

els.logoutButton.addEventListener("click", logout);
document.addEventListener("click", (event) => {
  const closeButton = event.target.closest("[data-dialog-close]");
  if (!closeButton) return;
  const dialog = closeButton.closest("dialog");
  if (dialog?.open) dialog.close();
});
document.querySelectorAll("dialog").forEach((dialog) => {
  dialog.addEventListener("click", (event) => {
    if (event.target === dialog) dialog.close();
  });
});
els.tabs.forEach((button) => button.addEventListener("click", () => switchTab(button.dataset.tab)));
els.subtabs.forEach((button) => button.addEventListener("click", () => switchProjectTab(button.dataset.projectTab)));

els.publishAllConceptsButton.addEventListener("click", async () => {
  if (!window.confirm("确认发布全部知识库概念吗？这不会删除任何内容，只会把隐藏概念设为已发布。")) return;
  try {
    const result = await api("/admin/knowledge/publish-all", { method: "POST" });
    setMessage(`知识库已一键发布：本次发布 ${result.published || 0} 条隐藏概念。`);
    await Promise.all([loadStats(), loadKnowledge()]);
  } catch (error) {
    setMessage(error.message, true);
  }
});
els.newConceptButton.addEventListener("click", () => openConceptDialog());
els.refreshKnowledgeButton.addEventListener("click", () => loadKnowledge().catch((error) => setMessage(error.message, true)));
els.conceptPublishedFilter.addEventListener("change", renderConcepts);
els.conceptCategoryFilter.addEventListener("change", () => {
  renderCategories();
  loadConcepts().catch((error) => setMessage(error.message, true));
});
els.conceptSearchInput.addEventListener("keyup", () => {
  window.clearTimeout(window.conceptSearchTimer);
  window.conceptSearchTimer = window.setTimeout(() => loadConcepts().catch((error) => setMessage(error.message, true)), 250);
});
els.categoryList.addEventListener("click", (event) => {
  const button = event.target.closest("button[data-category-id]");
  if (!button) return;
  els.conceptCategoryFilter.value = button.dataset.categoryId;
  renderCategories();
  loadConcepts().catch((error) => setMessage(error.message, true));
});
els.conceptList.addEventListener("click", async (event) => {
  const button = event.target.closest("button[data-action]");
  if (!button) return;
  const id = Number(button.dataset.id);
  const concept = state.concepts.find((item) => item.id === id);
  if (!concept) return;
  try {
    if (button.dataset.action === "edit-concept") openConceptDialog(concept);
    if (button.dataset.action === "toggle-concept") await toggleConceptPublish(id);
  } catch (error) {
    setMessage(error.message, true);
  }
});
els.saveConceptButton.addEventListener("click", () => saveCurrentConcept().catch((error) => setMessage(error.message, true)));
els.deleteConceptButton.addEventListener("click", () => deleteCurrentConcept().catch((error) => setMessage(error.message, true)));

els.newProjectButton.addEventListener("click", () => openProjectDialog());
els.editProjectButton.addEventListener("click", async () => {
  try {
    if (!state.activeProjectId) return setMessage("请先选择项目", true);
    const project =
      state.projects.find((item) => item.id === state.activeProjectId) ||
      await api(`/projects/${state.activeProjectId}`);
    openProjectDialog(project);
  } catch (error) {
    setMessage(error.message, true);
  }
});
els.deleteProjectButton.addEventListener("click", () => deleteActiveProject().catch((error) => setMessage(error.message, true)));
els.refreshProjectsButton.addEventListener("click", () => loadProjects().catch((error) => setMessage(error.message, true)));
els.saveProjectButton.addEventListener("click", () => saveProject().catch((error) => setMessage(error.message, true)));
els.parseProjectIntakeButton.addEventListener("click", () => parseProjectIntake().catch((error) => setMessage(error.message, true)));
els.projectList.addEventListener("click", (event) => {
  const button = event.target.closest("button[data-project-id]");
  if (!button) return;
  state.activeProjectId = Number(button.dataset.projectId);
  state.openProjectPhases.clear();
  renderProjects();
  loadActiveProjectData().catch((error) => setMessage(error.message, true));
});
els.seedWorkflowButton.addEventListener("click", async () => {
  try {
    const result = await api(`/projects/${state.activeProjectId}/standard-workflow`, { method: "POST" });
    setMessage(`已补齐标准流程：新增 ${result.created} 条`);
    await loadActiveProjectData();
  } catch (error) {
    setMessage(error.message, true);
  }
});
els.newProjectPhaseButton.addEventListener("click", () => openProjectPhaseDialog());
els.newTodoButton.addEventListener("click", () => openTodoDialog(null, orderedProjectPhases()[0]?.name || "流程待办"));
els.newMeetingButton.addEventListener("click", () => openMeetingDialog());
els.saveProjectPhaseButton.addEventListener("click", () => saveProjectPhase().catch((error) => setMessage(error.message, true)));
els.deleteProjectPhaseButton.addEventListener("click", () => deleteProjectPhase().catch((error) => setMessage(error.message, true)));
els.parseTodoDraftButton.addEventListener("click", () => parseTodoDraftToForm().catch((error) => setMessage(error.message, true)));
els.saveTodoButton.addEventListener("click", () => saveTodo().catch((error) => setMessage(error.message, true)));
els.deleteTodoButton.addEventListener("click", () => deleteTodo().catch((error) => setMessage(error.message, true)));
els.saveChecklistButton.addEventListener("click", () => saveChecklistItem().catch((error) => setMessage(error.message, true)));
els.deleteChecklistButton.addEventListener("click", () => deleteChecklistItem().catch((error) => setMessage(error.message, true)));
els.parseMeetingDraftButton.addEventListener("click", () => parseMeetingDraftToForm().catch((error) => setMessage(error.message, true)));
els.saveMeetingButton.addEventListener("click", () => saveMeeting().catch((error) => setMessage(error.message, true)));
els.deleteMeetingButton.addEventListener("click", () => deleteMeeting().catch((error) => setMessage(error.message, true)));
els.saveMemberButton.addEventListener("click", () => saveMember().catch((error) => setMessage(error.message, true)));
els.deleteMemberButton.addEventListener("click", () => deleteMember().catch((error) => setMessage(error.message, true)));
els.parseMemberTextButton.addEventListener("click", () => parseMemberText().catch((error) => setMessage(error.message, true)));
els.importTimelineTextButton.addEventListener("click", () => importTimelineText().catch((error) => setMessage(error.message, true)));
els.saveTimelineItemButton.addEventListener("click", () => saveTimelineItem().catch((error) => setMessage(error.message, true)));
els.timelineFileInput.addEventListener("change", () => {
  const file = els.timelineFileInput.files?.[0];
  els.timelineFileInput.value = "";
  importTimelineFile(file).catch((error) => setMessage(error.message, true));
});
els.parseAssistantButton.addEventListener("click", () => parseAssistantText().catch((error) => setMessage(error.message, true)));
els.clearAssistantButton.addEventListener("click", () => { els.assistantInput.value = ""; });
document.querySelector(".project-detail").addEventListener("click", async (event) => {
  const button = event.target.closest("button[data-action]");
  if (!button) return;
  event.preventDefault();
  event.stopPropagation();
  const id = Number(button.dataset.id);
  try {
    if (button.dataset.action === "add-phase-todo") {
      openTodoDialog(null, button.dataset.phase || "流程待办");
    } else if (button.dataset.action === "edit-phase") {
      openProjectPhaseDialog(state.projectPhases.find((phase) => phase.id === id));
    } else if (button.dataset.action === "move-phase-up") {
      await moveProjectPhase(id, -1);
    } else if (button.dataset.action === "move-phase-down") {
      await moveProjectPhase(id, 1);
    } else if (button.dataset.action === "delete-phase") {
      await deleteProjectPhase(id);
    } else if (button.dataset.action === "edit-todo") {
      openTodoDialog(state.todos.find((todo) => todo.id === id));
    } else if (button.dataset.action === "complete-todo") {
      const todo = state.todos.find((item) => item.id === id);
      await api(`/projects/todos/${id}`, { method: "PUT", body: JSON.stringify({ status: todo.status === "done" ? "open" : "done" }) });
      await loadActiveProjectData();
    } else if (button.dataset.action === "add-checklist") {
      openChecklistDialog(state.todos.find((todo) => todo.id === id));
    } else if (button.dataset.action === "edit-checklist") {
      const { todo, item } = findChecklistItem(id);
      if (!item) throw new Error("清单项不存在或已刷新");
      openChecklistDialog(todo, item);
    } else if (button.dataset.action === "toggle-checklist") {
      const { item } = findChecklistItem(id);
      if (!item) throw new Error("清单项不存在或已刷新");
      await api(`/projects/todos/checklist/${id}`, { method: "PUT", body: JSON.stringify({ is_done: !item.is_done }) });
      await loadActiveProjectData();
    } else if (button.dataset.action === "delete-checklist") {
      if (!window.confirm("确定删除这个清单项吗？")) return;
      await api(`/projects/todos/checklist/${id}`, { method: "DELETE" });
      await loadActiveProjectData();
    } else if (button.dataset.action === "view-meeting") {
      openMeetingDialog(state.meetings.find((meeting) => meeting.id === id));
    } else if (button.dataset.action === "edit-meeting") {
      openMeetingDialog(state.meetings.find((meeting) => meeting.id === id));
    } else if (button.dataset.action === "add-member") {
      openMemberDialog();
    } else if (button.dataset.action === "edit-member") {
      openMemberDialog(state.members.find((member) => member.id === id));
    } else if (button.dataset.action === "delete-member") {
      await deleteMember(id);
    } else if (button.dataset.action === "parse-members") {
      openMemberTextDialog();
    } else if (button.dataset.action === "import-timeline-text") {
      openTimelineTextDialog();
    } else if (button.dataset.action === "pick-timeline-file") {
      els.timelineFileInput.click();
    } else if (button.dataset.action === "edit-timeline") {
      const timelineItem = state.timelineImports
        .flatMap((timeline) => timeline.items || [])
        .find((item) => item.id === id);
      openTimelineItemDialog(timelineItem);
    } else if (button.dataset.action === "delete-timeline") {
      await deleteTimelineImport(id);
    }
  } catch (error) {
    setMessage(error.message, true);
  }
});

document.querySelector(".project-detail").addEventListener("toggle", (event) => {
  const section = event.target.closest?.(".phase-section");
  if (!section) return;
  if (section.open) {
    state.openProjectPhases.add(section.dataset.phase);
  } else {
    state.openProjectPhases.delete(section.dataset.phase);
  }
}, true);

document.querySelector(".project-detail").addEventListener("dragstart", (event) => {
  const row = event.target.closest(".todo-row[data-todo-id]");
  if (!row) return;
  state.draggingTodo = {
    id: Number(row.dataset.todoId),
    phase: row.dataset.phase,
  };
  row.classList.add("dragging");
  event.dataTransfer.effectAllowed = "move";
});

document.querySelector(".project-detail").addEventListener("dragover", (event) => {
  const dropzone = event.target.closest(".phase-todo-dropzone");
  if (!dropzone || !state.draggingTodo) return;
  if (dropzone.dataset.phase !== state.draggingTodo.phase) return;
  event.preventDefault();
  event.dataTransfer.dropEffect = "move";
});

document.querySelector(".project-detail").addEventListener("drop", async (event) => {
  const dropzone = event.target.closest(".phase-todo-dropzone");
  if (!dropzone || !state.draggingTodo) return;
  if (dropzone.dataset.phase !== state.draggingTodo.phase) return;
  event.preventDefault();
  const targetRow = event.target.closest(".todo-row[data-todo-id]");
  insertDraggedTodo(dropzone, targetRow, event);
  const todoIds = collectPhaseTodoIdsFromDom(dropzone);
  const phaseName = dropzone.dataset.phase;
  state.draggingTodo = null;
  try {
    await reorderProjectPhaseTodos(phaseName, todoIds);
  } catch (error) {
    setMessage(error.message, true);
    await loadActiveProjectData();
  }
});

document.querySelector(".project-detail").addEventListener("dragend", (event) => {
  event.target.closest?.(".todo-row")?.classList.remove("dragging");
  state.draggingTodo = null;
});

els.scanButton.addEventListener("click", async () => {
  try {
    setVideoProgress("扫描视频目录", 0, 1, "正在扫描...");
    const result = await api("/admin/nas-videos/scan", { method: "POST" });
    setVideoProgress("扫描视频目录", 1, 1, "扫描完成");
    const skippedText = result.skipped
      ? `，跳过 ${result.skipped} 项。首个错误：${result.errors?.[0]?.path || ""} ${result.errors?.[0]?.error || ""}`
      : "。";
    setMessage(`扫描完成：发现 ${result.scanned} 个，新增 ${result.created} 个，更新 ${result.updated} 个${skippedText}`, Boolean(result.skipped));
    const changedIds = [...(result.created_ids || []), ...(result.updated_ids || [])];
    if (changedIds.length) {
      await aiOrganizeVideoIds(changedIds, "AI整理本次扫描内容");
    } else {
      hideVideoProgressSoon();
    }
    await Promise.all([loadStats(), loadVideos()]);
  } catch (error) {
    setMessage(error.message, true);
    hideVideoProgressSoon();
  }
});
els.reorderVideosButton.addEventListener("click", () => {
  openVideoReorderDialog().catch((error) => setMessage(error.message, true));
});
els.saveVideoReorderButton.addEventListener("click", () => {
  saveVideoReorder().catch((error) => setMessage(error.message, true));
});
els.videoReorderList.addEventListener("dragstart", (event) => {
  const item = event.target.closest("[data-video-id]");
  if (!item) return;
  state.draggingVideoId = Number(item.dataset.videoId);
  item.classList.add("dragging");
  event.dataTransfer.effectAllowed = "move";
});
els.videoReorderList.addEventListener("dragover", (event) => {
  const target = event.target.closest("[data-video-id]");
  if (!target || !state.draggingVideoId) return;
  event.preventDefault();
  const dragging = els.videoReorderList.querySelector(`[data-video-id="${state.draggingVideoId}"]`);
  if (!dragging || dragging === target) return;
  const rect = target.getBoundingClientRect();
  const before = event.clientY < rect.top + rect.height / 2;
  els.videoReorderList.insertBefore(dragging, before ? target : target.nextSibling);
});
els.videoReorderList.addEventListener("drop", (event) => {
  if (!state.draggingVideoId) return;
  event.preventDefault();
  syncVideoReorderFromDom();
  renderVideoReorderList();
  state.draggingVideoId = null;
});
els.videoReorderList.addEventListener("dragend", () => {
  els.videoReorderList.querySelector(".dragging")?.classList.remove("dragging");
  if (state.draggingVideoId) {
    syncVideoReorderFromDom();
    renderVideoReorderList();
  }
  state.draggingVideoId = null;
});
els.newVideoCategoryButton.addEventListener("click", () => openVideoCategoryDialog());
els.deleteAllVideoCategoriesButton.addEventListener("click", () => deleteAllVideoCategories().catch((error) => setMessage(error.message, true)));
els.videoCategoryList.addEventListener("click", async (event) => {
  const button = event.target.closest("button[data-action]");
  if (!button) return;
  const id = Number(button.dataset.id);
  const category = state.videoCategories.find((item) => item.id === id);
  try {
    if (button.dataset.action === "toggle-video-category") {
      if (state.collapsedVideoCategoryIds.has(id)) {
        state.collapsedVideoCategoryIds.delete(id);
      } else {
        state.collapsedVideoCategoryIds.add(id);
      }
      renderVideoCategoryList();
    } else if (button.dataset.action === "filter-video-category") {
      els.videoCategoryFilter.value = String(id);
      renderVideoCategoryList();
      await loadVideos();
    } else if (button.dataset.action === "edit-video-category" && category) {
      openVideoCategoryDialog(category);
    } else if (button.dataset.action === "add-child-category") {
      openVideoCategoryDialog(null, id);
    } else if (button.dataset.action === "publish-video-category" && category) {
      await publishVideoCategory(category);
    } else if (button.dataset.action === "delete-video-category" && category) {
      await deleteVideoCategory(category);
    }
  } catch (error) {
    setMessage(error.message, true);
  }
});
els.saveVideoCategoryButton.addEventListener("click", async () => {
  try {
    const name = els.videoCategoryName.value.trim();
    if (!name) throw new Error("分类名称不能为空");
    const editId = els.videoCategoryEditId.value;
    await api(editId ? `/admin/nas-video-categories/${editId}` : "/admin/nas-video-categories", {
      method: editId ? "PUT" : "POST",
      body: JSON.stringify({
        name,
        parent_id: els.videoCategoryParent.value ? Number(els.videoCategoryParent.value) : null,
        sort_order: els.videoCategorySortOrder.value ? Number(els.videoCategorySortOrder.value) : 0,
        description: els.videoCategoryDescription.value.trim() || null,
      }),
    });
    els.videoCategoryDialog.close();
    setMessage(editId ? "视频分类已更新" : "视频分类已创建");
    await loadVideos();
  } catch (error) {
    setMessage(error.message, true);
  }
});
els.manualVideoButton.addEventListener("click", () => {
  els.manualVideoPath.value = "";
  els.manualVideoCategory.value = "";
  els.manualVideoEpisode.value = "";
  els.manualVideoTitle.value = "";
  els.manualVideoCourseName.value = "";
  els.manualVideoDescription.value = "";
  els.manualVideoDialog.showModal();
});
els.saveManualVideoButton.addEventListener("click", async () => {
  try {
    const relativePath = els.manualVideoPath.value.trim();
    if (!relativePath) throw new Error("请填写视频相对路径");
    await api("/admin/nas-videos/manual", {
      method: "POST",
      body: JSON.stringify({
        relative_path: relativePath,
        category_id: els.manualVideoCategory.value ? Number(els.manualVideoCategory.value) : null,
        episode_number: els.manualVideoEpisode.value ? Number(els.manualVideoEpisode.value) : null,
        title: els.manualVideoTitle.value.trim() || null,
        course_name: els.manualVideoCourseName.value.trim() || null,
        description: els.manualVideoDescription.value.trim() || null,
      }),
    });
    els.manualVideoDialog.close();
    setMessage("视频已添加到 NAS 视频库");
    await loadVideos();
  } catch (error) {
    setMessage(error.message, true);
  }
});
els.refreshButton.addEventListener("click", () => loadVideos().catch((error) => setMessage(error.message, true)));
els.searchInput.addEventListener("keyup", () => {
  window.clearTimeout(window.searchTimer);
  window.searchTimer = window.setTimeout(() => loadVideos().catch((error) => setMessage(error.message, true)), 250);
});
els.publishedFilter.addEventListener("change", () => loadVideos().catch((error) => setMessage(error.message, true)));
els.videoCategoryFilter.addEventListener("change", () => loadVideos().catch((error) => setMessage(error.message, true)));
els.scanSidecarsButton.addEventListener("click", () => scanVideoSidecars().catch((error) => {
  setMessage(error.message, true);
  hideVideoProgressSoon();
}));
els.aiOrganizeVideosButton.addEventListener("click", () => aiOrganizeCurrentVideos().catch((error) => setMessage(error.message, true)));
els.aiOrganizeAllVideosButton.addEventListener("click", () => aiOrganizeAllVideos().catch((error) => setMessage(error.message, true)));
els.deleteVideoLibraryButton.addEventListener("click", () => deleteVideoLibraryRecords().catch((error) => setMessage(error.message, true)));
els.tableBody.addEventListener("click", async (event) => {
  const button = event.target.closest("button[data-action]");
  if (!button) return;
  const id = Number(button.dataset.id);
  const video = state.videos.find((item) => item.id === id);
  if (!video) return;
  try {
    if (button.dataset.action === "edit") openEditDialog(video);
    if (button.dataset.action === "ai-organize") await aiOrganizeVideo(id);
    if (button.dataset.action === "delete-record") await deleteVideoRecord(video);
    if (button.dataset.action === "publish") await publishVideo(id);
  } catch (error) {
    setMessage(error.message, true);
  }
});
els.saveButton.addEventListener("click", () => saveCurrentVideo().catch((error) => setMessage(error.message, true)));
$("#publishButton").addEventListener("click", () => saveCurrentVideo({ publish: true }).catch((error) => setMessage(error.message, true)));

updateSession();
switchTab(state.activeTab);
switchProjectTab(state.activeProjectTab);
refreshAll();
