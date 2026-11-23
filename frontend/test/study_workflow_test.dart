import 'dart:async';

import 'package:bio_stat_helper/app/modules/video/controllers/study_controller.dart';
import 'package:bio_stat_helper/app/modules/video/views/study_home_view.dart';
import 'package:bio_stat_helper/app/modules/video/views/study_lists_view.dart';
import 'package:bio_stat_helper/app/modules/video/views/study_library_view.dart';
import 'package:bio_stat_helper/app/modules/video/views/study_search_view.dart';
import 'package:bio_stat_helper/app/modules/video/views/study_widgets.dart';
import 'package:bio_stat_helper/core/services/api_client.dart';
import 'package:bio_stat_helper/core/services/bilibili_service.dart';
import 'package:bio_stat_helper/shared/models/category_model.dart';
import 'package:bio_stat_helper/shared/models/study_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;

typedef _Handler = FutureOr<dynamic> Function(String path, dynamic data);

class _Api implements ApiClient {
  _Handler? onGet;
  _Handler? onPost;
  _Handler? onPut;
  Duration? lastPostTimeout;
  final calls = <({String method, String path, dynamic data})>[];

  Future<Response> _call(
      String method, String path, dynamic data, _Handler? handler) async {
    calls.add((method: method, path: path, data: data));
    return Response<dynamic>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: handler == null
            ? method == 'POST' && path == '/study/items'
                ? {
                    ...Map<String, dynamic>.from(data as Map),
                    'id': calls.length + 100
                  }
                : {'data': [], 'total': 0}
            : await handler(path, data));
  }

  @override
  Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) =>
      _call('GET', path, queryParameters, onGet);
  @override
  Future<Response> post(String path, {dynamic data, Duration? timeout}) {
    lastPostTimeout = timeout;
    return _call('POST', path, data, onPost);
  }

  @override
  Future<Response> put(String path, {dynamic data}) =>
      _call('PUT', path, data, onPut);
  @override
  Future<Response> delete(String path,
          {dynamic data, Map<String, dynamic>? queryParameters}) =>
      _call('DELETE', path, data, null);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _nas = StudyItem(
    id: 11,
    listId: 1,
    videoId: 42,
    source: 'nas',
    sourceData: {'nas_category_id': 3},
    title: '很长的 NAS 生物统计课程标题用于窄屏换行检查',
    durationSeconds: 600,
    positionSeconds: 90,
    status: StudyStatus.learning);
const _bili = StudyItem(
    id: 12,
    listId: 1,
    source: 'bilibili',
    sourceData: {'bvid': 'BV1234567890', 'cid': 321, 'page': 2},
    title: 'B站同一学习列表中的分P课程',
    durationSeconds: 500);
const _completed = StudyItem(
    id: 13,
    listId: 1,
    videoId: 43,
    title: '已完成的课程',
    status: StudyStatus.completed);

class _FixtureStudyController extends StudyController {
  _FixtureStudyController() : super(api: _Api()) {
    lists.assignAll(
        const [StudyList(id: 1, name: '跨来源生物统计学习列表名称很长', description: '课程计划')]);
    items.assignAll([_nas, _bili, _completed]);
    categories.assignAll([
      VideoCategory(id: 3, name: '临床统计课程', path: '研究方法/临床统计课程', videoCount: 3)
    ]);
  }
  StudyItem? openedItem;
  List<int>? reorderedIds;

  @override
  Future<bool> reorderItems(int listId, List<int> ids) async {
    reorderedIds = ids;
    return true;
  }

  @override
  Future<void> openItem(StudyItem item, {int? positionSeconds}) async {
    openedItem = item;
  }

  @override
  Future<void> refreshAll() async {}
  @override
  Future<bool> refreshItems() async => true;
  @override
  Future<bool> refreshSubscriptions() async => true;
  @override
  Future<bool> refreshUpdates() async => true;
  @override
  Future<bool> refreshLists() async => true;
  @override
  Future<bool> loadCategories() async => true;
  @override
  Future<bool> search(String query,
      {int? categoryId, String source = 'nas', int page = 1}) async {
    searchResults.assignAll([source == 'nas' ? _nas : _bili]);
    searchTotal.value = 1;
    return true;
  }

