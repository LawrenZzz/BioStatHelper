import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../shared/models/study_model.dart';
import '../controllers/study_controller.dart';
import 'study_library_view.dart';
import 'study_search_view.dart';
import 'study_widgets.dart';

class StudyListsView extends StatefulWidget {
  const StudyListsView({super.key, required this.controller});
  final StudyController controller;
  @override
  State<StudyListsView> createState() => _StudyListsViewState();
}

class _StudyListsViewState extends State<StudyListsView> {
  bool _archived = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
        appBar: AppBar(title: const Text('学习列表'), actions: [
          IconButton(
              tooltip: '新建列表',
              icon: const Icon(Icons.playlist_add),
              onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => StudyListEditor(controller: c))),
          IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh),
              onPressed: c.refreshAll),
        ]),
        body: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Obx(() {
            final lists =
                c.lists.where((list) => list.archived == _archived).toList();
            final saving = c.writing;
            return RefreshIndicator(
                onRefresh: c.refreshAll,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                      16, 12, 16, studyBottomPadding(context)),
                  children: [
                    SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                              value: false,
                              label: Text('正在学习'),
                              icon: Icon(Icons.menu_book_outlined)),
                          ButtonSegment(
                              value: true,
                              label: Text('已归档'),
                              icon: Icon(Icons.archive_outlined)),
                        ],
                        selected: {
                          _archived
                        },
                        onSelectionChanged: (value) =>
                            setState(() => _archived = value.first)),
                    StudyErrors(
                        controller: c, sections: const ['lists', 'items']),
                    if (c.busy.contains('lists'))
                      const LinearProgressIndicator(),
                    if (lists.isEmpty) const StudyEmpty('暂无学习列表'),
                    for (final list in lists)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 6),
                        leading: const Icon(Icons.playlist_play),
                        title: Text(list.name,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            '${c.itemsFor(list.id).length} 项'
                            '${list.description.isEmpty ? '' : ' · ${list.description}'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                                builder: (_) => StudyListDetailView(
                                    controller: c, listId: list.id))),
                        trailing: PopupMenuButton<String>(
                            tooltip: '列表操作',
                            enabled: !saving,
                            itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'edit', child: Text('编辑列表')),
                                  PopupMenuItem(
                                      value: 'remove', child: Text('删除列表')),
                                ],
                            onSelected: (action) async {
                              if (action == 'edit') {
                                await showDialog<bool>(
                                    context: context,
                                    builder: (_) => StudyListEditor(
                                        controller: c, list: list));
                              } else if (await studyConfirm(context, '删除学习列表',
                                  '删除“${list.name}”及其中的学习项？')) {
                                await c.deleteList(list);
                              }
                            }),
                      ),
                  ],
                ));
          }),
        )));
  }
}

class StudyListDetailView extends StatefulWidget {
  const StudyListDetailView(
      {super.key, required this.controller, required this.listId});
  final StudyController controller;
  final int listId;
  @override
  State<StudyListDetailView> createState() => _StudyListDetailViewState();
}

