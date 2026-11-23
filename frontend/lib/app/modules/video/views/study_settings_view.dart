import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/study_preferences.dart';
import '../../../../core/services/study_subscription_scheduler.dart';

class StudySettingsView extends StatefulWidget {
  const StudySettingsView(
      {super.key,
      required this.controller,
      this.scheduler,
      this.loadOnOpen = true});
  final StudyPreferencesController controller;
  final StudySubscriptionScheduler? scheduler;
  final bool loadOnOpen;

  @override
  State<StudySettingsView> createState() => _StudySettingsViewState();
}

class _StudySettingsViewState extends State<StudySettingsView> {
  static const _cards = {
    'continue': '继续学习',
    'lists': '学习列表',
    'focus': '专注计时',
    'updates': '订阅更新',
    'shortcuts': '快捷入口',
  };
  static const _actions = {
    'seek_backward': '快退',
    'seek_forward': '快进',
    'play_pause': '播放 / 暂停',
    'none': '无操作',
  };
  bool _allowPop = false;

  @override
  void initState() {
    super.initState();
    if (widget.loadOnOpen && !widget.controller.isLoaded) {
      unawaited(widget.controller.load());
    }
  }

  Future<bool> _confirm(String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(title: Text(title), actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认')),
        ]),
      ) ??
      false;

  Future<void> _leave() async {
    if (widget.controller.saving) return;
    if (widget.controller.dirty && !await _confirm('放弃未保存的设置？')) return;
    if (!mounted) return;
    widget.controller.discardDraft();
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _reload() async {
    if (widget.controller.dirty && !await _confirm('放弃更改并重新加载？')) return;
    if (mounted) await widget.controller.load(discardChanges: true);
  }

  Future<void> _export() async {
    final text = widget.controller.exportJson();
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('导出学习设置'),
              content: SizedBox(
                  width: 520,
                  child: SingleChildScrollView(child: SelectableText(text))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭')),
                TextButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text('复制 JSON'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: text));
                      if (context.mounted) Navigator.pop(context);
                    }),
              ],
            ));
  }

  Future<void> _import() async {
    final input = TextEditingController();
    String? error;
    await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
              builder: (context, setDialogState) => AlertDialog(
                title: const Text('导入学习设置'),
                content: SizedBox(
                    width: 520,
                    child: SingleChildScrollView(
                        child: TextField(
                      key: const ValueKey('study-preferences-import'),
                      controller: input,
                      minLines: 6,
                      maxLines: 14,
                      maxLength: 32768,
                      decoration: InputDecoration(
                          labelText: '设置 JSON',
                          errorText: error,
                          border: const OutlineInputBorder()),
                    ))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消')),
                  TextButton.icon(
                      icon: const Icon(Icons.content_paste),
                      label: const Text('粘贴'),
                      onPressed: () async {
                        final data =
                            await Clipboard.getData(Clipboard.kTextPlain);
                        if (context.mounted && data?.text != null) {
                          input.text = data!.text!;
                        }
                      }),
                  FilledButton.icon(
                      icon: const Icon(Icons.file_download_outlined),
                      label: const Text('导入草稿'),
                      onPressed: () {
                        try {
                          widget.controller.importJson(input.text);
                          Navigator.pop(context);
                        } on FormatException catch (failure) {
                          setDialogState(() => error = failure.message);
                        }
                      }),
                ],
              ),
            ));
    // A dialog can still animate its text field after showDialog completes.
    WidgetsBinding.instance.addPostFrameCallback((_) => input.dispose());
  }

  Widget _heading(String title) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 12),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([
          widget.controller,
          if (widget.scheduler != null) widget.scheduler!
        ]),
        builder: (context, _) {
          final c = widget.controller;
          final p = c.value;
          final enabled = c.isLoaded && !c.loading && !c.saving;
          return PopScope<Object?>(
            canPop: _allowPop || (!c.dirty && !c.saving),
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) unawaited(_leave());
            },
            child: Scaffold(
              appBar: AppBar(title: const Text('学习设置'), actions: [
                IconButton(
                    tooltip: '重新加载',
                    onPressed: c.loading || c.saving ? null : _reload,
                    icon: const Icon(Icons.refresh)),
                PopupMenuButton<String>(
                  tooltip: '设置操作',
                  enabled: enabled,
                  onSelected: (action) async {
                    switch (action) {
                      case 'import':
                        await _import();
                      case 'export':
                        await _export();
                      case 'reset':
                        if (await _confirm('恢复默认设置？')) c.resetDraft();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'import',
                        child: ListTile(
                            leading: Icon(Icons.file_download_outlined),
                            title: Text('导入设置'))),
                    PopupMenuItem(
                        value: 'export',
                        child: ListTile(
                            leading: Icon(Icons.file_upload_outlined),
                            title: Text('导出设置'))),
                    PopupMenuItem(
                        value: 'reset',
                        child: ListTile(
                            leading: Icon(Icons.restore), title: Text('恢复默认'))),
                  ],
                ),
              ]),
              body: Center(
                  child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      if (c.loading) const LinearProgressIndicator(),
                      if (c.error != null) _status(c.error!, error: true),
                      if (c.integrationError != null)
                        _status(c.integrationError!, error: true),
                      _heading('首页'),
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        buildDefaultDragHandles: false,
                        itemCount: p.cardOrder.length,
                        onReorderItem: (oldIndex, newIndex) {
                          if (enabled) {
                            c.reorderCards(oldIndex,
                                newIndex > oldIndex ? newIndex + 1 : newIndex);
                          }
                        },
                        itemBuilder: (context, index) {
                          final id = p.cardOrder[index];
                          final label = _cards[id]!;
                          final controls = Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                IconButton(
                                    tooltip: '上移$label',
                                    icon: const Icon(Icons.arrow_upward),
                                    onPressed: enabled && index > 0
                                        ? () => c.reorderCards(index, index - 1)
                                        : null),
                                IconButton(
                                    tooltip: '下移$label',
                                    icon: const Icon(Icons.arrow_downward),
                                    onPressed: enabled &&
                                            index + 1 < p.cardOrder.length
                                        ? () => c.reorderCards(index, index + 2)
                                        : null),
                                Semantics(
                                    label: '显示$label',
                                    child: Checkbox(
                                        key: ValueKey('study-card-visible-$id'),
                                        value: !p.hiddenCards.contains(id),
                                        onChanged: enabled
                                            ? (value) => c.setCardVisible(
                                                id, value == true)
                                            : null)),
                                Tooltip(
                                    message: '拖动$label',
                                    child: ReorderableDragStartListener(
                                        index: index,
                                        enabled: enabled,
                                        child: const SizedBox(
                                            width: 48,
                                            height: 48,
                                            child: Icon(Icons.drag_handle)))),
                              ]);
                          return Padding(
                            key: ValueKey('study-card-$id'),
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child:
                                LayoutBuilder(builder: (context, constraints) {
                              final title = Text(label,
                                  style: Theme.of(context).textTheme.bodyLarge);
                              if (constraints.maxWidth < 560) {
                                return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [title, controls]);
                              }
                              return Row(
                                  children: [Expanded(child: title), controls]);
                            }),
                          );
                        },
                      ),
                      const Divider(),
                      _heading('订阅'),
                      SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('订阅更新通知'),
                          value: p.subscriptionNotifications,
                          onChanged: enabled
                              ? (value) => c.update(
                                  p.copyWith(subscriptionNotifications: value))
                              : null),
                      SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('订阅定期检查'),
                          value: p.subscriptionBackground,
                          onChanged: enabled
                              ? (value) => c.update(
                                  p.copyWith(subscriptionBackground: value))
                              : null),
                      if (p.subscriptionNotifications &&
                          !(widget.scheduler?.notificationAvailable ?? false))
                        _status('设备通知未接入'),
                      if (widget.scheduler?.lastResult?.notificationStatus ==
                          StudySubscriptionNotificationStatus.declined)
                        _status('设备通知未获授权'),
                      const Divider(),
                      _heading('播放'),
                      _dropdown(
                          '左侧双击',
                          'study-double-tap-left',
                          p.doubleTapLeft,
                          _actions,
                          enabled
                              ? (action) =>
                                  c.update(p.copyWith(doubleTapLeft: action))
                              : null),
                      const SizedBox(height: 16),
                      _dropdown(
                          '中间双击',
                          'study-double-tap-center',
                          p.doubleTapCenter,
                          _actions,
                          enabled
                              ? (action) =>
                                  c.update(p.copyWith(doubleTapCenter: action))
                              : null),
                      const SizedBox(height: 16),
                      _dropdown(
                          '右侧双击',
                          'study-double-tap-right',
                          p.doubleTapRight,
                          _actions,
                          enabled
                              ? (action) =>
                                  c.update(p.copyWith(doubleTapRight: action))
                              : null),
                      _heading('双击区域'),
                      StudyDoubleTapRegionPreview(preferences: p),
                      const SizedBox(height: 16),
                      _regionSlider(
                          '左侧宽度',
                          'study-double-tap-left-width',
                          p.doubleTapLeftWidth,
                          0.1,
                          0.45,
                          7,
                          enabled
                              ? (value) => c
                                  .update(p.copyWith(doubleTapLeftWidth: value))
                              : null),
                      _regionSlider(
                          '右侧宽度',
                          'study-double-tap-right-width',
                          p.doubleTapRightWidth,
                          0.1,
                          0.45,
                          7,
                          enabled
                              ? (value) => c.update(
                                  p.copyWith(doubleTapRightWidth: value))
                              : null),
                      _regionSlider(
                          '区域高度',
                          'study-double-tap-height',
                          p.doubleTapHeight,
                          0.2,
                          1,
                          8,
                          enabled
                              ? (value) =>
                                  c.update(p.copyWith(doubleTapHeight: value))
                              : null),
                      const SizedBox(height: 20),
                      Text('快进 / 快退：${p.seekSeconds} 秒'),
                      Slider(
                          key: const ValueKey('study-seek-seconds'),
                          value: p.seekSeconds.toDouble(),
                          min: 1,
                          max: 120,
                          divisions: 119,
                          label: '${p.seekSeconds} 秒',
                          semanticFormatterCallback: (value) =>
                              '${value.round()} 秒',
                          onChanged: enabled
                              ? (value) => c.update(
                                  p.copyWith(seekSeconds: value.round()))
                              : null),
                      Text('长按倍速：${p.longPressRate.toStringAsFixed(2)} 倍'),
                      Slider(
                          key: const ValueKey('study-long-press-rate'),
                          value: p.longPressRate,
                          min: 1,
                          max: 4,
                          divisions: 12,
                          label: '${p.longPressRate} 倍',
                          semanticFormatterCallback: (value) => '$value 倍',
                          onChanged: enabled
                              ? (value) =>
                                  c.update(p.copyWith(longPressRate: value))
                              : null),
                      const SizedBox(height: 12),
                      _dropdown(
                          '播放布局',
                          'study-layout',
                          p.layout,
                          const {
                            'auto': '自动',
                            'portrait': '竖屏',
                            'landscape': '横屏'
                          },
                          enabled
                              ? (layout) => c.update(p.copyWith(layout: layout))
                              : null),
                    ]),
              )),
              bottomNavigationBar: SafeArea(
                  top: false,
                  child: Center(
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 840),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: LayoutBuilder(builder: (context, constraints) {
                          final status = Expanded(
                              child: Text(c.saving
                                  ? '正在保存'
                                  : c.dirty
                                      ? '未保存'
                                      : c.isLoaded
                                          ? '已同步'
                                          : '尚未加载'));
                          final discard = TextButton(
                              onPressed:
                                  enabled && c.dirty ? c.discardDraft : null,
                              child: const Text('放弃更改'));
                          final save = FilledButton.icon(
                              key: const ValueKey('study-preferences-save'),
                              onPressed: enabled &&
                                      (c.dirty || c.integrationError != null)
                                  ? c.save
                                  : null,
                              icon: const Icon(Icons.save_outlined),
                              label: const Text('保存'));
                          if (constraints.maxWidth < 560) {
                            return Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(children: [status, discard]),
                                  const SizedBox(height: 8),
                                  save
                                ]);
                          }
                          return Row(children: [
                            status,
                            discard,
                            const SizedBox(width: 8),
                            save
                          ]);
                        }),
                      ),
                    ),
                  )),
            ),
          );
        },
      );

  Widget _status(String text, {bool error = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Semantics(
            liveRegion: true,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(error ? Icons.error_outline : Icons.info_outline,
                  size: 20,
                  color: error ? Theme.of(context).colorScheme.error : null),
              const SizedBox(width: 8),
              Expanded(child: Text(text)),
            ])),
      );

  Widget _regionSlider(String title, String key, double value, double min,
          double max, int divisions, ValueChanged<double>? onChanged) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$title：${(value * 100).round()}%'),
          Semantics(
              label: title,
              child: Slider(
                  key: ValueKey(key),
                  value: value,
                  min: min,
                  max: max,
                  divisions: divisions,
                  label: '${(value * 100).round()}%',
                  semanticFormatterCallback: (value) =>
                      '${(value * 100).round()}%',
                  onChanged: onChanged == null
                      ? null
                      : (value) => onChanged((value * 100).round() / 100))),
        ],
      );

  Widget _dropdown(String label, String key, String value,
          Map<String, String> choices, ValueChanged<String>? onChanged) =>
      DropdownButtonFormField<String>(
        key: ValueKey('$key-$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
        items: choices.entries
            .map((entry) => DropdownMenuItem(
                value: entry.key, child: Text(entry.value, maxLines: 2)))
            .toList(),
        onChanged: onChanged == null
            ? null
            : (value) {
                if (value != null) onChanged(value);
              },
      );
}

