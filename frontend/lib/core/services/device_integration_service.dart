import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../shared/models/project_model.dart';

class MediaPlaybackAction {
  const MediaPlaybackAction({
    required this.action,
    required this.mediaId,
    this.position,
  });

  /// play, pause, seekTo, or stop. Apply only to the matching current mediaId.
  final String action;
  final String mediaId;
  final Duration? position;
}

class DeviceIntegrationService {
  DeviceIntegrationService._();

  static const MethodChannel _channel =
      MethodChannel('com.biostathelper.app/device');
  static final StreamController<bool> _pictureInPictureController =
      StreamController<bool>.broadcast();
  static final StreamController<String> _videoActionController =
      StreamController<String>.broadcast();
  static final StreamController<MediaPlaybackAction> _mediaPlaybackController =
      StreamController<MediaPlaybackAction>.broadcast();
  static bool _handlerInitialized = false;

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static Stream<bool> get pictureInPictureModeChanges {
    _ensureMethodHandler();
    return _pictureInPictureController.stream;
  }

  static Stream<String> get videoActionEvents {
    _ensureMethodHandler();
    return _videoActionController.stream;
  }

  static Stream<MediaPlaybackAction> get mediaPlaybackActions {
    _ensureMethodHandler();
    return _mediaPlaybackController.stream;
  }

  /// Call after setVideoPlaybackActive(true), then on player state/seek changes.
  /// Only display metadata is sent; never pass a URL, cookie, or access token.
  static Future<bool> updateMediaPlaybackState({
    required String mediaId,
    required String title,
    required bool playing,
    String artist = '',
    String album = '',
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
    bool buffering = false,
    double speed = 1,
    bool canSeek = true,
  }) async {
    if (mediaId.trim().isEmpty) {
      throw ArgumentError.value(mediaId, 'mediaId', 'Must not be empty');
    }
    if (!speed.isFinite || speed <= 0 || speed > 16) {
      throw ArgumentError.value(
          speed, 'speed', 'Must be finite and in (0, 16]');
    }
    _ensureMethodHandler();
    if (!_isAndroid) return false;
    final durationMs = duration.inMilliseconds.clamp(0, 0x7fffffffffffffff);
    final positionMs = position.inMilliseconds
        .clamp(0, durationMs > 0 ? durationMs : 0x7fffffffffffffff);
    return _invokeBool('updateMediaPlaybackState', {
      'mediaId': mediaId,
      'title': title,
      'artist': artist,
      'album': album,
      'playing': playing,
      'buffering': buffering,
      'positionMs': positionMs,
      'durationMs': durationMs,
      'speed': speed,
      'canSeek': canSeek,
    });
  }

  /// Suppresses automatic PiP on Home. mpv still owns the actual audio/video.
  static Future<bool> setAudioOnlyBackground(bool enabled) async {
    _ensureMethodHandler();
    if (!_isAndroid) return false;
    return _invokeBool('setAudioOnlyBackground', {'enabled': enabled});
  }

  /// Also performed natively by setVideoPlaybackActive(false).
  static Future<bool> stopMediaPlayback() async {
    if (!_isAndroid) return false;
    return _invokeBool('stopMediaPlayback');
  }

  /// Opt-in periodic work, approximately hourly subject to Android scheduling.
  static Future<bool> configureStudyBackground(bool enabled) async {
    if (!_isAndroid) return false;
    return _invokeBool('configureStudyBackground', {'enabled': enabled});
  }

  /// Call from studyBackgroundMain in finally; ignored by the foreground engine.
  static Future<bool> completeStudyBackground() async {
    if (!_isAndroid) return false;
    return _invokeBool('completeStudyBackground');
  }

  static Future<bool> showStudyNotification({
    required String title,
    required int count,
  }) async {
    if (count <= 0 || (!_isAndroid && !_isWindows)) return false;
    return _invokeBool(
        'showStudyNotification', {'title': title, 'count': count});
  }

  /// Foreground UI only. A headless worker never requests runtime permission.
  static Future<bool> requestNotificationPermission() async {
    if (_isWindows) return true;
    if (!_isAndroid) return false;
    return _invokeBool('requestNotificationPermission');
  }

  static Future<bool> requestFloatingWindowPermission() async {
    _ensureMethodHandler();
    if (_isWindows) return true;
    if (!_isAndroid) return false;
    return await _invokeBool('requestFloatingWindowPermission');
  }