class _StudyListDetailViewState extends State<StudyListDetailView> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  final _selected = <int>{};
  final _expandedCourses = <String>{};
  StudyStatus? _status;
  bool _favorites = false;
  String _sort = 'manual';
  StudyController get c => widget.controller;
  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _batch(String action, Iterable<int> ids) async {
    final selected = ids.toList();
    if (selected.isEmpty) return;
    if (action == 'remove' &&
        !await studyConfirm(context, '移除学习项', '移除 ${selected.length} 个学习项？')) {
      return;
    }
    final saved = await c.batchItems(selected, action);
    if (saved && mounted) setState(_selected.clear);
  }

  void _selectItems(Iterable<int> ids, bool selected) => setState(() {
        if (selected) {
          _selected.addAll(ids);
        } else {
          _selected.removeAll(ids);
        }
      });

  Widget _dragHandle(int index) => ReorderableDragStartListener(
      index: index,
      child: const Tooltip(
          message: '拖动排序',
          child: Padding(
              padding: EdgeInsets.all(12),
              child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Icon(Icons.drag_handle)))));

  Widget _itemRow(StudyItem item, {Widget? dragHandle, bool inCourse = false}) {
    final saving = c.writing;
    return StudyItemRow(
      key: ValueKey(item.id),
      item: item,
      displayTitle: inCourse ? item.partTitle : null,
      onPlay: c.busy.contains('play') ? null : () => c.openItem(item),
      leading: Checkbox(
          value: _selected.contains(item.id),
          onChanged: saving
              ? null
              : (value) => _selectItems([item.id], value == true)),
      actions: [
        PopupMenuButton<StudyStatus>(
            tooltip: '学习状态',
            enabled: !saving,
            initialValue: item.status,
            icon: Icon(switch (item.status) {
              StudyStatus.planned => Icons.radio_button_unchecked,
              StudyStatus.learning => Icons.timelapse,
              StudyStatus.completed => Icons.task_alt,
            }),
            itemBuilder: (_) => [
                  for (final status in StudyStatus.values)
                    PopupMenuItem(value: status, child: Text(status.label))
                ],
            onSelected: (status) =>
                c.updateItem(item, {'status': status.name})),
        IconButton(
            tooltip: item.favorite ? '取消收藏' : '收藏',
            color:
                item.favorite ? Theme.of(context).colorScheme.tertiary : null,
            icon: Icon(item.favorite ? Icons.star : Icons.star_outline),
            onPressed: saving
                ? null
                : () => c.updateItem(item, {'favorite': !item.favorite})),
        IconButton(
            tooltip: '时间点笔记',
            icon: const Icon(Icons.edit_note),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) =>
                        StudyNotesView(controller: c, item: item)))),
        IconButton(
            tooltip: '移除学习项',
            icon: const Icon(Icons.delete_outline),
            onPressed: saving ? null : () => _batch('remove', [item.id])),
        if (dragHandle != null) dragHandle,
      ],
    );
  }

  Widget _courseRow(StudyListGroup group, {Widget? dragHandle}) {
    final ids = group.items.map((item) => item.id).toSet();
    final count = ids.intersection(_selected).length;
    final next = group.continueItem;
    return ExpansionTile(
      key: PageStorageKey(group.key),
      initiallyExpanded: _expandedCourses.contains(group.key),
      onExpansionChanged: (expanded) => setState(() {
        if (expanded) {
          _expandedCourses.add(group.key);
        } else {
          _expandedCourses.remove(group.key);
        }
      }),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 8),
      leading: StudyThumbnail(group.first.thumbnailUrl),
      title: Text(group.title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            'B站 · ${group.items.length} 个分P · 已完成 ${group.completed}/${group.items.length}'),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: group.progress, minHeight: 3),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          Tooltip(
              message: '选择整门课程',
              child: Checkbox(
                  tristate: true,
                  value: count == 0
                      ? false
                      : count == ids.length
                          ? true
                          : null,
                  onChanged: c.writing
                      ? null
                      : (_) => _selectItems(ids, count != ids.length))),
          IconButton(
              tooltip: '继续学习',
              icon: const Icon(Icons.play_circle_outline),
              onPressed:
                  c.busy.contains('play') ? null : () => c.openItem(next)),
          if (dragHandle != null) dragHandle,
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Obx(() {
        final list =
            c.lists.firstWhereOrNull((list) => list.id == widget.listId);
        final all = c.itemsFor(widget.listId);
        final query = _query.text.trim().toLowerCase();
        final visible = all
            .where((item) =>
                (_status == null || item.status == _status) &&
                (!_favorites || item.favorite) &&
                '${item.title} ${item.courseTitle}'
                    .toLowerCase()
                    .contains(query))
            .toList();
        if (_sort == 'title') {
          visible.sort((a, b) => a.title.compareTo(b.title));
        }
        if (_sort == 'recent') {
          visible.sort((a, b) => (b.updatedAt ?? DateTime(1970))
              .compareTo(a.updatedAt ?? DateTime(1970)));
        }
        final groups = StudyListGroup.collect(visible);
        // Parts share the outer sliver so a large expanded course stays lazy.
        final entries = <({StudyListGroup group, StudyItem? part})>[
          for (final group in groups) ...[
            (group: group, part: null),
            if (group.isCourse && _expandedCourses.contains(group.key))
              for (final item in group.items) (group: group, part: item),
          ],
        ];
        final canReorder = _status == null &&
            !_favorites &&
            query.isEmpty &&
            _sort == 'manual' &&
            !c.writing &&
            !groups.any((group) => _expandedCourses.contains(group.key));
        final selected =
            _selected.intersection(visible.map((item) => item.id).toSet());
        final saving = c.writing;
        return Scaffold(
            appBar: AppBar(
                title: Text(list?.name ?? '学习列表',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                actions: [
                  IconButton(
                      tooltip: '添加学习内容',
                      icon: const Icon(Icons.add),
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) => StudySearchView(controller: c)))),
                  IconButton(
                      tooltip: '刷新',
                      icon: const Icon(Icons.refresh),
                      onPressed: c.refreshItems),
                  PopupMenuButton<String>(
                      tooltip: '列表操作',
                      enabled: !saving,
                      itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('编辑列表')),
                            PopupMenuItem(
                                value: 'completed', child: Text('移除所有已完成项')),
                          ],
                      onSelected: (action) async {
                        if (action == 'edit' && list != null) {
                          await showDialog<bool>(
                              context: context,
                              builder: (_) =>
                                  StudyListEditor(controller: c, list: list));
                        } else if (action == 'completed') {
                          await _batch(
                              'remove',
                              all
                                  .where((item) =>
                                      item.status == StudyStatus.completed)
                                  .map((item) => item.id));
                        }
                      }),
                ]),
            body: Center(
                child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: RefreshIndicator(
                  onRefresh: c.refreshItems,
                  child: CustomScrollView(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          sliver: SliverToBoxAdapter(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (list?.description.isNotEmpty ?? false)
                                    Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: Text(list!.description)),
                                  TextField(
                                      controller: _query,
                                      onChanged: (_) => setState(() {}),
                                      decoration: const InputDecoration(
                                          prefixIcon: Icon(Icons.search),
                                          hintText: '搜索列表内的学习项')),
                                  const SizedBox(height: 12),
                                  Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        ChoiceChip(
                                            label: const Text('全部'),
                                            selected: _status == null,
                                            onSelected: (_) =>
                                                setState(() => _status = null)),
                                        for (final status in StudyStatus.values)
                                          ChoiceChip(
                                              label: Text(status.label),
                                              selected: _status == status,
                                              onSelected: (_) => setState(
                                                  () => _status = status)),
                                        FilterChip(
                                            avatar: const Icon(
                                                Icons.star_outline,
                                                size: 18),
                                            label: const Text('收藏'),
                                            selected: _favorites,
                                            onSelected: (value) => setState(
                                                () => _favorites = value)),
                                        PopupMenuButton<String>(
                                            tooltip: '排序',
                                            initialValue: _sort,
                                            icon: const Icon(Icons.sort),
                                            itemBuilder: (_) => const [
                                                  PopupMenuItem(
                                                      value: 'manual',
                                                      child: Text('手动排序')),
                                                  PopupMenuItem(
                                                      value: 'title',
                                                      child: Text('名称排序')),
                                                  PopupMenuItem(
                                                      value: 'recent',
                                                      child: Text('最近学习')),
                                                ],
                                            onSelected: (value) =>
                                                setState(() => _sort = value)),
                                      ]),
                                  StudyErrors(
                                      controller: c,
                                      sections: const ['items', 'lists']),
                                  if (c.busy.contains('items'))
                                    const LinearProgressIndicator(),
                                  Wrap(
                                      spacing: 8,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                            '${visible.length} 项 · 已选 ${selected.length}'),
                                        IconButton(
                                            tooltip: '选择当前结果',
                                            icon: const Icon(Icons.select_all),
                                            onPressed: visible.isEmpty
                                                ? null
                                                : () => setState(() {
                                                      if (selected.length ==
                                                          visible.length) {
                                                        _selected.removeAll(
                                                            selected);
                                                      } else {
                                                        _selected.addAll(visible
                                                            .map((item) =>
                                                                item.id));
                                                      }
                                                    })),
                                        if (selected.isNotEmpty) ...[
                                          IconButton(
                                              tooltip: '标为已完成',
                                              icon: const Icon(Icons.task_alt),
                                              onPressed: saving
                                                  ? null
                                                  : () => _batch(
                                                      'complete', selected)),
                                          IconButton(
                                              tooltip: '标为待学习',
                                              icon: const Icon(
                                                  Icons.radio_button_unchecked),
                                              onPressed: saving
                                                  ? null
                                                  : () =>
                                                      _batch('plan', selected)),
                                          IconButton(
                                              tooltip: '移除所选',
                                              icon: const Icon(
                                                  Icons.delete_outline),
                                              onPressed: saving
                                                  ? null
                                                  : () => _batch(
                                                      'remove', selected)),
                                        ],
                                      ]),
                                  if (visible.isEmpty &&
                                      !c.busy.contains('items'))
                                    const StudyEmpty('暂无学习项'),
                                ]),
                          )),
                      SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverReorderableList(
                            itemCount: entries.length,
                            onReorderItem: (oldIndex, newIndex) async {
                              if (!canReorder) return;
                              final reordered = groups.toList();
                              reordered.insert(
                                  newIndex, reordered.removeAt(oldIndex));
                              await c.reorderItems(
                                  widget.listId,
                                  reordered
                                      .expand((group) =>
                                          group.items.map((item) => item.id))
                                      .toList());
                            },
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              if (entry.part != null) {
                                return _itemRow(entry.part!, inCourse: true);
                              }
                              final group = entry.group;
                              return KeyedSubtree(
                                  key: ValueKey(group.key),
                                  child: group.isCourse
                                      ? _courseRow(group,
                                          dragHandle: canReorder
                                              ? _dragHandle(index)
                                              : null)
                                      : _itemRow(group.first,
                                          dragHandle: canReorder
                                              ? _dragHandle(index)
                                              : null));
                            },
                          )),
                      SliverToBoxAdapter(
                          child: SizedBox(height: studyBottomPadding(context))),
                    ],
                  )),
            )));
      });
}
