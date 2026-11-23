import 'dart:async';
import 'dart:convert';

import 'package:bio_stat_helper/app/modules/video/controllers/video_controller.dart';
import 'package:bio_stat_helper/core/services/api_client.dart';
import 'package:bio_stat_helper/core/services/bilibili_service.dart';
import 'package:bio_stat_helper/core/services/study_media_cache.dart';
import 'package:bio_stat_helper/core/services/study_preferences.dart';
import 'package:bio_stat_helper/shared/models/video_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api implements ApiClient {
  Future<dynamic> Function(String)? onGet;
  Future<String> Function(String)? onText;
  final textCalls = <String>[];

  @override
  Future<Response> get(String path,
      {Map<String, dynamic>? queryParameters}) async {
    return Response<dynamic>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: await onGet!(path));
  }

  @override
  Future<String> getText(String path) async {
    textCalls.add(path);
    return await onText!(path);
  }

  @override
  String absoluteUrl(String path) => path;
  @override
  bool isBackendUrl(String path) => path.startsWith('https://nas.test/');
  @override
  String? get token => 'nas-only-token';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Bili extends BilibiliService {
  Future<void> Function()? onInitialize;
  Future<BiliVideo> Function(String)? onVideo;
  Future<BiliPlayback> Function(int)? onResolve;
  Future<List<BiliSubtitle>> Function()? onSubtitles;
  Future<List<BiliSubtitleCue>> Function(BiliSubtitle)? onBody;
  Future<String> Function(int)? onDanmaku;
  final bodyCalls = <String>[];
  final resolvedCids = <int>[];

  @override
  Future<void> initialize() async => await onInitialize?.call();
  @override
  Future<BiliVideo> getVideo(String bvid) => onVideo!(bvid);
  @override
  Future<BiliPlayback> resolvePlayback(String bvid, int cid,
      {int quality = 80, double speed = 1}) async {
    resolvedCids.add(cid);
    return onResolve == null ? _playback() : await onResolve!(cid);
  }

  @override
  Future<List<BiliSubtitle>> getSubtitles(String bvid, int cid) async =>
      await onSubtitles?.call() ?? [];
  @override
  Future<List<BiliSubtitleCue>> getSubtitleBody(BiliSubtitle subtitle) async {
    bodyCalls.add(subtitle.id);
    return await onBody?.call(subtitle) ?? _cues(subtitle.id);
  }

  @override
  Future<String> getDanmakuXml(int cid) async =>
      await onDanmaku?.call(cid) ?? _xml('bili danmaku');
}

class _Cache extends StudyMediaCache {
  @override
  Future<StudyCachedPlayback?> localBundle(Video video) async =>
      video.sourceData['offline'] == true ? _CachedPlayback(video) : null;
}

class _CachedPlayback extends StudyCachedPlayback {
  _CachedPlayback(this.video) : super(mediaUri: video.videoUrl);
  final Video video;
  @override
  List<VideoSidecar> get sidecars => video.sidecars;
}

class _NativePlayer extends PlatformPlayer {
  _NativePlayer() : super(configuration: const PlayerConfiguration());

