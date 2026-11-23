import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'auth_service.dart';

/// Device-only outbox. Keys contain server/user scope; payloads contain no token.
class StudyProgressSync {
  StudyProgressSync({ApiClient? api, String? Function()? scope})
      : _api = api ?? ApiClient(),
        _scopeOverride = scope;
  static final instance = StudyProgressSync();
  final ApiClient _api;
  final String? Function()? _scopeOverride;
  Future<void> _queue = Future.value();
  final _latest = <String, Map<String, dynamic>>{};

  String? get _scope {
    final override = _scopeOverride;
    if (override != null) return override();
    if (!Get.isRegistered<AuthService>()) return null;
    final id = Get.find<AuthService>().user.value?.id;
    if (id == null) return null;
    return 'study_progress_${sha256.convert(utf8.encode('${_api.baseUrl}:$id'))}';
  }

  Future<void> save(
      {int? itemId,
      int? videoId,
      required int position,
      required int duration,
      required bool completed}) {
    final scope = _scope;
    if (scope == null) return Future.value();
    final key = '${itemId ?? 'nas'}:${videoId ?? ''}';
    final record = {
      'item_id': itemId,
      'video_id': videoId,
      'position_seconds': position,
      'duration_seconds': duration,
      'completed': completed,
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
    };
    (_latest[scope] ??= {})[key] = record;
    return _serialize(() async {
      final prefs = await SharedPreferences.getInstance();
      final pending = _read(prefs, scope);
      pending[key] = record;
      await prefs.setString(scope, jsonEncode(pending));
      await _flush(prefs, scope, pending);
    });
  }

  Future<Map<int, Map<String, dynamic>>> pendingItems() async {
    final scope = _scope;
    if (scope == null) return {};
    final prefs = await SharedPreferences.getInstance();
    final pending = {..._read(prefs, scope), ...?_latest[scope]};
    return {
      for (final value in pending.values)
        if (value is Map && value['item_id'] is int)
          value['item_id'] as int: Map<String, dynamic>.from(value),
    };
  }

  Future<void> flush() {
    final scope = _scope;
    if (scope == null) return Future.value();
    return _serialize(() async {
      final prefs = await SharedPreferences.getInstance();
      await _flush(prefs, scope, _read(prefs, scope));
    });
  }

  Future<void> _serialize(Future<void> Function() task) {
    final next = _queue.then((_) => task());
    _queue = next.catchError((_) {});
    return next;
  }

  Map<String, dynamic> _read(SharedPreferences prefs, String scope) {
    try {
      return Map<String, dynamic>.from(
          jsonDecode(prefs.getString(scope) ?? '{}'));
    } catch (_) {
      return {};
    }
  }

  Future<void> _flush(SharedPreferences prefs, String scope,
      Map<String, dynamic> pending) async {
    for (final key in pending.keys.toList()) {
      if (_scope != scope) return;
      final row = Map<String, dynamic>.from(pending[key]);
      try {
        final position = row['position_seconds'] as int;
        final duration = row['duration_seconds'] as int;
        if (row['item_id'] != null) {
          await _api.put('/study/items/${row['item_id']}', data: {
            'position_seconds': position,
            if (duration > 0) 'duration_seconds': duration,
            'status': row['completed'] == true ? 'completed' : 'learning',
          });
        } else if (row['video_id'] != null && duration > 0) {
          await _api.put('/videos/${row['video_id']}/progress', data: {
            'progress_percent': (position / duration * 100).clamp(0, 100),
            'completed': row['completed'] == true,
          });
        }
        pending.remove(key);
        if (jsonEncode(_latest[scope]?[key]) == jsonEncode(row)) {
          _latest[scope]?.remove(key);
        }
        await prefs.setString(scope, jsonEncode(pending));
      } catch (error) {
        if (error is ApiException && error.statusCode == 404) {
          pending.remove(key);
          if (jsonEncode(_latest[scope]?[key]) == jsonEncode(row)) {
            _latest[scope]?.remove(key);
          }
          await prefs.setString(scope, jsonEncode(pending));
          continue;
        }
        return;
      }
    }
  }
}
