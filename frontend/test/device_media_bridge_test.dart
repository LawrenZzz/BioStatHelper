import 'dart:io';

import 'package:bio_stat_helper/core/services/device_integration_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('com.biostathelper.app/device');
final _messenger =
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

Future<dynamic> _native(String method, dynamic arguments) async {
  final reply = await _messenger.handlePlatformMessage(_channel.name,
      _channel.codec.encodeMethodCall(MethodCall(method, arguments)), null);
  return reply == null ? null : _channel.codec.decodeEnvelope(reply);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls.clear();
    _messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return true;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    _messenger.setMockMethodCallHandler(_channel, null);
  });

  test('media snapshot sends only explicit display metadata and player state',
      () async {
    expect(
        await DeviceIntegrationService.updateMediaPlaybackState(
          mediaId: 'study:42:part:9',
          title: 'Lesson',
          artist: 'Teacher',
          album: 'Course',
          playing: true,
          buffering: true,
          position: const Duration(seconds: 20),
          duration: const Duration(minutes: 5),
          speed: 1.5,
          canSeek: false,
        ),
        isTrue);
    expect(calls.single.method, 'updateMediaPlaybackState');
    expect(calls.single.arguments, {
      'mediaId': 'study:42:part:9',
      'title': 'Lesson',
      'artist': 'Teacher',
      'album': 'Course',
      'playing': true,
      'buffering': true,
      'positionMs': 20000,
      'durationMs': 300000,
      'speed': 1.5,
      'canSeek': false,
    });
  });

  test('known durations bound position; unknown durations retain position',
      () async {
    await DeviceIntegrationService.updateMediaPlaybackState(
        mediaId: 'a',
        title: 'A',
        playing: false,
        position: const Duration(seconds: 50),
        duration: const Duration(seconds: 30));
    expect((calls.last.arguments as Map)['positionMs'], 30000);
    await DeviceIntegrationService.updateMediaPlaybackState(
        mediaId: 'a',
        title: 'A',
        playing: false,
        position: const Duration(seconds: 50),
        duration: const Duration(seconds: -1));
    expect((calls.last.arguments as Map)['positionMs'], 50000);
    expect((calls.last.arguments as Map)['durationMs'], 0);
    await DeviceIntegrationService.updateMediaPlaybackState(
        mediaId: 'a',
        title: 'A',
        playing: false,
        position: const Duration(seconds: -1));
    expect((calls.last.arguments as Map)['positionMs'], 0);
  });

  for (final speed in [0.0, -1.0, 17.0, double.nan, double.infinity]) {
    test('invalid playback speed $speed never reaches native', () async {
      await expectLater(
          DeviceIntegrationService.updateMediaPlaybackState(
              mediaId: 'a', title: 'A', playing: true, speed: speed),
          throwsArgumentError);
      expect(calls, isEmpty);
    });
  }

  test('empty identity is rejected', () async {
    await expectLater(
        DeviceIntegrationService.updateMediaPlaybackState(
            mediaId: ' ', title: 'A', playing: true),
        throwsArgumentError);
    expect(calls, isEmpty);
  });

  test(
      'playback start, audio-only flag and both teardown paths retain wire API',
      () async {
    await DeviceIntegrationService.setVideoPlaybackActive(true);
    await DeviceIntegrationService.setAudioOnlyBackground(true);
    await DeviceIntegrationService.stopMediaPlayback();
    await DeviceIntegrationService.setVideoPlaybackActive(false);
    expect(calls.map((call) => call.method), [
      'setVideoPlaybackActive',
      'setAudioOnlyBackground',
      'stopMediaPlayback',
      'setVideoPlaybackActive',
    ]);
    expect(calls[1].arguments, {'enabled': true});
    expect(calls.last.arguments, {'active': false});
  });

  for (final action in ['play', 'pause', 'seekTo', 'stop']) {
    test('native $action carries media identity and typed seek position',
        () async {
      final event = DeviceIntegrationService.mediaPlaybackActions.first;
      expect(
          await _native('onMediaPlaybackAction', {
            'action': action,
            'mediaId': 'study:42:9',
            'positionMs': 1234,
          }),
          isTrue);
      final value = await event;
      expect(value.action, action);
      expect(value.mediaId, 'study:42:9');
      expect(value.position,
          action == 'seekTo' ? const Duration(milliseconds: 1234) : null);
    });
  }

  for (final payload in <dynamic>[
    null,
    'play',
    {'action': 'execute', 'mediaId': 'a'},
    {'action': 'play', 'mediaId': ''},
    {'action': 'play', 'mediaId': 4},
    {'action': 'seekTo', 'mediaId': 'a'},
    {'action': 'seekTo', 'mediaId': 'a', 'positionMs': -1},
    {'action': 'seekTo', 'mediaId': 'a', 'positionMs': 1.5},
  ]) {
    test('malformed native action is ignored: $payload', () async {
      final events = <MediaPlaybackAction>[];
      final subscription =
          DeviceIntegrationService.mediaPlaybackActions.listen(events.add);
      addTearDown(subscription.cancel);
      expect(await _native('onMediaPlaybackAction', payload), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
    });
  }

  test('legacy video/PiP events remain separate and compatible', () async {
    final legacy = DeviceIntegrationService.videoActionEvents.first;
    final pip = DeviceIntegrationService.pictureInPictureModeChanges.first;
    await _native('onVideoAction', {'action': 'togglePlayback'});
    await _native('onPictureInPictureModeChanged', {'active': true});
    expect(await legacy, 'togglePlayback');
    expect(await pip, isTrue);
  });

  test('hourly opt-in and completion are explicit native calls', () async {
    await DeviceIntegrationService.configureStudyBackground(true);
    await DeviceIntegrationService.configureStudyBackground(false);
    await DeviceIntegrationService.completeStudyBackground();
    expect(calls.map((call) => call.method), [
      'configureStudyBackground',
      'configureStudyBackground',
      'completeStudyBackground',
    ]);
    expect(calls[0].arguments, {'enabled': true});
    expect(calls[1].arguments, {'enabled': false});
  });

  test('notification permission is explicit and empty updates do not notify',
      () async {
    expect(
        await DeviceIntegrationService.showStudyNotification(
            title: 'Updates', count: 0),
        isFalse);
    expect(calls, isEmpty);
    await DeviceIntegrationService.requestNotificationPermission();
    await DeviceIntegrationService.showStudyNotification(
        title: 'Updates', count: 3);
    expect(calls.map((call) => call.method),
        ['requestNotificationPermission', 'showStudyNotification']);
    expect(calls.last.arguments, {'title': 'Updates', 'count': 3});
  });

  test('unsupported desktop calls are no-ops without invoking native',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(
        await DeviceIntegrationService.updateMediaPlaybackState(
            mediaId: 'a', title: 'A', playing: false),
        isFalse);
    expect(
        await DeviceIntegrationService.setAudioOnlyBackground(true), isFalse);
    expect(await DeviceIntegrationService.stopMediaPlayback(), isFalse);
    expect(
        await DeviceIntegrationService.configureStudyBackground(true), isFalse);
    expect(await DeviceIntegrationService.completeStudyBackground(), isFalse);
    expect(calls, isEmpty);
  });

  test('Windows notifications use runner and need no runtime permission',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(
        await DeviceIntegrationService.requestNotificationPermission(), isTrue);
    expect(calls, isEmpty);
    expect(
        await DeviceIntegrationService.showStudyNotification(
            title: 'Updates', count: 2),
        isTrue);
    expect(calls.single.method, 'showStudyNotification');
    expect(calls.single.arguments, {'title': 'Updates', 'count': 2});
  });

  test('native failures and missing plugins return false', () async {
    _messenger.setMockMethodCallHandler(
        _channel, (_) async => throw PlatformException(code: 'denied'));
    expect(
        await DeviceIntegrationService.setAudioOnlyBackground(true), isFalse);
    _messenger.setMockMethodCallHandler(
        _channel, (_) async => throw MissingPluginException());
    expect(
        await DeviceIntegrationService.configureStudyBackground(true), isFalse);
  });

  test(
      'native manifest keeps both services private and declares foreground types',
      () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(manifest,
        contains('android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK'));
    expect(manifest, contains('android.permission.RECEIVE_BOOT_COMPLETED'));
    expect(
        manifest,
        contains(
            'android:name=".MediaPlaybackService"\n            android:exported="false"'));
    expect(manifest, contains('android:foregroundServiceType="mediaPlayback"'));
    expect(manifest, contains('android.permission.BIND_JOB_SERVICE'));
  });

  test('headless job stays bounded and targets the agreed Dart library', () {
    final source = File(
            'android/app/src/main/kotlin/com/biostathelper/app/StudyBackgroundJobService.kt')
        .readAsStringSync();
    expect(
        source,
        contains(
            '"package:bio_stat_helper/core/services/study_background.dart"'));
    expect(source, contains('"studyBackgroundMain"'));
    expect(source, contains('handler.postDelayed(timeout, 80_000)'));
    expect(source, contains('PlaybackBridge.foreground || running != null'));
    expect(source, contains('scheduler.cancel(jobId)'));
    expect(source, contains('previous?.destroy()'));
  });

  test(
      'resume stops headless work before Flutter resumes; paused activity may run jobs',
      () {
    final source = File(
            'android/app/src/main/kotlin/com/biostathelper/app/MainActivity.kt')
        .readAsStringSync();
    final resume = source.substring(source.indexOf('override fun onResume()'),
        source.indexOf('override fun onPause()'));
    expect(resume.indexOf('PlaybackBridge.foreground = true'),
        lessThan(resume.indexOf('super.onResume()')));
    expect(resume.indexOf('StudyBackgroundJobService.stopForForeground()'),
        lessThan(resume.indexOf('super.onResume()')));
    expect(source, contains('PlaybackBridge.foreground = false'));
    final configure = source.substring(
        source.indexOf('override fun configureFlutterEngine'),
        source.indexOf('override fun onUserLeaveHint'));
    expect(configure, isNot(contains('stopForForeground()')));
  });
}
