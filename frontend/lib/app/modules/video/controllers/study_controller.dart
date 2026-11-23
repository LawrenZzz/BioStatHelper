import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart' show DioExceptionType;

import '../../../../core/services/api_client.dart';
import '../../../../core/services/bilibili_service.dart';
import '../../../../core/services/study_media_cache.dart';
import '../../../../core/services/study_offline_assets.dart';
import '../../../../core/services/study_progress_sync.dart';
import '../../../../core/services/study_subscription_check.dart';
import '../../../../core/services/study_preferences.dart';
import '../../../../core/services/study_subscription_scheduler.dart'
    hide StudySubscriptionCheck;
import '../../../../core/services/device_integration_service.dart';
import '../../../../shared/models/category_model.dart';
import '../../../../shared/models/study_model.dart';
import '../../../../shared/models/video_model.dart';
import '../../../routes/app_routes.dart';
import 'video_controller.dart';

typedef StudyBilibiliSearch = Future<List<StudyItem>> Function(
    String query, int page);

class StudyController extends GetxController {
  StudyController(
      {ApiClient? api,
      BilibiliService? bilibili,
      StudyMediaCache? mediaCache,
      StudyProgressSync? progressSync,
      this.bilibiliSearch})
      : api = api ?? ApiClient(),
        bili = bilibili ?? BilibiliService(),
        mediaCache = mediaCache ?? StudyMediaCache.instance,
        progressSync = progressSync ?? StudyProgressSync.instance,
        _ownsBili = bilibili == null;

  final ApiClient api;
  final BilibiliService bili;
  final StudyMediaCache mediaCache;
  final StudyProgressSync progressSync;
  final bool _ownsBili;
  StudyBilibiliSearch? bilibiliSearch;
  final lists = <StudyList>[].obs;
  final items = <StudyItem>[].obs;
  final notes = <StudyNote>[].obs;
  final subscriptions = <StudySubscription>[].obs;
  final updates = <StudyUpdate>[].obs;
  final focusHistory = <Map<String, dynamic>>[].obs;
  final stats = const StudyStats().obs;
  final categories = <VideoCategory>[].obs;
  final searchResults = <StudyItem>[].obs;
  final searchTotal = 0.obs;
  final busy = <String>{}.obs;
  final errors = <String, String>{}.obs;
  final focusSeconds = 0.obs;
  final focusRunning = false.obs;
  final focusTargetMinutes = 25.obs;
  final focusStarted = Rxn<DateTime>();
  final _readVersions = <String, int>{};
  final _clock = Stopwatch();
  Timer? _ticker;
  int _searchVersion = 0;
  late final preferences = StudyPreferencesController(
      api: api,
      beforeSave: (previous, next) async {
        if (!kIsWeb &&
            defaultTargetPlatform == TargetPlatform.android &&
            next.subscriptionNotifications &&
            !previous.subscriptionNotifications) {
          return DeviceIntegrationService.requestNotificationPermission();
        }
        return true;
      },
      afterSave: (_, next) async {
        await DeviceIntegrationService.configureStudyBackground(
            next.subscriptionBackground);
      });
  late final scheduler = StudySubscriptionScheduler(
      preferences: preferences,
      runWhileInactive:
          !kIsWeb && defaultTargetPlatform == TargetPlatform.windows,
      checkUpdates: () async {
        await refreshSubscriptions();
        if (!await checkUpdates()) throw StateError('订阅检查未完成');
        return updates.toList();
      },
      isFocusActive: () => focusRunning.value,
      notify: (fresh) => DeviceIntegrationService.showStudyNotification(
          title: fresh.length == 1 ? fresh.single.title : '学习订阅有新内容',
          count: fresh.length));

