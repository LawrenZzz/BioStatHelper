import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bio_stat_helper/core/services/api_client.dart';
import 'package:bio_stat_helper/core/services/study_media_cache.dart';
import 'package:bio_stat_helper/shared/models/video_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api implements ApiClient {
  @override
  String get baseUrl => 'https://nas.test:8443/api/v1';
  @override
  String? get token => 'nas-token';
  @override
  String absoluteUrl(String path) =>
      Uri.parse(baseUrl).resolve(path).toString();
  @override
  bool isBackendUrl(String url) =>
      Uri.parse(absoluteUrl(url)).origin == Uri.parse(baseUrl).origin;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final FutureOr<ResponseBody> Function(RequestOptions) respond;
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
        String type = 'video/mp4',
        String? range}) =>
    ResponseBody.fromBytes(bytes, status, headers: {
      'content-type': [type],
      'content-length': ['${length ?? bytes.length}'],
      'etag': ['"same-representation"'],
      if (range != null) 'content-range': [range]
    });

Video _video({String source = 'nas', List<VideoSidecar> sidecars = const []}) =>
    Video.fromJson({
      'id': source == 'nas' ? 42 : -7,
      'study_item_id': 7,
      'source': source,
      'title': 'Offline lesson',
      'duration_seconds': 60,
      'source_data': {'bvid': 'BV17x411w7KC', 'cid': 123},
      'sidecars': sidecars.map((item) => item.toJson()).toList()
    });

const _subtitle = StudyCacheAttachment.text(
    id: 'en',
    kind: 'subtitle',
    extension: '.srt',
    title: 'English',
    text: '1\n00:00:00,000 --> 00:00:01,500\nHello\n');
