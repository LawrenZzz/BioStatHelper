import 'dart:async';
import 'dart:convert';

import 'package:bio_stat_helper/app/modules/video/views/study_settings_view.dart';
import 'package:bio_stat_helper/core/services/api_client.dart';
import 'package:bio_stat_helper/core/services/study_preferences.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api implements ApiClient {
  dynamic data = StudyPreferences.defaults.toJson();
  FutureOr<dynamic> Function()? onGet;
  FutureOr<dynamic> Function(dynamic data)? onPut;
  final calls = <({String method, String path, dynamic data})>[];

  @override
  Future<Response> get(String path,
      {Map<String, dynamic>? queryParameters}) async {
    calls.add((method: 'GET', path: path, data: null));
    return Response(
        requestOptions: RequestOptions(path: path),
        data: onGet == null ? data : await onGet!());
  }

  @override
  Future<Response> put(String path, {dynamic data}) async {
    calls.add((method: 'PUT', path: path, data: data));
    final response = onPut == null ? data : await onPut!(data);
    return Response(requestOptions: RequestOptions(path: path), data: response);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('safe defaults match the preferences API contract exactly', () {
    final p = StudyPreferences();
    expect(p.toJson(), {
      'card_order': ['continue', 'lists', 'focus', 'updates', 'shortcuts'],
      'hidden_cards': [],
      'subscription_notifications': false,
      'subscription_background': false,
      'double_tap_left': 'seek_backward',
      'double_tap_center': 'play_pause',
      'double_tap_right': 'seek_forward',
      'double_tap_left_width': 0.35,
      'double_tap_right_width': 0.35,
      'double_tap_height': 1.0,
      'seek_seconds': 10,
      'long_press_rate': 3.0,
      'layout': 'auto',
    });
    expect(p, StudyPreferences.defaults);
    expect(p.visibleCards, p.cardOrder);
    expect(() => p.cardOrder.add('new'), throwsUnsupportedError);
    expect(StudyPreferences.fromJson(const {}), p);
  });

  test('home order fills missing known cards without duplicate entries', () {
    final p = StudyPreferences.fromJson(const {
      'card_order': ['focus', 'continue'],
      'hidden_cards': ['lists']
    });
    expect(p.cardOrder, ['focus', 'continue', 'lists', 'updates', 'shortcuts']);
    expect(p.visibleCards, ['focus', 'continue', 'updates', 'shortcuts']);
    final source = ['continue'];
    final frozen = StudyPreferences(cardOrder: source);
    source.add('bad');
    expect(frozen.cardOrder, StudyPreferences.defaultCardOrder);
  });

  for (final bad in <Map<String, dynamic>>[
    {
      'card_order': ['continue', 'continue']
    },
    {
      'card_order': ['unknown']
    },
    {'hidden_cards': 'focus'},
    {
      'hidden_cards': [1]
    },
    {'subscription_notifications': 'false'},
    {'subscription_background': 1},
    {'seek_seconds': 0},
    {'seek_seconds': 121},
    {'seek_seconds': 1.5},
    {'long_press_rate': double.nan},
    {'long_press_rate': double.infinity},
    {'long_press_rate': 4.1},
    {'double_tap_left': 'delete'},
    {'double_tap_center': 'delete'},
    {'double_tap_right': 'seek'},
    {'double_tap_left_width': 0.09},
    {'double_tap_left_width': 0.46},
    {'double_tap_left_width': double.nan},
    {'double_tap_right_width': 0.09},
    {'double_tap_right_width': 0.46},
    {'double_tap_right_width': double.infinity},
    {'double_tap_height': 0.19},
    {'double_tap_height': 1.01},
    {'double_tap_height': '0.5'},
    {'double_tap_height': double.nan},
    {'layout': 'compact'},
  ]) {
    test('invalid preferences fail closed: $bad', () {
      expect(() => StudyPreferences.fromJson(bad), throwsFormatException);
    });
  }

  test(
      'controller GET supports data wrapper and PUT contains only contract fields',
      () async {
    final api = _Api()
      ..data = {
        'data': {
          ...StudyPreferences.defaults.toJson(),
          'access_token': 'must-not-export'
        }
      };
    final c = StudyPreferencesController(api: api, scope: () => 'a');
    addTearDown(c.dispose);
    expect(await c.load(), isTrue);
    c.reorderCards(0, 5);
    c.setCardVisible('lists', false);
    c.update(
        c.value.copyWith(layout: 'landscape', doubleTapRight: 'play_pause'));
    expect(c.dirty, isTrue);
    expect(c.savedValue, StudyPreferences.defaults);
    expect(await c.save(), isTrue);
    expect(api.calls.map((call) => call.path),
        ['/study/preferences', '/study/preferences']);
    expect(api.calls.last.data.keys.toSet(), StudyPreferences.fields);
    expect(c.savedValue.cardOrder.last, 'continue');
    expect(c.savedValue.visibleCards, isNot(contains('lists')));
    expect(c.dirty, isFalse);
    expect(c.exportJson(), isNot(contains('must-not-export')));
    expect(c.exportJson(), isNot(contains('access_token')));
  });

  test('region dimensions survive copy and serialization without overlap', () {
    final p = StudyPreferences(
        doubleTapLeftWidth: 0.45,
        doubleTapRightWidth: 0.45,
        doubleTapHeight: 0.2,
        doubleTapCenter: 'none');
    expect(
        p.doubleTapLeftWidth + p.doubleTapRightWidth, lessThanOrEqualTo(0.9));
    expect(StudyPreferences.fromJson(p.toJson()), p);
    expect(p.copyWith(), p);
    expect(p.copyWith(doubleTapHeight: 1), isNot(p));
    expect(p.copyWith(doubleTapLeftWidth: 0.1).doubleTapLeftWidth, 0.1);
    expect(StudyPreferences.fromJson(const {}).doubleTapCenter, 'play_pause');
  });

  test(
      'normalized hit testing uses the centered vertical band and all three actions',
      () {
    final p = StudyPreferences(
        doubleTapLeftWidth: 0.1,
        doubleTapRightWidth: 0.45,
        doubleTapHeight: 0.4);
    expect(p.doubleTapActionAt(0.1, 0.5), 'seek_backward');
    expect(p.doubleTapActionAt(0.55, 0.5), 'seek_forward');
    expect(p.doubleTapActionAt(0.3, 0.5), 'play_pause');
    expect(p.doubleTapActionAt(0.3, 0.29), 'none');
    expect(p.doubleTapActionAt(0.3, 0.71), 'none');
    expect(p.doubleTapActionAt(0, 0.3), 'seek_backward');
    expect(p.doubleTapActionAt(1, 0.7), 'seek_forward');
    expect(p.doubleTapActionAt(-0.01, 0.5), 'none');
    expect(p.doubleTapActionAt(1.01, 0.5), 'none');
    expect(p.doubleTapActionAt(double.nan, 0.5), 'none');
    expect(p.doubleTapActionAt(0.5, double.infinity), 'none');
    expect(p.copyWith(doubleTapCenter: 'none').doubleTapActionAt(0.3, 0.5),
        'none');
  });

  test('geometry import/export stays draft-only and retains configured actions',
      () async {
    final c = StudyPreferencesController(api: _Api(), scope: () => 'geometry');
    addTearDown(c.dispose);
    await c.load();
    c.update(c.value.copyWith(
        doubleTapLeftWidth: 0.15,
        doubleTapRightWidth: 0.4,
        doubleTapHeight: 0.6,
        doubleTapCenter: 'seek_backward'));
    final expected = c.value;
    final exported = c.exportJson();
    c.discardDraft();
    c.importJson(exported);
    expect(c.value, expected);
    expect(c.savedValue, StudyPreferences.defaults);
    expect(await c.save(), isTrue);
    expect(c.savedValue, expected);
  });

  test('legacy backend preferences cannot masquerade as synced defaults',
      () async {
    final api = _Api()
      ..data = {
        'home_card_order': [
          'continue',
          'lists',
          'focus',
          'updates',
          'shortcuts'
        ],
        'notifications_enabled': true,
        'background_refresh_enabled': true,
        'layout': 'auto',
      };
    final c = StudyPreferencesController(api: api, scope: () => 'a');
    addTearDown(c.dispose);
    expect(await c.load(), isFalse);
    expect(c.isLoaded, isFalse);
    expect(await c.save(), isFalse);
    expect(api.calls.where((call) => call.method == 'PUT'), isEmpty);
  });

  testWidgets(
      'region preview displays live normalized rectangles with no overlap',
      (tester) async {
    for (final p in [
      StudyPreferences.defaults,
      StudyPreferences(
          doubleTapLeftWidth: 0.1,
          doubleTapRightWidth: 0.45,
          doubleTapHeight: 0.2)
    ]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: StudyDoubleTapRegionPreview(preferences: p))));
      final full = tester
          .getRect(find.byKey(const ValueKey('study-double-tap-preview')));
      final left = tester
          .getRect(find.byKey(const ValueKey('study-double-tap-left-region')));
      final center = tester.getRect(
          find.byKey(const ValueKey('study-double-tap-center-region')));
      final right = tester
          .getRect(find.byKey(const ValueKey('study-double-tap-right-region')));
      expect(left.width, closeTo(full.width * p.doubleTapLeftWidth, 0.01));
      expect(right.width, closeTo(full.width * p.doubleTapRightWidth, 0.01));
      expect(left.height, closeTo(full.height * p.doubleTapHeight, 0.01));
      expect(left.top,
          closeTo(full.top + full.height * (1 - p.doubleTapHeight) / 2, 0.01));
      expect(left.right, closeTo(center.left, 0.01));
      expect(center.right, closeTo(right.left, 0.01));
      expect(center.width, greaterThan(0));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'settings sliders and center action update the draft and region preview',
      (tester) async {
    tester.view.physicalSize = const Size(480, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _Api();
    final c = StudyPreferencesController(api: api, scope: () => 'regions');
    addTearDown(c.dispose);
    final semantics = tester.ensureSemantics();
    try {
      await c.load();
      await tester.pumpWidget(MaterialApp(
          home: StudySettingsView(controller: c, loadOnOpen: false)));

      for (final control in [
        (key: 'study-double-tap-left-width', direction: 1.0, value: 0.45),
        (key: 'study-double-tap-right-width', direction: -1.0, value: 0.1),
        (key: 'study-double-tap-height', direction: -1.0, value: 0.2),
      ]) {
        final slider = find.byKey(ValueKey(control.key));
        await tester.scrollUntilVisible(slider, 200,
            scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        await tester.drag(slider,
            Offset(tester.getSize(slider).width * control.direction, 0));
        await tester.pumpAndSettle();
        expect(tester.widget<Slider>(slider).value, control.value);
      }
      expect(c.value.doubleTapLeftWidth, 0.45);
      expect(c.value.doubleTapRightWidth, 0.1);
      expect(c.value.doubleTapHeight, 0.2);
      expect(
          tester
              .getSemantics(
                  find.byKey(const ValueKey('study-double-tap-height')))
              .getSemanticsData()
              .label,
          contains('区域高度'));

      final centerAction =
          find.byKey(const ValueKey('study-double-tap-center-play_pause'));
      await tester.scrollUntilVisible(centerAction, -200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(centerAction);
      await tester.pumpAndSettle();
      await tester.tap(find.text('无操作').last);
      await tester.pumpAndSettle();
      expect(c.value.doubleTapCenter, 'none');
      final preview = find.byKey(const ValueKey('study-double-tap-preview'));
      await tester.ensureVisible(preview);
      await tester.pumpAndSettle();
      final full = tester.getRect(preview);
      final left = tester
          .getRect(find.byKey(const ValueKey('study-double-tap-left-region')));
      final center =
          find.byKey(const ValueKey('study-double-tap-center-region'));
      final right = tester
          .getRect(find.byKey(const ValueKey('study-double-tap-right-region')));
      expect(left.width, closeTo(full.width * 0.45, 0.01));
      expect(right.width, closeTo(full.width * 0.1, 0.01));
      expect(left.height, closeTo(full.height * 0.2, 0.01));
      expect(left.top, closeTo(full.top + full.height * 0.4, 0.01));
      expect(find.descendant(of: center, matching: find.byIcon(Icons.block)),
          findsOneWidget);
      expect(c.savedValue, StudyPreferences.defaults);
      expect(api.calls.where((call) => call.method == 'PUT'), isEmpty);
      expect(await c.save(), isTrue);
      expect(c.savedValue, c.value);
      expect(api.calls.last.data['double_tap_left_width'], 0.45);
      expect(api.calls.last.data['double_tap_right_width'], 0.1);
      expect(api.calls.last.data['double_tap_height'], 0.2);
      expect(api.calls.last.data['double_tap_center'], 'none');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'settings import stays draft-only and permission denial blocks UI save',
      (tester) async {
    final api = _Api();
    var permissionRequests = 0;
    final c = StudyPreferencesController(
        api: api,
        scope: () => 'widget',
        beforeSave: (_, __) async {
          permissionRequests++;
          return false;
        });
    await c.load();
    await tester.pumpWidget(
        MaterialApp(home: StudySettingsView(controller: c, loadOnOpen: false)));
    await tester.tap(find.byTooltip('设置操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入设置'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('study-preferences-import')),
        '{"seek_seconds":25,"subscription_notifications":true}');
    await tester.tap(find.text('导入草稿'));
    await tester.pumpAndSettle();
    expect(c.value.seekSeconds, 25);
    expect(c.savedValue.seekSeconds, 10);
    expect(api.calls, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('study-preferences-save')));
    await tester.pumpAndSettle();
    expect(permissionRequests, 1);
    expect(c.savedValue.subscriptionNotifications, isFalse);
    expect(api.calls.where((call) => call.method == 'PUT'), isEmpty);
    expect(find.text('未获授权，设置未保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  test('export/import is versioned, draft-only, and cannot import credentials',
      () async {
    final api = _Api();
    final c = StudyPreferencesController(api: api, scope: () => 'a');
    addTearDown(c.dispose);
    await c.load();
    c.update(
        c.value.copyWith(subscriptionNotifications: true, seekSeconds: 25));
    final exported = c.exportJson();
    c.discardDraft();
    c.importJson(exported);
    expect(c.value.seekSeconds, 25);
    expect(c.savedValue.subscriptionNotifications, isFalse);
    expect(api.calls, hasLength(1));
    final before = c.value;
    for (final text in [
      '{"token":"secret"}',
      '{"cookie":"secret","seek_seconds":20}',
      '[]',
      '{"format":"focusbili-study-preferences","version":2,"preferences":{}}',
      '{"format":"focusbili-study-preferences","version":1,"preferences":{},"server":"secret"}',
      '{"seek_seconds":0}',
      '{"double_tap_left_width":0.46}',
      '{"double_tap_right_width":0.09}',
      '{"double_tap_height":0.19}',
      '{"double_tap_center":"unknown"}',
      '{bad',
      ' ' * 32769,
    ]) {
      expect(() => c.importJson(text), throwsFormatException);
      expect(c.value, before);
    }
    expect(jsonDecode(exported)['preferences'].keys.toSet(),
        StudyPreferences.fields);
  });

  test(
      'notification permission refusal prevents PUT including imported opt-ins',
      () async {
    final api = _Api();
    var hookCalls = 0;
    final c = StudyPreferencesController(
        api: api,
        scope: () => 'a',
        beforeSave: (previous, next) async {
          hookCalls++;
          expect(previous.subscriptionNotifications, isFalse);
          expect(next.subscriptionNotifications, isTrue);
          return false;
        });
    addTearDown(c.dispose);
    await c.load();
    c.importJson('{"subscription_notifications":true}');
    expect(await c.save(), isFalse);
    expect(hookCalls, 1);
    expect(api.calls.where((call) => call.method == 'PUT'), isEmpty);
    expect(c.savedValue.subscriptionNotifications, isFalse);
    expect(c.dirty, isTrue);
    expect(c.error, contains('未获授权'));
  });

  test(
      'native configuration runs after server commit and failure stays explicit',
      () async {
    final api = _Api();
    final c = StudyPreferencesController(
        api: api,
        scope: () => 'a',
        afterSave: (previous, next) async {
          expect(api.calls.last.method, 'PUT');
          expect(next.subscriptionBackground, isTrue);
          throw StateError('token=secret');
        });
    addTearDown(c.dispose);
    await c.load();
    c.update(c.value.copyWith(subscriptionBackground: true));
    expect(await c.save(), isTrue);
    expect(c.savedValue.subscriptionBackground, isTrue);
    expect(c.integrationError, '设置已保存，设备配置同步失败');
    expect(c.integrationError, isNot(contains('secret')));
  });

  test(
      'unsupported server never writes defaults or echoes sensitive diagnostics',
      () async {
    final api = _Api()
      ..onGet = () => throw const ApiException('https://private/?token=secret',
          statusCode: 404);
    final c = StudyPreferencesController(api: api, scope: () => 'a');
    addTearDown(c.dispose);
    expect(await c.load(), isFalse);
    expect(await c.save(), isFalse);
    expect(c.error, '当前服务器尚不支持学习设置');
    expect(api.calls, hasLength(1));
  });

  test('account/server switches hide old state and reject stale responses',
      () async {
    final api = _Api();
    var scope = 'server-a:user-a';
    final c = StudyPreferencesController(api: api, scope: () => scope);
    addTearDown(c.dispose);
    await c.load();
    c.update(c.value.copyWith(subscriptionNotifications: true));
    final pending = Completer<dynamic>();
    api.onPut = (_) => pending.future;
    final save = c.save();
    await Future<void>.delayed(Duration.zero);
    scope = 'server-b:user-b';
    expect(c.value, StudyPreferences.defaults);
    expect(c.savedValue, StudyPreferences.defaults);
    expect(c.isLoaded, isFalse);
    pending.complete({'subscription_notifications': true});
    expect(await save, isFalse);
    expect(await c.load(), isTrue);
    expect(c.savedValue.subscriptionNotifications, isFalse);
    final get = Completer<dynamic>();
    api.onGet = () => get.future;
    final load = c.load();
    scope = 'server-c:user-b';
    get.complete({'subscription_notifications': true});
    expect(await load, isFalse);
    expect(c.value.subscriptionNotifications, isFalse);
  });

  test(
      'in-flight save cannot overwrite a newer draft or create concurrent PUTs',
      () async {
    final api = _Api();
    final c = StudyPreferencesController(api: api, scope: () => 'a');
    addTearDown(c.dispose);
    await c.load();
    c.update(c.value.copyWith(seekSeconds: 20));
    final gate = Completer<dynamic>();
    api.onPut = (_) => gate.future;
    final save = c.save();
    expect(await c.save(), isFalse);
    c.update(c.value.copyWith(seekSeconds: 30));
    gate.complete({'seek_seconds': 20});
    expect(await save, isTrue);
    expect(c.savedValue.seekSeconds, 20);
    expect(c.value.seekSeconds, 30);
    expect(c.dirty, isTrue);
    expect(await c.load(), isFalse);
    expect(c.value.seekSeconds, 30);
  });

  test('signed-out requests and disposed response completion fail closed',
      () async {
    final api = _Api();
    final signedOut = StudyPreferencesController(api: api, scope: () => null);
    expect(await signedOut.load(), isFalse);
    expect(await signedOut.save(), isFalse);
    expect(api.calls, isEmpty);
    signedOut.dispose();
    final c = StudyPreferencesController(api: api, scope: () => 'a');
    final gate = Completer<dynamic>();
    api.onGet = () => gate.future;
    final pending = c.load();
    c.dispose();
    gate.complete(StudyPreferences.defaults.toJson());
    expect(await pending, isFalse);
  });

  for (final viewport in [
    (width: 320.0, height: 568.0, scale: 1.0),
    (width: 320.0, height: 568.0, scale: 2.0),
    (width: 360.0, height: 640.0, scale: 2.0),
    (width: 1280.0, height: 900.0, scale: 2.0)
  ]) {
    testWidgets('settings fit phone/Windows with text scale: $viewport',
        (tester) async {
      tester.view.physicalSize = Size(viewport.width, viewport.height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = StudyPreferencesController(api: _Api(), scope: () => 'widget');
      await c.load();
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(viewport.scale)),
              child: child!),
          home: StudySettingsView(controller: c, loadOnOpen: false)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('下移继续学习'));
      await tester.pumpAndSettle();
      expect(c.value.cardOrder.first, 'lists');
      await tester.tap(find.byKey(const ValueKey('study-card-visible-lists')));
      await tester.pumpAndSettle();
      expect(c.value.hiddenCards, contains('lists'));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('study-preferences-save')));
      await tester.pumpAndSettle();
      expect(c.dirty, isFalse);
      await tester.drag(find.byType(ListView).first, const Offset(0, -1800));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('播放布局'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    });
  }
}
