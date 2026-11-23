import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/services/study_media_cache.dart';
import '../../../../shared/widgets/liquid_glass_panel.dart';
import '../controllers/study_controller.dart';
import '../controllers/video_controller.dart';

class StudyPlayerTools extends StatelessWidget {
  const StudyPlayerTools({super.key, required this.player});
  final VideoController player;

  @override
  Widget build(BuildContext context) {
    final study = Get.isRegistered<StudyController>()
        ? Get.find<StudyController>()
        : null;
    return Obx(() {
      final video = player.activeVideo.value;
      final key = video == null ? '' : StudyMediaCache.instance.keyFor(video);
      final progress = StudyMediaCache.instance.progress[key];
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
              icon: const Icon(Icons.edit_note),
              label: const Text('时间点笔记'),
              onPressed: video?.studyItemId == null || study == null
                  ? null
                  : () => _note(context, study, screenshot: false)),
          OutlinedButton.icon(
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('截图笔记'),
              onPressed: video?.studyItemId == null || study == null
                  ? null
                  : () => _note(context, study, screenshot: true)),
          OutlinedButton.icon(
              icon: const Icon(Icons.notes),
              label: const Text('查看笔记'),
              onPressed: video?.studyItemId == null || study == null
                  ? null
                  : () async {
                      await study.refreshNotes(itemId: video!.studyItemId);
                      if (!context.mounted) return;
                      await showLiquidGlassBottomSheet(
                        context: context,
                        showDragHandle: true,
                        builder: (context) => SafeArea(
                            child: Obx(() => ListView(
                                    shrinkWrap: true,
                                    padding: const EdgeInsets.all(16),
                                    children: [
                                      Text('学习笔记',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium),
                                      if (study.notes
                                          .where((note) =>
                                              note.itemId == video.studyItemId)
                                          .isEmpty)
                                        const Padding(
                                            padding: EdgeInsets.all(24),
                                            child: Text('暂无笔记')),
                                      for (final note in study.notes.where(
                                          (note) =>
                                              note.itemId == video.studyItemId))
                                        ListTile(
                                            leading: const Icon(
                                                Icons.play_circle_outline),
                                            title: Text(note.content),
                                            subtitle: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(_time(
                                                      note.positionSeconds)),
                                                  if (note.imageData
                                                          ?.isNotEmpty ==
                                                      true)
                                                    Image.memory(
                                                        base64Decode(note
                                                            .imageData!
                                                            .split(',')
                                                            .last),
                                                        height: 120,
                                                        errorBuilder: (_, __,
                                                                ___) =>
                                                            const Icon(Icons
                                                                .broken_image_outlined)),
                                                ]),
                                            onTap: () {
                                              Navigator.pop(context);
                                              player.player?.seek(Duration(
                                                  seconds:
                                                      note.positionSeconds));
                                            }),
                                    ]))),
                      );
                    }),
          OutlinedButton.icon(
              icon: Icon(
                  video != null && StudyMediaCache.instance.isDownloading(video)
                      ? Icons.pause
                      : Icons.download_outlined),
              label: Text(progress == 1 ? '已缓存' : '离线缓存'),
              onPressed: video == null
                  ? null
                  : () async {
                      if (StudyMediaCache.instance.isDownloading(video)) {
                        StudyMediaCache.instance.pause(video);
                      } else {
                        try {
                          await player.downloadCurrent();
                        } catch (error) {
                          if (context.mounted) Get.snackbar('缓存失败', '$error');
                        }
                      }
                    }),
          if (study != null)
            OutlinedButton.icon(
                icon: Icon(study.focusRunning.value
                    ? Icons.pause_circle_outline
                    : Icons.timer_outlined),
                label: Text(study.focusRunning.value ? '暂停专注' : '开始专注'),
                onPressed: study.focusRunning.value
                    ? study.pauseFocus
                    : study.startFocus),
          if (study != null && study.focusSeconds.value > 0)
            TextButton(
                onPressed: study.finishFocus,
                child: Text('记录专注 ${_time(study.focusSeconds.value)}')),
        ]),
        if (progress != null && progress != 1)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(
                  value: progress < 0 ? null : progress)),
        if (StudyMediaCache.instance.errors[key] != null)
          Text(StudyMediaCache.instance.errors[key]!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ]);
    });
  }

  Future<void> _note(BuildContext context, StudyController study,
      {required bool screenshot}) async {
    final itemId = player.activeVideo.value?.studyItemId;
    if (itemId == null) return;
    final seconds = player.player?.state.position.inSeconds ?? 0;
    Uint8List? bytes;
    try {
      if (screenshot) {
        bytes = await player.player?.screenshot(format: 'image/jpeg');
        if (bytes == null) throw StateError('当前视频尚无可用画面');
        if (bytes.length > 2 * 1024 * 1024) throw StateError('截图超过2MB，请使用文字笔记');
      }
      if (!context.mounted) return;
      await showDialog<void>(
          context: context,
          builder: (_) => _StudyNoteDialog(
              study: study, itemId: itemId, position: seconds, bytes: bytes));
    } catch (error) {
      Get.snackbar('笔记', '$error');
    }
  }

  static String _time(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class _StudyNoteDialog extends StatefulWidget {
  const _StudyNoteDialog(
      {required this.study,
      required this.itemId,
      required this.position,
      this.bytes});
  final StudyController study;
  final int itemId;
  final int position;
  final Uint8List? bytes;
  @override
  State<_StudyNoteDialog> createState() => _StudyNoteDialogState();
}

class _StudyNoteDialogState extends State<_StudyNoteDialog> {
  final _text = TextEditingController();
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LiquidGlassAlertDialog(
        title: Text('笔记 · ${StudyPlayerTools._time(widget.position)}'),
        content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (widget.bytes != null)
                Image.memory(widget.bytes!, height: 180),
              TextField(
                  controller: _text,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(labelText: '笔记内容')),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
            ]))),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('取消')),
          FilledButton(
              onPressed: _saving
                  ? null
                  : () async {
                      setState(() {
                        _saving = true;
                        _error = null;
                      });
                      final ok = await widget.study.saveNote(
                          itemId: widget.itemId,
                          positionSeconds: widget.position,
                          content:
                              _text.text.trim().isEmpty && widget.bytes != null
                                  ? '截图笔记'
                                  : _text.text,
                          imageData: widget.bytes == null
                              ? null
                              : base64Encode(widget.bytes!));
                      if (!context.mounted) return;
                      if (ok) {
                        Navigator.pop(context);
                      } else {
                        setState(() {
                          _saving = false;
                          _error = widget.study.errors['write'];
                        });
                      }
                    },
              child: Text(_saving ? '保存中' : '保存')),
        ],
      );
}