  @override
  Future<bool> saveList(
      {StudyList? list,
      required String name,
      String description = '',
      bool archived = false}) async {
    lists.add(StudyList(id: 2, name: name, description: description));
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  StudyController controller(_Api api) {
    final value = StudyController(api: api);
    addTearDown(value.onDelete.call);
    return value;
  }

  test('study data preserves source metadata, aliases and bounded progress',
      () {
    final item = StudyItem.fromJson({
      'id': '5',
      'list_id': 3,
      'source': 'bilibili',
      'source_data': {
        'bvid': 'BV1234567890',
        'cid': 888,
        'parts': [
          {'page': 1}
        ]
      },
      'title': '课程',
      'duration_seconds': 10,
      'position_seconds': 20,
      'favorite': true
    });
    expect(item.id, 5);
    expect(item.progress, 1);
    expect(item.toJson()['source_data'], item.sourceData);
    expect(StudyNote.fromJson({'image_base64': 'abc'}).imageData, 'abc');
    expect(StudyNote.fromJson({'image_data': 'def'}).imageData, 'def');
    expect(studyTime(-1), '00:00');
    expect(studyTime(3661), '1:01:01');
    expect(() => studyRows({'wrong': []}), throwsFormatException);
  });

  test(
      'player handoff preserves mixed-source IDs, study identity and exact seek',
      () {
    final c = controller(_Api());
    final nas = c.videoForItem(_nas, positionSeconds: 0);
    final bili = c.videoForItem(_bili, positionSeconds: 123);
    expect(nas.id, 42);
    expect(nas.studyItemId, 11);
    expect(nas.sourceData['position_seconds'], 0);
    expect(bili.id, -12);
    expect(bili.source, 'bilibili');
    expect(bili.studyItemId, 12);
    expect(bili.sourceData['cid'], 321);
    expect(bili.sourceData['position_seconds'], 123);
  });

  test('latest item refresh wins when requests finish out of order', () async {
    final first = Completer<dynamic>();
    final second = Completer<dynamic>();
    var calls = 0;
    final api = _Api()
      ..onGet = (_, __) => calls++ == 0 ? first.future : second.future;
    final c = controller(api);
    final earlier = c.refreshItems();
    final later = c.refreshItems();
    second.complete({
      'data': [_bili.toJson()]
    });
    await later;
    first.complete({
      'data': [_nas.toJson()]
    });
    await earlier;
    expect(c.items.single.id, _bili.id);
    expect(c.busy.contains('items'), false);
  });

  test('writes reject duplicate submissions and retain visible failures',
      () async {
    final pending = Completer<dynamic>();
    final api = _Api()..onPost = (_, __) => pending.future;
    final c = controller(api);
    final saving = c.saveList(name: '课程');
    expect(c.writing, true);
    expect(await c.saveList(name: '重复'), false);
    expect(api.calls.where((call) => call.method == 'POST').length, 1);
    pending.completeError(StateError('offline'));
    expect(await saving, false);
    expect(c.writing, false);
    expect(c.errors['write'], contains('offline'));
  });

  test(
      'reorder refuses a partial list and notes PUT excludes immutable item_id',
      () async {
    final api = _Api();
    final c = controller(api)..items.assignAll([_nas, _bili]);
    expect(await c.reorderItems(1, [11]), false);
    expect(api.calls, isEmpty);
    expect(await c.reorderItems(1, [12, 11]), true);
    expect(api.calls.first.data, {
      'list_id': 1,
      'item_ids': [12, 11]
    });
    expect(
        await c.saveNote(
            note: const StudyNote(
                id: 2, itemId: 11, positionSeconds: 4, content: '旧'),
            itemId: 11,
            positionSeconds: 7,
            content: '新',
            imageData: 'image'),
        true);
    final payload =
        api.calls.firstWhere((call) => call.method == 'PUT').data as Map;
    expect(payload.containsKey('item_id'), false);
    expect(payload['position_seconds'], 7);
    expect(payload['image_base64'], 'image');
  });

  test('NAS course reports partial success and retains complete video metadata',
      () async {
    final api = _Api();
    api.onGet = (path, _) => path == '/videos/'
        ? {
            'data': [
              {
                'id': 42,
                'title': '第一课',
                'duration_seconds': 60,
                'nas_category_id': 3
              },
              {'id': 43, 'title': '第二课', 'duration_seconds': 70},
            ],
            'total': 2
          }
        : {'data': [], 'total': 0};
    var posts = 0;
    api.onPost = (_, __) {
      if (++posts == 2) throw StateError('offline');
      return {};
    };
    final c = controller(api);
    expect(await c.addNasCourse(VideoCategory(id: 3, name: '课程'), 1), false);
    expect(c.errors['write'], contains('已添加 1 项'));
    final payload =
        api.calls.firstWhere((call) => call.method == 'POST').data as Map;
    expect(payload['video_id'], 42);
    expect(payload['source_data']['nas_category_id'], 3);
    expect(payload.containsKey('id'), false);
    expect(payload.containsKey('status'), false);
    expect(payload.containsKey('position_seconds'), false);
  });

  test(
      'NAS single-item creation inherits server progress instead of resetting it',
      () async {
    final api = _Api();
    final c = controller(api);
    expect(await c.addItem(_nas, 1), true);
    final payload =
        api.calls.firstWhere((call) => call.method == 'POST').data as Map;
    expect(payload['video_id'], 42);
    expect(payload['source_data'], _nas.sourceData);
    expect(payload.containsKey('status'), false);
    expect(payload.containsKey('position_seconds'), false);
    expect(await c.addItem(_bili, 1), true);
    final biliPayload =
        api.calls.lastWhere((call) => call.method == 'POST').data as Map;
    expect(biliPayload['status'], 'planned');
    expect(biliPayload['position_seconds'], 0);
  });

  test('acknowledged Bili item remains visible when list refresh fails',
      () async {
    final api = _Api()..onGet = (_, __) => throw StateError('refresh offline');
    final c = controller(api);
    expect(await c.addItem(_bili, 3), isTrue);
    expect(c.itemsFor(3).single.source, 'bilibili');
    expect(c.itemsFor(3).single.title, _bili.title);
    expect(c.errors['items'], contains('refresh offline'));
    expect(c.errors.containsKey('write'), isFalse);
  });

  test(
      'selected Bili parts are visible after stale read and use compact metadata',
      () async {
    final api = _Api();
    final c = controller(api);
    final parts = List.generate(
        1500,
        (i) => BiliPart(
            cid: i + 1000,
            page: i + 1,
            title: '临床统计课程第${i + 1}节',
            duration: const Duration(minutes: 10)));
    final video = BiliVideo(
        bvid: 'BV1xx411c7mD',
        aid: 1,
        title: '课程',
        cover: '',
        description: '',
        ownerMid: 1,
        ownerName: '',
        duration: const Duration(hours: 100),
        parts: parts);
    expect(await c.addBiliParts(video, parts.take(2), 1), isTrue);
    expect(c.itemsFor(1).length, 2);
    expect(c.itemsFor(1).map((item) => item.sortOrder), [0, 1]);
    for (final item in c.itemsFor(1)) {
      expect((item.sourceData['parts'] as List).length, 1);
      expect(item.sourceData['cid'], isPositive);
    }
    expect(await c.addBiliParts(video, const [], 1), isFalse);
    expect(c.errors['write'], contains('至少一个'));
  });

  test('rejected creation is never shown as an empty successful addition',
      () async {
    final api = _Api()..onPost = (_, __) => {'message': 'invalid response'};
    final c = controller(api);
    expect(await c.addItem(_bili, 1), isFalse);
    expect(c.items, isEmpty);
    expect(c.errors['write'], contains('未返回有效的学习项'));
  });

  for (final failure in [
    DioExceptionType.receiveTimeout,
    DioExceptionType.connectionError,
    null
  ]) {
    test('uncertain or conflicting save reconciles existing item: $failure',
        () async {
      final api = _Api();
      api.onPost = (_, __) => throw ApiException('request failed',
          type: failure, statusCode: failure == null ? 409 : null);
      api.onGet = (_, __) => {
            'data': [
              {
                ..._bili.toJson(),
                'id': 90,
                'list_id': 3,
                'status': 'learning',
                'position_seconds': 123,
              }
            ]
          };
      final c = controller(api);
      expect(await c.addItem(_bili, 3), isTrue);
      expect(c.itemsFor(3).single.id, 90);
      expect(c.itemsFor(3).single.positionSeconds, 123);
      expect(api.calls.where((call) => call.method == 'POST').length, 1);
      expect(api.lastPostTimeout, const Duration(seconds: 45));
    });
  }

  test('timeout without matching saved identity is not success or retried',
      () async {
    final api = _Api()
      ..onPost = (_, __) => throw const ApiException('raw timeout',
          type: DioExceptionType.receiveTimeout);
    api.onGet = (_, __) => {
          'data': [
            {
              ..._bili.toJson(),
              'id': 90,
              'list_id': 3,
              'source_data': {..._bili.sourceData, 'cid': 999},
            }
          ]
        };
    final c = controller(api);
    expect(await c.addItem(_bili, 3), isFalse);
    expect(c.items, isEmpty);
    expect(c.errors['write'], contains('暂未确认'));
    expect(c.errors['write'], isNot(contains('raw timeout')));
    expect(api.calls.where((call) => call.method == 'POST').length, 1);
  });

  test('same source in another list is not used to acknowledge a timeout',
      () async {
    final api = _Api()
      ..onPost = (_, __) => throw const ApiException('timeout',
          type: DioExceptionType.receiveTimeout);
    api.onGet = (_, __) => {
          'data': [_bili.toJson()]
        };
    final c = controller(api);
    expect(await c.addItem(_bili, 3), isFalse);
    expect(c.items, isEmpty);
  });

  test(
      'course grouping retains IDs, part order and resume state without merging records',
      () {
    final parts = List.generate(
        12,
        (index) => StudyItem(
              id: index + 50,
              listId: 1,
              title: '完整课程 · P${index + 1}',
              source: 'bilibili',
              sourceData: {
                'bvid': 'BV1xx411c7mD',
                'video_title': '完整课程',
                'title': '第${index + 1}节',
                'page': index + 1,
                'cid': index + 200,
              },
              durationSeconds: 100,
              status: index == 0
                  ? StudyStatus.completed
                  : index == 1
                      ? StudyStatus.learning
                      : StudyStatus.planned,
              positionSeconds: index == 1 ? 50 : 0,
            ));
    final groups = StudyListGroup.collect([_nas, ...parts.reversed]);
    expect(groups.length, 2);
    final course = groups.last;
    expect(course.title, '完整课程');
    expect(course.isCourse, isTrue);
    expect(course.items.map((item) => item.id), parts.map((item) => item.id));
    expect(course.completed, 1);
    expect(course.progress, 0.125);
    expect(course.continueItem.id, parts[1].id);
    expect(course.items.first.partTitle, 'P1 第1节');
    final partial = StudyListGroup.collect([
      StudyItem.fromJson({
        ...parts.first.toJson(),
        'source_data': {...parts.first.sourceData, 'part_count': 12}
      })
    ]).single;
    expect(partial.isCourse, isTrue);
    expect(partial.title, '完整课程');
    expect(
        StudyListGroup.collect([
          parts.first,
          StudyItem.fromJson({...parts[1].toJson(), 'list_id': 2})
        ]).length,
        2);
  });

  for (final width in [320.0, 800.0, 1440.0]) {
    testWidgets('Bili course collapses by title and resumes a part at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = _FixtureStudyController();
      addTearDown(c.onDelete.call);
      c.items.assignAll(List.generate(
          2,
          (index) => StudyItem(
              id: 100 + index,
              listId: 1,
              title: '统计学完整视频课程 · P${index + 1}',
              source: 'bilibili',
              sourceData: {
                'bvid': 'BV1xx411c7mD',
                'video_title': '统计学完整视频课程',
                'title': index == 0 ? '统计推断' : '回归分析',
                'page': index + 1,
                'cid': 1000 + index,
              },
              durationSeconds: 120,
              status: index == 0 ? StudyStatus.completed : StudyStatus.learning,
              positionSeconds: index == 1 ? 40 : 0)));
      await tester.pumpWidget(
          GetMaterialApp(home: StudyListDetailView(controller: c, listId: 1)));
      await tester.pumpAndSettle();
      expect(find.text('统计学完整视频课程'), findsOneWidget);
      expect(find.text('P1 统计推断'), findsNothing);
      await tester.ensureVisible(find.byTooltip('继续学习'));
      await tester.tap(find.byTooltip('继续学习'));
      await tester.pumpAndSettle();
      expect(c.openedItem?.id, 101);
      await tester.tap(find.text('统计学完整视频课程'));
      await tester.pumpAndSettle();
      expect(find.text('P1 统计推断'), findsOneWidget);
      expect(find.text('P2 回归分析'), findsOneWidget);
      await tester.tap(find.byTooltip('选择整门课程'));
      await tester.pumpAndSettle();
      expect(find.text('2 项 · 已选 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final width in [320.0, 800.0, 1440.0]) {
    for (final screen in ['home', 'search', 'list', 'subscriptions']) {
      testWidgets('$screen renders without overflow at width $width',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = _FixtureStudyController();
        c.subscriptions.assignAll(const [
          StudySubscription(id: 1, name: '很长的课程来源名称测试手机平板和电脑批量操作显示'),
          StudySubscription(id: 2, name: '第二个订阅', enabled: false),
        ]);
        c.updates.assignAll(const [
          StudyUpdate(
              id: 1, subscriptionId: 1, title: '很长的课程更新标题测试加入学习列表按钮和多选框能否自动换行'),
        ]);
        addTearDown(c.onDelete.call);
        final Widget page = switch (screen) {
          'home' => StudyHomeView(controller: c),
          'search' => StudySearchView(controller: c),
          'subscriptions' => StudySubscriptionsView(controller: c),
          _ => StudyListDetailView(controller: c, listId: 1),
        };
        await tester.pumpWidget(GetMaterialApp(home: page));
        await tester.pumpAndSettle();
        if (screen == 'search') {
          await tester.enterText(find.byType(TextField), '临床');
          await tester.pump(const Duration(milliseconds: 450));
          await tester.pumpAndSettle();
          expect(find.text(_nas.title), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.drag(
            find.byType(CustomScrollView).evaluate().isNotEmpty
                ? find.byType(CustomScrollView).first
                : find.byType(ListView).first,
            const Offset(0, -700));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'category picker selection and close do not reuse a disposed controller',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = _FixtureStudyController();
    addTearDown(c.onDelete.call);
    await tester
        .pumpWidget(GetMaterialApp(home: StudySearchView(controller: c)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择课程分类'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextField)),
        '临床');
    await tester.pump();
    await tester.tap(find.text('临床统计课程'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('整课加入'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('临床统计课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'course reorder keeps all parts together and guards expanded rows',
      (tester) async {
    final c = _FixtureStudyController();
    addTearDown(c.onDelete.call);
    c.items.assignAll([
      for (final page in [2, 1])
        StudyItem(
            id: 100 + page,
            listId: 1,
            sortOrder: page == 2 ? 0 : 2,
            title: '整组课程 · P$page',
            source: 'bilibili',
            sourceData: {
              'bvid': 'BV1xx411c7mD',
              'video_title': '整组课程',
              'title': '第$page课',
              'page': page,
              'cid': page + 2000,
            }),
      StudyItem.fromJson({..._nas.toJson(), 'sort_order': 1}),
    ]);
    await tester.pumpWidget(
        GetMaterialApp(home: StudyListDetailView(controller: c, listId: 1)));
    await tester.pumpAndSettle();
    tester
        .widget<SliverReorderableList>(find.byType(SliverReorderableList))
        .onReorderItem!(0, 1);
    await tester.pumpAndSettle();
    expect(c.reorderedIds, [11, 101, 102]);
    c.reorderedIds = null;
    await tester.ensureVisible(find.text('整组课程'));
    await tester.tap(find.text('整组课程'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('拖动排序'), findsNothing);
    tester
        .widget<SliverReorderableList>(find.byType(SliverReorderableList))
        .onReorderItem!(0, 1);
    await tester.pumpAndSettle();
    expect(c.reorderedIds, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('expanded large Bili course builds visible parts lazily',
      (tester) async {
    final c = _FixtureStudyController();
    addTearDown(c.onDelete.call);
    c.items.assignAll(List.generate(
        500,
        (index) => StudyItem(
                id: 1000 + index,
                listId: 1,
                title: '大型课程 · P${index + 1}',
                source: 'bilibili',
                sourceData: {
                  'bvid': 'BV1xx411c7mD',
                  'video_title': '大型课程',
                  'title': '第${index + 1}课',
                  'page': index + 1,
                  'cid': index + 2000,
                })));
    await tester.pumpWidget(
        GetMaterialApp(home: StudyListDetailView(controller: c, listId: 1)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('大型课程'));
    await tester.tap(find.text('大型课程'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<SliverReorderableList>(find.byType(SliverReorderableList))
            .itemCount,
        501);
    expect(find.byType(StudyItemRow).evaluate().length, lessThan(20));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.byType(StudyItemRow).evaluate().length, lessThan(20));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'selection count reflects current filtered results and disables partial drag',
      (tester) async {
    final c = _FixtureStudyController();
    addTearDown(c.onDelete.call);
    await tester.pumpWidget(
        GetMaterialApp(home: StudyListDetailView(controller: c, listId: 1)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('选择当前结果'));
    await tester.pumpAndSettle();
    expect(find.text('3 项 · 已选 3'), findsOneWidget);
    await tester.tap(find.text('已完成').first);
    await tester.pumpAndSettle();
    expect(find.text('1 项 · 已选 1'), findsOneWidget);
    expect(find.byTooltip('拖动排序'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'list editor saves then disposes text controllers after dialog animation',
      (tester) async {
    final c = _FixtureStudyController();
    addTearDown(c.onDelete.call);
    await tester.pumpWidget(GetMaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showDialog<bool>(
                          context: context,
                          builder: (_) => StudyListEditor(controller: c)),
                      child: const Text('新建')),
                ))));
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '新课程');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(c.lists.last.name, '新课程');
    expect(tester.takeException(), isNull);
  });
}
