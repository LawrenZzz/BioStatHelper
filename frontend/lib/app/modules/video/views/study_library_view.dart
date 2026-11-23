import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../shared/models/category_model.dart';
import '../../../../shared/models/study_model.dart';
import '../controllers/study_controller.dart';
import 'study_search_view.dart';
import 'study_widgets.dart';

class StudyNotesView extends StatefulWidget {
  const StudyNotesView({super.key, required this.controller, this.item});
  final StudyController controller;
  final StudyItem? item;
  @override
  State<StudyNotesView> createState() => _StudyNotesViewState();
}

class _StudyNotesViewState extends State<StudyNotesView> {
  final _query = TextEditingController();
  StudyController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    unawaited(c.refreshNotes());
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('时间点笔记'), actions: [
          IconButton(
              tooltip: '新建笔记',
              icon: const Icon(Icons.note_add_outlined),
              onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) =>
                      _StudyNoteEditor(controller: c, item: widget.item))),
          IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh),
              onPressed: c.refreshNotes),
        ]),
        body: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Obx(() {
            final rows = c.notes
                .where((note) =>
                    (widget.item == null || note.itemId == widget.item!.id) &&
                    note.content
                        .toLowerCase()
                        .contains(_query.text.trim().toLowerCase()))
                .toList();
            final saving = c.writing;
            return RefreshIndicator(
                onRefresh: c.refreshNotes,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                      16, 8, 16, studyBottomPadding(context)),
                  children: [
                    if (widget.item != null)
                      Text(widget.item!.title,
                          style: Theme.of(context).textTheme.titleSmall),
                    TextField(
                        controller: _query,
                        decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search), hintText: '搜索笔记'),
                        onChanged: (_) => setState(() {})),
                    StudyErrors(controller: c, sections: const ['notes']),
                    if (c.busy.contains('notes'))
                      const LinearProgressIndicator(),
                    if (rows.isEmpty && !c.busy.contains('notes'))
                      const StudyEmpty('暂无笔记', icon: Icons.edit_note),
                    for (final note in rows)
                      Builder(builder: (context) {
                        final item = c.items
                            .firstWhereOrNull((item) => item.id == note.itemId);
                        return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Expanded(
                                        child: Text(
                                            item?.title ??
                                                '学习项 #${note.itemId}',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall)),
                                    IconButton(
                                        tooltip: '编辑笔记',
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: saving
                                            ? null
                                            : () => showDialog<bool>(
                                                context: context,
                                                builder: (_) =>
                                                    _StudyNoteEditor(
                                                        controller: c,
                                                        item: item,
                                                        note: note))),
                                    IconButton(
                                        tooltip: '删除笔记',
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: saving
                                            ? null
                                            : () async {
                                                if (await studyConfirm(context,
                                                    '删除笔记', '删除这条时间点笔记？')) {
                                                  await c.deleteNote(note);
                                                }
                                              }),
                                  ]),
                                  TextButton.icon(
                                      icon: const Icon(Icons.play_arrow),
                                      label:
                                          Text(studyTime(note.positionSeconds)),
                                      onPressed: item == null ||
                                              c.busy.contains('play')
                                          ? null
                                          : () => c.openItem(item,
                                              positionSeconds:
                                                  note.positionSeconds)),
                                  SelectableText(note.content),
                                  if (note.imageData?.isNotEmpty ?? false)
                                    Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child:
                                            _StudyNoteImage(note.imageData!)),
                                  const Divider(),
                                ]));
                      }),
                  ],
                ));
          }),
        )),
      );
}

class _StudyNoteImage extends StatelessWidget {
  const _StudyNoteImage(this.value);
  final String value;
  @override
  Widget build(BuildContext context) {
    try {
      final data = value.startsWith('data:')
          ? value.substring(value.indexOf(',') + 1)
          : value;
      return Image.memory(base64Decode(data),
          height: 180,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Text('图片无法读取'));
    } catch (_) {
      return const Text('图片无法读取');
    }
  }
}

