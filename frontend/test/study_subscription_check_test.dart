import 'package:bio_stat_helper/core/services/api_client.dart';
import 'package:bio_stat_helper/core/services/bilibili_service.dart';
import 'package:bio_stat_helper/core/services/study_subscription_check.dart';
import 'package:bio_stat_helper/shared/models/study_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api implements ApiClient {
  final payloads = <Map<String, dynamic>>[];
  @override
  Future<Response> post(String path, {dynamic data, Duration? timeout}) async {
    expect(path, '/study/updates');
    payloads.add(Map<String, dynamic>.from(data as Map));
    return Response(
        requestOptions: RequestOptions(path: path), statusCode: 200);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Bili extends BilibiliService {
  final calls = <({int mid, int? season, int page, bool reverse})>[];
  bool Function(int)? more;
  void Function()? afterFetch;
  int? failMid;
  @override
  Future<void> initialize() async {}
  BiliPage<BiliVideo> _result(int mid, int? season, int page, bool reverse) {
    calls.add((mid: mid, season: season, page: page, reverse: reverse));
    if (failMid == mid) throw StateError('source unavailable');
    afterFetch?.call();
    return BiliPage([
      BiliVideo.fromJson({
        'bvid': 'BV1234567890',
        'title': 'Lesson $page',
        'pubdate': 1700000000,
      })
    ], page: page, hasMore: more?.call(page) ?? true);
  }

  @override
  Future<BiliPage<BiliVideo>> getUploaderVideos(int mid,
          {int page = 1,
          BiliUploaderOrder order = BiliUploaderOrder.published}) async =>
      _result(mid, null, page, false);
  @override
  Future<BiliPage<BiliVideo>> getCollectionVideos(int mid, int collectionId,
          {int page = 1, bool reverse = false}) async =>
      _result(mid, collectionId, page, reverse);
}

const _up = StudySubscription(
    id: 1,
    name: 'UP',
    source: 'bilibili',
    kind: 'uploader',
    sourceData: {'mid': 8});
const _collection = StudySubscription(
    id: 2,
    name: 'Collection',
    source: 'bilibili',
    kind: 'collection',
    sourceData: {'owner_mid': 9, 'season_id': 18});

void main() {
  test('automatic check is bounded and skips NAS and paused sources', () async {
    final api = _Api();
    final bili = _Bili();
    addTearDown(bili.dispose);
    final failures = await StudySubscriptionCheck(api: api, bili: bili).run([
      _up,
      _collection,
      const StudySubscription(id: 3, name: 'NAS'),
      const StudySubscription(
          id: 4, name: 'Paused', source: 'bilibili', enabled: false),
    ]);
    expect(failures, isEmpty);
    expect(bili.calls.map((c) => c.page), [1, 2, 1, 2, 1, 2]);
    expect(bili.calls.where((c) => c.reverse), hasLength(2));
    expect(api.payloads, hasLength(6));
    final payload = api.payloads.last;
    final update = (payload['updates'] as List).single as Map;
    expect(payload['historical'], isFalse);
    expect(payload['subscription_id'], 2);
    expect(update['source_data']['owner_mid'], 9);
    expect(update['source_data']['season_id'], 18);
    expect(DateTime.parse(update['published_at']).millisecondsSinceEpoch,
        1700000000000);
  });

  test('history commits pages once and stops at the real end', () async {
    final api = _Api();
    final bili = _Bili()..more = (page) => page < 3;
    addTearDown(bili.dispose);
    await StudySubscriptionCheck(api: api, bili: bili)
        .run([_collection], historical: true);
    expect(bili.calls.map((c) => c.page), [1, 2, 3]);
    expect(bili.calls.any((c) => c.reverse), isFalse);
    expect(api.payloads.every((p) => p['historical'] == true), isTrue);
  });

  test('cancellation after a fetch prevents late writes', () async {
    final api = _Api();
    var cancelled = false;
    final bili = _Bili()..afterFetch = () => cancelled = true;
    addTearDown(bili.dispose);
    await StudySubscriptionCheck(api: api, bili: bili)
        .run([_up, _collection], cancelled: () => cancelled);
    expect(api.payloads, isEmpty);
    expect(bili.calls, hasLength(1));
  });

  test('one source failure does not suppress other sources', () async {
    final api = _Api();
    final bili = _Bili()
      ..failMid = 8
      ..more = (_) => false;
    addTearDown(bili.dispose);
    final failures = await StudySubscriptionCheck(api: api, bili: bili)
        .run([_up, _collection]);
    expect(failures.single, contains('UP'));
    expect(api.payloads, hasLength(2));
  });
}