  final opens = <({Media media, bool play})>[];
  final audio = <AudioTrack>[];
  final subtitles = <SubtitleTrack>[];
  final rates = <double>[];
  final seeks = <Duration>[];
  int playCalls = 0;
  int pauseCalls = 0;
  Future<void> Function()? onOpen;
  Future<void> Function()? onAudio;
  Future<void> Function()? onRate;
  Completer<void>? disposeGate;
  Future<void>? _disposing;
  bool disposeStarted = false;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    opens.add((media: playable as Media, play: play));
    await onOpen?.call();
  }

  @override
  Future<void> setAudioTrack(AudioTrack track) async {
    audio.add(track);
    // Reproduce media_kit's optimistic selected-track update, not readiness.
    state = state.copyWith(track: state.track.copyWith(audio: track));
    trackController.add(state.track);
    await onAudio?.call();
  }

  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) async {
    subtitles.add(track);
  }

  @override
  Future<void> setRate(double rate) async {
    rates.add(rate);
    await onRate?.call();
  }

  @override
  Future<void> play() async => playCalls++;
  @override
  Future<void> pause() async => pauseCalls++;
  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  void videoReady({bool dimensions = true}) {
    state = state.copyWith(
        width: dimensions ? 1280 : null,
        height: dimensions ? 720 : null,
        duration: const Duration(minutes: 10),
        buffering: false,
        tracks: const Tracks(video: [VideoTrack('1', null, null)]));
    tracksController.add(state.tracks);
    widthController.add(state.width);
    heightController.add(state.height);
    durationController.add(state.duration);
    bufferingController.add(state.buffering);
  }

  void audioReady() {
    state = state.copyWith(
        tracks: Tracks(
            video: state.tracks.video,
            audio: const [AudioTrack('2', null, null)]));
    tracksController.add(state.tracks);
  }

  void position(Duration position) => positionController.add(position);
  void completed() => completedController.add(true);
  void log(PlayerLog value) => logController.add(value);

  @override
  Future<void> dispose() async {
    if (disposeStarted) {
      await _disposing;
      return;
    }
    final done = Completer<void>();
    _disposing = done.future;
    disposeStarted = true;
    try {
      await disposeGate?.future;
      await super.dispose();
    } finally {
      done.complete();
    }
  }
}

class _Harness {
  final api = _Api();
  final bili = _Bili();
  final players = <_NativePlayer>[];
  void Function(_NativePlayer)? configure;
  late final VideoController controller;

  _Harness({Duration timeout = const Duration(milliseconds: 150)}) {
    controller = VideoController(
        apiClient: api,
        mediaCache: _Cache(),
        playerFactory: () {
          final native = _NativePlayer();
          players.add(native);
          configure?.call(native);
          return Player(platformPlayer: native);
        },
        videoControllerFactory: (_) => null,
        dashReadyTimeout: timeout)
      ..studyBilibili = bili;
    addTearDown(() async {
      await controller.stopCurrentPlayback();
      controller.onClose();
      await Future.wait(players.map((player) => player.dispose()));
      bili.dispose();
    });
  }

  Future<void> load(Video video) =>
      controller.loadVideoDetail(video.id, initial: video);
}

Video _video(int id,
        {bool bili = true, int? cid, List<VideoSidecar> sidecars = const []}) =>
    Video.fromJson({
      'id': id,
      'title': 'video $id',
      'source': bili ? 'bilibili' : 'nas',
      'video_url': 'https://nas.test/$id.mp4',
      'sidecars': sidecars.map((sidecar) => sidecar.toJson()).toList(),
      'source_data':
          bili ? {'bvid': 'BV1234567890', 'cid': cid ?? id} : {'offline': true},
    });

BiliPlayback _playback(
        {bool dash = false, int quality = 80, List<String>? segments}) =>
    BiliPlayback(
        segments: dash ? [] : segments ?? ['https://cdn.test/video.mp4'],
        videoUrl: dash ? 'https://cdn.test/video.m4s' : null,
        audioUrl: dash ? 'https://cdn.test/audio.m4s' : null,
        headers: const {
          'Referer': 'https://www.bilibili.com/',
          'User-Agent': 'ua'
        },
        quality: quality,
        requestedQuality: quality,
        availableQualities: [quality],
        speed: 1,
        isDash: dash);

const _subA = BiliSubtitle(
    id: 'a', language: 'zh', label: 'a', url: 'https://subtitle.test/a');
const _subB = BiliSubtitle(
    id: 'b', language: 'en', label: 'b', url: 'https://subtitle.test/b');
List<BiliSubtitleCue> _cues(String text) =>
    [BiliSubtitleCue(from: 1, to: 2, content: text)];
VideoSidecar _sidecar(String name, {bool danmaku = false}) => VideoSidecar(
    id: name.hashCode,
    fileName: name,
    extension: danmaku ? '.xml' : '.srt',
    kind: danmaku ? 'danmaku' : 'subtitle',
    title: name,
    url: name);