class _StudyNoteEditor extends StatefulWidget {
  const _StudyNoteEditor({required this.controller, this.item, this.note});
  final StudyController controller;
  final StudyItem? item;
  final StudyNote? note;
  @override
  State<_StudyNoteEditor> createState() => _StudyNoteEditorState();
}

class _StudyNoteEditorState extends State<_StudyNoteEditor> {
  late final TextEditingController _content;
  late final TextEditingController _seconds;
  int? _itemId;
  String? _image;
  String? _error;
  final _form = GlobalKey<FormState>();
  @override
  void initState() {
    super.initState();
    _content = TextEditingController(text: widget.note?.content);
    _seconds = TextEditingController(
        text:
            '${widget.note?.positionSeconds ?? widget.item?.positionSeconds ?? 0}');
    _itemId = widget.note?.itemId ?? widget.item?.id;
    _image = widget.note?.imageData;
  }

  @override
  void dispose() {
    _content.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Obx(() {
        final c = widget.controller;
        final saving = c.writing;
        return PopScope(
            canPop: !saving,
            child: AlertDialog(
              title: Text(widget.note == null ? '新建时间点笔记' : '编辑笔记'),
              content: SizedBox(
                  width: 560,
                  child: SingleChildScrollView(
                      child: Form(
                    key: _form,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.note == null && widget.item == null)
                            DropdownButtonFormField<int>(
                                initialValue: _itemId,
                                isExpanded: true,
                                decoration:
                                    const InputDecoration(labelText: '学习项'),
                                items: c.items
                                    .map((item) => DropdownMenuItem(
                                        value: item.id,
                                        child: Text(item.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis)))
                                    .toList(),
                                onChanged: saving
                                    ? null
                                    : (value) =>
                                        setState(() => _itemId = value),
                                validator: (value) =>
                                    value == null ? '请选择学习项' : null),
                          TextFormField(
                              controller: _seconds,
                              enabled: !saving,
                              decoration:
                                  const InputDecoration(labelText: '时间点（秒）'),
                              keyboardType: TextInputType.number,
                              validator: (value) =>
                                  (int.tryParse(value ?? '') ?? -1) < 0
                                      ? '请输入非负整数'
                                      : null),
                          TextFormField(
                              controller: _content,
                              enabled: !saving,
                              minLines: 4,
                              maxLines: 10,
                              decoration:
                                  const InputDecoration(labelText: '笔记'),
                              validator: (value) =>
                                  value?.trim().isEmpty ?? true
                                      ? '请输入笔记'
                                      : null),
                          const SizedBox(height: 8),
                          if (_image != null) _StudyNoteImage(_image!),
                          Align(
                              alignment: Alignment.centerLeft,
                              child: IconButton(
                                  tooltip: '附加图片',
                                  icon: const Icon(
                                      Icons.add_photo_alternate_outlined),
                                  onPressed: saving
                                      ? null
                                      : () async {
                                          try {
                                            final result = await FilePicker
                                                .platform
                                                .pickFiles(
                                                    type: FileType.image,
                                                    withData: true);
                                            if (!mounted || result == null) {
                                              return;
                                            }
                                            final bytes =
                                                result.files.single.bytes;
                                            if (bytes == null ||
                                                bytes.length >
                                                    2 * 1024 * 1024) {
                                              throw const FormatException(
                                                  '图片须小于 2 MB');
                                            }
                                            setState(() {
                                              _image = base64Encode(bytes);
                                              _error = null;
                                            });
                                          } catch (error) {
                                            if (mounted) {
                                              setState(() => _error = '$error');
                                            }
                                          }
                                        })),
                          if (_error != null)
                            Text(_error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                          StudyErrors(controller: c),
                        ]),
                  ))),
              actions: [
                TextButton(
                    onPressed: saving ? null : () => Navigator.pop(context),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: saving
                        ? null
                        : () async {
                            if (!_form.currentState!.validate() ||
                                _itemId == null) {
                              return;
                            }
                            final saved = await c.saveNote(
                                note: widget.note,
                                itemId: _itemId!,
                                positionSeconds: int.parse(_seconds.text),
                                content: _content.text,
                                imageData: _image);
                            if (saved && context.mounted) {
                              Navigator.pop(context, true);
                            }
                          },
                    child: Text(saving ? '保存中' : '保存')),
              ],
            ));
      });
}