  bool get writing => busy.contains('write');
  List<StudyList> get activeLists =>
      lists.where((list) => !list.archived).toList();
  StudyItem? get continueItem {
    final activeIds = activeLists.map((list) => list.id).toSet();
    final candidates = items
        .where((item) =>
            activeIds.contains(item.listId) &&
            item.status != StudyStatus.completed)
        .toList();
    candidates.sort((a, b) {
      final status = (a.status == StudyStatus.learning ? 0 : 1)
          .compareTo(b.status == StudyStatus.learning ? 0 : 1);
      if (status != 0) return status;
      if (a.status == StudyStatus.learning) {
        final recent = (b.lastWatchedAt ?? DateTime(1970))
            .compareTo(a.lastWatchedAt ?? DateTime(1970));
        if (recent != 0) return recent;
      }
      final listOrder = activeLists
          .indexWhere((list) => list.id == a.listId)
          .compareTo(activeLists.indexWhere((list) => list.id == b.listId));
      if (listOrder != 0) return listOrder;
      return a.sortOrder.compareTo(b.sortOrder);
    });
    return candidates.isEmpty ? null : candidates.first;
  }

  List<StudyItem> itemsFor(int listId) =>
      items.where((item) => item.listId == listId).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  @override
  void onInit() {
    super.onInit();
    unawaited(refreshAll());
    scheduler.start();
    unawaited(preferences.load().then((loaded) async {
      if (loaded && !isClosed) {
        await DeviceIntegrationService.configureStudyBackground(
            preferences.savedValue.subscriptionBackground);
      }
    }));
  }

  @override
  void onClose() {
    scheduler.dispose();
    preferences.dispose();
    _ticker?.cancel();
    _clock.stop();
    if (_ownsBili) bili.dispose();
    super.onClose();
  }

  Future<bool> _read(
      String key, Future<void> Function(int version) task) async {
    if (isClosed) return false;
    final version = (_readVersions[key] ?? 0) + 1;
    _readVersions[key] = version;
    busy.add(key);
    errors.remove(key);
    try {
      await task(version);
      return true;
    } catch (error) {
      if (!isClosed && _readVersions[key] == version) errors[key] = '$error';
      return false;
    } finally {
      if (!isClosed && _readVersions[key] == version) busy.remove(key);
    }
  }

  bool _current(String key, int version) =>
      !isClosed && _readVersions[key] == version;

  Future<bool> _write(Future<void> Function() task) async {
    if (writing || isClosed) return false;
    busy.add('write');
    errors.remove('write');
    try {
      await task();
      return true;
    } catch (error) {
      if (!isClosed) errors['write'] = '$error';
      return false;
    } finally {
      if (!isClosed) busy.remove('write');
    }
  }

  Future<void> refreshAll() async {
    await Future.wait([
      refreshLists(),
      refreshItems(),
      refreshStats(),
      refreshSubscriptions(),
      refreshUpdates(),
    ]);
  }

  Future<bool> refreshLists() => _read('lists', (version) async {
        final response = await api.get('/study/lists');
        final data = studyRows(response.data).map(StudyList.fromJson).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        if (_current('lists', version)) lists.assignAll(data);
      });

  Future<bool> refreshItems() => _read('items', (version) async {
        final local = await progressSync.pendingItems();
        if (_current('items', version) && local.isNotEmpty) {
          items.assignAll(_withLocalProgress(items.toList(), local));
        }
        unawaited(progressSync.flush());
        final response = await api
            .get('/study/items', queryParameters: {'sort': 'sort_order'});
        final data = studyRows(response.data).map(StudyItem.fromJson).toList();
        final pending = {...local, ...await progressSync.pendingItems()};
        if (_current('items', version)) {
          items.assignAll(_withLocalProgress(data, pending));
        }
      });

  List<StudyItem> _withLocalProgress(
          List<StudyItem> data, Map<int, Map<String, dynamic>> pending) =>
      data.map((item) {
        final progress = pending[item.id];
        if (progress == null) return item;
        final duration = studyInt(progress['duration_seconds']);
        final recorded = DateTime.tryParse('${progress['recorded_at'] ?? ''}');
        return StudyItem.fromJson({
          ...item.toJson(),
          'position_seconds': progress['position_seconds'],
          'duration_seconds': duration > 0 ? duration : item.durationSeconds,
          'updated_at': item.updatedAt?.toIso8601String(),
          'last_watched_at':
              (recorded ?? item.lastWatchedAt)?.toIso8601String(),
          'status': progress['completed'] == true ? 'completed' : 'learning',
        });
      }).toList();