String _srt(String text) => '1\n00:00:01,000 --> 00:00:02,000\n$text\n';
String _xml(String text) => '<i><d p="1,1,25,16777215">$text</d></i>';

Future<void> _flush() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _until(bool Function() ready) async {
  for (var i = 0; i < 100; i++) {
    if (ready()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Expected asynchronous operation was not reached');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.biostathelper.app/device'),
            (_) async => true);
  });

  test('saved double-tap regions dispatch actions and clamp the seek',
      () async {
    final h = _Harness();
    await h.load(_video(1));
    final native = h.players.single;
    native.videoReady();
    h.controller.applyStudyPreferences(StudyPreferences(
        doubleTapLeftWidth: .2,
        doubleTapRightWidth: .2,
        doubleTapHeight: .4,
        doubleTapCenter: 'none',
        seekSeconds: 15,
        longPressRate: 3.25));
    await h.controller.handleDoubleTap(x: .1, y: .5);
    await h.controller.handleDoubleTap(x: .9, y: .5);
    expect(native.seeks, [Duration.zero, const Duration(seconds: 15)]);
    await h.controller.handleDoubleTap(x: .1, y: .1);
    await h.controller.handleDoubleTap(x: .5, y: .5);
    await h.controller.handleDoubleTap(x: double.nan, y: .5);
    expect(native.seeks, hasLength(2));
    expect(h.controller.longPressRate.value, 3.25);
    h.controller.applyStudyPreferences(
        StudyPreferences(doubleTapCenter: 'seek_forward'));
    native.state =
        native.state.copyWith(position: const Duration(seconds: 599));
    await h.controller.handleDoubleTap(x: .5, y: .5);
    expect(native.seeks.last, const Duration(minutes: 10));
  });

  test('old native identity cannot control the next video or stopped player',
      () async {
    const channel = MethodChannel('com.biostathelper.app/device');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final identities = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'updateMediaPlaybackState') {
        identities.add((call.arguments as Map)['mediaId'] as String);
      }
      return true;
    });
    Future<void> seek(String id) async {
      await messenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(MethodCall('onMediaPlaybackAction', {
            'action': 'seekTo',
            'mediaId': id,
            'positionMs': 2000,
          })),
          null);
      await _flush();
    }

    final h = _Harness();
    h.controller.onInit();
    await h.load(_video(1));
    await _flush();
    final old = identities.last;
    await h.load(_video(2));
    await _flush();
    final current = identities.last;
    expect(old, isNot(current));
    await seek(old);
    expect(h.players.last.seeks, isEmpty);
    await seek(current);
    expect(h.players.last.seeks, [const Duration(seconds: 2)]);
    await h.controller.stopCurrentPlayback();
    await seek(current);
    expect(h.players.last.seeks, hasLength(1));
  });

  test('old detail failure cannot overwrite a newer playback or error',
      () async {
    final h = _Harness();
    final detail = Completer<dynamic>();
    h.api.onGet = (_) => detail.future;
    final old = h.controller.loadVideoDetail(1);
    await _flush();
    h.bili.onResolve = (_) async => throw StateError('current failure');
    await h.load(_video(2));
    final currentError = h.controller.playbackError.value;
    expect(currentError, contains('current failure'));
    detail.completeError(StateError('stale detail failure'));
    await old;
    expect(h.controller.playbackError.value, currentError);
    expect(h.controller.activeVideo.value?.id, 2);
  });

  for (final fails in [false, true]) {
    test('stop invalidates pending detail (failure=$fails)', () async {
      final h = _Harness();
      final detail = Completer<dynamic>();
      h.api.onGet = (_) => detail.future;
      final pending = h.controller.loadVideoDetail(1);
      await _flush();
      await h.controller.stopCurrentPlayback();
      if (fails) {
        detail.completeError(StateError('late detail error'));
      } else {
        detail.complete(_video(1, bili: false).toJson());
      }
      await pending;
      expect(h.players, isEmpty);
      expect(h.controller.playbackError.value, isEmpty);
      expect(h.controller.isVideoLoading.value, isFalse);
    });
  }

  test('late Bili resolution cannot commit quality or open a stale player',
      () async {
    final h = _Harness();
    final resolved = Completer<BiliPlayback>();
    h.bili.onResolve = (cid) async =>
        cid == 1 ? await resolved.future : _playback(quality: 64);
    final old = h.load(_video(1));
    await _until(() => h.bili.resolvedCids.contains(1));
    await h.load(_video(2));
    resolved.complete(_playback(dash: true, quality: 120));
    await old;
    expect(h.controller.activeVideo.value?.id, 2);
    expect(h.controller.playbackQuality.value, 64);
    expect(h.controller.availableQualities, [64]);
    expect(h.players.first.opens, isEmpty);
    expect(h.players.last.audio, isEmpty);
    expect(h.controller.playbackError.value, isEmpty);
  });

  test('late Bili part discovery cannot change current source metadata',
      () async {
    final h = _Harness();
    final detail = Completer<BiliVideo>();
    h.bili.onVideo = (_) => detail.future;
    final old = h.load(_video(1, cid: 0));
    await _flush();
    await h.load(_video(2));
    detail.complete(BiliVideo.fromJson({
      'bvid': 'BV1234567890',
      'pages': [
        {'cid': 99, 'page': 1, 'part': 'old part'}
      ]
    }));
    await old;
    expect(h.controller.activeVideo.value?.sourceData['cid'], 2);
    expect(h.bili.resolvedCids, [2]);
  });

  test('late Bili failure cannot replace a current successful playback',
      () async {
    final h = _Harness();
    final resolved = Completer<BiliPlayback>();
    h.bili.onResolve = (cid) async =>
        cid == 1 ? await resolved.future : _playback(quality: 64);
    final old = h.load(_video(1));
    await _until(() => h.bili.resolvedCids.contains(1));
    await h.load(_video(2));
    resolved.completeError(StateError('stale playback failure'));
    await old;
    expect(h.controller.player, isNotNull);
    expect(h.controller.playbackError.value, isEmpty);
    expect(h.controller.playbackQuality.value, 64);
  });

  for (final fails in [false, true]) {
    test(
        'late course response cannot replace related videos or errors '
        '(failure=$fails)', () async {
      final h = _Harness();
      final course = Completer<dynamic>();
      h.api.onGet = (path) async {
        if (path.contains('/1')) {
          return _video(1, bili: false).copyWith(nasCategoryId: 4).toJson();
        }
        return await course.future;
      };
      final old = h.controller.loadVideoDetail(1);
      await _until(
          () => h.players.isNotEmpty && h.players.single.opens.isNotEmpty);
      await _flush();
      await h.load(_video(2));
      if (fails) {
        course.completeError(StateError('stale course error'));
      } else {
        course.complete({
          'data': [_video(3, bili: false).toJson()]
        });
      }
      await old;
      expect(h.controller.activeVideo.value?.id, 2);
      expect(h.controller.allVideos, isEmpty);
      expect(h.controller.relatedVideos, isEmpty);
      expect(h.controller.playbackError.value, isEmpty);
    });
  }

  test('stop invalidates resolve immediately while disposal is pending',
      () async {
    final h = _Harness();
    final resolved = Completer<BiliPlayback>();
    final disposal = Completer<void>();
    h.configure = (native) => native.disposeGate = disposal;
    h.bili.onResolve = (_) => resolved.future;
    final loading = h.load(_video(1));
    await _until(() => h.bili.resolvedCids.isNotEmpty);
    final stopping = h.controller.stopCurrentPlayback();
    expect(h.controller.player, isNull);
    expect(h.controller.isVideoLoading.value, isFalse);
    resolved.complete(_playback(quality: 120));
    await loading;
    expect(h.players.single.opens, isEmpty);
    expect(h.controller.availableQualities, isEmpty);
    disposal.complete();
    await stopping;
  });

  test('latest invocation wins while previous Player disposal is delayed',
      () async {
    final h = _Harness();
    await h.load(_video(1, bili: false));
    final disposal = Completer<void>();
    h.players.single.disposeGate = disposal;
    final second = h.load(_video(2, bili: false));
    await h.load(_video(3, bili: false));
    disposal.complete();
    await second;
    expect(h.controller.activeVideo.value?.id, 3);
    expect(h.players, hasLength(2));
    expect(h.players.last.opens.single.media.uri, endsWith('/3.mp4'));
  });

  test('quality change cannot restart an old video after another selection',
      () async {
    final h = _Harness();
    await h.load(_video(1));
    final disposal = Completer<void>();
    h.players.single.disposeGate = disposal;
    final changing = h.controller.setPlaybackQuality(120);
    await h.load(_video(2));
    disposal.complete();
    await changing;
    expect(h.controller.activeVideo.value?.id, 2);
    expect(h.controller.playbackQuality.value, 80);
    expect(h.bili.resolvedCids, [1, 2]);
  });

  test('stop after open but before rate completes cannot initialize sidecars',
      () async {
    final h = _Harness();
    final rate = Completer<void>();
    h.configure = (native) => native.onRate = () => rate.future;
    final loading = h.load(_video(1));
    await _until(
        () => h.players.isNotEmpty && h.players.single.rates.isNotEmpty);
    await h.controller.stopCurrentPlayback();
    rate.complete();
    await loading;
    expect(h.controller.danmakuCues, isEmpty);
    expect(h.controller.player, isNull);
    expect(h.controller.playbackError.value, isEmpty);
  });

  test('failed media can be retried without leaving its id active', () async {
    final h = _Harness();
    var attempts = 0;
    h.bili.onResolve = (_) async {
      if (++attempts == 1) throw StateError('first failure');
      return _playback();
    };
    await h.load(_video(1));
    expect(h.controller.player, isNull);
    await h.load(_video(1));
    expect(attempts, 2);
    expect(h.controller.playbackError.value, isEmpty);
    expect(h.players.last.opens, hasLength(1));
  });

  test('MP4 EDL preserves segment order, byte escaping and platform headers',
      () async {
    final h = _Harness();
    final segments = [
      'https://cdn.test/a;one.mp4?x=1,2',
      'https://cdn.test/\u4e8c.mp4?x=%20'
    ];
    h.bili.onResolve = (_) async => _playback(segments: segments);
    await h.load(_video(1));
    final open = h.players.single.opens.single;
    expect(open.media.uri,
        'edl://${segments.map((url) => '%${utf8.encode(url).length}%$url').join(';')}');
    expect(open.media.httpHeaders, _playback().headers);
    expect(open.media.httpHeaders, isNot(contains('Authorization')));
    expect(open.play, isTrue);
    expect(h.players.single.audio, isEmpty);
  });

  test('NAS headers remain scoped to backend media', () async {
    final h = _Harness();
    final first = _video(1, bili: false).copyWith(sourceData: {});
    final second = _video(2, bili: false)
        .copyWith(sourceData: {}, videoUrl: 'https://other.test/video.mp4');
    h.api.onGet =
        (path) async => path.endsWith('/1') ? first.toJson() : second.toJson();
    await h.load(first);
    expect(h.players.single.opens.single.media.httpHeaders,
        {'Authorization': 'Bearer nas-only-token'});
    await h.load(second);
    expect(h.players.last.opens.single.media.httpHeaders, isEmpty);
  });

  test('cached local playback has no NAS bearer header', () async {
    final h = _Harness();
    await h.load(_video(1, bili: false));
    expect(h.players.single.opens.single.media.httpHeaders, isEmpty);
  });

  for (final firstBili in [false, true]) {
    for (final secondBili in [false, true]) {
      test('subtitle sequence latest wins (Bili=$firstBili -> $secondBili)',
          () async {
        final h = _Harness();
        await h.load(_video(1, bili: false));
        final oldNas = Completer<String>();
        final oldBili = Completer<List<BiliSubtitleCue>>();
        h.api.onText =
            (path) async => path == 'old' ? await oldNas.future : _srt('new');
        h.bili.onBody =
            (sub) async => sub.id == 'a' ? await oldBili.future : _cues('new');
        final old = firstBili
            ? h.controller.selectBiliSubtitle(_subA)
            : h.controller.selectSubtitleSidecar(_sidecar('old'));
        if (secondBili) {
          await h.controller.selectBiliSubtitle(_subB);
        } else {
          await h.controller.selectSubtitleSidecar(_sidecar('new'));
        }
        if (firstBili) {
          oldBili.complete(_cues('old'));
        } else {
          oldNas.complete(_srt('old'));
        }
        await old;
        expect(h.controller.subtitleCues.single.text, 'new');
        expect(h.players.single.subtitles, hasLength(1));
      });
    }
  }

  for (final disable in [false, true]) {
    test('subtitle ${disable ? 'disable' : 'clear'} invalidates pending body',
        () async {
      final h = _Harness();
      await h.load(_video(1));
      final body = Completer<List<BiliSubtitleCue>>();
      h.bili.onBody = (_) => body.future;
      final loading = h.controller.selectBiliSubtitle(_subA);
      if (disable) {
        await h.controller.setSubtitlesEnabled(false);
      } else {
        await h.controller.selectSubtitleSidecar(null);
      }
      body.complete(_cues('late'));
      await loading;
      expect(h.controller.subtitleCues, isEmpty);
      expect(h.players.single.subtitles.single.id, 'no');
    });
  }

  test('default Bili subtitle metadata cannot override a manual selection',
      () async {
    final h = _Harness();
    final metadata = Completer<List<BiliSubtitle>>();
    h.bili.onSubtitles = () => metadata.future;
    await h.load(_video(1));
    await h.controller.selectBiliSubtitle(_subB);
    metadata.complete([_subA, _subB]);
    await _flush();
    expect(h.bili.bodyCalls, ['b']);
    expect(h.controller.biliSubtitles, [_subA, _subB]);
    expect(h.controller.subtitleCues.single.text, 'b');
  });

  test('NAS pending subtitle and failed danmaku cannot touch a newer player',
      () async {
    final h = _Harness();
    final subtitle = Completer<String>();
    final danmaku = Completer<String>();
    h.api.onText = (path) => path == 'sub' ? subtitle.future : danmaku.future;
    await h.load(_video(1,
        bili: false,
        sidecars: [_sidecar('sub'), _sidecar('danmaku', danmaku: true)]));
    await _until(() => h.api.textCalls.length == 2);
    await h.load(_video(2));
    await h.controller.selectBiliSubtitle(_subB);
    await _until(() => h.controller.danmakuCues.isNotEmpty);
    subtitle.complete(_srt('stale NAS subtitle'));
    danmaku.completeError(StateError('stale NAS danmaku'));
    await _flush();
    expect(h.controller.subtitleCues.single.text, 'b');
    expect(h.controller.danmakuCues.single.text, 'bili danmaku');
    expect(h.players.first.subtitles, isEmpty);
  });

  test('late Bili track metadata and danmaku cannot modify new playback',
      () async {
    final h = _Harness();
    final metadata = Completer<List<BiliSubtitle>>();
    final danmaku = Completer<String>();
    h.bili.onSubtitles = () => metadata.future;
    h.bili.onDanmaku = (_) => danmaku.future;
    await h.load(_video(1));
    await h.load(_video(2, bili: false));
    metadata.complete([_subA]);
    danmaku.complete(_xml('stale Bili danmaku'));
    await _flush();
    expect(h.controller.biliSubtitles, isEmpty);
    expect(h.controller.subtitleCues, isEmpty);
    expect(h.controller.danmakuCues, isEmpty);
    expect(h.bili.bodyCalls, isEmpty);
  });

  for (final bodyPending in [false, true]) {
    test(
        'Bili danmaku is independent of subtitle failure or pending body '
        '(bodyPending=$bodyPending)', () async {
      final h = _Harness();
      final body = Completer<List<BiliSubtitleCue>>();
      h.bili.onSubtitles = () async {
        if (!bodyPending) throw StateError('subtitle unavailable');
        return [_subA];
      };
      h.bili.onBody = (_) => body.future;
      await h.load(_video(1));
      await _until(() => h.controller.danmakuCues.isNotEmpty);
      expect(h.controller.danmakuCues.single.text, 'bili danmaku');
      expect(h.controller.playbackError.value, isEmpty);
      if (bodyPending) {
        body.completeError(StateError('body unavailable'));
        await _flush();
        expect(h.controller.danmakuCues, hasLength(1));
      }
    });
  }

  test('NAS danmaku starts before a pending subtitle finishes', () async {
    final h = _Harness();
    final subtitle = Completer<String>();
    h.api.onText = (path) async =>
        path == 'sub' ? await subtitle.future : _xml('NAS danmaku');
    await h.load(_video(1,
        bili: false,
        sidecars: [_sidecar('sub'), _sidecar('danmaku', danmaku: true)]));
    await _until(() => h.controller.danmakuCues.isNotEmpty);
    expect(h.controller.danmakuCues.single.text, 'NAS danmaku');
    subtitle.completeError(StateError('subtitle failed'));
    await _flush();
    expect(h.controller.danmakuCues, hasLength(1));
    expect(h.controller.playbackError.value, isEmpty);
  });

  for (final fails in [false, true]) {
    test(
        'old NAS danmaku response cannot replace/clear a newer choice '
        '(failure=$fails)', () async {
      final h = _Harness();
      await h.load(_video(1, bili: false));
      final oldText = Completer<String>();
      h.api.onText =
          (path) async => path == 'old' ? await oldText.future : _xml('new');
      final old =
          h.controller.selectDanmakuSidecar(_sidecar('old', danmaku: true));
      await h.controller.selectDanmakuSidecar(_sidecar('new', danmaku: true));
      if (fails) {
        oldText.completeError(StateError('stale danmaku error'));
      } else {
        oldText.complete(_xml('old'));
      }
      await old;
      expect(h.controller.danmakuCues.single.text, 'new');
    });
  }

  test('old sidecar and progress streams require the same Player identity',
      () async {
    final h = _Harness();
    final video = _video(1, bili: false).copyWith(progressPercent: 50);
    h.controller.allVideos.add(video);
    await h.load(video);
    final native = h.players.single;
    final body = Completer<List<BiliSubtitleCue>>();
    h.bili.onBody = (_) => body.future;
    final loading = h.controller.selectBiliSubtitle(_subA);
    final replacement = _NativePlayer();
    h.players.add(replacement);
    h.controller.player = Player(platformPlayer: replacement);
    body.complete(_cues('stale player'));
    native.videoReady();
    native.position(const Duration(minutes: 9));
    native.completed();
    await loading;
    await _flush();
    expect(h.controller.subtitleCues, isEmpty);
    expect(native.subtitles, isEmpty);
    expect(native.seeks, isEmpty);
    expect(h.controller.allVideos.single.progressPercent, 50);
  });

  for (final dimensions in [false, true]) {
    test(
        'DASH waits for video and real audio tracks before play '
        '(dimensions=$dimensions)', () async {
      final h = _Harness(timeout: const Duration(seconds: 2));
      h.bili.onResolve = (_) async => _playback(dash: true);
      final loading = h.load(_video(1));
      await _until(
          () => h.players.isNotEmpty && h.players.single.opens.isNotEmpty);
      final native = h.players.single;
      expect(native.opens.single.play, isFalse);
      expect(native.opens.single.media.httpHeaders, _playback().headers);
      expect(native.audio, isEmpty);
      native.videoReady(dimensions: dimensions);
      await _until(() => native.audio.isNotEmpty);
      expect(native.audio.single.id, 'https://cdn.test/audio.m4s');
      expect(native.playCalls, 0);
      // setAudioTrack completion and selected uri are not proof of audio load.
      await _flush();
      expect(native.playCalls, 0);
      native.audioReady();
      await loading;
      expect(native.playCalls, 1);
      expect(native.rates, [1]);
      expect(h.controller.playbackError.value, isEmpty);
    });
  }

  test('DASH observes state changes emitted inside open/audio commands',
      () async {
    final h = _Harness();
    h.bili.onResolve = (_) async => _playback(dash: true);
    h.configure = (native) {
      native.onOpen = () async => native.videoReady();
      native.onAudio = () async => native.audioReady();
    };
    await h.load(_video(1));
    expect(h.players.single.playCalls, 1);
    expect(h.controller.playbackError.value, isEmpty);
  });

  for (final audioPhase in [false, true]) {
    test(
        'DASH ${audioPhase ? 'audio' : 'video'} timeout is bounded and retryable',
        () async {
      final h = _Harness();
      h.bili.onResolve = (_) async => _playback(dash: true);
      h.configure = (native) {
        if (audioPhase) native.onOpen = () async => native.videoReady();
      };
      await h.load(_video(1)).timeout(const Duration(seconds: 2));
      expect(h.controller.playbackError.value, contains('超时'));
      expect(h.controller.isVideoLoading.value, isFalse);
      expect(h.controller.player, isNull);
      expect(h.players.single.playCalls, 0);
      h.configure = (native) {
        native.onOpen = () async => native.videoReady();
        native.onAudio = () async => native.audioReady();
      };
      await h.load(_video(1));
      expect(h.players.last.playCalls, 1);
      expect(h.controller.playbackError.value, isEmpty);
    });
  }

  test('DASH native audio-add error is reported without signed URL/log leakage',
      () async {
    final h = _Harness(timeout: const Duration(seconds: 2));
    h.bili.onResolve = (_) async => _playback(dash: true);
    h.configure = (native) {
      native.onOpen = () async => native.videoReady();
      native.onAudio = () async => native.log(const PlayerLog(
          prefix: 'media_kit',
          level: 'error',
          text: 'audio-add failed https://cdn.test/audio?secret=credential'));
    };
    await h.load(_video(1));
    expect(h.controller.playbackError.value, contains('音轨加载失败'));
    expect(h.controller.playbackError.value, isNot(contains('secret')));
    expect(h.controller.playbackError.value, isNot(contains('https://')));
    expect(h.players.single.playCalls, 0);
  });

  test('DASH hung command and pending native disposal cannot hang loading',
      () async {
    final h = _Harness();
    final command = Completer<void>();
    final disposal = Completer<void>();
    h.bili.onResolve = (_) async => _playback(dash: true);
    h.configure = (native) {
      native.onOpen = () => command.future;
      native.disposeGate = disposal;
    };
    await h.load(_video(1)).timeout(const Duration(seconds: 2));
    expect(h.controller.playbackError.value, contains('超时'));
    expect(h.controller.isVideoLoading.value, isFalse);
    expect(h.controller.player, isNull);
    expect(h.players.single.disposeStarted, isTrue);
    command.completeError(StateError('late command failure'));
    disposal.complete();
    await _flush();
    expect(h.controller.playbackError.value, contains('超时'));
  });

  for (final audioPhase in [false, true]) {
    test(
        'stop cancels DASH ${audioPhase ? 'audio' : 'video'} wait promptly; '
        'late command failure is handled', () async {
      final h = _Harness(timeout: const Duration(seconds: 30));
      final command = Completer<void>();
      h.bili.onResolve = (_) async => _playback(dash: true);
      h.configure = (native) {
        native.onOpen = () async {
          if (audioPhase) {
            native.videoReady();
          } else {
            await command.future;
          }
        };
        if (audioPhase) native.onAudio = () => command.future;
      };
      final loading = h.load(_video(1));
      await _until(() =>
          h.players.isNotEmpty &&
          (audioPhase
              ? h.players.single.audio.isNotEmpty
              : h.players.single.opens.isNotEmpty));
      await h.controller.stopCurrentPlayback();
      await loading.timeout(const Duration(seconds: 1));
      command.completeError(StateError('late native command error'));
      await _flush();
      expect(h.controller.playbackError.value, isEmpty);
      expect(h.controller.isVideoLoading.value, isFalse);
      expect(h.players.single.playCalls, 0);
    });
  }
}
