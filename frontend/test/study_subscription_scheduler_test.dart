import 'dart:async';

import 'package:bio_stat_helper/core/services/api_client.dart';
import 'package:bio_stat_helper/core/services/study_preferences.dart';
import 'package:bio_stat_helper/core/services/study_subscription_scheduler.dart';
import 'package:bio_stat_helper/shared/models/study_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api implements ApiClient {
  StudyPreferences preferences = StudyPreferences.defaults;
  @override
  Future<Response> get(String path,
          {Map<String, dynamic>? queryParameters}) async =>
      Response(
          requestOptions: RequestOptions(path: path),
          data: preferences.toJson());
  @override
  Future<Response> put(String path, {dynamic data}) async =>
      Response(requestOptions: RequestOptions(path: path), data: data);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var sequence = 0;
  late String scope;
  late _Api api;
  late StudyPreferencesController preferences;
  final schedulers = <StudySubscriptionScheduler>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    scope = 'account-server-${sequence++}';
    api = _Api();
    preferences = StudyPreferencesController(api: api, scope: () => scope);
  });
  tearDown(() {
    for (final scheduler in schedulers) {
      scheduler.dispose();
    }
    schedulers.clear();
    preferences.dispose();
  });

  void schedulerTest(String description, WidgetTesterCallback body) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        // Stop inside the fake-async test body, before Flutter checks timers.
        for (final scheduler in schedulers) {
          scheduler.stop();
        }
      }
    });
  }

  StudySubscriptionScheduler make({
    required StudySubscriptionCheck check,
    StudySubscriptionNotify? notify,
    bool Function()? focus,
    DateTime Function()? now,
    bool runWhileInactive = false,
  }) {
    final scheduler = StudySubscriptionScheduler(
        preferences: preferences,
        checkUpdates: check,
        notify: notify,
        isFocusActive: focus ?? () => false,
        now: now,
        interval: const Duration(minutes: 1),
        runWhileInactive: runWhileInactive);
    schedulers.add(scheduler);
    return scheduler;
  }

  schedulerTest('both default opt-ins off means no request or process timer',
      (tester) async {
    var checks = 0;
    await preferences.load();
    final scheduler = make(check: () async {
      checks++;
      return [];
    });
    scheduler.start();
    scheduler.start();
    await tester.pump();
    expect(scheduler.timerActive, isFalse);
    expect((await scheduler.checkNow(force: true)).status,
        StudySubscriptionCheckStatus.disabled);
    preferences
        .update(preferences.value.copyWith(subscriptionBackground: true));
    await tester.pump();
    expect(checks, 0, reason: 'An unsaved draft is not scheduling consent');
    await preferences.save();
    await tester.pumpAndSettle();
    expect(checks, 1);
    expect(scheduler.timerActive, isTrue);
  });

  schedulerTest(
      'periodic timer pauses with lifecycle and resumes only when due',
      (tester) async {
    var now = DateTime.utc(2026, 10, 20);
    var checks = 0;
    api.preferences = StudyPreferences(subscriptionBackground: true);
    await preferences.load();
    final scheduler = make(
        now: () => now,
        check: () async {
          checks++;
          return [];
        });
    scheduler.start();
    await tester.pumpAndSettle();
    expect(checks, 1);
    now = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));
    expect(checks, 2);
    scheduler.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(scheduler.timerActive, isFalse);
    expect((await scheduler.checkNow(force: true)).status,
        StudySubscriptionCheckStatus.paused);
    now = now.add(const Duration(minutes: 3));
    await tester.pump(const Duration(minutes: 3));
    expect(checks, 2);
    scheduler.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(checks, 3);
    scheduler.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(checks, 3);
    scheduler.stop();
    expect(scheduler.timerActive, isFalse);
    expect((await scheduler.checkNow()).status,
        StudySubscriptionCheckStatus.stopped);
  });

  schedulerTest(
      'notification-only opt-in checks on resume but creates no timer',
      (tester) async {
    api.preferences = StudyPreferences(subscriptionNotifications: true);
    await preferences.load();
    var calls = 0;
    final scheduler = make(check: () async {
      calls++;
      return [];
    });
    scheduler.start();
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(scheduler.timerActive, isFalse);
    expect(scheduler.notificationAvailable, isFalse);
    expect(scheduler.lastResult!.notificationStatus,
        StudySubscriptionNotificationStatus.notConnected);
  });

  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused
  ]) {
    schedulerTest(
        'Windows runWhileInactive retains timer and checks during $state',
        (tester) async {
      api.preferences = StudyPreferences(
          subscriptionBackground: true, subscriptionNotifications: true);
      await preferences.load();
      var now = DateTime.utc(2026, 10, 20);
      var checks = 0;
      var notifications = 0;
      final scheduler = make(
          runWhileInactive: true,
          now: () => now,
          check: () async {
            checks++;
            return [StudyUpdate(id: checks, title: 'new')];
          },
          notify: (_) async {
            notifications++;
            return true;
          });
      scheduler.start();
      await tester.pumpAndSettle();
      expect(checks, 1);
      scheduler.didChangeAppLifecycleState(state);
      expect(scheduler.timerActive, isTrue);
      now = now.add(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(checks, 2);
      expect(notifications, 2);
      expect((await scheduler.checkNow(force: true)).status,
          StudySubscriptionCheckStatus.checked);
    });
  }

  schedulerTest(
      'Windows inactive policy also accepts an in-flight foreground result',
      (tester) async {
    api.preferences = StudyPreferences(subscriptionNotifications: true);
    await preferences.load();
    final gate = Completer<List<StudyUpdate>>();
    var notifications = 0;
    final scheduler = make(
        runWhileInactive: true,
        check: () => gate.future,
        notify: (_) async {
          notifications++;
          return true;
        });
    scheduler.start();
    scheduler.didChangeAppLifecycleState(AppLifecycleState.hidden);
    gate.complete([const StudyUpdate(id: 7, title: 'new')]);
    await tester.pumpAndSettle();
    expect(notifications, 1);
    expect(scheduler.lastResult!.notificationStatus,
        StudySubscriptionNotificationStatus.delivered);
  });

  schedulerTest(
      'focus suppresses checks and notifications, including an in-flight result',
      (tester) async {
    api.preferences = StudyPreferences(subscriptionNotifications: true);
    await preferences.load();
    var focused = true;
    var checks = 0;
    var notifications = 0;
    final gate = Completer<List<StudyUpdate>>();
    final scheduler = make(
        focus: () => focused,
        check: () {
          checks++;
          return checks == 1
              ? gate.future
              : Future.value(
                  [const StudyUpdate(id: 7, title: 'private title')]);
        },
        notify: (_) async {
          notifications++;
          return true;
        });
    scheduler.start();
    await tester.pumpAndSettle();
    expect(checks, 0);
    expect((await scheduler.checkNow(force: true)).status,
        StudySubscriptionCheckStatus.focused);
    focused = false;
    final first = scheduler.checkNow(force: true);
    focused = true;
    gate.complete([const StudyUpdate(id: 7, title: 'private title')]);
    expect((await first).notificationStatus,
        StudySubscriptionNotificationStatus.suppressed);
    expect(notifications, 0);
    focused = false;
    expect((await scheduler.checkNow(force: true)).notifiedCount, 1);
    expect(notifications, 1);
  });

  schedulerTest(
      'deduplicate payload, timer/resume calls and fresh scheduler instances',
      (tester) async {
    api.preferences = StudyPreferences(
        subscriptionNotifications: true, subscriptionBackground: true);
    await preferences.load();
    var notifications = 0;
    final batches = <List<int>>[];
    Future<List<StudyUpdate>> check() async => [
          const StudyUpdate(id: 7, title: 'secret URL token=private'),
          const StudyUpdate(id: 7, title: 'same item'),
          const StudyUpdate(id: 8, title: 'read', read: true),
          const StudyUpdate(id: 0, title: 'invalid'),
        ];
    Future<bool> notify(List<StudyUpdate> updates) async {
      notifications++;
      batches.add(updates.map((item) => item.id).toList());
      return true;
    }

    final scheduler = make(check: check, notify: notify);
    scheduler.start();
    await tester.pumpAndSettle();
    expect(notifications, 1);
    expect(batches, [
      [7]
    ]);
    expect(scheduler.lastResult!.notificationStatus,
        StudySubscriptionNotificationStatus.delivered);
    expect(scheduler.checking, isFalse);
    final storage = await SharedPreferences.getInstance();
    final key = StudySubscriptionScheduler.deliveredIdsKey(scope);
    expect(storage.getStringList(key), ['7']);
    final repeated = await scheduler.checkNow(force: true);
    expect(notifications, 1);
    expect(repeated.notificationStatus,
        StudySubscriptionNotificationStatus.nothingNew);
    expect(storage.getKeys().join(), isNot(contains(scope)));
    expect(storage.get(key).toString(), isNot(contains('private')));
    scheduler.stop();
    final restarted = make(check: check, notify: notify);
    restarted.start();
    await tester.pumpAndSettle();
    expect(notifications, 1);
  });

  schedulerTest(
      'existing persisted delivery IDs suppress notifications after process restart',
      (tester) async {
    api.preferences = StudyPreferences(subscriptionNotifications: true);
    await preferences.load();
    final storage = await SharedPreferences.getInstance();
    await storage.setStringList(
        StudySubscriptionScheduler.deliveredIdsKey(scope), ['42']);
    var notifications = 0;
    final scheduler = make(
        check: () async => [const StudyUpdate(id: 42, title: 'existing')],
        notify: (_) async {
          notifications++;
          return true;
        });
    scheduler.start();
    await tester.pumpAndSettle();
    expect(notifications, 0);
    expect(scheduler.lastResult!.notificationStatus,
        StudySubscriptionNotificationStatus.nothingNew);
  });

  schedulerTest(
      'overlapping calls and two live schedulers share one scoped check',
      (tester) async {
    api.preferences = StudyPreferences(subscriptionBackground: true);
    await preferences.load();
    var checks = 0;
    final gate = Completer<List<StudyUpdate>>();
    Future<List<StudyUpdate>> check() {
      checks++;
      return gate.future;
    }

    final first = make(check: check)..start();
    final second = make(check: check)..start();
    expect(first.checking, isTrue);
    expect((await first.checkNow(force: true)).status,
        StudySubscriptionCheckStatus.busy);
    expect((await second.checkNow(force: true)).status,
        StudySubscriptionCheckStatus.busy);
    expect(checks, 1);
    gate.complete([]);
    await tester.pumpAndSettle();
    expect(first.checking, isFalse);
  });

  schedulerTest(
      'account switch discards old in-flight results and uses separate receipts',
      (tester) async {
    api.preferences = StudyPreferences(subscriptionNotifications: true);
    await preferences.load();
    final oldScope = scope;
    final gate = Completer<List<StudyUpdate>>();
    var checks = 0;
    final delivered = <int>[];
    final scheduler = make(check: () {
      checks++;
      return checks == 1
          ? gate.future
          : Future.value([const StudyUpdate(id: 9, title: 'current')]);
    }, notify: (updates) async {
      delivered.addAll(updates.map((item) => item.id));
      return true;
    });
    scheduler.start();
    scope = '$scope:other-user';
    expect((await scheduler.checkNow(force: true)).status,
        StudySubscriptionCheckStatus.notReady);
    await preferences.load();
    gate.complete([const StudyUpdate(id: 7, title: 'previous account')]);
    await tester.pumpAndSettle();
    expect(delivered, isEmpty);
    expect((await scheduler.checkNow(force: true)).notifiedCount, 1);
    expect(delivered, [9]);
    final storage = await SharedPreferences.getInstance();
    expect(
        storage.getStringList(
            StudySubscriptionScheduler.deliveredIdsKey(oldScope)),
        isNull);
    expect(
        storage
            .getStringList(StudySubscriptionScheduler.deliveredIdsKey(scope)),
        ['9']);
  });

  for (final outcome in ['denied', 'throw']) {
    schedulerTest('notification $outcome is reported, not falsely acknowledged',
        (tester) async {
      api.preferences = StudyPreferences(subscriptionNotifications: true);
      await preferences.load();
      var accepted = false;
      final scheduler = make(
          check: () async => [const StudyUpdate(id: 7, title: 'new')],
          notify: (_) async {
            if (!accepted && outcome == 'throw') {
              throw StateError('cookie=secret');
            }
            return accepted;
          });
      scheduler.start();
      await tester.pumpAndSettle();
      expect(
          scheduler.lastResult!.notificationStatus,
          outcome == 'throw'
              ? StudySubscriptionNotificationStatus.failed
              : StudySubscriptionNotificationStatus.declined);
      expect(scheduler.lastResult!.errorClass, isNot(contains('secret')));
      final storage = await SharedPreferences.getInstance();
      expect(
          storage
              .getStringList(StudySubscriptionScheduler.deliveredIdsKey(scope)),
          isNull);
      accepted = true;
      expect((await scheduler.checkNow(force: true)).notifiedCount, 1);
    });
  }

  schedulerTest(
      'check failure exposes only class and resume does not create retry storm',
      (tester) async {
    api.preferences = StudyPreferences(subscriptionBackground: true);
    await preferences.load();
    var checks = 0;
    final scheduler = make(check: () async {
      checks++;
      throw StateError('https://private/?token=secret');
    });
    scheduler.start();
    await tester.pumpAndSettle();
    expect(scheduler.lastResult!.status, StudySubscriptionCheckStatus.failed);
    expect(scheduler.lastResult!.errorClass, 'StateError');
    scheduler.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(checks, 1);
    expect((await scheduler.checkNow(force: true)).status,
        StudySubscriptionCheckStatus.failed);
    expect(checks, 2);
  });

  schedulerTest('stop while checking prevents notifications and cancels timer',
      (tester) async {
    api.preferences = StudyPreferences(
        subscriptionBackground: true, subscriptionNotifications: true);
    await preferences.load();
    final gate = Completer<List<StudyUpdate>>();
    var notified = false;
    final scheduler = make(
        check: () => gate.future,
        notify: (_) async {
          notified = true;
          return true;
        });
    scheduler.start();
    scheduler.stop();
    gate.complete([const StudyUpdate(id: 7, title: 'stale')]);
    await tester.pumpAndSettle();
    expect(notified, isFalse);
    expect(scheduler.timerActive, isFalse);
  });
}