  static Future<bool> setVideoPlaybackActive(bool active) async {
    _ensureMethodHandler();
    if (!_isAndroid) return false;
    return await _invokeBool('setVideoPlaybackActive', {'active': active});
  }

  static Future<bool> enterPictureInPicture() async {
    _ensureMethodHandler();
    if (!_isAndroid && !_isWindows) return false;
    return await _invokeBool('enterPictureInPicture');
  }

  static Future<bool> exitPictureInPicture() async {
    _ensureMethodHandler();
    if (!_isWindows) return false;
    return await _invokeBool('exitPictureInPicture');
  }

  static Future<bool> startFloatingWindowDrag() async {
    _ensureMethodHandler();
    if (!_isWindows) return false;
    return await _invokeBool('startFloatingWindowDrag');
  }

  static Future<double?> getPlaybackBrightness() async {
    if (!_isAndroid) return null;
    return _invokeDouble('getPlaybackBrightness');
  }

  static Future<double?> setPlaybackBrightness(double value) async {
    if (!_isAndroid) return null;
    return _invokeDouble(
      'setPlaybackBrightness',
      {'value': value.clamp(0.02, 1).toDouble()},
    );
  }

  static Future<double?> getPlaybackVolume() async {
    if (!_isAndroid) return null;
    return _invokeDouble('getPlaybackVolume');
  }

  static Future<double?> setPlaybackVolume(double value) async {
    if (!_isAndroid) return null;
    return _invokeDouble(
      'setPlaybackVolume',
      {'value': value.clamp(0, 1).toDouble()},
    );
  }

  static Future<int?> getDynamicAccentColor() async {
    if (!_isAndroid) return null;
    try {
      return await _channel.invokeMethod<int>('getDynamicAccentColor');
    } on PlatformException catch (error) {
      debugPrint(
          '[DeviceIntegration] getDynamicAccentColor failed: ${error.message}');
      return null;
    } catch (error) {
      debugPrint('[DeviceIntegration] getDynamicAccentColor failed: $error');
      return null;
    }
  }

  static Future<bool> syncTodoReminder(
    ProjectTodo todo, {
    required String projectName,
  }) async {
    if (!_isAndroid || todo.dueAt == null) return false;
    return await _invokeBool('syncTodoReminder', {
      'todoId': todo.id,
      'title': todo.title,
      'description': todo.description,
      'projectName': projectName,
      'dueAtMillis': todo.dueAt!.millisecondsSinceEpoch,
    });
  }

  static Future<bool> _invokeBool(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      final result = await _channel.invokeMethod<bool>(method, arguments);
      return result ?? false;
    } on PlatformException catch (error) {
      debugPrint('[DeviceIntegration] $method failed: ${error.message}');
      return false;
    } catch (error) {
      debugPrint('[DeviceIntegration] $method failed: $error');
      return false;
    }
  }

  static Future<double?> _invokeDouble(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      final result = await _channel.invokeMethod<num>(method, arguments);
      return result?.toDouble();
    } on PlatformException catch (error) {
      debugPrint('[DeviceIntegration] $method failed: ${error.message}');
      return null;
    } catch (error) {
      debugPrint('[DeviceIntegration] $method failed: $error');
      return null;
    }
  }

  static void _ensureMethodHandler() {
    if (_handlerInitialized) return;
    _handlerInitialized = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onMediaPlaybackAction':
          final arguments = call.arguments;
          if (arguments is! Map) return false;
          final action = arguments['action'];
          final mediaId = arguments['mediaId'];
          if (!const {'play', 'pause', 'seekTo', 'stop'}.contains(action) ||
              mediaId is! String ||
              mediaId.trim().isEmpty) {
            return false;
          }
          final positionMs = arguments['positionMs'];
          if (action == 'seekTo' && (positionMs is! int || positionMs < 0)) {
            return false;
          }
          _mediaPlaybackController.add(MediaPlaybackAction(
            action: action as String,
            mediaId: mediaId,
            position: action == 'seekTo'
                ? Duration(milliseconds: positionMs as int)
                : null,
          ));
          return true;
        case 'onPictureInPictureModeChanged':
          final active = call.arguments is Map
              ? (call.arguments as Map)['active'] == true
              : call.arguments == true;
          _pictureInPictureController.add(active);
          return true;
        case 'onVideoAction':
          final action = call.arguments is Map
              ? (call.arguments as Map)['action']?.toString()
              : call.arguments?.toString();
          if (action != null && action.isNotEmpty) {
            _videoActionController.add(action);
          }
          return true;
      }
      return null;
    });
  }
}
