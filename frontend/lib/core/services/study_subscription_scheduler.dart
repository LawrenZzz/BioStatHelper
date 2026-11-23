import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/models/study_model.dart';
import 'study_preferences.dart';

typedef StudySubscriptionCheck = Future<List<StudyUpdate>> Function();
typedef StudySubscriptionNotify = Future<bool> Function(
    List<StudyUpdate> updates);

enum StudySubscriptionCheckStatus {
  checked,
  disabled,
  notReady,
  stopped,
  paused,
  focused,
  notDue,
  busy,
  superseded,
  failed,
}

enum StudySubscriptionNotificationStatus {
  disabled,
  notConnected,
  nothingNew,
  suppressed,
  delivered,
  declined,
  failed,
}

class StudySubscriptionCheckResult {
  const StudySubscriptionCheckResult(
    this.status, {
    this.updateCount = 0,
    this.notifiedCount = 0,
    this.notificationStatus = StudySubscriptionNotificationStatus.disabled,
    this.errorClass,
  });
  final StudySubscriptionCheckStatus status;
  final int updateCount;
  final int notifiedCount;
  final StudySubscriptionNotificationStatus notificationStatus;
  // Exception class only: backend errors can contain URLs or credentials.
  final String? errorClass;
}

/// In-process scheduling. Windows may opt into inactive/minimized checks.
/// Android headless work is separate; this timer cannot survive process death.
class StudySubscriptionScheduler extends ChangeNotifier
    with WidgetsBindingObserver {
  StudySubscriptionScheduler({
    required this.preferences,
    required StudySubscriptionCheck checkUpdates,
    required bool Function() isFocusActive,
    StudySubscriptionNotify? notify,
    this.interval = const Duration(minutes: 15),
    this.runWhileInactive = false,
    DateTime Function()? now,
    Future<SharedPreferences> Function()? storage,
  })  : _checkUpdates = checkUpdates,
        _isFocusActive = isFocusActive,
        _notifyUpdates = notify,
        _now = now ?? DateTime.now,
        _storage = storage ?? SharedPreferences.getInstance {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'interval');
    }
  }

  final StudyPreferencesController preferences;
  final StudySubscriptionCheck _checkUpdates;
  final bool Function() _isFocusActive;
  final StudySubscriptionNotify? _notifyUpdates;
  final Future<SharedPreferences> Function() _storage;
  final DateTime Function() _now;
  final Duration interval;
  final bool runWhileInactive;
  static final _checkingScopes = <String>{};
  static final _deliveredInProcess = <String, Set<int>>{};
  final _lastAttempt = <String, DateTime>{};
  Timer? _timer;
  bool _started = false;
  bool _disposed = false;
  bool _foreground = true;
  bool _busy = false;
  int _epoch = 0;
  StudySubscriptionCheckResult? _lastResult;

  bool get running => _started;
  bool get checking => _busy;
  bool get notificationAvailable => _notifyUpdates != null;
  bool get timerActive => _timer?.isActive ?? false;
  StudySubscriptionCheckResult? get lastResult => _lastResult;

  /// SharedPreferences contains delivered integer update IDs only, scoped by
  /// server/account. A native/headless integration must use the same identity.
  static String deliveredIdsKey(String scopeKey) =>
      'study_subscription_delivered_${sha256.convert(utf8.encode(scopeKey))}';

  bool get _enabled =>
      preferences.isLoaded &&
      (preferences.savedValue.subscriptionBackground ||
          preferences.savedValue.subscriptionNotifications);

  bool get _lifecycleAllowed => _foreground || runWhileInactive;

  void start() {
    if (_disposed || _started) return;
    _started = true;
    _epoch++;
    _foreground =
        (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) ==
            AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    preferences.addListener(_preferencesChanged);
    _preferencesChanged();
  }

  void _preferencesChanged() {
    _timer?.cancel();
    _timer = null;
    if (!_started || _disposed) return;
    if (_lifecycleAllowed &&
        preferences.isLoaded &&
        preferences.savedValue.subscriptionBackground) {
      _timer = Timer.periodic(interval, (_) => unawaited(checkNow()));
    }
    if (_lifecycleAllowed && _enabled) unawaited(checkNow());
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started || _disposed) return;
    _foreground = state == AppLifecycleState.resumed;
    _preferencesChanged();
  }

  bool _valid(String scope, int epoch) =>
      !_disposed &&
      _started &&
      _lifecycleAllowed &&
      _epoch == epoch &&
      preferences.scopeKey == scope &&
      _enabled;

  StudySubscriptionCheckResult _report(StudySubscriptionCheckResult result) {
    if (!_disposed) {
      _lastResult = result;
      notifyListeners();
    }
    return result;
  }

  Future<StudySubscriptionCheckResult> checkNow({bool force = false}) async {
    if (!_started || _disposed) {
      return const StudySubscriptionCheckResult(
          StudySubscriptionCheckStatus.stopped);
    }
    if (!preferences.isLoaded) {
      return _report(const StudySubscriptionCheckResult(
          StudySubscriptionCheckStatus.notReady));
    }
    if (!_enabled) {
      return _report(const StudySubscriptionCheckResult(
          StudySubscriptionCheckStatus.disabled));
    }
    if (!_lifecycleAllowed) {
      return _report(const StudySubscriptionCheckResult(
          StudySubscriptionCheckStatus.paused));
    }
    if (_isFocusActive()) {
      return _report(const StudySubscriptionCheckResult(
          StudySubscriptionCheckStatus.focused,
          notificationStatus: StudySubscriptionNotificationStatus.suppressed));
    }
    final scope = preferences.scopeKey!;
    if (_busy || _checkingScopes.contains(scope)) {
      return const StudySubscriptionCheckResult(
          StudySubscriptionCheckStatus.busy);
    }
    final last = _lastAttempt[scope];
    if (!force && last != null && _now().difference(last) < interval) {
      return _report(const StudySubscriptionCheckResult(
          StudySubscriptionCheckStatus.notDue));
    }
    final epoch = _epoch;
    _busy = true;
    _checkingScopes.add(scope);
    _lastAttempt[scope] = _now();
    notifyListeners();
    try {
      final updates = await _checkUpdates();
      if (!_valid(scope, epoch)) {
        return _report(const StudySubscriptionCheckResult(
            StudySubscriptionCheckStatus.superseded));
      }
      if (!preferences.savedValue.subscriptionNotifications) {
        return _report(StudySubscriptionCheckResult(
            StudySubscriptionCheckStatus.checked,
            updateCount: updates.length));
      }
      if (_isFocusActive()) {
        return _report(StudySubscriptionCheckResult(
            StudySubscriptionCheckStatus.checked,
            updateCount: updates.length,
            notificationStatus:
                StudySubscriptionNotificationStatus.suppressed));
      }
      if (_notifyUpdates == null) {
        return _report(StudySubscriptionCheckResult(
            StudySubscriptionCheckStatus.checked,
            updateCount: updates.length,
            notificationStatus:
                StudySubscriptionNotificationStatus.notConnected));
      }
      final storage = await _storage();
      await storage.reload();
      if (!_valid(scope, epoch) ||
          !preferences.savedValue.subscriptionNotifications ||
          _isFocusActive()) {
        return _report(const StudySubscriptionCheckResult(
            StudySubscriptionCheckStatus.superseded));
      }
      final key = deliveredIdsKey(scope);
      final delivered = <int>{
        ...?_deliveredInProcess[scope],
        for (final value in storage.getStringList(key) ?? <String>[])
          if (int.tryParse(value) case final int id) id,
      };
      final freshById = <int, StudyUpdate>{
        for (final update in updates)
          if (update.id > 0 && !update.read && !delivered.contains(update.id))
            update.id: update,
      };
      if (freshById.isEmpty) {
        return _report(StudySubscriptionCheckResult(
            StudySubscriptionCheckStatus.checked,
            updateCount: updates.length,
            notificationStatus:
                StudySubscriptionNotificationStatus.nothingNew));
      }
      final fresh = List<StudyUpdate>.unmodifiable(freshById.values);
      bool accepted;
      try {
        accepted = await _notifyUpdates!(fresh);
      } catch (error) {
        return _report(StudySubscriptionCheckResult(
            StudySubscriptionCheckStatus.checked,
            updateCount: updates.length,
            notificationStatus: StudySubscriptionNotificationStatus.failed,
            errorClass: error.runtimeType.toString()));
      }
      if (!accepted) {
        return _report(StudySubscriptionCheckResult(
            StudySubscriptionCheckStatus.checked,
            updateCount: updates.length,
            notificationStatus: StudySubscriptionNotificationStatus.declined));
      }
      // Keep the captured scope even if the user switches accounts while the
      // device displays the notification; never acknowledge under the new user.
      delivered.addAll(freshById.keys);
      _deliveredInProcess[scope] = delivered;
      final persisted = await storage.setStringList(
          key, delivered.map((id) => '$id').toList());
      return _report(StudySubscriptionCheckResult(
          StudySubscriptionCheckStatus.checked,
          updateCount: updates.length,
          notifiedCount: fresh.length,
          notificationStatus: StudySubscriptionNotificationStatus.delivered,
          errorClass: persisted ? null : 'DeliveryReceiptWriteFailed'));
    } catch (error) {
      return _report(StudySubscriptionCheckResult(
          StudySubscriptionCheckStatus.failed,
          errorClass: error.runtimeType.toString()));
    } finally {
      _checkingScopes.remove(scope);
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  void stop() {
    if (!_started) return;
    _started = false;
    _epoch++;
    _timer?.cancel();
    _timer = null;
    preferences.removeListener(_preferencesChanged);
    WidgetsBinding.instance.removeObserver(this);
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    stop();
    _disposed = true;
    super.dispose();
  }
}
