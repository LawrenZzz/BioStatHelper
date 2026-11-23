import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../shared/widgets/concept_card.dart';
import '../../../../shared/widgets/biostat_logo.dart';
import '../../../../shared/widgets/library_browse_sheet.dart';
import '../../../../shared/widgets/progress_card.dart';
import '../../../routes/app_routes.dart';
import '../controllers/home_controller.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final HomeController controller = Get.find<HomeController>();
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: controller.loadKnowledgeHome,
        child: CustomScrollView(
          slivers: [
            _buildAppBar(context),
            SliverToBoxAdapter(
              child: Obx(() {
                if (controller.isLoading.value) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSearchBar(context),
                    _buildOverview(context),
                    _buildLearningProgress(context),
                    _buildQuickActions(context),
                    _buildCategoryChips(context),
                    _buildHotTags(context),
                    _buildConceptSection(context),
                    const SizedBox(height: 96),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 132,
      floating: true,
      pinned: true,
      leadingWidth: 58,
      leading: const Padding(
        padding: EdgeInsets.only(left: 14),
        child: Center(child: BiostatLogo(size: 34)),
      ),
      title: const Text('生统知识库'),
      flexibleSpace: FlexibleSpaceBar(
        background: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.secondary,
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 12),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  '统计基础、临床试验、DM、CDISC、SAS 速查',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onPrimary
                            .withValues(alpha: 0.92),
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
      actions: [
        IconButton(
          tooltip: '快速参考',
          icon: const Icon(Icons.bookmark_border),
          onPressed: () => Get.toNamed(AppRoutes.reference),
        ),
      ],
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: TextField(
        decoration: InputDecoration(
          hintText: '搜索概念、公式、SAS、DM 或 CDISC...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: Obx(() {
            if (controller.searchQuery.value.isEmpty) {
              return IconButton(
                tooltip: '全部概念',
                icon: const Icon(Icons.manage_search),
                onPressed: () => Get.toNamed(AppRoutes.concepts),
              );
            }
            return IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.close),
              onPressed: () {
                _searchController.clear();
                controller.updateSearchQuery('');
              },
            );
          }),
        ),
        controller: _searchController,
        onChanged: controller.updateSearchQuery,
        onSubmitted: (_) => Get.toNamed(AppRoutes.concepts),
      ),
    );
  }

  /// 学习进度卡（数据来自 /statistics/progress）。
  Widget _buildLearningProgress(BuildContext context) {
    return Obx(() {
      if (!controller.hasProgress.value) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: ProgressCard(
          completedVideos: controller.completedVideos.value,
          totalVideos: controller.totalVideos.value,
          completedConcepts: controller.completedConcepts.value,
          totalConcepts: controller.totalConcepts.value,
          studyHours: controller.studyHours.value,
          streakDays: controller.streakDays.value,
        ),
      );
    });
  }

  Widget _buildOverview(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: _buildMetric(
              context,
              icon: Icons.library_books_outlined,
              label: '概念',
              value: '${controller.totalConceptCount}',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildMetric(
              context,
              icon: Icons.category_outlined,
              label: '分类',
              value: '${controller.categoryCount}',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildMetric(
              context,
              icon: Icons.local_offer_outlined,
              label: '标签',
              value: '${controller.tagCount}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.62),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 3.8,
        children: [
          _buildActionTile(
            context,
            icon: Icons.menu_book_outlined,
            label: '全部概念',
            color: Theme.of(context).colorScheme.primary,
            onTap: () => Get.toNamed(AppRoutes.concepts),
          ),
          _buildActionTile(
            context,
            icon: Icons.bookmark_border,
            label: '快速参考',
            color: Colors.orange,
            onTap: () => Get.toNamed(AppRoutes.reference),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  Theme.of(context).colorScheme.outline.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChips(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '分类：${controller.selectedCategory.value}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          TextButton.icon(
            onPressed: () => _showCategoryBrowser(context),
            icon: const Icon(Icons.view_list_outlined, size: 18),
            label: const Text('查看全部'),
          ),
        ],
      ),
    );
  }

  Widget _buildHotTags(BuildContext context) {
    return Obx(() {
      final tags = controller.hotTags;
      if (tags.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '热门标签',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _showTagBrowser(context),
                  icon: const Icon(Icons.sell_outlined, size: 18),
                  label: const Text('查看全部'),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: tags.take(6).map((tag) {
                return ActionChip(
                  label: Text(tag),
                  avatar: const Icon(Icons.tag, size: 16),
                  onPressed: () => controller.updateSearchQuery(tag),
                );
              }).toList(),
            ),
          ],
        ),
      );
    });
  }

  void _showCategoryBrowser(BuildContext context) {
    final options = <LibraryBrowseOption>[
      LibraryBrowseOption(
        id: '全部',
        title: '全部概念',
        subtitle: '清除分类筛选',
        icon: 'Σ',
        count: controller.concepts.length,
      ),
      ...controller.categories.map(
        (category) => LibraryBrowseOption(
          id: category.name,
          title: category.name,
          subtitle: category.description,
          icon: category.icon,
          count: category.conceptCount,
        ),
      ),
    ];
    showLibraryBrowseSheet(
      context: context,
      title: '全部知识分类',
      searchHint: '搜索分类',
      options: options,
      onSelected: (option) => controller.filterByCategory(option.id),
    );
  }

  void _showTagBrowser(BuildContext context) {
    final usage = controller.tagUsage;
    final options = controller.allTags
        .map(
          (tag) => LibraryBrowseOption(
            id: tag,
            title: tag,
            subtitle: '用于 ${usage[tag] ?? 0} 个概念',
            icon: '#',
            count: usage[tag] ?? 0,
          ),
        )
        .toList();
    showLibraryBrowseSheet(
      context: context,
      title: '全部标签',
      searchHint: '搜索标签',
      options: options,
      onSelected: (option) {
        _searchController.text = option.title;
        controller.updateSearchQuery(option.title);
      },
    );
  }

  Widget _buildConceptSection(BuildContext context) {
    return Obx(() {
      final concepts = controller.visibleConcepts;
      if (concepts.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.search_off,
                  size: 48,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.36),
                ),
                const SizedBox(height: 12),
                Text(
                  '没有找到匹配的概念',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Text(
                  controller.searchQuery.value.isEmpty ? '推荐概念' : '搜索结果',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => Get.toNamed(AppRoutes.concepts),
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: const Text('全部'),
                ),
              ],
            ),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: concepts.length > 12 ? 12 : concepts.length,
            itemBuilder: (context, index) {
              final concept = concepts[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ConceptCard(
                  concept: concept,
                  onTap: () => Get.toNamed(
                    AppRoutes.conceptDetail,
                    arguments: concept,
                  ),
                ),
              );
            },
          ),
        ],
      );
    });
  }
}
