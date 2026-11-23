import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../shared/models/project_model.dart';
import '../../../../shared/widgets/liquid_glass_panel.dart';
import '../controllers/projects_controller.dart';

class ProjectDetailView extends StatefulWidget {
  const ProjectDetailView({super.key, this.embedded});

  final bool? embedded;

  @override
  State<ProjectDetailView> createState() => _ProjectDetailViewState();
}

class _ProjectDetailViewState extends State<ProjectDetailView> {
  final ProjectsController controller = Get.find<ProjectsController>();
  final TextEditingController _assistantController = TextEditingController();
  final ScrollController _agentScrollController = ScrollController();
  final GlobalKey _focusTodoKey = GlobalKey();
  final TextEditingController _quickAddController = TextEditingController();
  bool _agentSubmitting = false;
  int? _focusTodoId;
  int _focusScrollAttempts = 0;
  bool _focusScrollScheduled = false;
  bool _didScrollToFocus = false;

  @override
  void initState() {
    super.initState();
    _handleInitialArgument(Get.arguments);
  }

  void _handleInitialArgument(Object? argument) {
    if (argument is ProjectTodoFocus) {
      _focusTodoId = argument.todoId;
      _focusScrollAttempts = 0;
      _didScrollToFocus = false;
      controller.activeTab.value = 'standard';
      controller.selectProject(argument.project);
      return;
    }
    if (argument is BiostatProject) {
      controller.selectProject(argument);
    }
  }

