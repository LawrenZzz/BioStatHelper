import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bio_stat_helper/app/modules/video/controllers/study_controller.dart';
import 'package:bio_stat_helper/app/modules/video/views/study_offline_view.dart';
import 'package:bio_stat_helper/core/services/api_client.dart';
import 'package:bio_stat_helper/core/services/bilibili_service.dart';
import 'package:bio_stat_helper/core/services/study_media_cache.dart';
import 'package:bio_stat_helper/core/services/study_progress_sync.dart';
import 'package:bio_stat_helper/shared/models/study_model.dart';
import 'package:bio_stat_helper/shared/models/video_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;

class _Api implements ApiClient {
  @override
  String get baseUrl => 'https://nas.example:8443/api/v1';
  @override
  String? get token => 'nas-token';
  @override
  String absoluteUrl(String path) =>
      Uri.parse(baseUrl).resolve(path).toString();
  @override
  bool isBackendUrl(String url) =>
      Uri.parse(absoluteUrl(url)).origin == Uri.parse(baseUrl).origin;
  final gets = <String>[];
  dynamic data = {'data': []};
  @override
  Future<Response> get(String path,
      {Map<String, dynamic>? queryParameters}) async {
    gets.add(path);
    return Response(requestOptions: RequestOptions(path: path), data: data);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions request) respond;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _body(List<int> bytes,
        {int status = 200,
        int? length,
        String? range,
        String? etag = '"v1"'}) =>
    ResponseBody.fromBytes(bytes, status, headers: {
      'content-type': ['video/mp4'],
      'content-length': ['${length ?? bytes.length}'],
      if (range != null) 'content-range': [range],
      if (etag != null) 'etag': [etag],
    });

final _video = Video.fromJson({
  'id': 42,
  'study_item_id': 7,
  'source': 'nas',
  'title': '课程缓存',
  'duration_seconds': 600,
  'video_url': '/videos/42/stream'
});
const _item = StudyItem(
    id: 7, listId: 1, videoId: 42, title: '课程缓存', durationSeconds: 600);
const _biliItem = StudyItem(
    id: 8,
    listId: 1,
    source: 'bilibili',
    title: '在线课程',
    sourceData: {'bvid': 'BV17x411w7KC', 'cid': 123});

class _Bili extends BilibiliService {
  int resolutions = 0;
  bool dash = false;
  bool multiple = false;
  @override
  Future<void> initialize() async {}
  @override
  Future<List<BiliSubtitle>> getSubtitles(String bvid, int cid) async => [
        const BiliSubtitle(
            id: 'en',
            language: 'en',
            label: 'English',
            url: 'https://unused.example/subtitle')
      ];
  @override
  Future<List<BiliSubtitleCue>> getSubtitleBody(BiliSubtitle subtitle) async =>
      [const BiliSubtitleCue(from: 0, to: 2, content: 'Offline subtitle')];
  @override
  Future<String> getDanmakuXml(int cid) async =>
      '<i><d p="1,1,25,16777215">Offline comment</d></i>';
  @override
  Future<BiliPlayback> resolvePlayback(String bvid, int cid,
      {int quality = 80, double speed = 1}) async {
    resolutions++;
    return BiliPlayback(
        segments: dash
            ? []
            : [
                'https://cdn.example/video.mp4?fresh=$resolutions',
                if (multiple) 'https://cdn.example/second.mp4'
              ],
        isDash: dash,
        videoUrl: dash ? 'https://cdn.example/video.m4s' : null,
        audioUrl: dash ? 'https://cdn.example/audio.m4s' : null,
        headers: {
          'User-Agent': 'test',
          'Referer': 'https://www.bilibili.com/',
          'Authorization': 'must-not-leak',
          'Cookie': 'must-not-leak'
        },
        quality: 80,
        requestedQuality: 80,
        availableQualities: [80],
        speed: 1);
  }
}

class _Pending extends StudyProgressSync {
  _Pending(this.rows) : super(scope: () => null);
  final Map<int, Map<String, dynamic>> rows;
  @override
  Future<Map<int, Map<String, dynamic>>> pendingItems() async => rows;
  @override
  Future<void> flush() async {}
}

class _ViewCache extends StudyMediaCache {
  final account = 'a'.obs;
  bool complete = false;
  @override
  String? get scopeKey => account.value;
  @override
  Future<List<StudyCacheEntry>> entries() async => account.value == 'a'
      ? [
          StudyCacheEntry(
              video: _video,
              complete: complete,
              receivedBytes: 4,
              totalBytes: 10)
        ]
      : [];
}

class _ViewController extends StudyController {
  _ViewController(this.cache) : super(api: _Api(), mediaCache: cache);
  final _ViewCache cache;
  int retries = 0;
  @override
  Future<void> cacheItem(StudyItem item) async {
    retries++;
    final key = cache.keyFor(videoForItem(item));
    if (retries == 1) {
      cache.errors[key] = '地址解析失败';
      throw StateError('地址解析失败');
    }
    cache.errors.remove(key);
    cache.complete = true;
    cache.progress[key] = 1;
    cache.revision.value++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late String scope;
  late _Api api;
  final caches = <StudyMediaCache>[];

  StudyMediaCache cache(_Adapter adapter) {
    final value = StudyMediaCache(
        dio: Dio()..httpClientAdapter = adapter,
        api: api,
        rootDirectory: () async => directory,
        scope: () => scope);
    caches.add(value);
    return value;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('study-cache-test-');
    scope = 'server-a_user-a';
    api = _Api();
  });
  tearDown(() async {
    for (final value in caches) {
      value.dispose();
    }
    caches.clear();
    await directory.delete(recursive: true);
  });

