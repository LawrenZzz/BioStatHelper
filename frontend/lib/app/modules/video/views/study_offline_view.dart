import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/services/study_media_cache.dart';
import '../../../../core/services/study_offline_assets.dart';
import '../../../../shared/models/study_model.dart';
import '../../../../shared/models/video_model.dart';
import '../../../routes/app_routes.dart';
import '../controllers/study_controller.dart';
import '../controllers/video_controller.dart';
import 'study_widgets.dart';

class StudyOfflineView extends StatefulWidget {
  const StudyOfflineView({super.key, required this.controller});
  final StudyController controller;
  @override
  State<StudyOfflineView> createState() => _StudyOfflineViewState();
}

class _StudyOfflineViewState extends State<StudyOfflineView> {
  StudyMediaCache get _cache => widget.controller.mediaCache;
  List<StudyCacheEntry> _entries = [];
  String? _loadedScope;
  bool _loading = false;
  bool _scheduled = false;
  bool _refreshPending = false;
  final _busy = <String>{};
  String? _error;
  String? _actionError;
  Worker? _cacheWorker;

  @override
  void initState() {
    super.initState();
    _cacheWorker = ever(_cache.revision, (_) => _scheduleRefresh());
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _cacheWorker?.dispose();
    super.dispose();
  }

