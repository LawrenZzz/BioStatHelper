import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../shared/models/project_model.dart';
import '../../../../shared/widgets/liquid_glass_panel.dart';
import '../controllers/projects_controller.dart';
import 'project_detail_view.dart';

class ProjectsView extends StatefulWidget {
  const ProjectsView({super.key});

  @override
  State<ProjectsView> createState() => _ProjectsViewState();
}

class _ProjectsViewState extends State<ProjectsView> {
  final ProjectsController controller = Get.find<ProjectsController>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('项目库'),
        actions: [
          IconButton(
            tooltip: '新建项目',
            icon: const Icon(Icons.add),
            onPressed: () => _showProjectDialog(context),
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value && controller.projects.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final wide = MediaQuery.sizeOf(context).width >= 900;
        final projects = controller.filteredProjects;
        final list = _buildProjectList(context, projects);
        if (!wide) {
          return RefreshIndicator(
            onRefresh: controller.loadProjects,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 104),
              children: [
                _buildStats(context),
                const SizedBox(height: 12),
                _buildUpcomingTodos(context),
                const SizedBox(height: 18),
                list,
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: controller.loadProjects,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 16, 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 320,
                  child: SingleChildScrollView(child: list),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: controller.selectedProject.value == null
                      ? _buildWideEmpty(context)
                      : const ProjectDetailView(embedded: true),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildSearch(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        onChanged: (value) => controller.searchQuery.value = value,
        decoration: InputDecoration(
          hintText: '搜索项目名称、方案编号、Sponsor、适应症…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: Obx(() => controller.searchQuery.value.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: '清除搜索',
                  icon: const Icon(Icons.close),
                  onPressed: () => controller.searchQuery.value = '',
                )),
          filled: true,
        ),
      ),
    );
  }