class StudyDoubleTapRegionPreview extends StatelessWidget {
  const StudyDoubleTapRegionPreview({super.key, required this.preferences});
  final StudyPreferences preferences;

  IconData _icon(String action) => switch (action) {
        'seek_backward' => Icons.fast_rewind,
        'seek_forward' => Icons.fast_forward,
        'play_pause' => Icons.play_arrow,
        _ => Icons.block,
      };

  Widget _region(String id, String label, String action, Color color) =>
      Semantics(
        label: label,
        child: Tooltip(
            message: label,
            child: ColoredBox(
                key: ValueKey('study-double-tap-$id-region'),
                color: color,
                child: Center(
                    child: Icon(_icon(action),
                        size: 20, color: const Color(0xff263238))))),
      );

  @override
  Widget build(BuildContext context) => Center(
          child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: LayoutBuilder(builder: (context, constraints) {
            final p = preferences;
            final top = constraints.maxHeight * (1 - p.doubleTapHeight) / 2;
            final height = constraints.maxHeight * p.doubleTapHeight;
            final left = constraints.maxWidth * p.doubleTapLeftWidth;
            final right = constraints.maxWidth * p.doubleTapRightWidth;
            return ClipRect(
              key: const ValueKey('study-double-tap-preview'),
              child: ColoredBox(
                  color: const Color(0xfff4f5f6),
                  child: Stack(children: [
                    Positioned(
                        left: 0,
                        top: top,
                        width: left,
                        height: height,
                        child: _region(
                            'left',
                            '左侧 ${(p.doubleTapLeftWidth * 100).round()}%',
                            p.doubleTapLeft,
                            const Color(0xffbde8de))),
                    Positioned(
                        left: left,
                        right: right,
                        top: top,
                        height: height,
                        child: _region(
                            'center',
                            '中间 ${(100 * (1 - p.doubleTapLeftWidth - p.doubleTapRightWidth)).round()}%',
                            p.doubleTapCenter,
                            const Color(0xffe3e7eb))),
                    Positioned(
                        right: 0,
                        top: top,
                        width: right,
                        height: height,
                        child: _region(
                            'right',
                            '右侧 ${(p.doubleTapRightWidth * 100).round()}%',
                            p.doubleTapRight,
                            const Color(0xffffd4d1))),
                  ])),
            );
          }),
        ),
      ));
}