class StudyHistoryView extends StatelessWidget {
  const StudyHistoryView({super.key, required this.controller});
  final StudyController controller;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('学习历史'), actions: [
        IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: controller.refreshItems),
      ]),
      body: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: Obx(() {
          final rows = controller.items
              .where((item) =>
                  item.positionSeconds > 0 ||
                  item.status == StudyStatus.completed)
              .toList()
            ..sort((a, b) => (b.updatedAt ?? DateTime(1970))
                .compareTo(a.updatedAt ?? DateTime(1970)));
          return RefreshIndicator(
              onRefresh: controller.refreshItems,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding:
                    EdgeInsets.fromLTRB(16, 8, 16, studyBottomPadding(context)),
                children: [
                  StudyErrors(
                      controller: controller, sections: const ['items']),
                  if (controller.busy.contains('items'))
                    const LinearProgressIndicator(),
                  if (rows.isEmpty)
                    const StudyEmpty('暂无学习历史', icon: Icons.history),
                  for (final item in rows)
                    StudyItemRow(
                        item: item,
                        onPlay: controller.busy.contains('play')
                            ? null
                            : () => controller.openItem(item)),
                ],
              ));
        }),
      )));
}

class StudyStatsView extends StatefulWidget {
  const StudyStatsView({super.key, required this.controller});
  final StudyController controller;
  @override
  State<StudyStatsView> createState() => _StudyStatsViewState();
}

class _StudyStatsViewState extends State<StudyStatsView> {
  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    await widget.controller.refreshStats();
    await widget.controller.refreshFocusHistory();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
        appBar: AppBar(title: const Text('学习统计'), actions: [
          IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh),
              onPressed: _refresh),
        ]),
        body: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Obx(() {
            final stats = c.stats.value;
            final maxSeconds = stats.daily
                .fold<int>(1, (value, day) => math.max(value, day.seconds));
            return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                      16, 8, 16, studyBottomPadding(context)),
                  children: [
                    StudyErrors(
                        controller: c, sections: const ['stats', 'focus']),
                    if (c.busy.contains('stats') || c.busy.contains('focus'))
                      const LinearProgressIndicator(),
                    Wrap(spacing: 24, runSpacing: 20, children: [
                      for (final metric in [
                        ('今日专注', studyTime(stats.todaySeconds)),
                        ('累计专注', studyTime(stats.totalSeconds)),
                        ('专注次数', '${stats.sessions}'),
                        ('已完成', '${stats.completedItems}'),
                        ('连续学习', '${stats.streakDays} 天')
                      ])
                        SizedBox(
                            width: 140,
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(metric.$1,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                  Text(metric.$2,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge),
                                ])),
                    ]),
                    const StudyHeading('每日专注'),
                    if (stats.daily.isEmpty)
                      const StudyEmpty('暂无专注记录', icon: Icons.insights_outlined),
                    for (final day in stats.daily)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(child: Text(day.date)),
                                  Text(studyTime(day.seconds))
                                ]),
                                const SizedBox(height: 4),
                                LinearProgressIndicator(
                                    value: day.seconds / maxSeconds,
                                    minHeight: 5),
                              ])),
                    const StudyHeading('专注记录'),
                    for (final row in c.focusHistory)
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(studyBool(row['completed'])
                              ? Icons.task_alt
                              : Icons.timer_outlined),
                          title:
                              Text(studyTime(studyInt(row['elapsed_seconds']))),
                          subtitle: Text('${row['started_at'] ?? ''}'),
                          trailing: Text(
                              studyBool(row['completed']) ? '已完成' : '已结束')),
                  ],
                ));
          }),
        )));
  }
}

class StudySubscriptionsView extends StatefulWidget {
  const StudySubscriptionsView({super.key, required this.controller});
  final StudyController controller;
  @override
  State<StudySubscriptionsView> createState() => _StudySubscriptionsViewState();
}