  Widget _buildProjectList(
      BuildContext context, List<BiostatProject> projects) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSearch(context),
        if (projects.isEmpty)
          _emptySection(context,
              controller.searchQuery.value.isEmpty ? '暂无项目' : '没有匹配的项目')
        else ...[
          Text('项目列表 · ${projects.length}',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          ...projects.map((project) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ProjectCard(
                  project: project,
                  selected: controller.selectedProject.value?.id == project.id,
                  onTap: () => MediaQuery.sizeOf(context).width >= 900
                      ? controller.selectProject(project)
                      : controller.openProject(project),
                  onQuickAdd: () => _quickAddToProject(context, project),
                ),
              )),
        ],
      ],
    );
  }

  Widget _buildWideEmpty(BuildContext context) => Center(
        child: Text('从左侧选择项目，右侧查看项目详情',
            style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _buildStats(BuildContext context) {
    final total = controller.projects.length;
    final completed = controller.completedProjects.length;
    final ongoing = controller.ongoingProjects.length;
    final ratio = total == 0 ? 0.0 : completed / total;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '项目完成概览',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                Text('${(ratio * 100).round()}%'),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 10,
                value: ratio,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _metric(context, '进行中', '$ongoing', Colors.blue),
                const SizedBox(width: 12),
                _metric(context, '已完成', '$completed', Colors.green),
                const SizedBox(width: 12),
                _metric(context, '全部', '$total', Colors.blueGrey),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(
      BuildContext context, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            Text(label),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingTodos(BuildContext context) {
    final todos = controller.upcomingTodos;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '最近待办',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            if (todos.isEmpty)
              Text(
                '暂无带日期的未完成待办',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.56),
                    ),
              )
            else
              ...todos.map((todo) {
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_available_outlined),
                  title: Text(todo.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(controller.projectNameForTodo(todo)),
                  trailing: Text(_formatDate(todo.dueAt)),
                  onTap: () {
                    final project = controller.projects.firstWhereOrNull(
                      (item) => item.id == todo.projectId,
                    );
                    if (project != null) {
                      controller.openProjectAtTodo(project, todo);
                    }
                  },
                );
              }),
          ],
        ),
      ),
    );
  }

  Future<void> _quickAddToProject(
      BuildContext context, BiostatProject project) async {
    final titleController = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('快捷添加 · ${project.name}'),
        content: TextField(
          controller: titleController,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: '输入任务标题'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, titleController.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty || !context.mounted) return;
    await controller.quickAddTodo(project, title);
  }

  Widget _emptySection(BuildContext context, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: Text(text),
    );
  }

  Future<void> _showProjectDialog(BuildContext context) async {
    final nameController = TextEditingController();
    final protocolController = TextEditingController();
    final phaseController = TextEditingController();
    final sponsorController = TextEditingController();
    final indicationController = TextEditingController();
    final descriptionController = TextEditingController();
    final intakeController = TextEditingController();
    Map<String, dynamic>? parsedDraft;
    var isParsing = false;
    var isCreating = false;
    var selectedProjectType = 'other';
    var isCdisc = false;
    String? parseMessage;
    final createdProject = await showDialog<BiostatProject>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final parsedTodos = (parsedDraft?['todos'] as List?)
                  ?.whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList() ??
              const <Map<String, dynamic>>[];
          final completedTitles =
              (parsedDraft?['completed_todo_titles'] as List?)
                      ?.map((item) => item.toString())
                      .where((item) => item.isNotEmpty)
                      .toList() ??
                  const <String>[];
          final inProgressTitles =
              (parsedDraft?['in_progress_todo_titles'] as List?)
                      ?.map((item) => item.toString())
                      .where((item) => item.isNotEmpty)
                      .toList() ??
                  const <String>[];

          Future<void> parseIntake() async {
            final text = intakeController.text.trim();
            if (text.isEmpty) {
              setDialogState(() => parseMessage = '请先粘贴项目介绍或当前进展。');
              return;
            }
            setDialogState(() {
              isParsing = true;
              parseMessage = null;
            });
            try {
              final result = await controller.draftProjectIntake(text);
              if (!dialogContext.mounted) return;
              parsedDraft = result;
              nameController.text = result['name']?.toString() ?? '';
              protocolController.text = result['protocol_no']?.toString() ?? '';
              phaseController.text = result['phase']?.toString() ?? '';
              sponsorController.text = result['sponsor']?.toString() ?? '';
              indicationController.text =
                  result['indication']?.toString() ?? '';
              descriptionController.text =
                  result['description']?.toString() ?? '';
              final current = result['current_phase']?.toString();
              final completed =
                  (result['completed_todo_titles'] as List?)?.length ?? 0;
              final ongoing =
                  (result['in_progress_todo_titles'] as List?)?.length ?? 0;
              final todos = (result['todos'] as List?)?.length ?? 0;
              final fallbackUsed = result['fallback_used'] == true;
              final modelUsed = result['model_used']?.toString();
              final parsedProjectType =
                  result['project_type']?.toString() ?? '';
              setDialogState(() {
                isParsing = false;
                selectedProjectType = isKnownProjectType(parsedProjectType)
                    ? parsedProjectType
                    : 'other';
                isCdisc = result['is_cdisc'] == true;
                parseMessage = [
                  fallbackUsed
                      ? '解析引擎：本地规则（MiMo 未成功）'
                      : '解析引擎：${modelUsed?.isNotEmpty == true ? modelUsed : 'MiMo'}',
                  if (current != null && current.isNotEmpty) '当前阶段：$current',
                  '类型：${projectTypeLabel(selectedProjectType)}',
                  'CDISC：${isCdisc ? '是' : '否'}',
                  '已完成 $completed 项',
                  '进行中 $ongoing 项',
                  '新增待办 $todos 项',
                ].join('  ·  ');
              });
            } catch (error) {
              if (!dialogContext.mounted) return;
              setDialogState(() {
                isParsing = false;
                parseMessage = 'AI 识别失败：$error';
              });
            }
          }

          Future<void> submit() async {
            final name = nameController.text.trim();
            if (name.isEmpty) {
              setDialogState(() => parseMessage = '项目名称不能为空。');
              return;
            }
            setDialogState(() {
              isCreating = true;
              parseMessage = null;
            });
            try {
              final sourceText = intakeController.text.trim();
              late final BiostatProject created;
              if (parsedDraft != null && sourceText.isNotEmpty) {
                final draft = Map<String, dynamic>.from(parsedDraft!);
                draft['name'] = name;
                draft['protocol_no'] = protocolController.text.trim().isEmpty
                    ? null
                    : protocolController.text.trim();
                draft['phase'] = phaseController.text.trim().isEmpty
                    ? null
                    : phaseController.text.trim();
                draft['project_type'] = selectedProjectType;
                draft['is_cdisc'] = isCdisc;
                draft['sponsor'] = sponsorController.text.trim().isEmpty
                    ? null
                    : sponsorController.text.trim();
                draft['indication'] = indicationController.text.trim().isEmpty
                    ? null
                    : indicationController.text.trim();
                draft['description'] = descriptionController.text.trim().isEmpty
                    ? null
                    : descriptionController.text.trim();
                created = await controller.createProjectFromIntake(
                  text: sourceText,
                  draft: draft,
                );
              } else {
                created = await controller.createProject(
                  name,
                  protocolNo: protocolController.text.trim(),
                  phase: phaseController.text.trim(),
                  sponsor: sponsorController.text.trim(),
                  projectType: selectedProjectType,
                  isCdisc: isCdisc,
                  indication: indicationController.text.trim(),
                  description: descriptionController.text.trim(),
                );
              }
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext, created);
              }
            } catch (error) {
              if (!dialogContext.mounted) return;
              setDialogState(() {
                isCreating = false;
                parseMessage = '项目创建失败：$error';
              });
            }
          }

          return LiquidGlassAlertDialog(
            title: const Text('新建临床项目'),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 620,
                maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.68,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: intakeController,
                      minLines: 4,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: '项目介绍 / 当前进展',
                        hintText: '粘贴项目背景、方案信息、已完成工作和下一步安排，AI 会自动整理。',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: isParsing ? null : parseIntake,
                        icon: isParsing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.auto_awesome),
                        label: Text(isParsing ? '识别中...' : 'AI 识别项目与进度'),
                      ),
                    ),
                    if (parseMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        parseMessage!,
                        style: Theme.of(dialogContext)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color:
                                  Theme.of(dialogContext).colorScheme.primary,
                            ),
                      ),
                    ],
                    if (parsedDraft != null) ...[
                      const SizedBox(height: 8),
                      if (completedTitles.isNotEmpty)
                        _buildIntakeTitleList(
                          dialogContext,
                          '识别为已完成',
                          completedTitles,
                          Icons.check_circle_outline,
                          Colors.green,
                        ),
                      if (inProgressTitles.isNotEmpty)
                        _buildIntakeTitleList(
                          dialogContext,
                          '识别为进行中',
                          inProgressTitles,
                          Icons.timelapse,
                          Colors.orange,
                        ),
                      if (parsedTodos.isNotEmpty) ...[
                        Text(
                          '识别出的新待办',
                          style: Theme.of(dialogContext)
                              .textTheme
                              .labelLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        ...parsedTodos.take(8).map(
                              (todo) => ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.task_alt_outlined),
                                title: Text(
                                  todo['title']?.toString() ?? '项目待办',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  todo['phase']?.toString() ?? '流程待办',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                        if (parsedTodos.length > 8)
                          Text(
                            '还有 ${parsedTodos.length - 8} 项将在创建后加入项目。',
                            style: Theme.of(dialogContext).textTheme.bodySmall,
                          ),
                      ],
                    ],
                    const Divider(height: 24),
                    TextField(
                      controller: nameController,
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
                      key: ValueKey(selectedProjectType),
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
                      onChanged: isCreating
                          ? null
                          : (value) {
                              if (value == null) return;
                              setDialogState(() => selectedProjectType = value);
                            },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('CDISC 项目'),
                      subtitle: Text(
                        isCdisc
                            ? '流程包含 SDTM、ADaM、define.xml 和 reviewer guides'
                            : '使用非 CDISC 分析数据集与可追溯性流程',
                      ),
                      value: isCdisc,
                      onChanged: isCreating
                          ? null
                          : (value) => setDialogState(() => isCdisc = value),
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
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(labelText: '项目摘要'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    isCreating ? null : () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: isParsing || isCreating ? null : submit,
                child: isCreating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('创建项目'),
              ),
            ],
          );
        },
      ),
    );
    if (createdProject != null && mounted) {
      await controller.openProject(createdProject);
    }
  }

  Widget _buildIntakeTitleList(
    BuildContext context,
    String title,
    List<String> items,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          ...items.take(4).map(
                (item) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  minLeadingWidth: 24,
                  leading: Icon(icon, size: 18, color: color),
                  title:
                      Text(item, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ),
          if (items.length > 4)
            Text(
              '还有 ${items.length - 4} 项将在创建后同步。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return '${date.month}/${date.day}';
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.onTap,
    this.onQuickAdd,
    this.selected = false,
  });

  final BiostatProject project;
  final VoidCallback onTap;
  final VoidCallback? onQuickAdd;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: selected
          ? Theme.of(context)
              .colorScheme
              .primaryContainer
              .withValues(alpha: 0.45)
          : null,
      child: InkWell(
        onTap: onTap,
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
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (onQuickAdd != null)
                    IconButton(
                      tooltip: '快捷添加任务',
                      icon: const Icon(Icons.add_circle_outline, size: 22),
                      onPressed: onQuickAdd,
                    ),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
              const SizedBox(height: 6),
              if (project.sponsor.isNotEmpty)
                Text(project.sponsor,
                    style: Theme.of(context).textTheme.bodyMedium),
              if (project.protocolNo.isNotEmpty)
                Text('方案：${project.protocolNo}',
                    style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (project.phase.isNotEmpty) Text(project.phase),
                  Text(projectTypeLabel(project.projectType)),
                  Text(project.cdiscLabel),
                ],
              ),
              if (project.currentWorkflowPhase.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('当前阶段：${project.currentWorkflowPhase}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        )),
              ],
              if (project.snapshotCurrentState.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '进度记录：${project.snapshotCurrentState}',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 12),
              _SegmentedProgress(project: project),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _statusCount(
                      context, '已完成', project.doneTodoCount, Colors.green),
                  _statusCount(context, '进行中', project.inProgressTodoCount,
                      Colors.orange),
                  _statusCount(context, '未开始', project.notStartedTodoCount,
                      Theme.of(context).colorScheme.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusCount(
      BuildContext context, String label, int count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 5),
        Text('$label $count', style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _SegmentedProgress extends StatelessWidget {
  const _SegmentedProgress({required this.project});

  final BiostatProject project;

  @override
  Widget build(BuildContext context) {
    final total = project.todoCount;
    if (total <= 0) {
      return _bar(context, [
        (1, Theme.of(context).colorScheme.surfaceContainerHighest),
      ]);
    }
    final notStarted = project.notStartedTodoCount;
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
