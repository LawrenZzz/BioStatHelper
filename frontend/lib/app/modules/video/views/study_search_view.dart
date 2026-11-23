import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/services/bilibili_service.dart';
import '../../../../shared/models/category_model.dart';
import '../../../../shared/models/study_model.dart';
import '../controllers/study_controller.dart';
import 'bilibili_account_view.dart';
import 'study_widgets.dart';

class StudySearchView extends StatefulWidget {
  const StudySearchView({super.key, required this.controller});
  final StudyController controller;
  @override
  State<StudySearchView> createState() => _StudySearchViewState();
}

class _StudySearchViewState extends State<StudySearchView> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  String _source = 'nas';
  VideoCategory? _category;
  int _page = 1;
  StudyController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.clearSearch();
    unawaited(c.loadCategories());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _scroll.dispose();
    c.clearSearch();
    super.dispose();
  }

  Future<void> _search({bool more = false}) async {
    _debounce?.cancel();
    if (_source == 'bilibili' && _query.text.trim().isEmpty) {
      c.clearSearch();
      return;
    }
    if (!more) _page = 1;
    final page = more ? _page + 1 : 1;
    final ok = await c.search(_query.text,
        categoryId: _category?.id, source: _source, page: page);
    if (ok && mounted) _page = page;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('搜索学习内容'), actions: [
          IconButton(
              tooltip: 'B站账号',
              icon: const Icon(Icons.account_circle_outlined),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => BilibiliAccountView(
                            service: c.bili,
                            qrBuilder: (_, value) =>
                                QrImageView(data: value, size: 224),
                            onAdd: (metadata) async {
                              final listId = await studyPickList(context, c);
                              if (listId == null) {
                                throw const BiliException('已取消添加',
                                    kind: BiliErrorKind.cancelled);
                              }
                              final saved = await c.addItem(
                                  StudyItem(
                                      id: 0,
                                      listId: listId,
                                      source: 'bilibili',
                                      sourceData: metadata,
                                      title:
                                          '${metadata['video_title'] ?? metadata['title'] ?? ''}'
                                          ' · P${metadata['page'] ?? 1} ${metadata['title'] ?? ''}',
                                      thumbnailUrl:
                                          '${metadata['cover'] ?? ''}',
                                      durationSeconds: studyInt(
                                          metadata['duration_seconds'])),
                                  listId);
                              if (!saved) {
                                throw StateError(
                                    c.errors['write'] ?? '加入学习列表失败');
                              }
                            },
                          )))),
        ]),
        body: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Obx(() {
            final loading = c.busy.contains('search');
            final writing = c.writing;
            final results = c.searchResults.toList();
            return CustomScrollView(controller: _scroll, slivers: [
              SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  sliver: SliverToBoxAdapter(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                        SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                  value: 'nas',
                                  icon: Icon(Icons.storage_outlined),
                                  label: Text('NAS')),
                              ButtonSegment(
                                  value: 'bilibili',
                                  icon: Icon(Icons.ondemand_video_outlined),
                                  label: Text('B站')),
                            ],
                            selected: {
                              _source
                            },
                            onSelectionChanged: (selection) {
                              setState(() {
                                _source = selection.first;
                                _category = null;
                              });
                              c.clearSearch();
                              unawaited(_search());
                            }),
                        const SizedBox(height: 16),
                        TextField(
                            controller: _query,
                            autofocus: true,
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                                hintText: _source == 'nas'
                                    ? '关键词或课程名称'
                                    : '关键词 / BV号 / 视频链接',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: IconButton(
                                    tooltip: '清空搜索',
                                    icon: const Icon(Icons.close),
                                    onPressed: () {
                                      _query.clear();
                                      unawaited(_search());
                                    })),
                            onChanged: (_) {
                              _debounce?.cancel();
                              c.clearSearch();
                              _debounce = Timer(
                                  const Duration(milliseconds: 400),
                                  () => unawaited(_search()));
                            },
                            onSubmitted: (_) => _search()),
                        if (_source == 'nas') ...[
                          const SizedBox(height: 12),
                          Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                OutlinedButton.icon(
                                    icon:
                                        const Icon(Icons.folder_open_outlined),
                                    label: ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(maxWidth: 220),
                                        child: Text(_category?.name ?? '选择课程分类',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis)),
                                    onPressed: c.busy.contains('categories')
                                        ? null
                                        : () async {
                                            final selected =
                                                await studyPickCategory(context,
                                                    c.categories.toList());
                                            if (!mounted || selected == null) {
                                              return;
                                            }
                                            setState(
                                                () => _category = selected);
                                            await _search();
                                          }),
                                if (_category != null) ...[
                                  IconButton(
                                      tooltip: '清除分类',
                                      icon: const Icon(
                                          Icons.filter_alt_off_outlined),
                                      onPressed: () {
                                        setState(() => _category = null);
                                        unawaited(_search());
                                      }),
                                  FilledButton.tonalIcon(
                                      icon: const Icon(Icons.playlist_add),
                                      label: const Text('整课加入'),
                                      onPressed: writing
                                          ? null
                                          : () async {
                                              final category = _category!;
                                              final listId =
                                                  await studyPickList(
                                                      context, c);
                                              if (!context.mounted ||
                                                  listId == null) {
                                                return;
                                              }
                                              if (!await studyConfirm(
                                                  context,
                                                  '添加整门课程',
                                                  '将“${category.name}”的全部视频加入学习列表？')) {
                                                return;
                                              }
                                              await c.addNasCourse(
                                                  category, listId);
                                            }),
                                  IconButton(
                                      tooltip: '订阅课程更新',
                                      icon:
                                          const Icon(Icons.notifications_none),
                                      onPressed: writing
                                          ? null
                                          : () async {
                                              final saved =
                                                  await c.saveSubscription(
                                                      name: _category!.name,
                                                      categoryId:
                                                          _category!.id);
                                              if (saved && context.mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                        const SnackBar(
                                                            content:
                                                                Text('已订阅课程')));
                                              }
                                            }),
                                ],
                              ]),
                        ],
                        StudyErrors(controller: c, sections: const [
                          'search',
                          'categories',
                          'lists',
                          'biliDetail'
                        ]),
                        if (loading) const LinearProgressIndicator(),
                        if (!loading && results.isEmpty)
                          StudyEmpty(
                              _query.text.trim().isEmpty && _category == null
                                  ? '搜索内容或选择课程'
                                  : '没有匹配的内容',
                              icon: Icons.search),
                        if (results.isNotEmpty)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text('搜索结果 · ${c.searchTotal.value}')),
                      ]))),
              SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.builder(
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final item = results[index];
                      return StudyItemRow(item: item, onPlay: null, actions: [
                        FilledButton.tonalIcon(
                            icon: const Icon(Icons.playlist_add),
                            label: const Text('加入学习列表'),
                            onPressed: writing || c.busy.contains('biliDetail')
                                ? null
                                : () async {
                                    final saved = await studyAddLearningItem(
                                        context, c, item);
                                    if (saved && context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(const SnackBar(
                                              content: Text('已加入学习列表')));
                                    }
                                  }),
                      ]);
                    },
                  )),
              SliverToBoxAdapter(
                  child: Padding(
                padding: EdgeInsets.fromLTRB(
                    16, 12, 16, studyBottomPadding(context)),
                child: results.length < c.searchTotal.value &&
                        results.isNotEmpty
                    ? OutlinedButton.icon(
                        onPressed: loading ? null : () => _search(more: true),
                        icon: const Icon(Icons.expand_more),
                        label: const Text('加载更多'))
                    : const SizedBox.shrink(),
              )),
            ]);
          }),
        )),
      );
}