class _StudySubscriptionsViewState extends State<StudySubscriptionsView> {
  bool _unread = true;
  int? _sourceId;
  final _selectedSources = <int>{};
  final _selectedUpdates = <int>{};
  StudyController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    unawaited(c.refreshSubscriptions());
    unawaited(c.refreshUpdates());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('订阅与更新'), actions: [
        IconButton(
            tooltip: '添加订阅',
            icon: const Icon(Icons.add_alert_outlined),
            onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => _StudySubscriptionEditor(controller: c))),
        Obx(() => IconButton(
            tooltip: '检查更新',
            icon: const Icon(Icons.refresh),
            onPressed: c.writing ? null : c.checkUpdates)),
      ]),
      body: Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: Obx(() {
          final sourceIds = c.subscriptions.map((s) => s.id).toSet();
          final filter = sourceIds.contains(_sourceId) ? _sourceId : null;
          final rows = c.updates
              .where((update) =>
                  (!_unread || !update.read) &&
                  (filter == null || update.subscriptionId == filter))
              .toList()
            ..sort((a, b) {
              final read = (a.read ? 1 : 0).compareTo(b.read ? 1 : 0);
              return read != 0
                  ? read
                  : (b.discoveredAt ?? DateTime(1970))
                      .compareTo(a.discoveredAt ?? DateTime(1970));
            });
          final selectedSources = _selectedSources.intersection(sourceIds);
          final selectedUpdates =
              _selectedUpdates.intersection(rows.map((u) => u.id).toSet());
          final saving = c.writing;
          return ListView(
              padding:
                  EdgeInsets.fromLTRB(16, 8, 16, studyBottomPadding(context)),
              children: [
                StudyErrors(
                    controller: c,
                    sections: const ['subscriptions', 'updates', 'biliDetail']),
                if (saving || c.busy.contains('updates'))
                  const LinearProgressIndicator(),
                const StudyHeading('订阅来源'),
                if (c.subscriptions.isNotEmpty)
                  Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Checkbox(
                            value: selectedSources.length ==
                                c.subscriptions.length,
                            onChanged: saving
                                ? null
                                : (value) => setState(() {
                                      _selectedSources.clear();
                                      if (value == true) {
                                        _selectedSources.addAll(sourceIds);
                                      }
                                    })),
                        Text('已选 ${selectedSources.length} 个来源'),
                        PopupMenuButton<String>(
                            tooltip: '批量管理订阅',
                            enabled: !saving && selectedSources.isNotEmpty,
                            icon: const Icon(Icons.more_horiz),
                            itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'pause', child: Text('暂停所选')),
                                  PopupMenuItem(
                                      value: 'resume', child: Text('恢复所选')),
                                  PopupMenuItem(
                                      value: 'delete', child: Text('删除所选')),
                                ],
                            onSelected: (action) async {
                              if (action == 'delete' &&
                                  !await studyConfirm(context, '删除所选订阅',
                                      '删除 ${selectedSources.length} 个订阅及其更新记录？学习清单和笔记保留。')) {
                                return;
                              }
                              if (await c.batchSubscriptions(
                                      selectedSources, action) &&
                                  mounted) {
                                setState(_selectedSources.clear);
                              }
                            }),
                      ]),
                if (c.subscriptions.isEmpty)
                  const StudyEmpty('暂无订阅', icon: Icons.notifications_none),
                for (final subscription in c.subscriptions)
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Checkbox(
                          value: selectedSources.contains(subscription.id),
                          onChanged: saving
                              ? null
                              : (value) => setState(() {
                                    value == true
                                        ? _selectedSources.add(subscription.id)
                                        : _selectedSources
                                            .remove(subscription.id);
                                  })),
                      title: Text(subscription.name,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(!subscription.enabled
                          ? '已暂停'
                          : subscription.source == 'nas'
                              ? 'NAS 课程'
                              : subscription.kind == 'up'
                                  ? 'B站 UP主'
                                  : 'B站合集'),
                      trailing: PopupMenuButton<String>(
                          tooltip: '订阅操作',
                          enabled: !saving,
                          itemBuilder: (_) => [
                                PopupMenuItem(
                                    value: 'pause',
                                    child: Text(subscription.enabled
                                        ? '暂停订阅'
                                        : '恢复订阅')),
                                if (subscription.source == 'bilibili')
                                  const PopupMenuItem(
                                      value: 'history', child: Text('导入历史内容')),
                                const PopupMenuItem(
                                    value: 'edit', child: Text('编辑订阅')),
                                const PopupMenuItem(
                                    value: 'remove', child: Text('删除订阅'))
                              ],
                          onSelected: (action) async {
                            if (action == 'pause') {
                              await c.setSubscriptionEnabled(
                                  subscription, !subscription.enabled);
                            } else if (action == 'history') {
                              await c.importSubscriptionHistory(subscription);
                            } else if (action == 'edit') {
                              await showDialog<bool>(
                                  context: context,
                                  builder: (_) => _StudySubscriptionEditor(
                                      controller: c,
                                      subscription: subscription));
                            } else if (await studyConfirm(context, '删除订阅',
                                '不再订阅“${subscription.name}”？')) {
                              await c.deleteSubscription(subscription);
                            }
                          })),
                StudyHeading('订阅更新',
                    action: FilterChip(
                        label: const Text('仅未读'),
                        selected: _unread,
                        onSelected: (value) =>
                            setState(() => _unread = value))),
                DropdownButtonFormField<int?>(
                    key: ValueKey(filter),
                    initialValue: filter,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '来源筛选'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('全部来源')),
                      for (final subscription in c.subscriptions)
                        DropdownMenuItem(
                            value: subscription.id,
                            child: Text(subscription.name,
                                overflow: TextOverflow.ellipsis))
                    ],
                    onChanged: (value) => setState(() => _sourceId = value)),
                if (rows.isNotEmpty)
                  Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Checkbox(
                            value: selectedUpdates.length == rows.length,
                            onChanged: saving
                                ? null
                                : (value) => setState(() {
                                      _selectedUpdates.clear();
                                      if (value == true) {
                                        _selectedUpdates
                                            .addAll(rows.map((u) => u.id));
                                      }
                                    })),
                        Text('已选 ${selectedUpdates.length} 条更新'),
                        IconButton(
                            tooltip: '所选标为已读',
                            icon: const Icon(Icons.mark_email_read_outlined),
                            onPressed: saving || selectedUpdates.isEmpty
                                ? null
                                : () async {
                                    if (await c.batchUpdates(selectedUpdates) &&
                                        mounted) {
                                      setState(_selectedUpdates.clear);
                                    }
                                  }),
                      ]),
                if (rows.isEmpty)
                  const StudyEmpty('暂无更新', icon: Icons.inbox_outlined),
                for (var i = 0; i < rows.length; i++) ...[
                  if (i == 0 ||
                      _updateGroup(rows[i]) != _updateGroup(rows[i - 1]))
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(_updateGroup(rows[i]),
                            style: Theme.of(context).textTheme.titleSmall)),
                  for (final update in [rows[i]])
                    StudyItemRow(
                        item: update.toItem(0),
                        onPlay: null,
                        actions: [
                          Checkbox(
                              value: selectedUpdates.contains(update.id),
                              onChanged: saving
                                  ? null
                                  : (value) => setState(() {
                                        value == true
                                            ? _selectedUpdates.add(update.id)
                                            : _selectedUpdates
                                                .remove(update.id);
                                      })),
                          if (!update.read)
                            IconButton(
                                tooltip: '标为已读',
                                icon:
                                    const Icon(Icons.mark_email_read_outlined),
                                onPressed: saving
                                    ? null
                                    : () => c.markUpdateRead(update)),
                          FilledButton.tonalIcon(
                              icon: const Icon(Icons.playlist_add),
                              label: const Text('加入学习列表'),
                              onPressed: saving || c.busy.contains('biliDetail')
                                  ? null
                                  : () async {
                                      final saved = await studyAddLearningItem(
                                          context, c, update.toItem(0));
                                      if (saved) await c.markUpdateRead(update);
                                    }),
                        ]),
                ],
              ]);
        }),
      )));

  String _updateGroup(StudyUpdate update) =>
      '${update.read ? '已读' : '未读'} · ${update.discoveredAt?.toIso8601String().substring(0, 10) ?? '日期未知'}';
}