const _danmaku = StudyCacheAttachment.text(
    id: 'comments',
    kind: 'danmaku',
    extension: '.xml',
    title: 'Comments',
    text: '<i><d p="1,1,25,16777215">Hi</d></i>');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late String scope;
  final caches = <StudyMediaCache>[];
  StudyMediaCache cache(_Adapter adapter) {
    final value = StudyMediaCache(
        dio: Dio()..httpClientAdapter = adapter,
        api: _Api(),
        rootDirectory: () async => directory,
        scope: () => scope);
    caches.add(value);
    return value;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('study-bundle-');
    scope = 'server-a_user-a';
  });
  tearDown(() async {
    for (final value in caches) {
      value.dispose();
    }
    caches.clear();
    await directory.delete(recursive: true);
  });

  test(
      'ordered segments publish only verified local files as byte-escaped mpv EDL',
      () async {
    directory =
        await Directory('${directory.path}/\u5b66\u4e60 space').create();
    final adapter = _Adapter(
        (request) => _body([request.uri.path.endsWith('first') ? 1 : 2]));
    final value = cache(adapter);
    final video = _video();
    await value.downloadBundle(
        video, ['https://cdn.test/first', 'https://cdn.test/second'], {});
    final bundle = (await value.localBundle(video))!;
    expect(bundle.segments.length, 2);
    expect(await File(bundle.segments[0]).readAsBytes(), [1]);
    expect(await File(bundle.segments[1]).readAsBytes(), [2]);
    expect(bundle.videoPath,
        'edl://${bundle.segments.map((path) => '%${utf8.encode(path).length}%$path').join(';')}');
    expect(await value.localPath(video), bundle.videoPath);
    final entry = (await value.entries()).single;
    expect(entry.layout, 'segments');
    expect(entry.complete, true);
    expect(entry.receivedBytes, 2);
    expect(entry.totalBytes, 2);
  });

  test(
      'DASH stores independent complete video and audio, never a fake muxed file',
      () async {
    final value = cache(_Adapter((request) =>
        _body(request.uri.path.contains('audio') ? [3, 4] : [1, 2])));
    final video = _video(source: 'bilibili');
    await value.downloadBundle(video, ['https://cdn.test/video.m4s'], {},
        audioUrl: 'https://cdn.test/audio.m4s');
    final bundle = (await value.localBundle(video))!;
    expect(await File(bundle.videoPath).readAsBytes(), [1, 2]);
    expect(await File(bundle.audioPath!).readAsBytes(), [3, 4]);
    expect(bundle.videoPath, isNot(bundle.audioPath));
    expect(await value.localPath(video), isNull);
    expect((await value.entries()).single.layout, 'dash');
    expect((await value.entries()).single.receivedBytes, 4);
  });

  test('audio retry uses fresh URL and validator Range, keeps verified video',
      () async {
    final video = _video(source: 'bilibili');
    final first = cache(_Adapter((request) => request.uri.path.contains('audio')
        ? _body([3, 4], length: 5)
        : _body([1, 2])));
    await expectLater(
        first.downloadBundle(video, ['https://cdn.test/video.m4s'], {},
            audioUrl: 'https://cdn.test/audio.m4s?expired=1'),
        throwsStateError);
    expect(await first.localBundle(video), isNull);
    expect((await first.entries()).single.complete, false);
    final adapter = _Adapter((request) {
      expect(request.uri.query, 'fresh=2');
      expect(request.headers['Range'], 'bytes=2-');
      expect(request.headers['If-Range'], '"same-representation"');
      return _body([5, 6, 7], status: 206, range: 'bytes 2-4/5');
    });
    final restarted = cache(adapter);
    await restarted.downloadBundle(
        video, ['https://cdn.test/video.m4s?fresh=2'], {},
        audioUrl: 'https://cdn.test/audio.m4s?fresh=2');
    expect(adapter.requests.length, 1);
    final bundle = (await restarted.localBundle(video))!;
    expect(await File(bundle.audioPath!).readAsBytes(), [3, 4, 5, 6, 7]);
  });

  test('single-file bundle reuses a legacy cache without another media request',
      () async {
    final adapter = _Adapter((_) => _body([1, 2, 3]));
    final value = cache(adapter);
    final video = _video();
    await value.download(video, 'https://cdn.test/old', {});
    final oldPath = await value.localPath(video);
    await value.downloadBundle(video, ['https://cdn.test/fresh'], {},
        attachments: [_subtitle]);
    expect(adapter.requests.length, 1);
    expect(await value.localPath(video), oldPath);
    expect((await value.localBundle(video))!.sidecars.length, 1);
  });

  test(
      'a full uncommitted partial file restarts instead of requesting an invalid tail',
      () async {
    final video = _video();
    final value = cache(_Adapter((_) => _body([1, 2], length: 5)));
    await expectLater(
        value.download(video, 'https://cdn.test/old', {}), throwsStateError);
    final partial = (await Directory('${directory.path}/study_cache/$scope')
            .list()
            .toList())
        .whereType<File>()
        .singleWhere((file) => file.path.endsWith('.part'));
    await partial.writeAsBytes([1, 2, 3, 4, 5]);
    final adapter = _Adapter((request) {
      expect(request.headers['Range'], isNull);
      return _body([6, 7, 8, 9, 10]);
    });
    final restarted = cache(adapter);
    await restarted.download(video, 'https://cdn.test/fresh', {});
    expect(await File((await restarted.localPath(video))!).readAsBytes(),
        [6, 7, 8, 9, 10]);
  });

  test('a changed Range total restarts even when a server reuses the ETag',
      () async {
    final video = _video();
    final value = cache(_Adapter((_) => _body([1, 2], length: 5)));
    await expectLater(
        value.download(video, 'https://cdn.test/old', {}), throwsStateError);
    var count = 0;
    final adapter = _Adapter((request) {
      if (count++ == 0) {
        expect(request.headers['Range'], 'bytes=2-');
        return _body([3, 4, 5, 6], status: 206, range: 'bytes 2-5/6');
      }
      expect(request.headers['Range'], isNull);
      return _body([7, 8, 9, 10, 11, 12]);
    });
    final restarted = cache(adapter);
    await restarted.download(video, 'https://cdn.test/fresh', {});
    expect(adapter.requests.length, 2);
    expect(await File((await restarted.localPath(video))!).readAsBytes(),
        [7, 8, 9, 10, 11, 12]);
  });

  test(
      'incomplete segment, malformed range and unknown-length audio never publish bundles',
      () async {
    final video = _video();
    final broken = cache(_Adapter((request) =>
        request.uri.path.endsWith('second')
            ? _body([2], length: 3)
            : _body([1])));
    await expectLater(
        broken.downloadBundle(
            video, ['https://cdn.test/first', 'https://cdn.test/second'], {}),
        throwsStateError);
    expect(await broken.localPath(video), isNull);
    await broken.remove(video);
    final malformed =
        cache(_Adapter((_) => _body([1], status: 206, range: 'bytes 4-4/5')));
    await expectLater(
        malformed.downloadBundle(video, ['https://cdn.test/first'], {}),
        throwsStateError);
    expect(await malformed.localBundle(video), isNull);
    await malformed.remove(video);
    final unknown = cache(_Adapter((request) =>
        request.uri.path.contains('audio')
            ? ResponseBody.fromBytes([2], 200)
            : _body([1])));
    await expectLater(
        unknown.downloadBundle(video, ['https://cdn.test/video'], {},
            audioUrl: 'https://cdn.test/audio'),
        throwsStateError);
    expect(await unknown.localBundle(video), isNull);
    expect((await unknown.entries()).single.complete, false);
  });

  test(
      'all tracks retain exact NAS origin authentication and reject caller credentials',
      () async {
    final adapter = _Adapter((_) => _body([1]));
    final value = cache(adapter);
    await value.downloadBundle(_video(), ['https://cdn.test/video.m4s'],
        {'Authorization': 'foreign', 'Cookie': 'secret'},
        audioUrl: 'https://nas.test:8443/audio.m4s');
    expect(adapter.requests.first.headers['Authorization'], isNull);
    expect(adapter.requests.last.headers['Authorization'], 'Bearer nas-token');
    await value.downloadBundle(
        _video(source: 'bilibili'), ['https://nas.test:8443/video.m4s'], {},
        audioUrl: 'https://nas.test/audio.m4s');
    for (final request in adapter.requests.skip(2)) {
      expect(request.headers['Authorization'], isNull);
    }
    for (final request in adapter.requests) {
      expect(request.headers['Cookie'], isNull);
      expect(request.headers.values, isNot(contains('foreign')));
      expect(request.followRedirects, false);
    }
  });

  test(
      'NAS downloads cache text sidecars with exact-origin auth and verified local reads',
      () async {
    final video = _video(sidecars: [
      const VideoSidecar(
          id: 1,
          fileName: 'en.srt',
          extension: '.srt',
          kind: 'subtitle',
          title: 'English',
          url: 'https://nas.test:8443/subtitle'),
      const VideoSidecar(
          id: 2,
          fileName: 'comments.xml',
          extension: '.xml',
          kind: 'danmaku',
          title: 'Comments',
          url: 'https://cdn.test/comments')
    ]);
    final adapter = _Adapter((request) => request.uri.path == '/video'
        ? _body([1])
        : _body(
            utf8.encode(request.uri.path == '/subtitle'
                ? _subtitle.text!
                : _danmaku.text!),
            type: 'text/plain'));
    final value = cache(adapter);
    await value.download(video, 'https://nas.test:8443/video', {});
    final bundle = (await value.localBundle(video))!;
    expect(bundle.sidecars.length, 2);
    expect(
        await value.readSidecar(video, bundle.sidecars.first), _subtitle.text);
    expect(adapter.requests[1].headers['Authorization'], 'Bearer nas-token');
    expect(adapter.requests[2].headers['Authorization'], isNull);
    expect((await value.entries()).single.attachments.length, 2);
    expect(
        (await cache(_Adapter((_) => throw StateError('No network')))
                .localBundle(video))!
            .sidecars
            .length,
        2);
  });

  test(
      'Bili SRT and XML inline attachments need no network and survive restart',
      () async {
    final video = _video(source: 'bilibili');
    final adapter = _Adapter((_) => _body([1]));
    final value = cache(adapter);
    await value.downloadBundle(video, ['https://cdn.test/video'], {},
        attachments: [_subtitle, _danmaku]);
    expect(adapter.requests.length, 1);
    final bundle = (await value.localBundle(video))!;
    expect(bundle.sidecars.map((item) => item.extension), ['.srt', '.xml']);
    expect(await value.readSidecar(video, bundle.sidecars.last), _danmaku.text);
    expect(
        await cache(_Adapter((_) => throw StateError('No network')))
            .localPath(video),
        bundle.videoPath);
  });

  test(
      'arbitrary file URLs, tampered bytes and cross-account sidecars are not readable',
      () async {
    final video = _video();
    final value = cache(_Adapter((_) => _body([1])));
    await value.download(video, 'https://cdn.test/video', {});
    await value.cacheAttachments(video, [_subtitle]);
    final sidecar = (await value.localBundle(video))!.sidecars.single;
    final foreign = VideoSidecar(
        id: sidecar.id,
        fileName: 'secret',
        extension: '.srt',
        kind: 'subtitle',
        title: '',
        url: File('${directory.path}/secret.srt').uri.toString());
    expect(await value.readSidecar(video, foreign), isNull);
    scope = 'server-a_user-b';
    expect(await value.readSidecar(video, sidecar), isNull);
    expect(await value.localBundle(video), isNull);
    scope = 'server-a_user-a';
    final file = File.fromUri(Uri.parse(sidecar.url));
    final text = await file.readAsString();
    await file.writeAsString(text.replaceFirst('Hello', 'Jello'));
    expect(await value.readSidecar(video, sidecar), isNull);
    expect((await value.localBundle(video))!.sidecars, isEmpty);
  });

  test(
      'attachment format, size, encoding and HTTP length failures preserve media',
      () async {
    var mode = 'html';
    final adapter = _Adapter((request) => request.uri.path == '/video'
        ? _body([1])
        : mode == 'html'
            ? _body(utf8.encode('<html>login</html>'), type: 'text/html')
            : mode == 'short'
                ? _body([65], length: 5, type: 'text/plain')
                : mode == 'binary'
                    ? _body([255, 254], type: 'text/plain')
                    : mode == 'large'
                        ? _body([65],
                            length: 8 * 1024 * 1024 + 1, type: 'text/plain')
                        : _body(
                            utf8.encode(
                                '<!DOCTYPE i [<!ENTITY x SYSTEM "file:///secret">]><i/>'),
                            type: 'text/xml'));
    final value = cache(adapter);
    final video = _video();
    await value.download(video, 'https://cdn.test/video', {});
    const remote = StudyCacheAttachment.remote(
        id: 'remote',
        kind: 'subtitle',
        extension: '.srt',
        url: 'https://cdn.test/attachment');
    for (mode in ['html', 'short', 'binary', 'large', 'entity']) {
      await expectLater(value.cacheAttachments(video, [remote]),
          throwsA(anyOf(isA<Exception>(), isA<Error>())));
      expect(value.attachmentErrors[value.keyFor(video)], isNotNull);
      expect(await value.localPath(video), isNotNull);
      expect(await value.localAttachments(video), isEmpty);
    }
    await expectLater(
        value.cacheAttachments(video, [
          const StudyCacheAttachment.text(
              id: '../escape',
              kind: 'subtitle',
              extension: '/../srt',
              text: 'data')
        ]),
        throwsArgumentError);
  });

  test('optional attachment failure does not report incomplete media',
      () async {
    final value = cache(_Adapter((request) => request.uri.path == '/video'
        ? _body([1])
        : _body(utf8.encode('<html>blocked</html>'), type: 'text/html')));
    final video = _video();
    await value.downloadBundle(video, [
      'https://cdn.test/video'
    ], {}, attachments: [
      const StudyCacheAttachment.remote(
          id: 'sub',
          kind: 'subtitle',
          extension: '.srt',
          url: 'https://cdn.test/sub')
    ]);
    expect(await value.localBundle(video), isNotNull);
    expect(value.progress[value.keyFor(video)], 1);
    expect(value.errors[value.keyFor(video)], isNull);
    expect(value.attachmentErrors[value.keyFor(video)], isNotNull);
  });

  test(
      'remove cancels active bundle, never starts later parts and removes every artifact',
      () async {
    final gate = Completer<void>();
    Stream<Uint8List> bytes() async* {
      yield Uint8List.fromList([1]);
      await gate.future;
      yield Uint8List.fromList([2]);
    }

    final adapter = _Adapter((_) => ResponseBody(bytes(), 200, headers: {
          'content-length': ['2'],
          'content-type': ['video/mp4'],
          'etag': ['"v1"']
        }));
    final value = cache(adapter);
    final video = _video();
    final received = Completer<void>();
    final subscription = value.progress.listen((rows) {
      if ((rows[value.keyFor(video)] ?? 0) > 0 && !received.isCompleted) {
        received.complete();
      }
    });
    addTearDown(subscription.cancel);
    final downloading = value.downloadBundle(
        video, ['https://cdn.test/first', 'https://cdn.test/second'], {});
    await received.future;
    final removing = value.remove(video);
    gate.complete();
    await downloading;
    await removing;
    expect(adapter.requests.length, 1);
    expect(await value.entries(), isEmpty);
    final files =
        await Directory('${directory.path}/study_cache/$scope').list().toList();
    expect(files, isEmpty);
  });

  test(
      'remove cancels attachment and deletes all media and attachment artifacts',
      () async {
    final gate = Completer<void>();
    final emitted = Completer<void>();
    Stream<Uint8List> bytes() async* {
      yield Uint8List.fromList([65]);
      emitted.complete();
      await gate.future;
      yield Uint8List.fromList([66]);
    }

    final value = cache(_Adapter((request) => request.uri.path == '/video'
        ? _body([1])
        : ResponseBody(bytes(), 200, headers: {
            'content-length': ['2'],
            'content-type': ['text/plain']
          })));
    final video = _video();
    await value.download(video, 'https://cdn.test/video', {});
    final downloading = value.cacheAttachments(video, [
      const StudyCacheAttachment.remote(
          id: 'sub',
          kind: 'subtitle',
          extension: '.srt',
          url: 'https://cdn.test/sub'),
      _danmaku
    ]);
    await emitted.future;
    expect(value.isCachingAttachments(video), true);
    final removing = value.remove(video);
    gate.complete();
    await downloading;
    await removing;
    expect(value.isCachingAttachments(video), false);
    expect(await value.entries(), isEmpty);
    expect(
        await Directory('${directory.path}/study_cache/$scope').list().toList(),
        isEmpty);
  });

  test(
      'a scope switch aborts remaining tracks and rejects previously fetched attachments',
      () async {
    final gate = Completer<void>();
    final emitted = Completer<void>();
    Stream<Uint8List> bytes() async* {
      yield Uint8List.fromList([1]);
      emitted.complete();
      await gate.future;
      yield Uint8List.fromList([2]);
    }

    final adapter = _Adapter((_) => ResponseBody(bytes(), 200, headers: {
          'content-length': ['2'],
          'content-type': ['video/mp4']
        }));
    final value = cache(adapter);
    final video = _video();
    final previousScope = scope;
    final checked = expectLater(
        value.downloadBundle(
            video, ['https://cdn.test/first', 'https://cdn.test/second'], {}),
        throwsStateError);
    await emitted.future;
    scope = 'server-b_user-b';
    gate.complete();
    await checked;
    expect(adapter.requests.length, 1);
    expect(await value.entries(), isEmpty);
    expect(value.isDownloading(video), false);
    await expectLater(
        value.cacheAttachments(video, [_subtitle],
            expectedScope: previousScope),
        throwsStateError);
    expect(await value.localAttachments(video), isEmpty);
  });

  test(
      'scope switch during attachment streaming cannot publish into either account',
      () async {
    final gate = Completer<void>();
    final emitted = Completer<void>();
    Stream<Uint8List> bytes() async* {
      yield Uint8List.fromList([65]);
      emitted.complete();
      await gate.future;
      yield Uint8List.fromList([66]);
    }

    final value = cache(_Adapter((request) => request.uri.path == '/video'
        ? _body([1])
        : ResponseBody(bytes(), 200, headers: {
            'content-length': ['2'],
            'content-type': ['text/plain']
          })));
    final video = _video();
    await value.download(video, 'https://cdn.test/video', {});
    final checked = expectLater(
        value.cacheAttachments(video, [
          const StudyCacheAttachment.remote(
              id: 'sub',
              kind: 'subtitle',
              extension: '.srt',
              url: 'https://cdn.test/sub')
        ]),
        throwsStateError);
    await emitted.future;
    scope = 'server-b_user-b';
    gate.complete();
    await checked;
    expect(await value.localAttachments(video), isEmpty);
    scope = 'server-a_user-a';
    expect(await value.localAttachments(video), isEmpty);
  });
}