Future<bool> studyAddLearningItem(
    BuildContext context, StudyController c, StudyItem item) async {
  if (item.source == 'bilibili') {
    final video = await c.loadBiliDetail(item);
    if (video == null || !context.mounted) return false;
    final parts = video.parts.length == 1
        ? video.parts
        : await showDialog<List<BiliPart>>(
            context: context, builder: (_) => _StudyPartsPicker(video: video));
    if (parts == null || parts.isEmpty || !context.mounted) return false;
    final id = await studyPickList(context, c);
    if (id == null) return false;
    return c.addBiliParts(video, parts, id);
  }
  final id = await studyPickList(context, c);
  if (id == null) return false;
  return c.addItem(item, id);
}

class _StudyPartsPicker extends StatefulWidget {
  const _StudyPartsPicker({required this.video});
  final BiliVideo video;
  @override
  State<_StudyPartsPicker> createState() => _StudyPartsPickerState();
}

class _StudyPartsPickerState extends State<_StudyPartsPicker> {
  final _selected = <int>{};
  @override
  void initState() {
    super.initState();
    _selected.add(widget.video.parts.first.cid);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.video.title,
              maxLines: 2, overflow: TextOverflow.ellipsis),
          content: SizedBox(
              width: 560,
              height: MediaQuery.sizeOf(context).height * .55,
              child: Column(children: [
                CheckboxListTile(
                    title: const Text('整组分P'),
                    value: _selected.length == widget.video.parts.length,
                    onChanged: (selected) => setState(() {
                          _selected.clear();
                          if (selected == true) {
                            _selected.addAll(
                                widget.video.parts.map((part) => part.cid));
                          }
                        })),
                Expanded(
                    child: ListView.builder(
                        itemCount: widget.video.parts.length,
                        itemBuilder: (context, index) {
                          final part = widget.video.parts[index];
                          return CheckboxListTile(
                              value: _selected.contains(part.cid),
                              title: Text('P${part.page} ${part.title}',
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle:
                                  Text(studyTime(part.duration.inSeconds)),
                              onChanged: (selected) => setState(() {
                                    if (selected == true) {
                                      _selected.add(part.cid);
                                    } else {
                                      _selected.remove(part.cid);
                                    }
                                  }));
                        })),
              ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.pop(
                        context,
                        widget.video.parts
                            .where((part) => _selected.contains(part.cid))
                            .toList()),
                child: const Text('加入列表')),
          ]);
}

Future<VideoCategory?> studyPickCategory(
        BuildContext context, List<VideoCategory> categories) =>
    showDialog<VideoCategory>(
        context: context,
        builder: (_) => _StudyCategoryPicker(categories: categories));

class _StudyCategoryPicker extends StatefulWidget {
  const _StudyCategoryPicker({required this.categories});
  final List<VideoCategory> categories;
  @override
  State<_StudyCategoryPicker> createState() => _StudyCategoryPickerState();
}

class _StudyCategoryPickerState extends State<_StudyCategoryPicker> {
  final _query = TextEditingController();
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.text.trim().toLowerCase();
    final rows = widget.categories
        .where((category) => category.path.toLowerCase().contains(query))
        .toList();
    return AlertDialog(
        title: const Text('课程分类'),
        content: SizedBox(
            width: 540,
            height: MediaQuery.sizeOf(context).height * .6,
            child: Column(children: [
              TextField(
                  controller: _query,
                  decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search), hintText: '课程或分类名称'),
                  onChanged: (_) => setState(() {})),
              const SizedBox(height: 8),
              Expanded(
                  child: rows.isEmpty
                      ? const StudyEmpty('暂无分类')
                      : ListView.builder(
                          itemCount: rows.length,
                          itemBuilder: (context, index) {
                            final category = rows[index];
                            return ListTile(
                                leading: const Icon(Icons.folder_outlined),
                                title: Text(category.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(category.path,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                trailing: Text('${category.videoCount}'),
                                onTap: () => Navigator.pop(context, category));
                          },
                        )),
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消'))
        ]);
  }
}