class _StudySubscriptionEditor extends StatefulWidget {
  const _StudySubscriptionEditor({required this.controller, this.subscription});
  final StudyController controller;
  final StudySubscription? subscription;
  @override
  State<_StudySubscriptionEditor> createState() =>
      _StudySubscriptionEditorState();
}

class _StudySubscriptionEditorState extends State<_StudySubscriptionEditor> {
  late final TextEditingController _name;
  late final TextEditingController _mid;
  late final TextEditingController _season;
  late String _source;
  late String _kind;
  VideoCategory? _category;
  final _form = GlobalKey<FormState>();
  @override
  void initState() {
    super.initState();
    final subscription = widget.subscription;
    _name = TextEditingController(text: subscription?.name);
    _mid = TextEditingController(
        text:
            '${subscription?.sourceData['mid'] ?? subscription?.sourceData['owner_mid'] ?? ''}');
    _season = TextEditingController(
        text: '${subscription?.sourceData['season_id'] ?? ''}');
    _source = subscription?.source ?? 'nas';
    _kind = subscription?.kind ?? 'category';
    if (subscription?.nasCategoryId != null) {
      _category = VideoCategory(
          id: subscription!.nasCategoryId!, name: subscription.name);
    }
    unawaited(widget.controller.loadCategories());
  }

