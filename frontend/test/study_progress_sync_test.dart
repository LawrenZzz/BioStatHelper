import 'dart:async';
import 'dart:convert';

import 'package:bio_stat_helper/core/services/api_client.dart';
import 'package:bio_stat_helper/core/services/study_progress_sync.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ProgressApi implements ApiClient {
  final calls = <({String path, dynamic data})>[];
  FutureOr<void> Function(String path, dynamic data)? handler;

  @override
  Future<Response> put(String path, {dynamic data}) async {
    calls.add((path: path, data: data));
    await handler?.call(path, data);
    return Response(
        requestOptions: RequestOptions(path: path), statusCode: 200);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('offline progress persists and a fresh instance retries it', () async {
    final api = _ProgressApi()
      ..handler = (_, __) => throw const ApiException('offline');
    final sync = StudyProgressSync(api: api, scope: () => 'account-a');
    await sync.save(
        itemId: 7, videoId: 42, position: 90, duration: 600, completed: false);
    expect((await sync.pendingItems())[7]?['position_seconds'], 90);
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('account-a')!;
    expect(stored, isNot(contains('Authorization')));
    expect(stored, isNot(contains('token')));

    api.handler = null;
    final restarted = StudyProgressSync(api: api, scope: () => 'account-a');
    await restarted.flush();
    expect(api.calls.last.path, '/study/items/7');
    expect(api.calls.last.data['position_seconds'], 90);
    expect(api.calls.last.data['status'], 'learning');
    expect(await restarted.pendingItems(), isEmpty);
    expect(jsonDecode(prefs.getString('account-a')!), isEmpty);
  });

  test('latest position and completion replace an older offline record',
      () async {
    final api = _ProgressApi()
      ..handler = (_, __) => throw const ApiException('offline');
    final sync = StudyProgressSync(api: api, scope: () => 'account-a');
    await sync.save(itemId: 1, position: 40, duration: 100, completed: false);
    await sync.save(itemId: 1, position: 100, duration: 100, completed: true);
    api.handler = null;
    api.calls.clear();
    await sync.flush();
    expect(api.calls, hasLength(1));
    expect(api.calls.single.data['position_seconds'], 100);
    expect(api.calls.single.data['status'], 'completed');
    expect(await sync.pendingItems(), isEmpty);
  });

  test('deleted items leave neither a persisted nor a local pending overlay',
      () async {
    final api = _ProgressApi()
      ..handler = (_, __) => throw const ApiException('offline');
    final sync = StudyProgressSync(api: api, scope: () => 'account-a');
    await sync.save(itemId: 1, position: 10, duration: 100, completed: false);
    await sync.save(itemId: 2, position: 20, duration: 100, completed: false);
    api.calls.clear();
    api.handler = (path, _) {
      if (path.endsWith('/1')) {
        throw const ApiException('deleted', statusCode: 404);
      }
    };
    await sync.flush();
    expect(api.calls.map((call) => call.path),
        ['/study/items/1', '/study/items/2']);
    expect(await sync.pendingItems(), isEmpty);
  });

  test('account changes do not upload the previous account queue', () async {
    var scope = 'account-a';
    final api = _ProgressApi()
      ..handler = (_, __) => throw const ApiException('offline');
    final sync = StudyProgressSync(api: api, scope: () => scope);
    await sync.save(itemId: 7, position: 10, duration: 100, completed: false);
    scope = 'account-b';
    api.handler = null;
    api.calls.clear();
    expect(await sync.pendingItems(), isEmpty);
    await sync.flush();
    expect(api.calls, isEmpty);
    scope = 'account-a';
    await sync.flush();
    expect(api.calls.single.path, '/study/items/7');
  });

  test(
      'new progress during an upload is not lost by the earlier acknowledgement',
      () async {
    final first = Completer<void>();
    final api = _ProgressApi();
    api.handler = (_, __) => api.calls.length == 1 ? first.future : null;
    final sync = StudyProgressSync(api: api, scope: () => 'account-a');
    final older =
        sync.save(itemId: 7, position: 10, duration: 100, completed: false);
    await Future<void>.delayed(Duration.zero);
    final newer =
        sync.save(itemId: 7, position: 80, duration: 100, completed: false);
    expect((await sync.pendingItems())[7]?['position_seconds'], 80);
    first.complete();
    await Future.wait([older, newer]);
    expect(api.calls.last.data['position_seconds'], 80);
    expect(await sync.pendingItems(), isEmpty);
  });

  test('legacy NAS queue converts seconds to bounded percent', () async {
    final api = _ProgressApi();
    final sync = StudyProgressSync(api: api, scope: () => 'account-a');
    await sync.save(videoId: 42, position: 120, duration: 100, completed: true);
    expect(api.calls.single.path, '/videos/42/progress');
    expect(api.calls.single.data['progress_percent'], 100);
    expect(api.calls.single.data['completed'], isTrue);
  });
}
