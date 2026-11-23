import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/concepts_controller.dart';
import '../../../routes/app_routes.dart';
import '../../../../shared/widgets/concept_card.dart';
import '../../../../shared/widgets/library_browse_sheet.dart';
import '../../../../shared/widgets/liquid_glass_panel.dart';

class ConceptsView extends StatefulWidget {
  const ConceptsView({super.key});

  @override
  State<ConceptsView> createState() => _ConceptsViewState();
}

class _ConceptsViewState extends State<ConceptsView> {
  final ConceptsController controller = Get.find<ConceptsController>();
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('知识库'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              _showFilterDialog(context);
            },
          ),
        ],
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        return RefreshIndicator(
          onRefresh: controller.loadConceptHub,
          child: CustomScrollView(
            slivers: [
              _buildSearchBar(context),
              _buildCategoryChips(context),
              _buildTagBrowser(context),
              _buildConceptList(context),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: TextField(
          decoration: InputDecoration(
            hintText: '搜索概念、标签、SAS、DM、CDISC...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: Obx(() {
              if (controller.searchQuery.value.isEmpty) {
                return const Icon(Icons.manage_search);
              }
              return IconButton(
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
        ),
      ),
    );
  }

  Widget _buildCategoryChips(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
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
      ),
    );
  }

  Widget _buildTagBrowser(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '标签 ${controller.allTags.length}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            TextButton.icon(
              onPressed: () => _showTagBrowser(context),
              icon: const Icon(Icons.sell_outlined, size: 18),
              label: const Text('查看全部'),
            ),
          ],
        ),
      ),
    );
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

  Widget _buildConceptList(BuildContext context) {
    if (controller.filteredConcepts.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.book_outlined,
                size: 64,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              Text(
                '暂无概念',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                '该分类下暂无概念内容',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.3),
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final concept = controller.filteredConcepts[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ConceptCard(
                concept: concept,
                onTap: () => Get.toNamed(
                  AppRoutes.conceptDetail,
                  arguments: concept,
                ),
              ),
            );
          },
          childCount: controller.filteredConcepts.length,
        ),
      ),
    );
  }

  void _showFilterDialog(BuildContext context) {
    showLiquidGlassBottomSheet(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '筛选概念',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 20),
              Text(
                '排序方式',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('最新'),
                    selected: controller.sortBy.value == 'newest',
                    onSelected: (selected) {
                      controller.sortConcepts('newest');
                      Navigator.pop(context);
                    },
                  ),
                  ChoiceChip(
                    label: const Text('最热'),
                    selected: controller.sortBy.value == 'popular',
                    onSelected: (selected) {
                      controller.sortConcepts('popular');
                      Navigator.pop(context);
                    },
                  ),
                  ChoiceChip(
                    label: const Text('阅读量'),
                    selected: controller.sortBy.value == 'readCount',
                    onSelected: (selected) {
                      controller.sortConcepts('readCount');
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}