  @override
  void dispose() {
    _name.dispose();
    _mid.dispose();
    _season.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Obx(() {
        final c = widget.controller;
        final saving = c.writing;
        return PopScope(
            canPop: !saving,
            child: AlertDialog(
              title: Text(widget.subscription == null ? '添加订阅' : '编辑订阅'),
              content: SizedBox(
                  width: 480,
                  child: SingleChildScrollView(
                      child: Form(
                    key: _form,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.subscription == null)
                            SegmentedButton<String>(
                                segments: const [
                                  ButtonSegment(
                                      value: 'nas', label: Text('NAS')),
                                  ButtonSegment(
                                      value: 'bilibili', label: Text('B站')),
                                ],
                                selected: {
                                  _source
                                },
                                onSelectionChanged: saving
                                    ? null
                                    : (value) => setState(() {
                                          _source = value.first;
                                          _kind = _source == 'nas'
                                              ? 'category'
                                              : 'up';
                                        })),
                          TextFormField(
                              controller: _name,
                              enabled: !saving,
                              decoration:
                                  const InputDecoration(labelText: '名称'),
                              validator: (value) =>
                                  value?.trim().isEmpty ?? true
                                      ? '请输入名称'
                                      : null),
                          if (_source == 'nas')
                            TextButton.icon(
                                icon: const Icon(Icons.folder_open_outlined),
                                label: Text(_category?.name ?? '选择课程分类',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                onPressed: saving ||
                                        c.busy.contains('categories')
                                    ? null
                                    : () async {
                                        final category =
                                            await studyPickCategory(
                                                context, c.categories.toList());
                                        if (mounted && category != null) {
                                          setState(() => _category = category);
                                        }
                                      }),
                          if (_source == 'bilibili') ...[
                            if (widget.subscription == null)
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  child: SegmentedButton<String>(
                                      segments: const [
                                        ButtonSegment(
                                            value: 'up', label: Text('UP主')),
                                        ButtonSegment(
                                            value: 'collection',
                                            label: Text('合集'))
                                      ],
                                      selected: {
                                        _kind
                                      },
                                      onSelectionChanged: saving
                                          ? null
                                          : (value) => setState(
                                              () => _kind = value.first))),
                            TextFormField(
                                controller: _mid,
                                enabled: !saving,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                    labelText: _kind == 'up'
                                        ? 'UP主 UID'
                                        : '合集所属 UP主 UID'),
                                validator: (value) =>
                                    (int.tryParse(value ?? '') ?? 0) <= 0
                                        ? '请输入有效 UID'
                                        : null),
                            if (_kind == 'collection')
                              TextFormField(
                                  controller: _season,
                                  enabled: !saving,
                                  keyboardType: TextInputType.number,
                                  decoration:
                                      const InputDecoration(labelText: '合集 ID'),
                                  validator: (value) =>
                                      (int.tryParse(value ?? '') ?? 0) <= 0
                                          ? '请输入有效合集 ID'
                                          : null),
                          ],
                          StudyErrors(
                              controller: c, sections: const ['categories']),
                        ]),
                  ))),
              actions: [
                TextButton(
                    onPressed: saving ? null : () => Navigator.pop(context),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: saving || (_source == 'nas' && _category == null)
                        ? null
                        : () async {
                            if (!_form.currentState!.validate()) return;
                            final saved = await c.saveSubscription(
                                subscription: widget.subscription,
                                name: _name.text,
                                source: _source,
                                kind: _kind,
                                categoryId: _category?.id,
                                sourceData: {
                                  if (_source == 'bilibili' && _kind == 'up')
                                    'mid': _mid.text.trim(),
                                  if (_source == 'bilibili' &&
                                      _kind == 'collection') ...{
                                    'owner_mid': _mid.text.trim(),
                                    'season_id': _season.text.trim()
                                  },
                                });
                            if (saved && context.mounted) {
                              Navigator.pop(context, true);
                            }
                          },
                    child: Text(saving ? '保存中' : '保存')),
              ],
            ));
      });
}