  /// Resolve fresh URLs for every retry; never persist CDN URLs or credentials.
  Future<void> cacheItem(StudyItem item) async {
    final key = mediaCache.keyFor(videoForItem(item));
    final scope = mediaCache.scopeKey;
    if (busy.contains('cache:$key') ||
        mediaCache.isDownloading(videoForItem(item))) {
      return;
    }
    busy.add('cache:$key');
    errors.remove('cache:$key');
    try {
      var video = videoForItem(item);
      String url;
      Map<String, String> headers;
      BiliPlayback? resolved;
      List<StudyCacheAttachment> attachments = [];
      if (item.source == 'nas') {
        if (item.videoId == null) throw StateError('学习项缺少 NAS 视频 ID');
        final response = await api.get('/videos/${item.videoId}');
        video = videoForItem(item, sourceData: studyMap(response.data));
        if (video.videoUrl.isEmpty) throw StateError('此 NAS 视频没有可下载地址');
        url = api.absoluteUrl(video.videoUrl);
        headers = {};
      } else if (item.source == 'bilibili') {
        await bili.initialize();
        final bvid = '${item.sourceData['bvid'] ?? ''}';
        var cid = studyInt(item.sourceData['cid']);
        if (cid <= 0) {
          final detail = await bili.getVideo(bvid);
          final page = studyInt(item.sourceData['page'], 1);
          final part =
              detail.parts.firstWhereOrNull((part) => part.page == page);
          if (part == null) throw StateError('无法确定原视频分P，不能安全恢复缓存');
          cid = part.cid;
          video =
              videoForItem(item, sourceData: detail.toSourceData(part: part));
        }
        final playback = await bili.resolvePlayback(bvid, cid);
        resolved = playback;
        url = playback.videoUrl ?? playback.segments.first;
        headers = playback.headers;
        video = video.copyWith(sourceData: {...video.sourceData, 'cid': cid});
        attachments =
            await biliOfflineAttachments(bili, video, warning: (message) {
          if (!isClosed && mediaCache.scopeKey == scope) {
            errors['cache:$key'] = message;
          }
        });
      } else {
        throw StateError('不支持此视频来源的离线缓存');
      }
      if (isClosed || mediaCache.scopeKey != scope) {
        throw StateError('账号或服务器已切换，请重试');
      }
      if (resolved != null) {
        await mediaCache.downloadBundle(video,
            resolved.isDash ? [resolved.videoUrl!] : resolved.segments, headers,
            audioUrl: resolved.audioUrl,
            attachments: attachments,
            representationId: 'quality:${resolved.quality}',
            expectedScope: scope);
      } else {
        await mediaCache.download(video, url, headers);
      }
    } catch (error) {
      if (!isClosed && mediaCache.scopeKey == scope) {
        errors['cache:$key'] = '$error';
      }
      rethrow;
    } finally {
      if (!isClosed) busy.remove('cache:$key');
    }
  }

  Future<bool> refreshNotes({int? itemId}) => _read('notes', (version) async {
        final response = await api.get('/study/notes',
            queryParameters: {if (itemId != null) 'item_id': itemId});
        final data = studyRows(response.data).map(StudyNote.fromJson).toList();
        if (_current('notes', version)) notes.assignAll(data);
      });

  Future<bool> refreshStats() => _read('stats', (version) async {
        final response = await api.get('/study/stats');
        final data = studyMap(response.data);
        final value = StudyStats.fromJson(
            data['data'] is Map ? studyMap(data['data']) : data);
        if (_current('stats', version)) stats.value = value;
      });