  void _scheduleFocusScroll() {
    final todoId = _focusTodoId;
    if (todoId == null ||
        _didScrollToFocus ||
        _focusScrollScheduled ||
        controller.activeTab.value == 'meetings') {
      return;
    }

    _focusScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusScrollScheduled = false;
      if (!mounted) return;

      final targetContext = _focusTodoKey.currentContext;
      if (targetContext == null) {
        if (_focusScrollAttempts < 6) {
          _focusScrollAttempts += 1;
          Future<void>.delayed(const Duration(milliseconds: 120), () {
            if (mounted) _scheduleFocusScroll();
          });
        }
        return;
      }

      _didScrollToFocus = true;
      _focusScrollAttempts = 0;
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        alignment: 0.14,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final settledContext = _focusTodoKey.currentContext;
        if (settledContext == null) return;
        Scrollable.ensureVisible(
          settledContext,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: 0.14,
        );
      });
    });
  }

  @override
  void dispose() {
    _assistantController.dispose();
    _agentScrollController.dispose();
    _quickAddController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final project = controller.selectedProject.value;
      return Scaffold(
        appBar: widget.embedded == true
            ? null
            : AppBar(
                title: Text(project?.name ?? '项目工作台'),
                actions: [
                  IconButton(
                    tooltip: '编辑项目',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: project == null
                        ? null
                        : () => _showProjectEditDialog(context, project),
                  ),
                  IconButton(
                    tooltip: '删除项目',
                    color: Theme.of(context).colorScheme.error,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: project == null
                        ? null
                        : () => _confirmDeleteProject(context, project),
                  ),
                  IconButton(
                    tooltip: '快捷创建',
                    icon: const Icon(Icons.add_task),
                    onPressed: project == null
                        ? null
                        : () => _showQuickCreateSheet(context),
                  ),
                ],
              ),
        body: project == null
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: controller.refreshWorkspace,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 104),
                  children: [
                    _buildProjectHeader(context, project),
                    const SizedBox(height: 12),
                    _buildTabs(context),
                    const SizedBox(height: 12),
                    _buildCurrentList(context),
                    const SizedBox(height: 16),
                    _buildAssistant(context),
                  ],
                ),
              ),
        floatingActionButton: project == null
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _showQuickCreateSheet(context),
                icon: const Icon(Icons.add),
                label: const Text('快捷创建'),
              ),
      );
    });
  }

  Widget _buildProjectHeader(BuildContext context, BiostatProject project) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    project.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                Chip(
                  label: Text(project.isCompleted ? '已结束' : '进行中'),
                  backgroundColor:
                      (project.isCompleted ? Colors.green : Colors.blue)
                          .withValues(alpha: 0.12),
                  side: BorderSide.none,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Chip(
                  avatar: const Icon(Icons.category_outlined, size: 16),
                  label: Text(projectTypeLabel(project.projectType)),
                  side: BorderSide.none,
                ),
                Chip(
                  avatar: Icon(
                    project.isCdisc
                        ? Icons.verified_outlined
                        : Icons.data_object,
                    size: 16,
                  ),
                  label: Text(project.cdiscLabel),
                  side: BorderSide.none,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                project.sponsor,
                project.protocolNo,
                project.phase,
                project.indication,
              ].where((item) => item.isNotEmpty).join(' · '),
            ),
            if (project.displayDescription.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                project.displayDescription,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 16),
            _SegmentedProgress(project: project),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _legend(Colors.green, '已完成 ${project.doneTodoCount}'),
                _legend(Colors.orange, '进行中 ${project.inProgressTodoCount}'),
                _legend(Colors.blueGrey, '未开始 ${project.openTodoCount}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }

  Widget _buildTabs(BuildContext context) {
    return Obx(() {
      final validTabs = {'standard', 'meetings', 'members', 'timeline'};
      final tab = validTabs.contains(controller.activeTab.value)
          ? controller.activeTab.value
          : 'standard';
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'standard',
              label: Text('标准流程'),
              icon: Icon(Icons.account_tree_outlined),
            ),
            ButtonSegment(
              value: 'meetings',
              label: Text('会议'),
              icon: Icon(Icons.video_call_outlined),
            ),
            ButtonSegment(
              value: 'members',
              label: Text('项目成员'),
              icon: Icon(Icons.groups_outlined),
            ),
            ButtonSegment(
              value: 'timeline',
              label: Text('Timeline'),
              icon: Icon(Icons.timeline_outlined),
            ),
          ],
          selected: {tab},
          onSelectionChanged: (values) =>
              controller.activeTab.value = values.first,
        ),
      );
    });
  }

  Widget _buildCurrentList(BuildContext context) {
    final tab = controller.activeTab.value;
    if (tab == 'meetings') {
      return _buildMeetings(context);
    }
    if (tab == 'members') {
      return _buildMembers(context);
    }
    if (tab == 'timeline') {
      return _buildTimeline(context);
    }
    return _buildStandardWorkflow(context);
  }

  Widget _buildStandardWorkflow(BuildContext context) {
    final grouped = controller.workflowTodosByPhase;
    if (grouped.isEmpty) {
      return Column(
        children: [
          _buildWorkflowActions(context),
          _buildEmpty(context, '暂无流程待办'),
        ],
      );
    }
    return Column(
      children: [
        _buildWorkflowActions(context),
        ...grouped.entries.map((entry) {
          final phase = controller.orderedWorkflowPhases
              .firstWhereOrNull((item) => item.name == entry.key);
          final movablePhases = controller.orderedWorkflowPhases
              .where((item) => item.id > 0)
              .toList();
          final phaseIndex = phase == null
              ? -1
              : movablePhases.indexWhere((item) => item.id == phase.id);
          final canMoveUp = phaseIndex > 0;
          final canMoveDown =
              phaseIndex >= 0 && phaseIndex < movablePhases.length - 1;
          final todos = entry.value;
          final done = todos.where((todo) => todo.isDone).length;
          final isFocusPhase = _focusTodoId != null &&
              todos.any((todo) => todo.id == _focusTodoId);
          return Card(
            child: ExpansionTile(
              key: PageStorageKey(
                'phase-${entry.key}-${isFocusPhase ? _focusTodoId : 'normal'}',
              ),
              controlAffinity: ListTileControlAffinity.leading,
              initiallyExpanded: isFocusPhase,
              title: Text(entry.key),
              subtitle: Text('$done/${todos.length} 完成'),
              trailing: IconButton(
                tooltip: '阶段操作',
                icon: const Icon(Icons.more_vert),
                onPressed: () => _showGlassActionSheet(
                  context,
                  title: '阶段操作',
                  actions: [
                    _GlassAction(
                      icon: Icons.add_task,
                      label: '新增本阶段待办',
                      onTap: () => _showTodoDialog(
                        context,
                        todoType: 'standard',
                        phase: entry.key,
                      ),
                    ),
                    if (phase != null && phase.id > 0) ...[
                      _GlassAction(
                        icon: Icons.edit_outlined,
                        label: '编辑阶段',
                        onTap: () => _showPhaseDialog(context, phase: phase),
                      ),
                      if (canMoveUp)
                        _GlassAction(
                          icon: Icons.arrow_upward,
                          label: '上移阶段',
                          onTap: () => controller.movePhase(phase, -1),
                        ),
                      if (canMoveDown)
                        _GlassAction(
                          icon: Icons.arrow_downward,
                          label: '下移阶段',
                          onTap: () => controller.movePhase(phase, 1),
                        ),
                      _GlassAction(
                        icon: Icons.delete_outline,
                        label: '删除阶段',
                        destructive: true,
                        onTap: () => _confirmDeletePhase(context, phase),
                      ),
                    ],
                  ],
                ),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: LinearProgressIndicator(
                    value: todos.isEmpty ? 0 : done / todos.length,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                if (todos.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '本阶段暂无待办',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                  )
                else
                  ..._buildTodoCardsForPhase(context, entry.key, todos),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildWorkflowActions(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final project = controller.selectedProject.value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 常驻快捷添加行：回车即建「流程待办」状态的下一条任务。
          TextField(
            controller: _quickAddController,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) async {
              final title = _quickAddController.text.trim();
              if (title.isEmpty || project == null) return;
              _quickAddController.clear();
              await controller.quickAddTodo(project, title);
            },
            decoration: InputDecoration(
              hintText: '输入任务，回车快速添加到流程待办…',
              prefixIcon: const Icon(Icons.fastfood, size: 20),
              suffixIcon: IconButton(
                tooltip: '快捷添加',
                onPressed: () async {
                  final title = _quickAddController.text.trim();
                  if (title.isEmpty || project == null) return;
                  _quickAddController.clear();
                  await controller.quickAddTodo(project, title);
                },
                icon: const Icon(Icons.send, size: 20),
              ),
              filled: true,
              fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: controller.seedStandardWorkflow,
                  icon: const Icon(Icons.playlist_add_check),
                  label: const Text('补齐标准流程'),
                ),
                TextButton.icon(
                  onPressed: () => _showPhaseDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('新增阶段'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTodoCardsForPhase(
    BuildContext context,
    String phaseName,
    List<ProjectTodo> todos,
  ) {
    return [
      for (var index = 0; index < todos.length; index++)
        _buildDraggableTodoCard(
          context,
          phaseName: phaseName,
          todos: todos,
          index: index,
        ),
      _buildTodoDropTarget(context, phaseName, todos, todos.length),
    ];
  }

  Widget _buildDraggableTodoCard(
    BuildContext context, {
    required String phaseName,
    required List<ProjectTodo> todos,
    required int index,
  }) {
    final todo = todos[index];
    final isFocused = todo.id == _focusTodoId;
    if (isFocused) {
      _scheduleFocusScroll();
    }

    return Container(
      key: isFocused ? _focusTodoKey : ValueKey('todo-anchor-${todo.id}'),
      child: _buildTodoDropTarget(
        context,
        phaseName,
        todos,
        index,
        child: LongPressDraggable<int>(
          data: todo.id,
          feedback: _buildTodoDragFeedback(context, todo),
          childWhenDragging: Opacity(
            opacity: 0.35,
            child: _buildTodoCard(
              context,
              todo,
              showDragHandle: true,
            ),
          ),
          child: _buildTodoCard(
            context,
            todo,
            showDragHandle: true,
          ),
        ),
      ),
    );
  }

  Widget _buildTodoDropTarget(
    BuildContext context,
    String phaseName,
    List<ProjectTodo> todos,
    int targetIndex, {
    Widget? child,
  }) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) {
        final draggedId = details.data;
        return todos.any((todo) => todo.id == draggedId) &&
            (targetIndex >= todos.length || todos[targetIndex].id != draggedId);
      },
      onAcceptWithDetails: (details) {
        _moveTodoInPhase(phaseName, todos, details.data, targetIndex);
      },
      builder: (context, candidateData, rejectedData) {
        final isActive = candidateData.isNotEmpty;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: isActive ? 12 : 0,
              margin: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            if (child != null) child,
          ],
        );
      },
    );
  }

  Widget _buildTodoDragFeedback(BuildContext context, ProjectTodo todo) {
    final width = MediaQuery.sizeOf(context).width.clamp(240.0, 420.0) - 48;
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      color: Theme.of(context).colorScheme.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.drag_handle),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  todo.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _moveTodoInPhase(
    String phaseName,
    List<ProjectTodo> todos,
    int draggedTodoId,
    int targetIndex,
  ) {
    final oldIndex = todos.indexWhere((todo) => todo.id == draggedTodoId);
    if (oldIndex < 0) return;
    var insertIndex = oldIndex < targetIndex ? targetIndex - 1 : targetIndex;
    final reordered = [...todos];
    final moved = reordered.removeAt(oldIndex);
    insertIndex = insertIndex.clamp(0, reordered.length);
    if (insertIndex == oldIndex) return;
    reordered.insert(insertIndex, moved);
    controller.reorderTodosInPhase(
      phaseName,
      reordered.map((todo) => todo.id).toList(),
    );
  }

  Widget _buildTodoCard(
    BuildContext context,
    ProjectTodo todo, {
    bool showDragHandle = false,
  }) {
    final metaText = [
      _displayPhase(todo.phase),
      todo.priority,
      todo.startAt == null ? '' : '开始 ${_formatDateTime(todo.startAt!)}',
      todo.dueAt == null ? '' : '截止 ${_formatDateTime(todo.dueAt!)}',
    ].where((item) => item.isNotEmpty).join(' · ');
    final colorScheme = Theme.of(context).colorScheme;
    final isFocused = todo.id == _focusTodoId;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      color: isFocused
          ? colorScheme.primaryContainer.withValues(alpha: 0.32)
          : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox.square(
                  dimension: 40,
                  child: Checkbox(
                    value: todo.isDone,
                    onChanged: (_) => controller.toggleTodo(todo),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          todo.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    decoration: todo.isDone
                                        ? TextDecoration.lineThrough
                                        : null,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        if (todo.isWorkflowInferred) ...[
                          const SizedBox(height: 4),
                          Text('流程推断 · 可修改',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary)),
                        ],
                        if (metaText.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            metaText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                        ],
                        if (!todo.isDone) ...[
                          const SizedBox(height: 8),
                          _buildStatusChips(context, todo),
                        ],
                      ],
                    ),
                  ),
                ),
                if (showDragHandle)
                  const SizedBox.square(
                    dimension: 40,
                    child: Icon(Icons.drag_handle),
                  ),
                SizedBox.square(
                  dimension: 40,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    tooltip: '待办操作',
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => _showGlassActionSheet(
                      context,
                      title: '待办操作',
                      actions: [
                        _GlassAction(
                          icon: Icons.edit_outlined,
                          label: '编辑',
                          onTap: () => _showTodoDialog(context, todo: todo),
                        ),
                        _GlassAction(
                          icon: Icons.notifications_active_outlined,
                          label: '同步提醒',
                          onTap: () => controller.syncTodoReminder(todo),
                        ),
                        _GlassAction(
                          icon: Icons.delete_outline,
                          label: '删除',
                          destructive: true,
                          onTap: () => controller.deleteTodo(todo),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (todo.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 46, right: 6),
                child: Text(
                  todo.description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
            _buildChecklist(context, todo),
          ],
        ),
      ),
    );
  }

  /// 紧凑状态 chips：一键改状态，避免打开编辑框。
  Widget _buildStatusChips(BuildContext context, ProjectTodo todo) {
    final scheme = Theme.of(context).colorScheme;
    Widget chip(String label, String status, {bool highlight = false}) {
      final selected = todo.status == status;
      return InkWell(
        onTap: () => controller.setTodoStatus(todo, status),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: highlight
                ? scheme.primaryContainer.withValues(alpha: selected ? 1 : 0.5)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: highlight ? scheme.primary : null,
                ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        chip('下一步', 'next'),
        chip('进行中', 'in_progress'),
        chip('等待', 'waiting'),
        chip('稍后', 'someday'),
        chip('✓ 完成', 'done', highlight: true),
      ],
    );
  }

  Widget _buildChecklist(BuildContext context, ProjectTodo todo) {
    final items = todo.checklistItems;
    final done = items.where((item) => item.isDone).length;
    final colorScheme = Theme.of(context).colorScheme;
    final isFocused = todo.id == _focusTodoId;

    return Padding(
      padding: const EdgeInsets.only(left: 46, right: 6, top: 8),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey(
            'checklist-${todo.id}-${isFocused ? _focusTodoId : 'normal'}',
          ),
          initiallyExpanded: isFocused,
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 6),
          leading: const Icon(Icons.checklist_rtl, size: 20),
          title: Text(
            '清单 $done/${items.length}',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          subtitle: Text(
            items.isEmpty ? '暂无清单项' : '展开查看清单、截止时间和绑定会议',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          children: [
            if (items.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 6),
                  child: Text(
                    '这个待办还没有清单项',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              )
            else
              ...items.map((item) {
                final meeting = controller.meetingForChecklist(item);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.32),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(2, 6, 4, 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox.square(
                            dimension: 36,
                            child: Checkbox(
                              value: item.isDone,
                              onChanged: (_) =>
                                  _handleChecklistToggle(context, todo, item),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      decoration: item.isDone
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                  if (item.dueAt != null) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      '截止 ${_formatDateTime(item.dueAt!)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                  if (meeting != null) ...[
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Chip(
                                          avatar: const Icon(
                                            Icons.video_call_outlined,
                                            size: 16,
                                          ),
                                          label: Text(
                                            meeting.title,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          visualDensity: VisualDensity.compact,
                                          side: BorderSide.none,
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: () =>
                                              _showMeetingDetailSheet(
                                            context,
                                            meeting,
                                          ),
                                          icon: const Icon(
                                            Icons.event_note_outlined,
                                            size: 16,
                                          ),
                                          label: const Text('查看会议详情'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          SizedBox.square(
                            dimension: 36,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              tooltip: '清单项操作',
                              icon: const Icon(Icons.more_vert),
                              onPressed: () => _showGlassActionSheet(
                                context,
                                title: '清单项操作',
                                actions: [
                                  _GlassAction(
                                    icon: Icons.edit_outlined,
                                    label: '编辑',
                                    onTap: () => _showChecklistDialog(
                                      context,
                                      todo,
                                      item: item,
                                    ),
                                  ),
                                  if (controller.meetings.isNotEmpty)
                                    _GlassAction(
                                      icon: Icons.video_call_outlined,
                                      label: meeting == null ? '绑定会议' : '更换会议',
                                      onTap: () => _showChecklistDialog(
                                        context,
                                        todo,
                                        item: item,
                                      ),
                                    ),
                                  if (meeting != null)
                                    _GlassAction(
                                      icon: Icons.link_off_outlined,
                                      label: '取消会议绑定',
                                      onTap: () =>
                                          controller.updateChecklistItem(
                                        item,
                                        clearMeeting: true,
                                      ),
                                    ),
                                  _GlassAction(
                                    icon: Icons.delete_outline,
                                    label: '删除',
                                    destructive: true,
                                    onTap: () =>
                                        controller.deleteChecklistItem(item),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _showChecklistDialog(context, todo),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加清单项'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateTimeRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required DateTime? value,
    required String pickTooltip,
    required String clearTooltip,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyLarge),
                Text(
                  value == null ? '未设置' : _formatDateTime(value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: pickTooltip,
            icon: const Icon(Icons.edit_calendar),
            onPressed: onPick,
            visualDensity: VisualDensity.compact,
          ),
          if (value != null)
            IconButton(
              tooltip: clearTooltip,
              icon: const Icon(Icons.close),
              onPressed: onClear,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _buildMeetings(BuildContext context) {
    if (controller.meetings.isEmpty) return _buildEmpty(context, '暂无会议');
    return Column(
      children: controller.meetings.map((meeting) {
        return Card(
          child: ListTile(
            leading: const Icon(Icons.video_call_outlined),
            title: Text(meeting.title),
            subtitle: Text(
              [
                _formatMeetingRange(meeting),
                meeting.location,
                meeting.agenda,
              ].where((item) => item.isNotEmpty).join('\n'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showMeetingDetailSheet(context, meeting),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMembers(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const memberTypes = [
      'sponsor',
      'statistical_partner',
      'internal',
      'other',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _showMemberParseDialog(context),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('AI 识别成员'),
            ),
            FilledButton.icon(
              onPressed: () => _showMemberDialog(context),
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label: const Text('添加成员'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (controller.members.isEmpty)
          _buildEmpty(context, '暂无项目成员，可手动添加或粘贴文本识别')
        else
          ...memberTypes.map((type) {
            final items = controller.members
                .where((member) => member.memberType == type)
                .toList();
            if (items.isEmpty) return const SizedBox.shrink();
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      projectMemberTypeLabel(type),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    ...items.map(
                      (member) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: scheme.primaryContainer,
                          foregroundColor: scheme.onPrimaryContainer,
                          child: Text(
                            member.name.isEmpty
                                ? '?'
                                : member.name.characters.first,
                          ),
                        ),
                        title: Text(member.name),
                        subtitle: Text(
                          [
                            member.organization,
                            member.role,
                            member.email,
                            member.phone,
                            member.notes,
                          ].where((value) => value.isNotEmpty).join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: PopupMenuButton<String>(
                          tooltip: '成员操作',
                          onSelected: (action) {
                            if (action == 'edit') {
                              _showMemberDialog(context, member: member);
                            } else if (action == 'delete') {
                              _confirmDeleteMember(context, member);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('编辑')),
                            PopupMenuItem(value: 'delete', child: Text('删除')),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildTimeline(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _showTimelineTextDialog(context),
              icon: const Icon(Icons.notes_outlined, size: 18),
              label: const Text('粘贴文字'),
            ),
            FilledButton.icon(
              onPressed: () => _pickTimelineFile(context),
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: const Text('导入 Excel/CSV'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (controller.timelineImports.isEmpty)
          _buildEmpty(context, '暂无 Timeline 导入记录')
        else
          ...controller.timelineImports.map(
            (timeline) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ExpansionTile(
                initiallyExpanded: false,
                title: Text(
                  timeline.fileName.isEmpty ? '文字 Timeline' : timeline.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${timeline.items.length} 条 · ${timeline.status}${timeline.fallbackUsed ? ' · 本地规则' : ''}',
                ),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Timeline 操作',
                  onSelected: (action) {
                    if (action == 'delete') {
                      _confirmDeleteTimeline(context, timeline);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'delete', child: Text('删除导入记录')),
                  ],
                ),
                children: timeline.items
                    .map((item) => _buildTimelineItem(context, item))
                    .toList(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTimelineItem(
    BuildContext context,
    ProjectTimelineItem item,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final targetValue = _timelineTargetValue(item);
    final targetItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: 'none', child: Text('未绑定项目事项')),
      ...controller.todos.map(
        (todo) => DropdownMenuItem(
          value: 'todo-${todo.id}',
          child: Text('任务 · ${todo.title}', overflow: TextOverflow.ellipsis),
        ),
      ),
      ...controller.checklistItems.map(
        (checklist) => DropdownMenuItem(
          value: 'checklist-${checklist.id}',
          child: Text(
            '清单 · ${_checklistLabel(checklist)}',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 14,
                    child: Text('${item.rowNumber}'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  Icon(
                    item.isMatched ? Icons.link : Icons.link_off,
                    color: item.isMatched ? scheme.primary : scheme.error,
                    size: 20,
                  ),
                ],
              ),
              if (item.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  item.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue:
                    targetItems.any((entry) => entry.value == targetValue)
                        ? targetValue
                        : 'none',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '绑定到项目任务或清单',
                  prefixIcon: Icon(Icons.account_tree_outlined),
                ),
                items: targetItems,
                onChanged: (value) =>
                    _saveTimelineTarget(item, value ?? 'none'),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _timelineDateSummary(item),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _showTimelineDateDialog(context, item),
                    icon: const Icon(Icons.edit_calendar, size: 18),
                    label: const Text('日期'),
                  ),
                ],
              ),
              if (item.warning.isNotEmpty)
                Text(
                  item.warning,
                  style: TextStyle(color: scheme.error),
                ),
              if (item.confidence != null)
                Text(
                  '匹配置信度 ${(item.confidence! * 100).round()}%',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _timelineTargetValue(ProjectTimelineItem item) {
    if (item.targetType == 'todo' && item.matchedTodoId != null) {
      return 'todo-${item.matchedTodoId}';
    }
    if (item.targetType == 'checklist' && item.matchedChecklistItemId != null) {
      return 'checklist-${item.matchedChecklistItemId}';
    }
    return 'none';
  }

  String _timelineDateSummary(ProjectTimelineItem item) {
    if (item.startAt == null && item.dueAt == null) return '未识别到日期';
    final start =
        item.startAt == null ? '' : '开始 ${_formatDateTime(item.startAt!)}';
    final due = item.dueAt == null ? '' : '截止 ${_formatDateTime(item.dueAt!)}';
    return [start, due].where((value) => value.isNotEmpty).join(' · ');
  }

  Future<void> _saveTimelineTarget(
    ProjectTimelineItem item,
    String value,
  ) async {
    String targetType = 'none';
    int? todoId;
    int? checklistId;
    if (value.startsWith('todo-')) {
      targetType = 'todo';
      todoId = int.tryParse(value.substring(5));
    } else if (value.startsWith('checklist-')) {
      targetType = 'checklist';
      checklistId = int.tryParse(value.substring(10));
    }
    try {
      await controller.updateTimelineItem(
        item,
        targetType: targetType,
        todoId: todoId,
        checklistItemId: checklistId,
      );
      Get.snackbar('Timeline', '绑定已保存，日期已同步到目标事项');
    } catch (error) {
      Get.snackbar('Timeline', '绑定失败: $error');
    }
  }

  Future<void> _showTimelineDateDialog(
    BuildContext context,
    ProjectTimelineItem item,
  ) async {
    DateTime? startAt = item.startAt;
    DateTime? dueAt = item.dueAt;
    await showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => LiquidGlassAlertDialog(
          title: const Text('编辑 Timeline 日期'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDateTimeRow(
                dialogContext,
                icon: Icons.play_circle_outline,
                title: '开始时间',
                value: startAt,
                pickTooltip: '选择开始时间',
                clearTooltip: '清除开始时间',
                onPick: () async {
                  final value = await _pickDateTime(dialogContext, startAt);
                  if (value != null) setDialogState(() => startAt = value);
                },
                onClear: () => setDialogState(() => startAt = null),
              ),
              _buildDateTimeRow(
                dialogContext,
                icon: Icons.event_available,
                title: '截止时间',
                value: dueAt,
                pickTooltip: '选择截止时间',
                clearTooltip: '清除截止时间',
                onPick: () async {
                  final value = await _pickDateTime(dialogContext, dueAt);
                  if (value != null) setDialogState(() => dueAt = value);
                },
                onClear: () => setDialogState(() => dueAt = null),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                await controller.updateTimelineItem(
                  item,
                  startAt: startAt,
                  dueAt: dueAt,
                  clearStartAt: startAt == null,
                  clearDueAt: dueAt == null,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('保存并同步'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMemberDialog(
    BuildContext context, {
    ProjectMember? member,
  }) {
    final name = TextEditingController(text: member?.name ?? '');
    final organization =
        TextEditingController(text: member?.organization ?? '');
    final role = TextEditingController(text: member?.role ?? '');
    final email = TextEditingController(text: member?.email ?? '');
    final phone = TextEditingController(text: member?.phone ?? '');
    final notes = TextEditingController(text: member?.notes ?? '');
    var type = member?.memberType ?? 'other';
    return showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => LiquidGlassAlertDialog(
          title: Text(member == null ? '添加项目成员' : '编辑项目成员'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '成员类型'),
                  items: const [
                    DropdownMenuItem(value: 'sponsor', child: Text('申办方')),
                    DropdownMenuItem(
                        value: 'statistical_partner', child: Text('合作统计方')),
                    DropdownMenuItem(value: 'internal', child: Text('内部团队')),
                    DropdownMenuItem(value: 'other', child: Text('其他')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => type = value);
                  },
                ),
                TextField(
                    controller: name,
                    autofocus: member == null,
                    decoration: const InputDecoration(labelText: '姓名')),
                TextField(
                    controller: organization,
                    decoration: const InputDecoration(labelText: '组织/公司')),
                TextField(
                    controller: role,
                    decoration: const InputDecoration(labelText: '职责')),
                TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: '邮箱')),
                TextField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: '电话')),
                TextField(
                    controller: notes,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: '备注')),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                if (name.text.trim().isEmpty) {
                  Get.snackbar('项目成员', '姓名不能为空');
                  return;
                }
                if (member == null) {
                  await controller.createMember(
                    memberType: type,
                    name: name.text,
                    organization: organization.text,
                    role: role.text,
                    email: email.text,
                    phone: phone.text,
                    notes: notes.text,
                  );
                } else {
                  await controller.updateMember(
                    member,
                    memberType: type,
                    name: name.text,
                    organization: organization.text,
                    role: role.text,
                    email: email.text,
                    phone: phone.text,
                    notes: notes.text,
                  );
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      name.dispose();
      organization.dispose();
      role.dispose();
      email.dispose();
      phone.dispose();
      notes.dispose();
    });
  }

  Future<void> _showMemberParseDialog(BuildContext context) async {
    final text = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => LiquidGlassAlertDialog(
        title: const Text('AI 识别项目成员'),
        content: TextField(
          controller: text,
          autofocus: true,
          minLines: 5,
          maxLines: 10,
          decoration: const InputDecoration(
            hintText: '粘贴姓名、公司、职责、邮箱等信息，AI 会按四类成员保存',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              if (text.text.trim().isEmpty) return;
              await controller.parseMembers(text.text);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('识别并保存'),
          ),
        ],
      ),
    );
    text.dispose();
  }

  Future<void> _confirmDeleteMember(
    BuildContext context,
    ProjectMember member,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => LiquidGlassAlertDialog(
        title: const Text('删除项目成员'),
        content: Text('确定删除 ${member.name} 的成员记录吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.deleteMember(member);
  }

  Future<void> _showTimelineTextDialog(BuildContext context) async {
    final text = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => LiquidGlassAlertDialog(
        title: const Text('导入文字 Timeline'),
        content: TextField(
          controller: text,
          autofocus: true,
          minLines: 6,
          maxLines: 14,
          decoration: const InputDecoration(
            hintText: '每行输入一个事项，也支持制表符、逗号或竖线分隔的表格文本',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              if (text.text.trim().isEmpty) return;
              await controller.importTimelineText(text.text);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('解析并导入'),
          ),
        ],
      ),
    );
    text.dispose();
  }

  Future<void> _pickTimelineFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'xlsm', 'csv', 'tsv', 'txt'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      Get.snackbar('Timeline', '无法读取文件内容');
      return;
    }
    try {
      await controller.importTimelineFile(bytes, file.name);
      Get.snackbar('Timeline', '导入完成，已尝试匹配项目任务和清单');
    } catch (error) {
      Get.snackbar('Timeline', '导入失败: $error');
    }
  }

  Future<void> _confirmDeleteTimeline(
    BuildContext context,
    ProjectTimelineImport timeline,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => LiquidGlassAlertDialog(
        title: const Text('删除 Timeline 导入记录'),
        content: const Text('只删除导入记录，不会删除本地文件，也不会自动清除已经同步到任务的日期。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed == true) await controller.deleteTimelineImport(timeline);
  }

  Widget _buildAssistant(BuildContext context) {
    if (controller.agentMessages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_agentScrollController.hasClients) return;
        _agentScrollController.animateTo(
          _agentScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      });
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '项目 Agent',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            if (controller.agentMessages.isNotEmpty) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.separated(
                  controller: _agentScrollController,
                  shrinkWrap: true,
                  itemCount: controller.agentMessages.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _buildAgentMessage(
                      context, controller.agentMessages[index]),
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _assistantController,
              minLines: 2,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: '告诉 Agent 已完成什么、接下来做什么，或粘贴会议内容',
                prefixIcon: Icon(Icons.chat_bubble_outline),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _agentSubmitting ? null : _submitAgentMessage,
                icon: _agentSubmitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(_agentSubmitting ? '整理中…' : '发送并整理项目'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgentMessage(
    BuildContext context,
    ProjectAgentMessage message,
  ) {
    final colors = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? colors.primaryContainer : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message.content,
          style: TextStyle(
            color: isUser ? colors.onPrimaryContainer : colors.onSurface,
          ),
        ),
      ),
    );
  }

  Future<void> _submitAgentMessage() async {
    final text = _assistantController.text.trim();
    if (text.isEmpty || _agentSubmitting) return;
    setState(() {
      _agentSubmitting = true;
    });
    _assistantController.clear();
    try {
      final result = await controller.runProjectAgent(text);
      if (!mounted || result == null) return;
      if (result.currentPhase?.isNotEmpty == true) {
        controller.activeTab.value = 'standard';
      }
    } catch (error) {
      if (!mounted) return;
      controller.addLocalAgentError('整理失败：$error');
    } finally {
      if (mounted) setState(() => _agentSubmitting = false);
    }
  }

  Widget _buildEmpty(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.5),
              ),
        ),
      ),
    );
  }

  void _showProjectEditDialog(
    BuildContext context,
    BiostatProject project,
  ) {
    final nameController = TextEditingController(text: project.name);
    final protocolController = TextEditingController(text: project.protocolNo);
    final phaseController = TextEditingController(text: project.phase);
    final sponsorController = TextEditingController(text: project.sponsor);
    final indicationController =
        TextEditingController(text: project.indication);
    final descriptionController =
        TextEditingController(text: project.description);
    String status = project.isCompleted ? 'completed' : 'active';
    String selectedProjectType =
        isKnownProjectType(project.projectType) ? project.projectType : 'other';
    bool isCdisc = project.isCdisc;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return LiquidGlassAlertDialog(
            title: const Text('编辑项目详情'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: '项目名称'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: protocolController,
                    decoration: const InputDecoration(labelText: '方案编号'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: phaseController,
                    decoration: const InputDecoration(labelText: '分期/阶段'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedProjectType,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '项目类型'),
                    items: projectTypeOptions
                        .map(
                          (option) => DropdownMenuItem(
                            value: option.value,
                            child: Text(
                              option.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => selectedProjectType = value);
                    },
                  ),
                  if (project.isCdiscUnconfirmed)
                    DropdownButtonFormField<String>(
                      initialValue: 'unknown',
                      decoration: const InputDecoration(labelText: 'CDISC 标记'),
                      items: const [
                        DropdownMenuItem(value: 'unknown', child: Text('待确认')),
                        DropdownMenuItem(value: 'yes', child: Text('CDISC 项目')),
                        DropdownMenuItem(
                            value: 'no', child: Text('非 CDISC 项目')),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          isCdisc = value == 'yes';
                          final description = descriptionController.text
                              .replaceAll('[snapshot:cdisc-unconfirmed]', '')
                              .trim();
                          descriptionController.text = value == 'unknown'
                              ? '$description\n[snapshot:cdisc-unconfirmed]'
                              : description;
                        });
                      },
                    )
                  else
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('CDISC 项目'),
                      subtitle: Text(
                        isCdisc ? '包含标准化数据集与监管提交资料' : '采用非 CDISC 分析数据与编程流程',
                      ),
                      value: isCdisc,
                      onChanged: (value) =>
                          setDialogState(() => isCdisc = value),
                    ),
                  TextField(
                    controller: sponsorController,
                    decoration: const InputDecoration(labelText: 'Sponsor'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: indicationController,
                    decoration: const InputDecoration(labelText: '适应症/治疗领域'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descriptionController,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(labelText: '项目描述'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: '项目状态'),
                    items: const [
                      DropdownMenuItem(value: 'active', child: Text('进行中')),
                      DropdownMenuItem(
                        value: 'completed',
                        child: Text('已结束'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => status = value);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.trim().isEmpty) {
                    Get.snackbar('项目详情', '项目名称不能为空');
                    return;
                  }
                  final updated = await controller.updateProject(
                    project,
                    name: nameController.text,
                    protocolNo: protocolController.text,
                    phase: phaseController.text,
                    sponsor: sponsorController.text,
                    projectType: selectedProjectType,
                    isCdisc: isCdisc,
                    indication: indicationController.text,
                    description: descriptionController.text,
                    status: status,
                  );
                  if (updated != null && dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteProject(
    BuildContext context,
    BiostatProject project,
  ) async {
    var confirmation = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final matches = confirmation.trim() == project.name.trim();
          return LiquidGlassAlertDialog(
            title: const Text('删除整个项目'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '将永久删除“${project.name}”及其全部阶段、待办、清单、会议和项目对话记录。',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: '输入项目名称确认',
                      hintText: project.name,
                    ),
                    onChanged: (value) {
                      setDialogState(() => confirmation = value);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(dialogContext).colorScheme.error,
                  foregroundColor: Theme.of(dialogContext).colorScheme.onError,
                ),
                onPressed:
                    matches ? () => Navigator.pop(dialogContext, true) : null,
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('永久删除'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await controller.deleteProject(project);
      if (!mounted) return;
      Get.back();
      Get.snackbar('项目已删除', '“${project.name}”及其关联记录已删除');
    } catch (error) {
      if (!mounted) return;
      Get.snackbar('删除失败', error.toString());
    }
  }

  void _showGlassActionSheet(
    BuildContext context, {
    required String title,
    required List<_GlassAction> actions,
  }) {
    showLiquidGlassBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                  child: Text(
                    title,
                    style: Theme.of(sheetContext)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 6),
                ...actions.map(
                  (action) => ListTile(
                    leading: Icon(
                      action.icon,
                      color: action.destructive ? scheme.error : null,
                    ),
                    title: Text(
                      action.label,
                      style: action.destructive
                          ? TextStyle(color: scheme.error)
                          : null,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      action.onTap();
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showQuickCreateSheet(BuildContext context) {
    showLiquidGlassBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            runSpacing: 12,
            children: [
              ListTile(
                leading: const Icon(Icons.add_task),
                title: const Text('新增流程待办'),
                onTap: () {
                  Navigator.pop(context);
                  _showTodoDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.video_call_outlined),
                title: const Text('快捷创建会议'),
                onTap: () {
                  Navigator.pop(context);
                  _showMeetingDialog(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPhaseDialog(BuildContext context, {ProjectPhase? phase}) {
    final nameController = TextEditingController(text: phase?.name ?? '');
    showDialog(
      context: context,
      builder: (_) => LiquidGlassAlertDialog(
        title: Text(phase == null ? '新增阶段' : '编辑阶段'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: '阶段名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              if (phase == null) {
                await controller.createPhase(name);
              } else {
                await controller.updatePhase(phase, name);
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(phase == null ? '创建' : '保存'),
          ),
        ],
      ),
    );
  }

  void _confirmDeletePhase(BuildContext context, ProjectPhase phase) {
    showDialog(
      context: context,
      builder: (_) => LiquidGlassAlertDialog(
        title: const Text('删除阶段'),
        content: Text('确定删除“${phase.name}”吗？该阶段下的待办不会删除，会移动到“流程待办”。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              await controller.deletePhase(phase);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 勾选清单项；若由此导致清单全部完成，提示用户同时完成待办。
  Future<void> _handleChecklistToggle(
    BuildContext context,
    ProjectTodo todo,
    ProjectChecklistItem item,
  ) async {
    final willCheck = !item.isDone;
    await controller.toggleChecklistItem(item);
    if (!willCheck) return;
    final allDone =
        todo.checklistItems.every((e) => e.isDone || identical(e, item));
    if (!allDone || !context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => LiquidGlassAlertDialog(
        title: const Text('清单已全部完成'),
        content: Text('是否同时将待办「${todo.title}」标记为已完成？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('完成待办'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.updateTodo(todo, status: 'done');
    }
  }

  void _showTodoDialog(
    BuildContext context, {
    ProjectTodo? todo,
    String todoType = 'extra',
    String phase = '流程待办',
  }) {
    final titleController = TextEditingController(text: todo?.title ?? '');
    final descController = TextEditingController(text: todo?.description ?? '');
    final phaseController = TextEditingController(
      text: todo == null ? phase : _displayPhase(todo.phase),
    );
    final checklistController = TextEditingController();
    DateTime? startAt = todo?.startAt;
    DateTime? dueAt = todo?.dueAt;
    bool syncReminder = dueAt != null;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return LiquidGlassAlertDialog(
            title: Text(todo == null ? '新增待办' : '编辑待办'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: '标题'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(labelText: '描述'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: phaseController,
                    decoration: const InputDecoration(labelText: '阶段'),
                  ),
                  const SizedBox(height: 8),
                  _buildDateTimeRow(
                    dialogContext,
                    icon: Icons.play_circle_outline,
                    title: '开始日期',
                    value: startAt,
                    pickTooltip: '选择开始日期',
                    clearTooltip: '清除开始日期',
                    onPick: () async {
                      final selected = await _pickDateTime(
                        dialogContext,
                        startAt,
                      );
                      if (selected == null) return;
                      setDialogState(() => startAt = selected);
                    },
                    onClear: () => setDialogState(() => startAt = null),
                  ),
                  const SizedBox(height: 4),
                  _buildDateTimeRow(
                    dialogContext,
                    icon: Icons.event_available,
                    title: '截止时间',
                    value: dueAt,
                    pickTooltip: '选择时间',
                    clearTooltip: '清除时间',
                    onPick: () async {
                      final selected = await _pickDateTime(
                        dialogContext,
                        dueAt,
                      );
                      if (selected == null) return;
                      setDialogState(() {
                        dueAt = selected;
                        syncReminder = true;
                      });
                    },
                    onClear: () {
                      setDialogState(() {
                        dueAt = null;
                        syncReminder = false;
                      });
                    },
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: syncReminder && dueAt != null,
                    onChanged: dueAt == null
                        ? null
                        : (value) {
                            setDialogState(() {
                              syncReminder = value ?? false;
                            });
                          },
                    title: const Text('同步到手机日历和系统提醒'),
                    subtitle: const Text('默认提前 1小时、30分钟、10分钟提醒'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (todo == null) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: checklistController,
                      minLines: 3,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: '清单项',
                        hintText: '每行一项，可留空',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () async {
                  ProjectTodo? savedTodo;
                  if (todo == null) {
                    savedTodo = await controller.createTodo(
                      titleController.text.trim(),
                      description: descController.text.trim(),
                      todoType: todoType,
                      phase: phaseController.text.trim(),
                      startAt: startAt,
                      dueAt: dueAt,
                      checklistItems: checklistController.text.split('\n'),
                    );
                  } else {
                    savedTodo = await controller.updateTodo(
                      todo,
                      title: titleController.text.trim(),
                      description: descController.text.trim(),
                      phase: phaseController.text.trim(),
                      startAt: startAt,
                      dueAt: dueAt,
                      clearStartAt: startAt == null,
                      clearDueAt: dueAt == null,
                    );
                  }
                  if (syncReminder && savedTodo != null) {
                    await controller.syncTodoReminder(savedTodo);
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: Text(todo == null ? '创建' : '保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<DateTime?> _pickDateTime(
      BuildContext context, DateTime? current) async {
    final now = DateTime.now();
    final initial = current ?? now.add(const Duration(days: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !context.mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _formatDateTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  String _formatTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}';
  }

  String _formatMeetingRange(ProjectMeeting meeting) {
    final startsAt = meeting.startsAt;
    final endsAt = meeting.endsAt;
    if (startsAt == null && endsAt == null) return '未设置会议时间段';
    if (startsAt != null && endsAt != null) {
      final sameDay = startsAt.year == endsAt.year &&
          startsAt.month == endsAt.month &&
          startsAt.day == endsAt.day;
      if (sameDay) {
        return '${_formatDateTime(startsAt)} - ${_formatTime(endsAt)}';
      }
      return '${_formatDateTime(startsAt)} - ${_formatDateTime(endsAt)}';
    }
    if (startsAt != null) return '开始 ${_formatDateTime(startsAt)}';
    return '结束 ${_formatDateTime(endsAt!)}';
  }

  String _checklistLabel(ProjectChecklistItem item) {
    final todo = controller.todos.firstWhereOrNull(
      (entry) => entry.id == item.todoId,
    );
    final todoTitle = todo?.title ?? '待办';
    return '$todoTitle / ${item.title}';
  }

  String _displayPhase(String value) {
    return value.isEmpty || value == '额外待办' ? '流程待办' : value;
  }

  void _showChecklistDialog(
    BuildContext context,
    ProjectTodo todo, {
    ProjectChecklistItem? item,
  }) {
    final controllerText = TextEditingController(text: item?.title ?? '');
    DateTime? dueAt = item?.dueAt;
    final meetingIds = controller.meetings.map((meeting) => meeting.id).toSet();
    int? selectedMeetingId =
        meetingIds.contains(item?.meetingId) ? item?.meetingId : null;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return LiquidGlassAlertDialog(
            title: Text(item == null ? '添加清单项' : '编辑清单项'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controllerText,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: '清单内容'),
                  ),
                  const SizedBox(height: 8),
                  _buildDateTimeRow(
                    dialogContext,
                    icon: Icons.event_available,
                    title: '清单截止时间',
                    value: dueAt,
                    pickTooltip: '选择截止时间',
                    clearTooltip: '清除截止时间',
                    onPick: () async {
                      final selected =
                          await _pickDateTime(dialogContext, dueAt);
                      if (selected == null) return;
                      setDialogState(() => dueAt = selected);
                    },
                    onClear: () => setDialogState(() => dueAt = null),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int?>(
                    initialValue: selectedMeetingId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '绑定会议',
                      helperText: '会议使用开始/结束时间段，不会替代清单截止时间',
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('不绑定会议'),
                      ),
                      ...controller.meetings.map(
                        (meeting) => DropdownMenuItem<int?>(
                          value: meeting.id,
                          child: Text(
                            '${meeting.title} · ${_formatMeetingRange(meeting)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setDialogState(() => selectedMeetingId = value);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (item == null) {
                    await controller.addChecklistItem(
                      todo,
                      controllerText.text,
                      dueAt: dueAt,
                      meetingId: selectedMeetingId,
                    );
                  } else {
                    await controller.updateChecklistItem(
                      item,
                      title: controllerText.text.trim(),
                      dueAt: dueAt,
                      meetingId: selectedMeetingId,
                      clearDueAt: dueAt == null,
                      clearMeeting: selectedMeetingId == null,
                    );
                  }
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: Text(item == null ? '添加' : '保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showMeetingDetailSheet(BuildContext context, ProjectMeeting meeting) {
    showLiquidGlassBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  meeting.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 12),
                _detailRow(
                  context,
                  Icons.schedule_outlined,
                  '会议时间段',
                  _formatMeetingRange(meeting),
                ),
                if (meeting.location.isNotEmpty)
                  _detailRow(
                    context,
                    Icons.place_outlined,
                    '地点',
                    meeting.location,
                  ),
                if (meeting.attendees.isNotEmpty)
                  _detailRow(
                    context,
                    Icons.people_outline,
                    '参会人',
                    meeting.attendees,
                  ),
                if (meeting.agenda.isNotEmpty)
                  _detailRow(
                    context,
                    Icons.subject_outlined,
                    '议程',
                    meeting.agenda,
                  ),
                if (meeting.notes.isNotEmpty)
                  _detailRow(
                    context,
                    Icons.sticky_note_2_outlined,
                    '备注',
                    meeting.notes,
                  ),
                if (meeting.meetingUrl.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse(meeting.meetingUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('打开会议链接'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 2),
                Text(value),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMeetingDialog(BuildContext context) {
    final titleController = TextEditingController();
    final urlController = TextEditingController();
    final agendaController = TextEditingController();
    DateTime? startsAt;
    DateTime? endsAt;
    int? selectedChecklistId;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return LiquidGlassAlertDialog(
            title: const Text('快捷创建会议'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: '会议标题'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: urlController,
                    decoration: const InputDecoration(labelText: '会议链接'),
                  ),
                  const SizedBox(height: 8),
                  _buildDateTimeRow(
                    dialogContext,
                    icon: Icons.play_circle_outline,
                    title: '会议开始时间',
                    value: startsAt,
                    pickTooltip: '选择开始时间',
                    clearTooltip: '清除开始时间',
                    onPick: () async {
                      final selected =
                          await _pickDateTime(dialogContext, startsAt);
                      if (selected == null) return;
                      setDialogState(() => startsAt = selected);
                    },
                    onClear: () => setDialogState(() => startsAt = null),
                  ),
                  _buildDateTimeRow(
                    dialogContext,
                    icon: Icons.stop_circle_outlined,
                    title: '会议结束时间',
                    value: endsAt,
                    pickTooltip: '选择结束时间',
                    clearTooltip: '清除结束时间',
                    onPick: () async {
                      final selected =
                          await _pickDateTime(dialogContext, endsAt);
                      if (selected == null) return;
                      setDialogState(() => endsAt = selected);
                    },
                    onClear: () => setDialogState(() => endsAt = null),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int?>(
                    initialValue: selectedChecklistId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '绑定到清单项',
                      helperText: '创建后清单项下会显示查看会议详情入口',
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('不绑定清单'),
                      ),
                      ...controller.checklistItems.map(
                        (item) => DropdownMenuItem<int?>(
                          value: item.id,
                          child: Text(
                            _checklistLabel(item),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setDialogState(() => selectedChecklistId = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: agendaController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: '议程'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () async {
                  await controller.createMeeting(
                    titleController.text.trim(),
                    url: urlController.text.trim(),
                    agenda: agendaController.text.trim(),
                    startsAt: startsAt,
                    endsAt: endsAt,
                    bindChecklistItemId: selectedChecklistId,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: const Text('创建'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GlassAction {
  const _GlassAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
}

class _SegmentedProgress extends StatelessWidget {
  const _SegmentedProgress({required this.project});

  final BiostatProject project;

  @override
  Widget build(BuildContext context) {
    final total = project.todoCount;
    if (total <= 0) {
      return _bar(context,
          [(1, Theme.of(context).colorScheme.surfaceContainerHighest)]);
    }
    final notStarted =
        total - project.doneTodoCount - project.inProgressTodoCount;
    return _bar(context, [
      if (project.doneTodoCount > 0) (project.doneTodoCount, Colors.green),
      if (project.inProgressTodoCount > 0)
        (project.inProgressTodoCount, Colors.orange),
      if (notStarted > 0)
        (notStarted, Theme.of(context).colorScheme.surfaceContainerHighest),
    ]);
  }

  Widget _bar(BuildContext context, List<(int, Color)> segments) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 10,
        child: Row(
          children: segments
              .map((segment) => Expanded(
                    flex: segment.$1,
                    child: Container(color: segment.$2),
                  ))
              .toList(),
        ),
      ),
    );
  }
}