  test('incomplete task survives restart and resumes a validated fresh URL',
      () async {
    final first = cache(_Adapter((_) => _body([0, 1, 2, 3], length: 10)));
    await expectLater(
        first.download(_video, 'https://nas.example:8443/old', {}),
        throwsStateError);
    expect(await first.localPath(_video), isNull);
    expect((await first.entries()).single.receivedBytes, 4);
    final adapter = _Adapter((request) {
      expect(request.headers['Range'], 'bytes=4-');
      expect(request.headers['If-Range'], '"v1"');
      return _body([4, 5, 6, 7, 8, 9], status: 206, range: 'bytes 4-9/10');
    });
    final restarted = cache(adapter);
    expect((await restarted.entries()).single.complete, false);
    await restarted.download(_video, 'https://nas.example:8443/fresh', {});
    expect(await File((await restarted.localPath(_video))!).readAsBytes(),
        List.generate(10, (index) => index));
    expect((await restarted.list()).single.id, 42);
  });

  test('pause retains a resumable task and cancels the active state', () async {
    final gate = Completer<void>();
    Stream<Uint8List> bytes() async* {
      yield Uint8List.fromList([0, 1, 2, 3]);
      await gate.future;
      yield Uint8List.fromList([4, 5, 6, 7, 8, 9]);
    }

    final value = cache(_Adapter((_) => ResponseBody(bytes(), 200, headers: {
          'content-length': ['10'],
          'content-type': ['video/mp4'],
          'etag': ['"v1"'],
        })));
    final received = Completer<void>();
    final subscription = value.progress.listen((progress) {
      if ((progress[value.keyFor(_video)] ?? 0) > 0 && !received.isCompleted) {
        received.complete();
      }
    });
    addTearDown(subscription.cancel);
    final downloading =
        value.download(_video, 'https://nas.example:8443/file', {});
    await received.future;
    expect(value.isDownloading(_video), true);
    value.pause(_video);
    gate.complete();
    await downloading;
    expect(value.isDownloading(_video), false);
    expect(await value.localPath(_video), isNull);
    expect((await value.entries()).single.receivedBytes, 4);
    expect(value.errors[value.keyFor(_video)], isNull);
  });

  test('validator change restarts instead of combining different resources',
      () async {
    final value = cache(_Adapter((_) => _body([1, 1], length: 5)));
    await expectLater(
        value.download(_video, 'https://nas.example:8443/old', {}),
        throwsStateError);
    var request = 0;
    final adapter = _Adapter((options) {
      if (request++ == 0) {
        return _body([2, 2, 2],
            status: 206, range: 'bytes 2-4/5', etag: '"v2"');
      }
      expect(options.headers.containsKey('Range'), false);
      return _body([2, 2, 2, 2, 2], etag: '"v2"');
    });
    final restarted = cache(adapter);
    await restarted.download(_video, 'https://nas.example:8443/new', {});
    expect(adapter.requests.length, 2);
    expect(await File((await restarted.localPath(_video))!).readAsBytes(),
        [2, 2, 2, 2, 2]);
  });

  test('without a resource validator a retry safely starts from zero',
      () async {
    final value = cache(_Adapter((_) => _body([1, 1], length: 5, etag: null)));
    await expectLater(
        value.download(_video, 'https://nas.example:8443/old', {}),
        throwsStateError);
    final adapter = _Adapter((request) {
      expect(request.headers.containsKey('Range'), false);
      return _body([2, 2, 2, 2, 2]);
    });
    final restarted = cache(adapter);
    await restarted.download(_video, 'https://nas.example:8443/new', {});
    expect(await File((await restarted.localPath(_video))!).readAsBytes(),
        [2, 2, 2, 2, 2]);
  });