  Future<bool> refreshSubscriptions() =>
      _read('subscriptions', (version) async {
        final response = await api.get('/study/subscriptions');
        final data =
            studyRows(response.data).map(StudySubscription.fromJson).toList();
        if (_current('subscriptions', version)) subscriptions.assignAll(data);
      });

  Future<bool> refreshUpdates() => _read('updates', (version) async {
        final response = await api.get('/study/updates');
        final data =
            studyRows(response.data).map(StudyUpdate.fromJson).toList();
        if (_current('updates', version)) updates.assignAll(data);
      });

  Future<bool> refreshFocusHistory() => _read('focus', (version) async {
        final response = await api.get('/study/focus');
        final data = studyRows(response.data);
        if (_current('focus', version)) focusHistory.assignAll(data);
      });

  Future<bool> saveList(
          {StudyList? list,
          required String name,
          String description = '',
          bool archived = false}) =>
      _write(() async {
        if (name.trim().isEmpty) throw const FormatException('请输入列表名称');
        final data = {
          'name': name.trim(),
          'description': description.trim(),
          'archived': archived,
          'sort_order': list?.sortOrder ?? lists.length
        };
        if (list == null) {
          await api.post('/study/lists', data: data);
        } else {
          await api.put('/study/lists/${list.id}', data: data);
        }
        await refreshLists();
      });

  Future<bool> deleteList(StudyList list) => _write(() async {
        await api.delete('/study/lists/${list.id}');
        await refreshLists();
        await refreshItems();
      });

  Map<String, dynamic> _creationPayload(
      StudyItem item, int listId, int sortOrder) {
    final data = item.toJson()..remove('id');
    if (item.source == 'nas') {
      // NAS creation must inherit existing watch progress on the server.
      data.remove('status');
      data.remove('position_seconds');
    }
    return {...data, 'list_id': listId, 'sort_order': sortOrder};
  }

  StudyItem _acceptCreatedItem(dynamic response) {
    final saved = StudyItem.fromJson(studyMap(response));
    if (saved.id <= 0 || saved.listId <= 0 || saved.title.isEmpty) {
      throw const FormatException('服务器未返回有效的学习项，请刷新列表后确认是否已保存。');
    }
    if (isClosed) return saved;
    final index = items.indexWhere((item) => item.id == saved.id);
    if (index < 0) {
      items.add(saved);
    } else {
      items[index] = saved;
    }
    return saved;
  }

  Future<void> _refreshAfterCreation(List<StudyItem> saved) async {
    if (isClosed) return;
    await refreshItems();
    if (isClosed) return;
    // Preserve acknowledged writes if a failed or stale read omitted them.
    for (final item in saved) {
      if (!items.any((entry) => entry.id == item.id)) {
        items.add(item);
      }
    }
  }

  bool _sameSource(StudyItem saved, StudyItem requested, int listId) {
    if (saved.listId != listId || saved.source != requested.source) {
      return false;
    }
    if (saved.source == 'nas') return saved.videoId == requested.videoId;
    return saved.sourceData['bvid'] == requested.sourceData['bvid'] &&
        '${saved.sourceData['cid'] ?? 'default'}' ==
            '${requested.sourceData['cid'] ?? 'default'}';
  }

  Future<StudyItem> _createItem(
      StudyItem item, int listId, int sortOrder) async {
    try {
      final response = await api.post('/study/items',
          data: _creationPayload(item, listId, sortOrder),
          timeout: const Duration(seconds: 45));
      final saved = StudyItem.fromJson(studyMap(response.data));
      if (saved.id > 0 &&
          saved.listId > 0 &&
          saved.title.isNotEmpty &&
          !_sameSource(saved, item, listId)) {
        throw const ApiException('服务器返回的学习项不匹配，请刷新列表确认。');
      }
      return _acceptCreatedItem(response.data);
    } on ApiException catch (error) {
      final uncertain =
          error.isTimeout || error.type == DioExceptionType.connectionError;
      if (!uncertain && error.statusCode != 409) rethrow;
      // A lost acknowledgement is not evidence that the transaction failed.
      // Reconcile by source identity; never resend a write automatically.
      try {
        final response = await api.get('/study/items', queryParameters: {
          'list_id': listId,
          'source': item.source,
        });
        final existing = studyRows(response.data)
            .map(StudyItem.fromJson)
            .toList()
            .firstWhereOrNull((saved) => _sameSource(saved, item, listId));
        if (existing != null) return _acceptCreatedItem(existing.toJson());
      } catch (_) {
        // Retain the original write outcome if the verification read also failed.
      }
      if (uncertain) {
        throw const ApiException(
            '服务器响应较慢，暂未确认本项是否保存。请稍后刷新学习列表；重试时会核对已有记录，避免重复添加。');
      }
      throw const ApiException('服务器暂时无法保存此项，请刷新学习列表后重试。');
    }
  }