class StudyTransferView extends StatefulWidget {
  const StudyTransferView({super.key, required this.controller});
  final StudyController controller;
  @override
  State<StudyTransferView> createState() => _StudyTransferViewState();
}

class _StudyTransferViewState extends State<StudyTransferView> {
  final _json = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _notice;
  @override
  void dispose() {
    _json.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await task();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('学习资料 JSON')),
        body: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: ListView(
              padding:
                  EdgeInsets.fromLTRB(16, 12, 16, studyBottomPadding(context)),
              children: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                      icon: const Icon(Icons.file_download_outlined),
                      label: const Text('导出 JSON'),
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                                final value =
                                    await widget.controller.exportData();
                                if (value == null || !mounted) return;
                                _json.text = value;
                                final bytes =
                                    Uint8List.fromList(utf8.encode(value));
                                final path = await FilePicker.platform.saveFile(
                                    dialogTitle: '导出学习资料',
                                    fileName:
                                        'study-${DateTime.now().toIso8601String().substring(0, 10)}.json',
                                    type: FileType.custom,
                                    allowedExtensions: ['json'],
                                    bytes: bytes);
                                if (path != null && !kIsWeb) {
                                  await File(path).writeAsBytes(bytes);
                                }
                                if (path != null && mounted) {
                                  setState(() => _notice = '已导出学习资料');
                                }
                              })),
                  OutlinedButton.icon(
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('打开 JSON'),
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                                final result = await FilePicker.platform
                                    .pickFiles(
                                        type: FileType.custom,
                                        allowedExtensions: ['json'],
                                        withData: true);
                                if (!mounted || result == null) return;
                                final bytes = result.files.single.bytes;
                                if (bytes == null) {
                                  throw const FormatException('无法读取文件');
                                }
                                final value = utf8.decode(bytes);
                                if (jsonDecode(value) is! Map) {
                                  throw const FormatException('请选择学习资料 JSON');
                                }
                                _json.text = value;
                              })),
                  OutlinedButton.icon(
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: const Text('导入到账号'),
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                                if (!await studyConfirm(context, '导入学习资料',
                                    '将此 JSON 中的学习资料合并到当前账号？')) {
                                  return;
                                }
                                final saved = await widget.controller
                                    .importData(_json.text);
                                if (saved && mounted) {
                                  setState(() => _notice = '已导入学习资料');
                                }
                              })),
                ]),
                if (_busy)
                  const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator()),
                StudyErrors(
                    controller: widget.controller,
                    sections: const ['transfer']),
                if (_error != null)
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                if (_notice != null)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(_notice!)),
                const SizedBox(height: 16),
                TextField(
                    controller: _json,
                    enabled: !_busy,
                    minLines: 12,
                    maxLines: 28,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    decoration: const InputDecoration(
                        labelText: '学习资料 JSON',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder())),
              ]),
        )),
      );
}