  void _scheduleRefresh() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    if (_loading) {
      _refreshPending = true;
      return;
    }
    final scope = _cache.scopeKey;
    setState(() {
      _loading = true;
      _error = null;
      if (_loadedScope != scope) {
        _entries = [];
        _actionError = null;
      }
      _loadedScope = scope;
    });
    try {
      final entries = await _cache.entries();
      if (mounted && scope == _cache.scopeKey) {
        setState(() => _entries = entries);
      }
    } catch (error) {
      if (mounted && scope == _cache.scopeKey) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
      if (_refreshPending && mounted) {
        _refreshPending = false;
        _scheduleRefresh();
      }
    }
  }

  Future<void> _action(Video video, Future<void> Function() task) async {
    final key = _cache.keyFor(video);
    final scope = _cache.scopeKey;
    if (_busy.contains(key)) return;
    setState(() {
      _busy.add(key);
      _actionError = null;
    });
    try {
      await task();
    } catch (error) {
      if (mounted && scope == _cache.scopeKey) {
        setState(() => _actionError = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy.remove(key));
        await _refresh();
      }
    }
  }

  Future<void> _retry(Video video) => _action(video, () async {
        final itemId =
            video.studyItemId ?? (video.source == 'bilibili' ? -video.id : 0);
        if (video.source == 'bilibili' && itemId <= 0) {
          throw StateError('缓存任务缺少稳定学习项标识，请从学习列表重新缓存');
        }
        await widget.controller.cacheItem(StudyItem(
          id: itemId,
          listId: 0,
          title: video.title,
          source: video.source,
          videoId: video.source == 'nas' ? video.id : null,
          sourceData: video.sourceData,
          thumbnailUrl: video.thumbnailUrl,
          durationSeconds: video.duration.inSeconds,
          positionSeconds: studyInt(video.sourceData['position_seconds']),
        ));
      });

  Future<void> _open(Video video) => _action(video, () async {
        final bundle = await _cache.localBundle(video);
        if (bundle == null) {
          throw StateError('缓存文件不存在，请刷新列表');
        }
        final item = widget.controller.items
            .firstWhereOrNull((item) => item.id == video.studyItemId);
        final metadata =
            item == null ? video : widget.controller.videoForItem(item);
        final playable = Video.fromJson({
          ...metadata.toJson(),
          'id': video.id,
          'source': video.source,
          'sidecars':
              bundle.sidecars.map((sidecar) => sidecar.toJson()).toList(),
          'source_data': {
            ...video.sourceData,
            ...metadata.sourceData,
            for (final key in const ['bvid', 'cid', 'page'])
              if (video.sourceData.containsKey(key)) key: video.sourceData[key],
            'offline': true,
          }
        });
        final player = Get.isRegistered<VideoController>()
            ? Get.find<VideoController>()
            : Get.put(VideoController());
        player.studyBilibili = widget.controller.bili;
        player.courseQueue.assignAll([playable]);
        await Get.toNamed(AppRoutes.videoPlayer, arguments: playable);
        await widget.controller.refreshItems();
      });

  Future<void> _cacheSidecars(Video video) => _action(video, () async {
        final scope = _cache.scopeKey;
        final attachments = <StudyCacheAttachment>[];
        final failures = <String>[];
        if (video.source == 'nas') {
          final response =
              await widget.controller.api.get('/videos/${video.id}');
          final fresh = Video.fromJson(studyMap(response.data));
          for (final sidecar in fresh.sidecars) {
            attachments.add(StudyCacheAttachment.remote(
                id: '${sidecar.kind}:${sidecar.id}',
                kind: sidecar.kind,
                extension: sidecar.extension,
                title: sidecar.title,
                url: sidecar.url));
          }
        } else {
          final bili = widget.controller.bili;
          final cid = studyInt(video.sourceData['cid']);
          if (cid <= 0) throw StateError('缓存任务缺少分P标识，请重新解析视频');
          await bili.initialize();
          if (scope != _cache.scopeKey) throw StateError('账号已切换');
          attachments.addAll(
              await biliOfflineAttachments(bili, video, warning: failures.add));
        }
        await _cache.cacheAttachments(video, attachments, expectedScope: scope);
        if (failures.isNotEmpty) throw StateError(failures.join('\n'));
      });

  Future<void> _showSidecars(StudyCacheEntry entry) async {
    final scope = _cache.scopeKey;
    final update = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        constraints: const BoxConstraints(maxWidth: 640),
        builder: (context) => Obx(() {
              final revision = _cache.revision.value;
              if (scope != _cache.scopeKey) {
                return SafeArea(
                    key: ValueKey(revision),
                    child: const Padding(
                        padding: EdgeInsets.all(24), child: Text('账号已切换')));
              }
              return SafeArea(
                  key: ValueKey(revision),
                  top: false,
                  child: SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.65,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text('字幕与弹幕',
                                  style:
                                      Theme.of(context).textTheme.titleMedium)),
                          Expanded(
                              child: ListView(children: [
                            if (entry.attachments.isEmpty)
                              const ListTile(title: Text('暂无离线附件')),
                            for (final attachment in entry.attachments)
                              ListTile(
                                  leading: Icon(attachment.kind == 'subtitle'
                                      ? Icons.closed_caption_outlined
                                      : Icons.comment_outlined),
                                  title: Text(attachment.title.isEmpty
                                      ? attachment.id
                                      : attachment.title),
                                  subtitle: Text(
                                      '${attachment.extension} · ${(attachment.bytes / 1024).toStringAsFixed(1)} KiB'),
                                  trailing: const Icon(Icons.check)),
                          ])),
                          Padding(
                              padding: const EdgeInsets.all(16),
                              child: FilledButton.icon(
                                  onPressed: () => Navigator.pop(context, true),
                                  icon: const Icon(Icons.sync),
                                  label: const Text('更新字幕与弹幕'))),
                        ]),
                  ));
            }));
    if (update == true && mounted && scope == _cache.scopeKey) {
      await _cacheSidecars(entry.video);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('离线缓存'), actions: [
          IconButton(
              tooltip: '刷新缓存',
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _refresh),
        ]),
        body: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Obx(() {
            final scope = _cache.scopeKey;
            if (scope != _loadedScope) _scheduleRefresh();
            final entries = <String, StudyCacheEntry>{
              if (scope == _loadedScope)
                for (final entry in _entries) _cache.keyFor(entry.video): entry,
            };
            for (final item in widget.controller.items) {
              final video = widget.controller.videoForItem(item);
              final key = _cache.keyFor(video);
              if (_cache.progress.containsKey(key) ||
                  _cache.errors.containsKey(key)) {
                entries.putIfAbsent(
                    key,
                    () => StudyCacheEntry(
                        video: video,
                        complete: _cache.progress[key] == 1,
                        receivedBytes: 0));
              }
            }
            return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                      16, 8, 16, studyBottomPadding(context)),
                  children: [
                    if (_loading) const LinearProgressIndicator(),
                    if ((_error != null || _actionError != null) &&
                        scope == _loadedScope)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(_actionError ?? _error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                    if (entries.isEmpty && !_loading)
                      const StudyEmpty('暂无离线缓存',
                          icon: Icons.download_done_outlined),
                    for (final entry in entries.entries)
                      Builder(builder: (context) {
                        final video = entry.value.video;
                        final active = _cache.isDownloading(video);
                        final attaching = _cache.isCachingAttachments(video);
                        final progress = _cache.progress[entry.key];
                        final error = _cache.errors[entry.key] ??
                            widget.controller.errors['cache:${entry.key}'];
                        final complete = entry.value.complete || progress == 1;
                        final working = _busy.contains(entry.key);
                        final attachmentError =
                            _cache.attachmentErrors[entry.key];
                        final item = StudyItem(
                            id: video.studyItemId ?? 0,
                            listId: 0,
                            title: video.title,
                            source: video.source,
                            thumbnailUrl: video.thumbnailUrl,
                            durationSeconds: video.duration.inSeconds);
                        final storedProgress = (entry.value.totalBytes ?? 0) > 0
                            ? (entry.value.receivedBytes /
                                    entry.value.totalBytes!)
                                .clamp(0.0, 1.0)
                            : null;
                        return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              StudyItemRow(
                                  item: item,
                                  onPlay: !complete || working || active
                                      ? null
                                      : () => _open(video),
                                  actions: [
                                    IconButton(
                                        tooltip: '字幕与弹幕',
                                        icon: const Icon(
                                            Icons.closed_caption_outlined),
                                        onPressed: active ||
                                                working ||
                                                attaching
                                            ? null
                                            : () => _showSidecars(entry.value)),
                                    if (active)
                                      IconButton(
                                          tooltip: '暂停缓存',
                                          icon: const Icon(Icons.pause),
                                          onPressed: () => _cache.pause(video))
                                    else if (attaching)
                                      IconButton(
                                          tooltip: '暂停附件缓存',
                                          icon: const Icon(Icons.pause),
                                          onPressed: () => _cache.pause(video))
                                    else if (!complete)
                                      IconButton(
                                          tooltip: error != null
                                              ? '重试缓存'
                                              : entry.value.receivedBytes > 0
                                                  ? '继续缓存'
                                                  : '开始缓存',
                                          icon: Icon(error != null
                                              ? Icons.refresh
                                              : Icons.download_outlined),
                                          onPressed: working
                                              ? null
                                              : () => _retry(video)),
                                    IconButton(
                                        tooltip: '删除缓存',
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: working
                                            ? null
                                            : () async {
                                                if (!await studyConfirm(
                                                    context,
                                                    '删除缓存',
                                                    '删除“${video.title}”的本机缓存？')) {
                                                  return;
                                                }
                                                if (mounted) {
                                                  await _action(
                                                      video,
                                                      () =>
                                                          _cache.remove(video));
                                                }
                                              }),
                                  ]),
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                      complete
                                          ? entry.value.layout == 'dash'
                                              ? '已缓存 · 独立音视频'
                                              : entry.value.layout == 'segments'
                                                  ? '已缓存 · 分段视频'
                                                  : '已缓存'
                                          : active
                                              ? '下载中'
                                              : working
                                                  ? '正在解析'
                                                  : error != null
                                                      ? '缓存失败'
                                                      : '未完成',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall)),
                              if (entry.value.attachments.isNotEmpty ||
                                  attaching)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                        attaching
                                            ? '正在缓存字幕与弹幕'
                                            : '字幕 ${entry.value.attachments.where((item) => item.kind == 'subtitle').length} · '
                                                '弹幕 ${entry.value.attachments.where((item) => item.kind == 'danmaku').length}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall)),
                              if (!complete)
                                LinearProgressIndicator(
                                    value: active
                                        ? progress
                                        : storedProgress ?? 0),
                              if (error != null)
                                Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    child: Text(error,
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error))),
                              if (attachmentError != null)
                                Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    child: Text('附件：$attachmentError',
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error))),
                            ]);
                      }),
                  ],
                ));
          }),
        )),
      );
}