  Future<bool> addItem(StudyItem item, int listId) => _write(() async {
        final saved = await _createItem(item, listId, itemsFor(listId).length);
        await _refreshAfterCreation([saved]);
      });

  Future<bool> updateItem(StudyItem item, Map<String, dynamic> changes) =>
      _write(() async {
        await api.put('/study/items/${item.id}', data: changes);
        await refreshItems();
        unawaited(refreshStats());
      });

  Future<bool> removeItem(StudyItem item) => _write(() async {
        await api.delete('/study/items/${item.id}');
        await refreshItems();
      });

  Future<bool> batchItems(Iterable<int> ids, String action) => _write(() async {
        if (!{'complete', 'plan', 'remove'}.contains(action)) {
          throw const FormatException('无效的批量操作');
        }
        if (ids.isEmpty) return;
        await api.post('/study/items/batch',
            data: {'item_ids': ids.toList(), 'action': action});
        await refreshItems();
        unawaited(refreshStats());
      });

  Future<bool> reorderItems(int listId, List<int> ids) => _write(() async {
        final existing = itemsFor(listId).map((item) => item.id).toSet();
        if (ids.length != existing.length ||
            ids.toSet().length != ids.length ||
            !existing.containsAll(ids)) {
          throw const FormatException('列表已更新，请刷新后重新排序');
        }
        await api.post('/study/items/reorder',
            data: {'list_id': listId, 'item_ids': ids});
        await refreshItems();
      });

  Future<bool> saveNote(
          {StudyNote? note,
          required int itemId,
          required int positionSeconds,
          required String content,
          String? imageData}) =>
      _write(() async {
        if (content.trim().isEmpty) throw const FormatException('请输入笔记内容');
        final data = {
          if (note == null) 'item_id': itemId,
          'position_seconds': positionSeconds,
          'content': content.trim(),
          if (imageData != null) 'image_base64': imageData
        };
        if (note == null) {
          await api.post('/study/notes', data: data);
        } else {
          await api.put('/study/notes/${note.id}', data: data);
        }
        await refreshNotes();
      });

  Future<bool> deleteNote(StudyNote note) => _write(() async {
        await api.delete('/study/notes/${note.id}');
        await refreshNotes();
      });

  Future<bool> loadCategories() => _read('categories', (version) async {
        final response = await api.get('/videos/nas-categories');
        final data =
            studyRows(response.data).map(VideoCategory.fromJson).toList();
        if (_current('categories', version)) categories.assignAll(data);
      });

  void clearSearch() {
    _searchVersion++;
    searchResults.clear();
    searchTotal.value = 0;
    errors.remove('search');
    busy.remove('search');
  }

  StudyItem _nasItem(Map<String, dynamic> row) => StudyItem(
        id: 0,
        listId: 0,
        videoId: studyInt(row['id']),
        sourceData: row,
        title: '${row['title'] ?? ''}',
        thumbnailUrl: '${row['thumbnail_url'] ?? ''}',
        durationSeconds: studyInt(row['duration_seconds']),
      );

