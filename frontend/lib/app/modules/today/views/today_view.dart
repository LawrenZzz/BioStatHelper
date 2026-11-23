import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../../../shared/models/project_model.dart';
import '../../../../shared/widgets/section_header.dart';
import '../controllers/today_controller.dart';
import '../today_workspace.dart';

class TodayView extends GetView<TodayController> {
  const TodayView({super.key, this.embeddedInShell = false});

  final bool embeddedInShell;
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      backgroundColor: Colors.transparent,
      // Keep the capture action above the shell's mobile bottom navigation.
      floatingActionButton: Obx(
        () {
          if (!wide && controller.mobileDrawerOpen.value) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: EdgeInsets.only(
              bottom: embeddedInShell && !wide ? 140 : 0,
            ),
            child: FloatingActionButton.extended(
              onPressed: () => _showQuickCapture(context),
              icon: const Icon(Icons.add),
              label: const Text('快速捕获'),
            ),
          );
        },
      ),
      body: Obx(
        () {
          final mode = controller.bodyMode.value;
          final workspaceContent = switch (mode) {
            1 => _CalendarView(controller: controller),
            2 => _KanbanView(
                controller: controller,
                tasks: [
                  ...controller.focusTasks,
                  ...controller.nextActions,
                ],
              ),
            _ => _WideContentArea(
                controller: controller,
                reserveMobileMenuSpace: !wide,
              ),
          };
          if (wide) {
            return SafeArea(
              bottom: false,
              child: _buildWideLayout(context, workspaceContent),
            );
          }
          // Keep the workspace drawer available on narrow screens.
          return SafeArea(
            bottom: false,
            child: _buildNarrowDrawerLayout(
              context,
              workspaceContent,
            ),
          );
        },
      ),
    );
  }

  Widget _buildWideLayout(BuildContext context, Widget content) {
    return Row(
      children: [
        SizedBox(width: 240, child: _SidebarNav(controller: controller)),
        const VerticalDivider(width: 1),
        Expanded(child: content),
      ],
    );
  }

  // Narrow (<900). Right-side Drawer for workspace switching.
  Widget _buildNarrowDrawerLayout(
    BuildContext context,
    Widget content,
  ) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      // The outer TodayView scaffold owns the single capture action.
      /* floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showQuickCapture(context),
        icon: const Icon(Icons.add),
        label: const Text('快速捕获'),
      ), */
      drawerEdgeDragWidth: 48,
      onDrawerChanged: (isOpened) {
        controller.mobileDrawerOpen.value = isOpened;
      },
      drawer: _DrawerNav(controller: controller),
      body: Stack(
        children: [
          Positioned.fill(child: content),
          Positioned(
            top: -4,
            left: -4,
            child: Builder(
              builder: (buttonContext) => SizedBox(
                width: 52,
                height: 52,
                child: IconButton(
                  tooltip: '切换工作区',
                  icon: const Icon(Icons.menu),
                  iconSize: 28,
                  padding: EdgeInsets.zero,
                  onPressed: () => Scaffold.of(buttonContext).openDrawer(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerNav extends StatelessWidget {
  const _DrawerNav({required this.controller});

  final TodayController controller;
  static const _items = <TodayWorkspace>[
    TodayWorkspace.focus,
    TodayWorkspace.list,
    TodayWorkspace.calendar,
    TodayWorkspace.kanban,
    TodayWorkspace.inbox,
    TodayWorkspace.next,
    TodayWorkspace.waiting,
    TodayWorkspace.someday,
    TodayWorkspace.context,
    TodayWorkspace.review,
  ];

  String? _badgeCount(TodayWorkspace ws, TodayController c) {
    switch (ws) {
      case TodayWorkspace.inbox:
        return c.inbox.isNotEmpty ? '${c.inbox.length}' : null;
      case TodayWorkspace.focus:
        final total = c.focusTasks.length;
        if (total == 0) return null;
        final done = c.focusTasks.where((t) => t.isDone).length;
        if (done == total) return null;
        return '$done/$total';
      case TodayWorkspace.next:
        return c.nextActions.isNotEmpty ? '${c.nextActions.length}' : null;
      case TodayWorkspace.waiting:
        return c.waiting.isNotEmpty ? '${c.waiting.length}' : null;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Obx(() {
      final active = controller.currentWorkspace.value;
      return Container(
        color: scheme.surface,
        width: 260,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.today, color: scheme.primary, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    '今日工作台',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                '工作区',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            // Nav items
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  children: [
                    for (final ws in _items)
                      _DrawerNavItem(
                        workspace: ws,
                        selected: active == ws,
                        onTap: () {
                          controller.currentWorkspace.value = ws;
                          if (Navigator.of(context).canPop()) {
                            Navigator.of(context).pop();
                          }
                        },
                        badge: _badgeCount(ws, controller),
                      ),
                  ],
                ),
              ),
            ),
            // Footer
            const Divider(height: 1, thickness: 0.5),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Obx(() {
                if (!controller.reviewDue.value) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.event_repeat,
                        size: 16,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '本周回顾待处理',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: scheme.primary),
                        ),
                      ),
                      TextButton(
                        onPressed: controller.runWeeklyReview,
                        child: const Text('开始'),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ],
        ),
      );
    });
  }
}

class _DrawerNavItem extends StatelessWidget {
  const _DrawerNavItem({
    required this.workspace,
    required this.selected,
    required this.onTap,
    this.badge,
  });
  final TodayWorkspace workspace;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(
              workspace.icon,
              size: 20,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                workspace.label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? scheme.primary : scheme.onSurface,
                  fontSize: 14,
                ),
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SidebarNav extends StatelessWidget {
  const _SidebarNav({required this.controller});
  final TodayController controller;
  static const _items = <TodayWorkspace>[
    TodayWorkspace.focus,
    TodayWorkspace.list,
    TodayWorkspace.calendar,
    TodayWorkspace.kanban,
    TodayWorkspace.inbox,
    TodayWorkspace.next,
    TodayWorkspace.waiting,
    TodayWorkspace.someday,
    TodayWorkspace.context,
    TodayWorkspace.review,
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Obx(() {
      final active = controller.currentWorkspace.value;
      return SingleChildScrollView(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Workspace header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                '工作区',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            // Nav items
            for (final ws in _items)
              _SidebarNavItem(
                workspace: ws,
                selected: active == ws,
                onTap: () => controller.currentWorkspace.value = ws,
                badge: _badgeCount(ws, controller),
              ),
            const Divider(height: 1, thickness: 0.5),
            // Footer info
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Obx(() {
                    if (!controller.reviewDue.value) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.event_repeat,
                            size: 16,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '本周回顾待处理',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: scheme.primary),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  Text(
                    '今日工作台',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  String? _badgeCount(TodayWorkspace ws, TodayController c) {
    switch (ws) {
      case TodayWorkspace.inbox:
        return c.inbox.isNotEmpty ? '${c.inbox.length}' : null;
      case TodayWorkspace.focus:
        final total = c.focusTasks.length;
        if (total == 0) return null;
        final done = c.focusTasks.where((t) => t.isDone).length;
        if (done == total) return null;
        return '$done/$total';
      case TodayWorkspace.next:
        return c.nextActions.isNotEmpty ? '${c.nextActions.length}' : null;
      case TodayWorkspace.waiting:
        return c.waiting.isNotEmpty ? '${c.waiting.length}' : null;
      default:
        return null;
    }
  }
}

class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
    required this.workspace,
    required this.selected,
    required this.onTap,
    this.badge,
  });
  final TodayWorkspace workspace;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.65)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  workspace.icon,
                  size: 20,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    workspace.label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: selected ? scheme.primary : scheme.onSurface,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                        ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: selected
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: selected
                                ? scheme.onPrimary
                                : scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ================================================================
//  Wide content area — responds to currentWorkspace
// ================================================================
class _WideContentArea extends StatelessWidget {
  const _WideContentArea({
    required this.controller,
    this.reserveMobileMenuSpace = false,
  });
  final TodayController controller;
  final bool reserveMobileMenuSpace;
  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final ws = controller.currentWorkspace.value;
      return ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          reserveMobileMenuSpace ? 64 : 16,
          20,
          140,
        ),
        children: [
          _buildHeader(
            controller,
            context,
          ),
          const SizedBox(height: 12),
          _buildReviewPrompt(controller, context),
          const SizedBox(height: 8),
          switch (ws) {
            TodayWorkspace.focus => _WideFocusSection(controller: controller),
            TodayWorkspace.list => _WideAllTasksSection(controller: controller),
            TodayWorkspace.calendar => const _CalendarViewInline(),
            TodayWorkspace.kanban => const _KanbanViewInline(),
            TodayWorkspace.inbox => _WideInboxSection(controller: controller),
            TodayWorkspace.next => _WideSection(
                title: '下一步',
                trailing: _countChip(context, controller.nextActions.length),
                body: _buildNextActions(controller, context),
              ),
            TodayWorkspace.waiting => _WideSection(
                title: '等待',
                trailing: _countChip(context, controller.waiting.length),
                body: _buildWaiting(controller, context),
              ),
            TodayWorkspace.someday =>
              _WideSomedaySection(controller: controller),
            TodayWorkspace.context =>
              _WideContextSection(controller: controller),
            TodayWorkspace.review => _WideReviewSection(controller: controller),
          },
          const SizedBox(height: 24),
        ],
      );
    });
  }
}

// ================================================================
//  Section widgets for wide layout
// ================================================================
class _WideSection extends StatelessWidget {
  const _WideSection({
    required this.title,
    required this.body,
    this.trailing,
  });
  final String title;
  final Widget? trailing;
  final Widget body;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: title, trailing: trailing),
        const SizedBox(height: 8),
        body,
        const SizedBox(height: 24),
      ],
    );
  }
}