  test('malformed partial range and unknown lengths never become playable',
      () async {
    final adapter =
        _Adapter((_) => _body([1, 2], status: 206, range: 'bytes 3-4/5'));
    final value = cache(adapter);
    await expectLater(
        value.download(_video, 'https://nas.example:8443/file', {}),
        throwsStateError);
    expect(await value.list(), isEmpty);
    final unknown = cache(_Adapter((_) => ResponseBody.fromBytes([1, 2], 200,
        headers: {
          'content-type': ['video/mp4']
        })));
    await expectLater(
        unknown.download(_video, 'https://nas.example:8443/file', {}),
        throwsStateError);
    expect(await unknown.localPath(_video), isNull);
  });

  test(
      'NAS authentication only reaches the exact NAS origin; caller secrets are discarded',
      () async {
    final adapter = _Adapter((_) => _body([1, 2, 3]));
    final value = cache(adapter);
    for (final url in [
      'https://nas.example:8443/video',
      'https://nas.example/video',
      'https://cdn.example/video',
      'https://nas.example.evil.test:8443/video'
    ]) {
      await value.remove(_video);
      await value.download(_video, url, {
        'authorization': 'foreign-token',
        'Cookie': 'session',
        'Referer': 'https://www.bilibili.com/'
      });
      final headers = adapter.requests.last.headers;
      expect(headers['Authorization'],
          url == 'https://nas.example:8443/video' ? 'Bearer nas-token' : null);
      expect(headers.keys.any((key) => key.toLowerCase() == 'cookie'), false);
      expect(headers.values, isNot(contains('foreign-token')));
      expect(adapter.requests.last.followRedirects, false);
    }
  });

  test('server/account namespaces isolate progress, errors and files',
      () async {
    final value = cache(_Adapter((_) => _body([1, 2], length: 5)));
    final firstKey = value.keyFor(_video);
    await expectLater(
        value.download(_video, 'https://nas.example:8443/video', {}),
        throwsStateError);
    expect(value.errors[firstKey], isNotNull);
    scope = 'server-a_user-b';
    expect(value.keyFor(_video), isNot(firstKey));
    expect(value.errors[value.keyFor(_video)], isNull);
    expect(value.progress[value.keyFor(_video)], isNull);
    expect(value.isDownloading(_video), false);
    expect(await value.entries(), isEmpty);
    scope = 'server-b_user-a';
    expect(await value.entries(), isEmpty);
    scope = 'server-a_user-a';
    expect((await value.entries()).single.receivedBytes, 2);
  });

  test('switching scope during a transfer cannot publish into the new account',
      () async {
    final gate = Completer<void>();
    final emitted = Completer<void>();
    Stream<Uint8List> bytes() async* {
      yield Uint8List.fromList([1, 2]);
      emitted.complete();
      await gate.future;
      yield Uint8List.fromList([3, 4]);
    }

    final value = cache(_Adapter((_) => ResponseBody(bytes(), 200, headers: {
          'content-length': ['4'],
          'etag': ['"v1"'],
        })));
    final downloading =
        value.download(_video, 'https://nas.example:8443/video', {});
    final checked = expectLater(downloading, throwsStateError);
    await emitted.future;
    scope = 'server-a_user-b';
    expect(value.isDownloading(_video), false);
    gate.complete();
    await checked;
    expect(await value.entries(), isEmpty);
    scope = 'server-a_user-a';
    expect((await value.entries()).single.complete, false);
  });