  Future<bool> search(String query,
      {int? categoryId, String source = 'nas', int page = 1}) async {
    if (source == 'nas' && query.trim().isEmpty && categoryId == null) {
      clearSearch();
      return true;
    }
    final version = ++_searchVersion;
    busy.add('search');
    errors.remove('search');
    if (page == 1) searchResults.clear();
    try {
      List<StudyItem> data;
      int total;
      if (source == 'bilibili') {
        if (bilibiliSearch != null) {
          data = await bilibiliSearch!(query.trim(), page);
          total =
              searchResults.length + data.length + (data.length >= 20 ? 1 : 0);
        } else {
          await bili.initialize();
          final result = await bili.search(query.trim(), page: page);
          data = result.items.map((video) => biliItem(video)).toList();
          total = result.total ??
              ((page - 1) * 20 + data.length + (result.hasMore ? 1 : 0));
        }
      } else {
        final response = await api.get('/videos/', queryParameters: {
          'search': query.trim(),
          if (categoryId != null) 'nas_category_id': categoryId,
          'skip': (page - 1) * 40,
          'limit': 40,
          'sort': 'episode',
        });
        data = studyRows(response.data).map(_nasItem).toList();
        total = studyInt(studyMap(response.data)['total'], data.length);
      }
      if (isClosed || version != _searchVersion) return false;
      if (page == 1) {
        searchResults.assignAll(data);
      } else {
        searchResults.addAll(data);
      }
      searchTotal.value = total;
      return true;
    } catch (error) {
      if (!isClosed && version == _searchVersion) errors['search'] = '$error';
      return false;
    } finally {
      if (!isClosed && version == _searchVersion) busy.remove('search');
    }
  }

  StudyItem biliItem(BiliVideo video, {BiliPart? part}) => StudyItem(
      id: 0,
      listId: 0,
      title: part == null
          ? video.title
          : '${video.title} · P${part.page} ${part.title}',
      source: 'bilibili',
      sourceData: video.toSourceData(part: part, compact: part != null),
      thumbnailUrl: video.cover,
      durationSeconds: (part?.duration ?? video.duration).inSeconds);

  Future<BiliVideo?> loadBiliDetail(StudyItem item) async {
    BiliVideo? result;
    await _read('biliDetail', (_) async {
      await bili.initialize();
      result = await bili.getVideo('${item.sourceData['bvid'] ?? ''}');
    });
    return result;
  }

  Future<bool> addBiliParts(
          BiliVideo video, Iterable<BiliPart> parts, int listId) =>
      _write(() async {
        var added = 0;
        final selected = parts.toList();
        if (selected.isEmpty) throw const FormatException('请选择至少一个视频分P。');
        final saved = <StudyItem>[];
        final sortStart = itemsFor(listId).fold<int>(
                -1,
                (highest, item) =>
                    item.sortOrder > highest ? item.sortOrder : highest) +
            1;
        final existing = itemsFor(listId)
            .where((item) => item.source == 'bilibili')
            .map((item) =>
                '${item.sourceData['bvid']}:${item.sourceData['cid']}')
            .toSet();
        try {
          for (final part in selected) {
            if (existing.contains('${video.bvid}:${part.cid}')) continue;
            final item = biliItem(video, part: part);
            saved.add(await _createItem(item, listId, sortStart + added));
            existing.add('${video.bvid}:${part.cid}');
            added++;
          }
        } catch (error) {
          throw ApiException('已添加 $added 项，其余尚未确认添加：$error');
        } finally {
          await _refreshAfterCreation(saved);
        }
      });

  Future<bool> addNasCourse(VideoCategory category, int listId) =>
      _write(() async {
        var added = 0;
        var skip = 0;
        final existing = itemsFor(listId)
            .where((item) => item.source == 'nas')
            .map((item) => item.videoId)
            .toSet();
        try {
          while (true) {
            final response = await api.get('/videos/', queryParameters: {
              'nas_category_id': category.id,
              'skip': skip,
              'limit': 200,
              'sort': 'episode',
            });
            final rows = studyRows(response.data);
            for (final row in rows) {
              final item = _nasItem(row);
              if (existing.contains(item.videoId)) continue;
              await api.post('/study/items',
                  data: _creationPayload(
                      item, listId, itemsFor(listId).length + added));
              existing.add(item.videoId);
              added++;
            }
            skip += rows.length;
            final total = studyInt(studyMap(response.data)['total'], skip);
            if (rows.isEmpty || skip >= total) break;
          }
        } catch (error) {
          throw StateError('已添加 $added 项，其余未添加：$error');
        } finally {
          await refreshItems();
        }
      });

