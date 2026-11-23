import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../home/views/home_view.dart';
import '../../projects/views/projects_view.dart';
import '../../settings/views/settings_view.dart';
import '../../today/controllers/today_controller.dart';
import '../../today/views/today_view.dart';
import '../../video/views/video_list_view.dart';
import '../../../../shared/widgets/biostat_logo.dart';
import '../../../../shared/widgets/liquid_glass_panel.dart';
import '../controllers/shell_controller.dart';

class ShellView extends GetView<ShellController> {
  const ShellView({super.key});

  static const _items = <GlassTab>[
    GlassTab(
      icon: Icon(Icons.menu_book_outlined),
      activeIcon: Icon(Icons.menu_book),
      label: '知识库',
    ),
    GlassTab(
      icon: Icon(Icons.work_outline),
      activeIcon: Icon(Icons.work),
      label: '项目库',
    ),
    GlassTab(
      icon: Icon(Icons.video_library_outlined),
      activeIcon: Icon(Icons.video_library),
      label: '视频库',
    ),
    GlassTab(
      icon: Icon(Icons.person_outline),
      activeIcon: Icon(Icons.person),
      label: '我的',
    ),
    GlassTab(
      icon: Icon(Icons.today_outlined),
      activeIcon: Icon(Icons.today),
      label: '今日工作台',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final content = Obx(
      () => IndexedStack(
        index: controller.currentIndex.value,
        children: const [
          HomeView(),
          ProjectsView(),
          VideoListView(),
          SettingsView(),
          TodayView(embeddedInShell: true),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final useDesktopLayout = constraints.maxWidth >= 900;
          if (useDesktopLayout) {
            return SafeArea(
              child: Row(
                children: [
                  Obx(
                    () {
                      final collapsed = controller.sidebarCollapsed.value;
                      final navWidth = collapsed ? 64.0 : 220.0;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        width: navWidth,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                          child: _DesktopNavigation(
                            controller: controller,
                          ),
                        ),
                      );
                    },
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              ),
            );
          }

          return GlassScaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            body: content,
            bottomBar: Obx(
              () {
                final todayDrawerOpen = controller.currentIndex.value == 4 &&
                    Get.isRegistered<TodayController>() &&
                    Get.find<TodayController>().mobileDrawerOpen.value;
                if (todayDrawerOpen) return const SizedBox.shrink();

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassTabBar.bottom(
                    tabs: _items,
                    selectedIndex: controller.currentIndex.value,
                    onTabSelected: controller.switchTab,
                    barHeight: 76,
                    barBorderRadius: 24,
                    iconSize: 22,
                    labelFontSize: 11,
                    selectedLabelStyle:
                        const TextStyle(fontWeight: FontWeight.w800),
                    settings: LiquidGlassSettings(
                      glassColor:
                          Theme.of(context).brightness == Brightness.dark
                              ? Theme.of(context)
                                  .colorScheme
                                  .surface
                                  .withValues(alpha: 0.48)
                              : Colors.white.withValues(alpha: 0.38),
                      blur: 6,
                      saturation: 1.18,
                      chromaticAberration: 0.002,
                    ),
                    indicatorColor: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withValues(alpha: 0.58),
                    selectedIconColor: Theme.of(context).colorScheme.primary,
                    unselectedIconColor: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.68),
                    selectedLabelColor: Theme.of(context).colorScheme.primary,
                    unselectedLabelColor: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.68),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class ShellNavItem {
  final String label;
  final IconData icon;
  final int index;
  const ShellNavItem(
      {required this.label, required this.icon, required this.index});
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({required this.controller});

  final ShellController controller;

  static const _navItems = <ShellNavItem>[
    ShellNavItem(label: '工作台', icon: Icons.home_outlined, index: 0),
    ShellNavItem(label: '项目库', icon: Icons.work_outline, index: 1),
    ShellNavItem(label: '视频', icon: Icons.video_library_outlined, index: 2),
    ShellNavItem(label: '设置', icon: Icons.settings_outlined, index: 3),
    ShellNavItem(label: '今日', icon: Icons.today_outlined, index: 4),
  ];

  @override
  Widget build(BuildContext context) {
    final collapsed = controller.sidebarCollapsed.value;

    return LiquidGlassPanel(
      borderRadius: 24,
      padding: EdgeInsets.zero,
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: const BoxDecoration(color: Colors.transparent),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with logo + toggle
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
              child: Row(
                children: [
                  BiostatLogo(size: collapsed ? 28 : 38),
                  if (!collapsed) ...[
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        '生统助手',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      collapsed ? Icons.chevron_right : Icons.chevron_left,
                      size: 20,
                    ),
                    tooltip: collapsed ? '展开' : '收起',
                    onPressed: controller.toggleSidebar,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Nav items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (var index = 0; index < _navItems.length; index++)
                    Obx(
                      () => _NavMenuItem(
                        item: _navItems[index],
                        index: index,
                        selected: controller.currentIndex.value == index,
                        collapsed: collapsed,
                        onTap: () => controller.switchTab(index),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavMenuItem extends StatelessWidget {
  const _NavMenuItem({
    required this.item,
    required this.index,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final ShellNavItem item;
  final int index;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4, left: 8, right: 8),
      child: Material(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.70)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: collapsed
                ? IconTheme(
                    data: IconThemeData(color: color, size: 22),
                    child: Icon(item.icon),
                  )
                : Row(
                    children: [
                      IconTheme(
                        data: IconThemeData(color: color, size: 22),
                        child: Icon(item.icon),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.label,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: color,
                                    fontWeight: selected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
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