  test(
      'Bili retry resolves fresh URLs and caches stable DASH, segments and sidecars',
      () async {
    var requests = 0;
    final adapter = _Adapter((request) {
      if (requests++ == 0) return _body([1, 2], length: 5);
      if (requests == 2) {
        expect(request.headers['Range'], 'bytes=2-');
        expect(request.headers['If-Range'], '"v1"');
        return _body([3, 4, 5], status: 206, range: 'bytes 2-4/5');
      }
      return _body([6, 7, 8]);
    });
    final media = cache(adapter);
    final bili = _Bili();
    final controller =
        StudyController(api: api, bilibili: bili, mediaCache: media);
    addTearDown(controller.onDelete.call);
    addTearDown(bili.dispose);
    await expectLater(controller.cacheItem(_biliItem), throwsStateError);
    await controller.cacheItem(_biliItem);
    expect(bili.resolutions, 2);
    expect(
        adapter.requests.map((request) => request.uri.queryParameters['fresh']),
        ['1', '2']);
    expect(
        adapter.requests.every((request) => !request.headers.keys.any(
            (key) => {'authorization', 'cookie'}.contains(key.toLowerCase()))),
        true);
    bili.dash = true;
    await controller.cacheItem(_biliItem);
    final video = controller.videoForItem(_biliItem);
    final dash = (await media.localBundle(video))!;
    expect(dash.audioPath, isNotNull);
    expect(await media.localPath(video), isNull);
    expect(dash.sidecars.map((sidecar) => sidecar.extension), ['.srt', '.xml']);
    expect(await media.readSidecar(video, dash.sidecars.first),
        contains('Offline subtitle'));
    bili.dash = false;
    bili.multiple = true;
    await controller.cacheItem(_biliItem);
    final segments = (await media.localBundle(video))!;
    expect(segments.videoPath, startsWith('edl://'));
    expect(segments.segments.length, 2);
    expect(segments.audioPath, isNull);
    expect(adapter.requests.length, 6);
    final manifests = (await Directory('${directory.path}/study_cache/$scope')
            .list()
            .toList())
        .whereType<File>()
        .where((file) =>
            file.path.endsWith('.json') &&
            !file.path.contains('.track.') &&
            !file.path.contains('.attachments.'));
    final manifest = jsonDecode(await manifests.single.readAsString()) as Map;
    expect(
        (manifest['_cache']['tracks'] as List).every(
            (track) => (track['id'] as String).startsWith('quality:80:')),
        true);
    expect(
        adapter.requests.every((request) => !request.headers.keys.any(
            (key) => {'authorization', 'cookie'}.contains(key.toLowerCase()))),
        true);
  });

  test(
      'NAS retry fetches video detail instead of reusing a stale stored address',
      () async {
    api.data = {'id': 42, 'title': '课程', 'video_url': '/new-stream'};
    final adapter = _Adapter((_) => _body([1, 2, 3]));
    final controller = StudyController(api: api, mediaCache: cache(adapter));
    addTearDown(controller.onDelete.call);
    await controller.cacheItem(_item);
    expect(api.gets, ['/videos/42']);
    expect(adapter.requests.single.uri.path, '/new-stream');
  });

  test(
      'continue prioritizes last watched learning and pending zero duration preserves known duration',
      () async {
    final rows = [
      {
        'id': 7,
        'list_id': 1,
        'title': '较早观看',
        'source': 'nas',
        'video_id': 42,
        'duration_seconds': 600,
        'status': 'learning',
        'sort_order': 0,
        'last_watched_at': '2026-10-19T00:00:00Z'
      },
      {
        'id': 8,
        'list_id': 1,
        'title': '较新观看',
        'source': 'nas',
        'video_id': 43,
        'duration_seconds': 500,
        'status': 'learning',
        'sort_order': 9,
        'last_watched_at': '2026-10-20T00:00:00Z'
      },
    ];
    api.data = {'data': rows};
    final sync = _Pending({
      7: {
        'position_seconds': 120,
        'duration_seconds': 0,
        'completed': false,
        'recorded_at': '2026-10-21T00:00:00Z'
      }
    });
    final controller = StudyController(api: api, progressSync: sync);
    addTearDown(controller.onDelete.call);
    controller.lists.assignAll(const [StudyList(id: 1, name: '课程')]);
    controller.items.assignAll(rows.map(StudyItem.fromJson));
    expect(controller.continueItem?.id, 8);
    await controller.refreshItems();
    expect(controller.items.first.durationSeconds, 600);
    expect(controller.items.first.positionSeconds, 120);
    expect(controller.items.first.lastWatchedAt, DateTime.utc(2026, 10, 21));
    expect(controller.continueItem?.id, 7);
  });

  testWidgets(
      'paused cache offers continue, failed retry and completion without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final media = _ViewCache();
    final controller = _ViewController(media);
    addTearDown(controller.onDelete.call);
    addTearDown(media.dispose);
    await tester.pumpWidget(
        GetMaterialApp(home: StudyOfflineView(controller: controller)));
    await tester.pumpAndSettle();
    expect(find.byTooltip('继续缓存'), findsOneWidget);
    await tester.tap(find.byTooltip('继续缓存'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('重试缓存'), findsOneWidget);
    await tester.tap(find.byTooltip('重试缓存'));
    await tester.pumpAndSettle();
    expect(controller.retries, 2);
    expect(find.text('已缓存'), findsOneWidget);
    expect(tester.takeException(), isNull);
    media.account.value = 'b';
    await tester.pumpAndSettle();
    expect(find.text('课程缓存'), findsNothing);
    expect(find.text('暂无离线缓存'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