  void startFocus() {
    if (writing || focusRunning.value) return;
    focusStarted.value ??= DateTime.now().toUtc();
    _clock.start();
    focusRunning.value = true;
    unawaited(_saveFocusQuietPeriod(true));
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isClosed) {
        focusSeconds.value = _clock.elapsed.inSeconds;
        if (focusRunning.value &&
            focusSeconds.value >= focusTargetMinutes.value * 60) {
          unawaited(finishFocus());
        }
      }
    });
  }

  void pauseFocus() {
    _clock.stop();
    focusRunning.value = false;
    focusSeconds.value = _clock.elapsed.inSeconds;
    unawaited(_saveFocusQuietPeriod(false));
  }

  Future<void> _saveFocusQuietPeriod(bool running) async {
    final scope = preferences.scopeKey;
    if (scope == null) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'study_focus_until_$scope';
    if (running) {
      final remaining =
          (focusTargetMinutes.value * 60 - focusSeconds.value).clamp(0, 7200);
      await prefs.setInt(
          key,
          DateTime.now()
              .add(Duration(seconds: remaining))
              .millisecondsSinceEpoch);
    } else {
      await prefs.remove(key);
    }
  }

  Future<bool> finishFocus({bool completed = true}) {
    pauseFocus();
    return _write(() async {
      final started = focusStarted.value;
      if (started == null || focusSeconds.value <= 0) return;
      await api.post('/study/focus', data: {
        'elapsed_seconds': focusSeconds.value,
        'started_at': started.toIso8601String(),
        'ended_at': DateTime.now().toUtc().toIso8601String(),
        'completed': completed,
      });
      if (isClosed) return;
      _clock.reset();
      focusSeconds.value = 0;
      focusStarted.value = null;
      await refreshStats();
      unawaited(refreshFocusHistory());
    });
  }

  Future<bool> saveSubscription(
          {StudySubscription? subscription,
          required String name,
          String source = 'nas',
          int? categoryId,
          Map<String, dynamic> sourceData = const {},
          String? kind}) =>
      _write(() async {
        final data = {
          'name': name.trim(),
          'source': source,
          'kind': kind ?? (source == 'nas' ? 'category' : 'up'),
          if (source == 'nas') 'category_id': categoryId,
          for (final key in ['mid', 'owner_mid', 'season_id'])
            if (sourceData[key] != null) key: '${sourceData[key]}'
        };
        if (subscription == null) {
          await api.post('/study/subscriptions', data: data);
        } else {
          await api.put('/study/subscriptions/${subscription.id}', data: data);
        }
        await refreshSubscriptions();
      });

  Future<bool> deleteSubscription(StudySubscription subscription) =>
      _write(() async {
        await api.delete('/study/subscriptions/${subscription.id}');
        await refreshSubscriptions();
      });

  Future<bool> checkUpdates() => _write(() async {
        final failures = await StudySubscriptionCheck(api: api, bili: bili)
            .run(subscriptions.toList(), cancelled: () => isClosed);
        await refreshUpdates();
        if (failures.isNotEmpty) throw StateError(failures.join('\n'));
      });

  Future<bool> importSubscriptionHistory(StudySubscription subscription) =>
      _write(() async {
        final failures = await StudySubscriptionCheck(api: api, bili: bili)
            .run([subscription], historical: true, cancelled: () => isClosed);
        await refreshUpdates();
        if (failures.isNotEmpty) throw StateError(failures.join('\n'));
      });

  Future<bool> setSubscriptionEnabled(
          StudySubscription subscription, bool enabled) =>
      _write(() async {
        await api.put('/study/subscriptions/${subscription.id}',
            data: {'enabled': enabled});
        await refreshSubscriptions();
      });

  Future<bool> batchSubscriptions(Iterable<int> ids, String action) =>
      _write(() async {
        await api.post('/study/subscriptions/batch',
            data: {'subscription_ids': ids.toList(), 'action': action});
        await refreshSubscriptions();
        await refreshUpdates();
      });

  Future<bool> batchUpdates(Iterable<int> ids) => _write(() async {
        await api.post('/study/updates/batch',
            data: {'update_ids': ids.toList(), 'action': 'read'});
        await refreshUpdates();
      });

  Future<bool> markUpdateRead(StudyUpdate update) => _write(() async {
        await api.put('/study/updates/${update.id}', data: {'read': true});
        await refreshUpdates();
      });

  Future<String?> exportData() async {
    String? result;
    await _read('transfer', (version) async {
      final response = await api.get('/study/export');
      result = const JsonEncoder.withIndent('  ').convert(response.data);
    });
    return result;
  }

  Future<bool> importData(String value) => _write(() async {
        final data = jsonDecode(value);
        if (data is! Map<String, dynamic>) {
          throw const FormatException('请选择学习资料 JSON 对象');
        }
        await api.post('/study/import', data: data);
        await preferences.load(discardChanges: true);
        await refreshAll();
        await refreshNotes();
      });

  /// Player handoff: retain source identifiers and an explicit seek position.
  Video videoForItem(StudyItem item,
      {Map<String, dynamic>? sourceData, int? positionSeconds}) {
    final position = positionSeconds ?? item.positionSeconds;
    return Video.fromJson({
      ...item.sourceData,
      ...?sourceData,
      'id': item.videoId ?? -item.id,
      'title': item.title,
      'thumbnail_url': item.thumbnailUrl,
      'duration_seconds': item.durationSeconds,
      'study_item_id': item.id,
      'source_data': {
        ...item.sourceData,
        ...?sourceData,
        'position_seconds': position
      },
      'source': item.source,
      'position_seconds': position,
      'progress_percent': item.durationSeconds > 0
          ? position / item.durationSeconds * 100
          : 0.0,
    });
  }

  Future<void> openItem(StudyItem item, {int? positionSeconds}) async {
    if (busy.contains('play') || isClosed) return;
    busy.add('play');
    errors.remove('play');
    try {
      var sourceData = Map<String, dynamic>.from(item.sourceData);
      final videoController = Get.isRegistered<VideoController>()
          ? Get.find<VideoController>()
          : Get.put(VideoController());
      videoController.studyBilibili = bili;
      StudyCachedPlayback? cached;
      try {
        cached = await mediaCache.localBundle(videoForItem(item));
      } catch (_) {}
      if (cached != null) {
        sourceData['offline'] = true;
      } else if (item.source == 'nas') {
        if (item.videoId == null) {
          throw const FormatException('学习项缺少 NAS 视频 ID');
        }
        final response = await api.get('/videos/${item.videoId}');
        sourceData = {...sourceData, ...studyMap(response.data)};
      } else {
        await bili.initialize();
      }
      if (isClosed) return;
      final video = videoForItem(item,
          sourceData: sourceData, positionSeconds: positionSeconds);
      videoController.courseQueue.assignAll(itemsFor(item.listId)
          .map((entry) => entry.id == item.id ? video : videoForItem(entry)));
      if (videoController.courseQueue.isEmpty) {
        videoController.courseQueue.add(video);
      }
      final index =
          videoController.allVideos.indexWhere((v) => v.id == video.id);
      if (index < 0) {
        videoController.allVideos.add(video);
      } else {
        videoController.allVideos[index] = video;
      }
      await Get.toNamed(AppRoutes.videoPlayer, arguments: video);
      if (!isClosed) await refreshAll();
    } catch (error) {
      if (!isClosed) errors['play'] = '$error';
    } finally {
      if (!isClosed) busy.remove('play');
    }
  }
}