class _WideFocusSection extends StatelessWidget {
  const _WideFocusSection({required this.controller});
  final TodayController controller;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: '今日 · 专注',
          trailing: _focusProgress(controller, context),
        ),
        const SizedBox(height: 8),
        _buildFocus(controller, context),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _WideAllTasksSection extends StatelessWidget {
  const _WideAllTasksSection({required this.controller});
  final TodayController controller;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        _SearchBar(controller: controller),
        _SavedFiltersRow(controller: controller),
        _CaptureBar(controller: controller),
        if (controller.searchQuery.value.trim().isNotEmpty ||
            controller.searchResults.isNotEmpty)
          _buildSearchResults(controller, context),
        const SizedBox(height: 16),
        SectionHeader(
          title: '收件箱',
          trailing: _countChip(context, controller.inbox.length),
        ),
        _buildInbox(controller, context),
        const SizedBox(height: 20),
        SectionHeader(
          title: '今日 · 专注',
          trailing: _focusProgress(controller, context),
        ),
        _buildFocus(controller, context),
        const SizedBox(height: 20),
        SectionHeader(
          title: '下一步',
          trailing: _countChip(context, controller.nextActions.length),
        ),
        _buildNextActions(controller, context),
        const SizedBox(height: 20),
        SectionHeader(
          title: '等待',
          trailing: _countChip(context, controller.waiting.length),
        ),
        _buildWaiting(controller, context),
        const SizedBox(height: 24),
        _ContextsStrip(
          controller: controller,
          people: controller.contextPeople,
          places: controller.contextPlaces,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _WideInboxSection extends StatelessWidget {
  const _WideInboxSection({required this.controller});
  final TodayController controller;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CaptureBar(controller: controller),
        const SizedBox(height: 16),
        SectionHeader(
          title: '收件箱',
          trailing: _countChip(context, controller.inbox.length),
        ),
        const SizedBox(height: 8),
        _buildInbox(controller, context),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _WideSomedaySection extends StatelessWidget {
  const _WideSomedaySection({required this.controller});
  final TodayController controller;
  @override
  Widget build(BuildContext context) {
    final someday =
        controller.nextActions.where((t) => t.status == 'someday').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: '稍后 / 也许',
          trailing: _countChip(context, someday.length),
        ),
        const SizedBox(height: 8),
        if (someday.isEmpty)
          _emptyCard(
            context,
            '没有稍后事项',
            '把不急但值得记住的事丢到"稍后"。',
          )
        else
          Column(
            children: [
              for (final todo in someday)
                _TaskTile(controller: controller, todo: todo),
            ],
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _WideContextSection extends StatelessWidget {
  const _WideContextSection({required this.controller});
  final TodayController controller;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: '上下文',
          trailing: Obx(
            () => controller.activeContext.value.isNotEmpty
                ? Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TextButton(
                      onPressed: controller.clearSearch,
                      child: const Text('清除'),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
        const SizedBox(height: 8),
        if (controller.contextPeople.isEmpty &&
            controller.contextPlaces.isEmpty)
          _emptyCard(
            context,
            '暂无上下文',
            '给任务添加 @人 或 @地点 后会在这里显示。',
          )
        else ...[
          if (controller.contextPeople.isNotEmpty)
            _chipGroup(
              context,
              '@人',
              controller.contextPeople,
              Icons.person_outline,
              Theme.of(context).colorScheme.primary,
            ),
          if (controller.contextPlaces.isNotEmpty)
            _chipGroup(
              context,
              '@地点',
              controller.contextPlaces,
              Icons.place_outlined,
              Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          const SizedBox(height: 16),
          Text(
            '点击上下文即可按该情境筛选任务',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _chipGroup(
    BuildContext context,
    String title,
    List<String> items,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in items)
                ActionChip(
                  label: Text(item),
                  avatar: Icon(icon, size: 16, color: color),
                  onPressed: () => controller
                      .searchByContext(item.startsWith('@') ? item : '@$item'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WideReviewSection extends StatelessWidget {
  const _WideReviewSection({required this.controller});
  final TodayController controller;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: '每周回顾',
          trailing: Obx(
            () => controller.reviewDue.value
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      '待处理',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: Colors.red),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
        const SizedBox(height: 8),
        Obx(() {
          if (!controller.reviewDue.value) {
            return _plainPanel(
              context: context,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: Theme.of(context).colorScheme.primary,
                    size: 40,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '本周暂无待回顾事项',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '当有到期任务或项目需要审视时，会提示开始回顾。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            );
          }
          return Column(
            children: [
              _plainPanel(
                context: context,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.event_repeat,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '该做每周回顾了，看看本周完成、清理过期事项',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    FilledButton(
                      onPressed: controller.runWeeklyReview,
                      child: const Text('开始回顾'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Obx(() {
                if (controller.reviewLoading.value) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                final info = controller.review.value;
                if (info == null) return const SizedBox.shrink();
                return _ReviewResultPanel(info: info);
              }),
            ],
          );
        }),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ReviewResultPanel extends StatelessWidget {
  const _ReviewResultPanel({required this.info});
  final dynamic info;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _plainPanel(
      context: context,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '回顾结果',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          _reviewStatRow(
            context,
            '已完成任务',
            info.counts.completedTodos,
            Icons.check_circle,
            scheme.primary,
          ),
          _reviewStatRow(
            context,
            '已完成清单',
            info.counts.completedChecklistItems,
            Icons.done_all,
            scheme.primary,
          ),
          _reviewStatRow(
            context,
            '收件箱待处理',
            info.counts.inbox,
            Icons.inbox,
            scheme.secondaryContainer,
          ),
          _reviewStatRow(
            context,
            '下一步',
            info.counts.next,
            Icons.arrow_forward,
            scheme.secondary,
          ),
          _reviewStatRow(
            context,
            '等待中',
            info.counts.waiting,
            Icons.hourglass_empty,
            scheme.tertiary,
          ),
          if (info.staleOpen.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '需审查的过期项',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            for (final stale in info.staleOpen)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• ${stale.title} (${stale.reason})',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.error),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _reviewStatRow(
    BuildContext context,
    String label,
    int count,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarViewInline extends StatelessWidget {
  const _CalendarViewInline();
  @override
  Widget build(BuildContext context) {
    // Reuse the controller via Get.find since this widget is outside the
    // original TodayView scope that held the controller reference.
    final controller = Get.find<TodayController>();
    return _CalendarView(controller: controller);
  }
}

class _KanbanViewInline extends StatelessWidget {
  const _KanbanViewInline();
  @override
  Widget build(BuildContext context) {
    final controller = Get.find<TodayController>();
    return _KanbanView(
      controller: controller,
      tasks: [
        ...controller.focusTasks,
        ...controller.nextActions,
      ],
    );
  }
}

// ================================================================
//  Helper widgets (shared by today view and wide-layout sections)
// ================================================================
/// Minimal plain-surface helper for in-page cards/tiles.
Widget _plainPanel({
  required BuildContext context,
  required Widget child,
  EdgeInsetsGeometry? padding = const EdgeInsets.all(18),
  double borderRadius = 28,
}) =>
    Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        color: Theme.of(context).scaffoldBackgroundColor,
      ),
      child:
          Padding(padding: padding ?? const EdgeInsets.all(18), child: child),
    );

/// Plain modal bottom sheet (replaces showLiquidGlassBottomSheet).
Future<T?> _plainSheet<T>({
  required BuildContext context,
  required Widget child,
  bool isScrollControlled = false,
  double borderRadius = 28,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: true,
    showDragHandle: false,
    elevation: 0,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(borderRadius)),
    ),
    builder: (sheetContext) => SafeArea(
      top: false,
      child: child,
    ),
  );
}

/// Plain alert dialog (replaces LiquidGlassAlertDialog).
Widget _plainDialog({
  required BuildContext context,
  Widget? title,
  Widget? content,
  List<Widget>? actions,
}) {
  return AlertDialog(
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    title: title,
    content: content,
    actions: actions,
  );
}

// ================================================================
//  Top-level helper functions for wide layout
// ================================================================
Widget _buildHeader(
  TodayController controller,
  BuildContext context,
) {
  final scheme = Theme.of(context).colorScheme;
  return _plainPanel(
    context: context,
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
    child: Row(
      children: [
        Icon(Icons.today, color: scheme.primary, size: 30),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '今日工作台',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              controller.todayLabel,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const Spacer(),
      ],
    ),
  );
}

Widget _buildReviewPrompt(TodayController controller, BuildContext context) {
  return Obx(() {
    if (!controller.reviewDue.value) return const SizedBox.shrink();
    return _plainPanel(
      context: context,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Row(
        children: [
          Icon(
            Icons.event_repeat,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '该做每周回顾了，看看本周完成、清理过期事项',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
              onPressed: controller.runWeeklyReview, child: const Text('开始')),
        ],
      ),
    );
  });
}

Widget _countChip(BuildContext context, int count) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      '$count',
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
  );
}

Widget _focusProgress(TodayController controller, BuildContext context) {
  if (controller.focusTasks.isEmpty) return _countChip(context, 0);
  final total = controller.focusTasks.length;
  final done = controller.focusTasks.where((t) => t.isDone).length;
  final fraction = total == 0 ? 0.0 : done / total;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '$done/$total',
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 64,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: fraction,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            minHeight: 6,
          ),
        ),
      ),
    ],
  );
}

Widget _emptyCard(BuildContext context, String title, String subtitle) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: _plainPanel(
      context: context,
      child: Column(
        children: [
          Icon(
            Icons.check_circle_outline,
            color: Theme.of(context).colorScheme.outline,
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    ),
  );
}

Widget _buildInbox(TodayController controller, BuildContext context) {
  final items = controller.inbox;
  if (items.isEmpty) return _emptyCard(context, '收件箱是空的', '捕获任意想法，稍后再处理。');
  return Column(
    children: [
      for (final todo in items) _InboxTile(controller: controller, todo: todo),
    ],
  );
}

Widget _buildFocus(TodayController controller, BuildContext context) {
  final items = controller.focusTasks;
  if (items.isEmpty) {
    return _emptyCard(context, '今天清空了', '为任务点亮星标，或设定截止日期出现在这里。');
  }
  return Column(
    children: [
      for (final todo in items) _TaskTile(controller: controller, todo: todo),
    ],
  );
}

Widget _buildNextActions(TodayController controller, BuildContext context) {
  final items = controller.nextActions;
  if (items.isEmpty) return _emptyCard(context, '没有下一步', '从收件箱处理一条事项到这里。');
  return Column(
    children: [
      for (final todo in items) _TaskTile(controller: controller, todo: todo),
    ],
  );
}

Widget _buildWaiting(TodayController controller, BuildContext context) {
  final items = controller.waiting;
  if (items.isEmpty) return _emptyCard(context, '没有等待中的事项', '等待他人回应的任务会出现在这里。');
  return Column(
    children: [
      for (final todo in items) _TaskTile(controller: controller, todo: todo),
    ],
  );
}

Widget _buildSearchResults(TodayController controller, BuildContext context) {
  final results = controller.searchResults;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionHeader(
        title: '搜索结果',
        trailing: Obx(() => _countChip(context, results.length)),
      ),
      if (controller.searching.value)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (results.isEmpty)
        _emptyCard(
          context,
          '没有匹配的任务',
          '换个关键词或放宽筛选条件。',
        )
      else
        for (final todo in results)
          _TaskTile(controller: controller, todo: todo),
    ],
  );
}

// ================================================================
//  Capture
// ================================================================
class _CaptureShell extends StatefulWidget {
  final bool fromSheet;
  const _CaptureShell({this.fromSheet = false});
  @override
  State<_CaptureShell> createState() => _CaptureShellState();
}

class _CaptureShellState extends State<_CaptureShell> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final description = _descriptionController.text.trim();
    if (widget.fromSheet) {
      Navigator.pop(
          context, description.isEmpty ? title : '$title|$description');
      return;
    }
    Get.find<TodayController>().createInbox(title, description: description);
    _titleController.clear();
    _descriptionController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Text(
            '快速捕获',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: _titleController,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText: '把脑子里的事倒进来……',
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: TextField(
            controller: _descriptionController,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(hintText: '备注（可选）'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _submit,
                child: Obx(
                  () => Get.find<TodayController>().capturingToInbox.value
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('捕获到收件箱'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CaptureSheet extends StatelessWidget {
  const _CaptureSheet();
  @override
  Widget build(BuildContext context) {
    return const _CaptureShell(fromSheet: true);
  }
}

// ================================================================
//  Task tile (shared for focus / next / waiting)
// ================================================================
class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.controller, required this.todo});
  final TodayController controller;
  final ProjectTodo todo;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: _plainPanel(
        context: context,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            _Checkbox(
              checked: todo.isDone,
              onChanged: () => controller.updateTaskStatus(
                  todo, todo.isDone ? 'next' : 'done'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _showTaskDetail(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      todo.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        decoration:
                            todo.isDone ? TextDecoration.lineThrough : null,
                        color: todo.isDone ? scheme.onSurfaceVariant : null,
                      ),
                    ),
                    if (todo.projectName.isNotEmpty &&
                        !todo.isInbox &&
                        todo.projectName != '收件箱')
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          todo.projectName,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    if (todo.recurrence.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.autorenew,
                              size: 12,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              todo.recurrence,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: scheme.primary),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (todo.dueAt != null) _dueChip(context, todo.dueAt!),
            IconButton(
              onPressed: () => controller.toggleFocus(todo),
              icon: Icon(
                todo.isFocusedToday ? Icons.star : Icons.star_border,
                color: todo.isFocusedToday ? Colors.amber : scheme.outline,
              ),
              tooltip: todo.isFocusedToday ? '移出今日专注' : '放入今日专注',
            ),
            _statusMenu(context),
          ],
        ),
      ),
    );
  }

  Widget _dueChip(BuildContext context, DateTime dueAt) {
    final overdue = dueAt.isBefore(DateTime.now());
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: overdue
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        DateFormat('M/d').format(dueAt),
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _statusMenu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      onSelected: (status) => controller.updateTaskStatus(todo, status),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'done', child: Text('✔ 完成')),
        const PopupMenuItem(value: 'next', child: Text('下一步')),
        const PopupMenuItem(value: 'in_progress', child: Text('进行中')),
        const PopupMenuItem(value: 'waiting', child: Text('等待')),
        const PopupMenuItem(value: 'someday', child: Text('稍后/也许')),
        const PopupMenuItem(value: 'archived', child: Text('归档')),
      ],
    );
  }

  void _showTaskDetail(BuildContext context) {
    _plainSheet<void>(
      context: context,
      isScrollControlled: true,
      child: _TaskDetailSheet(controller: controller, todo: todo),
    );
  }
}

class _Checkbox extends StatelessWidget {
  const _Checkbox({required this.checked, required this.onChanged});
  final bool checked;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onChanged,
        customBorder: const CircleBorder(),
        child: checked
            ? Icon(
                Icons.check_circle,
                color: scheme.primary,
                size: 26,
              )
            : Icon(
                Icons.radio_button_unchecked,
                color: scheme.outline,
                size: 26,
              ),
      ),
    );
  }
}

// ================================================================
//  Capture bar (inline on the page)
// ================================================================
void _showQuickCapture(BuildContext context) {
  final controller = Get.find<TodayController>();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _CaptureBar(controller: controller),
  );
}

class _CaptureBar extends StatelessWidget {
  const _CaptureBar({required this.controller});
  final TodayController controller;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: _plainPanel(
        context: context,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openCaptureSheet(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(
                  Icons.edit_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Text(
                  '快速捕获到收件箱……',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const Spacer(),
                const Icon(Icons.add, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openCaptureSheet(BuildContext context) async {
    final result = await _plainSheet<String>(
      context: context,
      isScrollControlled: true,
      child: const _CaptureSheet(),
    );
    if (result == null || result.trim().isEmpty) return;
    final parts = result.split('|');
    controller.createInbox(parts.first,
        description: parts.length > 1 ? parts.sublist(1).join('|') : null);
  }
}

// ================================================================
//  Inbox tile (with process actions)
// ================================================================
class _InboxTile extends StatelessWidget {
  const _InboxTile({required this.controller, required this.todo});
  final TodayController controller;
  final ProjectTodo todo;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: _plainPanel(
        context: context,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.inbox_outlined,
              color: scheme.primary,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                todo.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () => _showProcessSheet(context),
              child: const Text('处理'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showProcessSheet(BuildContext context) async {
    final action = await _plainSheet<String>(
      context: context,
      child: _ProcessSheet(
        controller: controller,
        todo: todo,
      ),
    );
    if (action != null) {
      controller.processInbox(todo, action: action);
    }
  }
}

// ================================================================
//  Inbox process
// ================================================================
class _ProcessSheet extends StatefulWidget {
  const _ProcessSheet({required this.controller, required this.todo});
  final TodayController controller;
  final ProjectTodo todo;
  @override
  State<_ProcessSheet> createState() => _ProcessSheetState();
}

class _ProcessSheetState extends State<_ProcessSheet> {
  String _action = 'next';
  int? _projectId;
  bool _focus = false;
  // Mindwtr 2 分钟法则动作清单。
  static const _actions = [
    ('next', '下一步', Icons.play_circle_outline),
    ('done', '完成', Icons.check_circle_outline),
    ('waiting', '等待', Icons.hourglass_empty),
    ('someday', '稍后/也许', Icons.outbox_outlined),
    ('reference', '参考', Icons.bookmark_outline),
  ];
  @override
  Widget build(BuildContext context) {
    final projects = widget.controller.realProjects;
    final actionNeedsProject = _action == 'next';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '处理：${widget.todo.title}',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '2 分钟法则：能做就做，做不了就设定好下一步。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (action, label, icon) in _actions)
                ChoiceChip(
                  selected: _action == action,
                  avatar: Icon(icon, size: 18),
                  label: Text(label),
                  onSelected: (_) => setState(() => _action = action),
                ),
            ],
          ),
          if (actionNeedsProject) ...[
            const SizedBox(height: 16),
            Text(
              '归入项目',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('不归入'),
                  selected: _projectId == null,
                  onSelected: (_) => setState(() => _projectId = null),
                ),
                for (final project in projects)
                  ChoiceChip(
                    label: Text(project.name),
                    selected: _projectId == project.id,
                    onSelected: (_) => setState(() => _projectId = project.id),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('放入今日专注'),
              value: _focus,
              onChanged: (value) => setState(() => _focus = value),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.pop(context, _action),
                child: const Text('确认'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ================================================================
//  Global search bar
// ================================================================
class _SearchBar extends StatefulWidget {
  const _SearchBar({required this.controller});
  final TodayController controller;
  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final _controller = TextEditingController();
  StreamSubscription<String>? _sub;
  @override
  void initState() {
    super.initState();
    // Keep the visible field in sync when the active query is changed outside
    // this field (a context-chip filter or clearing it), so the box always
    // reflects the real active query and never shows stale text.
    _sub = widget.controller.searchQuery.listen((q) {
      if (_controller.text != q) _controller.text = q;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: _plainPanel(
        context: context,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: '搜索全部任务……',
            prefixIcon: const Icon(Icons.search, size: 20),
            border: InputBorder.none,
            suffixIcon: Obx(
              () => widget.controller.searchQuery.value.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      tooltip: '清除搜索',
                      onPressed: () {
                        _controller.clear();
                        widget.controller.clearSearch();
                      },
                    ),
            ),
          ),
          onSubmitted: (_) =>
              widget.controller.searchTasks(q: _controller.text),
          onChanged: (value) => widget.controller.searchQuery.value = value,
        ),
      ),
    );
  }
}

// ================================================================
//  Saved filters row
// ================================================================
class _SavedFiltersRow extends StatelessWidget {
  const _SavedFiltersRow({required this.controller});
  final TodayController controller;
  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final filters = controller.savedFilters;
      if (filters.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final filter in filters)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InputChip(
                          label: Text(filter.name),
                          avatar:
                              const Icon(Icons.filter_alt_outlined, size: 16),
                          onPressed: () => controller.applySavedFilter(filter),
                          onDeleted: () => _confirmDelete(context, filter),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.bookmark_add_outlined, size: 20),
              tooltip: '保存当前搜索为筛选',
              onPressed: () => _saveCurrent(context),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _saveCurrent(BuildContext context) async {
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final field = TextEditingController();
          return _plainDialog(
            context: dialogContext,
            title: const Text('保存当前筛选'),
            content: TextField(
              controller: field,
              autofocus: true,
              decoration: const InputDecoration(hintText: '筛选名称'),
              textInputAction: TextInputAction.done,
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  Navigator.pop(dialogContext, value.trim());
                }
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () {
                  final value = field.text.trim();
                  if (value.isNotEmpty) {
                    Navigator.pop(dialogContext, value);
                  }
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    if (name is String && name.isNotEmpty) {
      controller.saveCurrentFilter(name);
    }
  }

  Future<void> _confirmDelete(BuildContext context, SavedFilter filter) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _plainDialog(
        context: dialogContext,
        title: const Text('删除筛选'),
        content: Text('确定删除「${filter.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      controller.deleteSavedFilter(filter);
    }
  }
}

// ================================================================
//  Contexts strip (@人 / @地点)
// ================================================================
class _ContextsStrip extends StatelessWidget {
  const _ContextsStrip({
    required this.controller,
    required this.people,
    required this.places,
  });
  final TodayController controller;
  final List<String> people;
  final List<String> places;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (people.isEmpty && places.isEmpty) {
      return const SizedBox.shrink();
    }
    return Obx(() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Row(
                children: [
                  Text(
                    '上下文',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (controller.activeContext.value.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    InputChip(
                      label: Text('筛选 ${controller.activeContext.value}'),
                      onDeleted: controller.clearSearch,
                    ),
                  ],
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _openWorkbench(context),
                    icon: const Icon(Icons.manage_search, size: 18),
                    label: const Text('工作台'),
                  ),
                ],
              ),
            ),
            if (people.isNotEmpty)
              _chipGroup(
                context,
                '@人',
                people,
                Icons.person_outline,
                scheme.primary,
              ),
            if (places.isNotEmpty)
              _chipGroup(
                context,
                '@地点',
                places,
                Icons.place_outlined,
                scheme.onSurfaceVariant,
              ),
          ],
        ));
  }

  Widget _chipGroup(BuildContext context, String title, List<String> items,
      IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          for (final item in items)
            ActionChip(
              label: Text(item),
              avatar: Icon(icon, size: 16, color: color),
              onPressed: () => controller.searchByContext(item),
            ),
        ],
      ),
    );
  }

  void _openWorkbench(BuildContext context) {
    _plainSheet<void>(
      context: context,
      isScrollControlled: true,
      child: _ContextWorkbench(controller: controller),
    );
  }
}

// ================================================================
//  Context workbench (上下文工作台) — 按 @人/@地点 查看与筛选
// ================================================================
class _ContextWorkbench extends StatefulWidget {
  const _ContextWorkbench({required this.controller});
  final TodayController controller;
  @override
  State<_ContextWorkbench> createState() => _ContextWorkbenchState();
}

class _ContextWorkbenchState extends State<_ContextWorkbench> {
  final _input = TextEditingController();
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _apply(String label) {
    final value = label.trim();
    if (value.isEmpty) return;
    Navigator.pop(context);
    widget.controller
        .searchByContext(value.startsWith('@') ? value : '@$value');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final counts = widget.controller.contextCounts();
    final people = widget.controller.contextPeople;
    final places = widget.controller.contextPlaces;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '上下文工作台',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '按情境专注：@人 来自项目成员，@地点 来自任务上下文。点一下即筛选可做的任务。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          _section(context, '@人', people, Icons.person_outline, scheme.primary,
              counts),
          const SizedBox(height: 16),
          _section(context, '@地点', places, Icons.place_outlined,
              scheme.onSurfaceVariant, counts),
          const SizedBox(height: 12),
          TextField(
            controller: _input,
            decoration: const InputDecoration(
              hintText: '按新上下文筛选，如 @办公室（或直接输入办公室）',
              prefixIcon: Icon(Icons.search, size: 20),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: _apply,
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<String> items,
      IconData icon, Color color, Map<String, int> counts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Text(
            '暂无',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in items)
                ActionChip(
                  avatar: Icon(icon, size: 16, color: color),
                  label: Text(item),
                  onPressed: () => _apply(item),
                  tooltip: counts[item] == null || counts[item] == 0
                      ? '暂无活动任务'
                      : '${counts[item]} 个活动任务',
                ),
            ],
          ),
      ],
    );
  }
}

// ================================================================
//  Calendar month view
// ================================================================
class _CalendarView extends StatefulWidget {
  const _CalendarView({required this.controller});
  final TodayController controller;
  @override
  State<_CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<_CalendarView> {
  late DateTime _selected;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selected = DateTime(now.year, now.month, now.day);
  }

  static DateTime _day(ProjectTodo todo) {
    final due = todo.occurrenceDueAt ?? todo.dueAt;
    if (due == null) return DateTime(9999);
    return DateTime(due.year, due.month, due.day);
  }

  @override
  Widget build(BuildContext context) {
    final month = widget.controller.visibleMonth.value;
    // Keep the selected-day panel in the displayed month: if the user shifted
    // to another month, reset the selection to its first day instead of showing
    // a stale date from the previous month under a grid that no longer has it.
    if (_selected.year != month.year || _selected.month != month.month) {
      _selected = DateTime(month.year, month.month, 1);
    }
    final tasks = widget.controller.calendarTasks;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final firstWeekday = DateTime(month.year, month.month, 1).weekday; // Mon=1
    // Group by date bucket.
    final Map<DateTime, List<ProjectTodo>> byDay = {};
    for (final todo in tasks) {
      final key = _day(todo);
      byDay.putIfAbsent(key, () => []).add(todo);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _plainPanel(
        context: context,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Month header.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => widget.controller.shiftMonth(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Obx(
                      () => Text(
                        DateFormat('yyyy年M月', 'zh_CN')
                            .format(widget.controller.visibleMonth.value),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => widget.controller.shiftMonth(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // Weekday row.
            Row(
              children: [
                for (final label in const ['一', '二', '三', '四', '五', '六', '日'])
                  Expanded(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // Day grid (up to 6 rows).
            for (var week = 0; week < 6; week++) ...[
              Row(
                children: [
                  for (var wd = 0; wd < 7; wd++) ...[
                    Expanded(
                      child: _buildDayCell(
                        context,
                        month,
                        week,
                        wd,
                        daysInMonth,
                        firstWeekday,
                        byDay,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
            ],
            const SizedBox(height: 8),
            // Selected day tasks.
            _buildSelectedDay(context, byDay),
          ],
        ),
      ),
    );
  }

  Widget _buildDayCell(
    BuildContext context,
    DateTime month,
    int week,
    int wd,
    int daysInMonth,
    int firstWeekday,
    Map<DateTime, List<ProjectTodo>> byDay,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final dayNumber = (week * 7) + wd - firstWeekday + 2;
    final inMonth = dayNumber >= 1 && dayNumber <= daysInMonth;
    final day = inMonth ? DateTime(month.year, month.month, dayNumber) : null;
    final count = (day == null ? 0 : byDay[day]?.length ?? 0);
    final isToday = day != null &&
        day.year == DateTime.now().year &&
        day.month == DateTime.now().month &&
        day.day == DateTime.now().day;
    final isSelected = day != null &&
        day.year == _selected.year &&
        day.month == _selected.month &&
        day.day == _selected.day;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap:
          inMonth && day != null ? () => setState(() => _selected = day) : null,
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primary
              : isToday
                  ? scheme.primaryContainer
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              inMonth ? '$dayNumber' : '',
              style: TextStyle(
                fontSize: 13,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                color: isSelected ? scheme.onPrimary : null,
              ),
            ),
            if (count > 0)
              Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: isSelected ? scheme.onPrimary : scheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedDay(
    BuildContext context,
    Map<DateTime, List<ProjectTodo>> byDay,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final tasks = byDay[_selected] ?? const <ProjectTodo>[];
    if (tasks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '这一天没有到期任务',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
          child: Text(
            '${DateFormat('M月d日').format(_selected)} · ${tasks.length} 项',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        for (final todo in tasks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(
                  todo.isDone
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: todo.isDone ? scheme.primary : scheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    todo.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      decoration:
                          todo.isDone ? TextDecoration.lineThrough : null,
                      color: todo.isDone ? scheme.onSurfaceVariant : null,
                    ),
                  ),
                ),
                if (todo.recurrence.isNotEmpty)
                  Icon(
                    Icons.autorenew,
                    size: 14,
                    color: scheme.primary,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ================================================================
//  Kanban board (grouped by GTD status)
// ================================================================
class _KanbanView extends StatelessWidget {
  const _KanbanView({required this.controller, required this.tasks});
  final TodayController controller;
  final List<ProjectTodo> tasks;
  static const _columns = [
    ('next', '下一步'),
    ('in_progress', '进行中'),
    ('waiting', '等待'),
    ('someday', '稍后'),
    ('done', '完成'),
  ];
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 280,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (status, label) in _columns)
              _buildColumn(context, status, label),
          ],
        ),
      ),
    );
  }

  Widget _buildColumn(BuildContext context, String status, String label) {
    final scheme = Theme.of(context).colorScheme;
    final columnTasks = tasks.where((t) => t.status == status).toList();
    return SizedBox(
      width: 168,
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: _plainPanel(
          context: context,
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    '${columnTasks.length}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (columnTasks.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            '空',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.outline),
                          ),
                        )
                      else
                        for (final todo in columnTasks)
                          _kanbanCard(context, todo),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kanbanCard(BuildContext context, ProjectTodo todo) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () =>
            controller.updateTaskStatus(todo, todo.isDone ? 'next' : 'done'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                todo.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              if (todo.projectName.isNotEmpty && todo.projectName != '收件箱') ...[
                const SizedBox(height: 2),
                Text(
                  todo.projectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
              if (todo.recurrence.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.autorenew,
                      size: 12,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      todo.recurrence,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================
//  Task detail sheet — 参考笔记 + 文件附件
// ================================================================
class _TaskDetailSheet extends StatefulWidget {
  const _TaskDetailSheet({required this.controller, required this.todo});
  final TodayController controller;
  final ProjectTodo todo;
  @override
  State<_TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends State<_TaskDetailSheet> {
  List<TaskNote> _notes = const [];
  List<TaskAttachment> _attachments = const [];
  bool _loading = true;
  bool _uploading = false;
  int? _downloadingId;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      widget.controller.loadTaskNotes(widget.todo.id),
      widget.controller.loadTaskAttachments(widget.todo.id),
    ]);
    if (!mounted) return;
    setState(() {
      _notes = results[0] as List<TaskNote>;
      _attachments = results[1] as List<TaskAttachment>;
      _loading = false;
    });
  }

  Future<void> _addNote() async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final titleField = TextEditingController();
          final contentField = TextEditingController();
          return _plainDialog(
            context: dialogContext,
            title: const Text('添加参考笔记'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleField,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: '标题（可选）'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: contentField,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(hintText: '笔记内容……'),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消')),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext,
                    '${titleField.text.trim()}|${contentField.text.trim()}'),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    if (result == null || !result.contains('|')) {
      return;
    }
    final separator = result.indexOf('|');
    await widget.controller.addTaskNote(
      widget.todo.id,
      title: result.substring(0, separator),
      content: result.substring(separator + 1),
    );
    _reload();
  }

  Future<void> _confirmDeleteNote(TaskNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _plainDialog(
        context: dialogContext,
        title: const Text('删除笔记'),
        content: Text('确定删除「${note.title.isEmpty ? '笔记' : note.title}」吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed == true && await widget.controller.deleteTaskNote(note.id)) {
      _reload();
    }
  }

  Future<void> _upload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      Get.snackbar('附件', '无法读取文件内容');
      return;
    }
    setState(() => _uploading = true);
    final ok = await widget.controller.uploadTaskAttachment(widget.todo.id,
        bytes: bytes, filename: file.name);
    if (!mounted) return;
    setState(() => _uploading = false);
    if (ok) {
      Get.snackbar('附件', '上传成功');
      _reload();
    } else {
      Get.snackbar('附件', '上传失败');
    }
  }

  Future<void> _download(TaskAttachment attachment) async {
    // Re-entrancy guard: a double-tap on the download button must not fire two
    // concurrent network downloads (and two stacked OS save dialogs).
    if (_downloadingId != null) return;
    setState(() => _downloadingId = attachment.id);
    Uint8List? data;
    try {
      data = await widget.controller.downloadTaskAttachment(attachment.id);
    } finally {
      if (mounted) {
        setState(() => _downloadingId = null);
      }
    }
    if (data == null || data.isEmpty) {
      Get.snackbar('附件', '下载失败');
      return;
    }
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '保存附件',
      fileName: attachment.filename,
      bytes: data,
    );
    if (path == null || path.isEmpty) return;
    Get.snackbar('附件', '已保存到 $path');
  }

  Future<void> _confirmDeleteAttachment(TaskAttachment attachment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _plainDialog(
        context: dialogContext,
        title: const Text('删除附件'),
        content: Text('确定删除「${attachment.filename}」吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirmed == true &&
        await widget.controller.deleteTaskAttachment(attachment.id)) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.9,
      builder: (context, scrollController) => SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.todo.title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (widget.todo.projectName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  widget.todo.projectName,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.bookmark_outline, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  '参考笔记',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add, size: 20),
                  tooltip: '添加笔记',
                  onPressed: _addNote,
                ),
              ],
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_notes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '暂无笔记',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              )
            else
              for (final note in _notes) _noteTile(context, note),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.attach_file, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  '附件',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (_uploading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.upload_file, size: 20),
                    tooltip: '上传附件',
                    onPressed: _upload,
                  ),
              ],
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_attachments.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '暂无附件',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              )
            else
              for (final attachment in _attachments)
                _attachmentTile(context, attachment),
          ],
        ),
      ),
    );
  }

  Widget _noteTile(BuildContext context, TaskNote note) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (note.title.isNotEmpty)
                  Text(
                    note.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                if (note.content.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      note.content,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: '删除',
            onPressed: () => _confirmDeleteNote(note),
          ),
        ],
      ),
    );
  }

  Widget _attachmentTile(BuildContext context, TaskAttachment attachment) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            color: scheme.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  attachment.sizeLabel,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.download_outlined, size: 20),
            tooltip: '下载',
            onPressed: () => _download(attachment),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: '删除',
            onPressed: () => _confirmDeleteAttachment(attachment),
          ),
        ],
      ),
    );
  }
}
