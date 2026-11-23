import 'dart:convert';

import 'package:bio_stat_helper/app/modules/video/controllers/study_controller.dart';
import 'package:bio_stat_helper/app/modules/video/views/study_offline_view.dart';
import 'package:bio_stat_helper/core/services/api_client.dart';
import 'package:bio_stat_helper/core/services/bilibili_service.dart';
import 'package:bio_stat_helper/core/services/study_media_cache.dart';
import 'package:bio_stat_helper/shared/models/video_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _Api implements ApiClient {
  @override
  String get baseUrl => 'https://nas.test/api/v1';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _video = Video.fromJson({
  'id': -7,
  'study_item_id': 7,
  'source': 'bilibili',
  'title': 'Offline lesson',
  'source_data': {'bvid': 'BV17x411w7KC', 'cid': 123},
  'duration_seconds': 60
});

class _Cache extends StudyMediaCache {
  final account = 'a'.obs;
  final saved = <StudyCacheAttachment>[];
  @override
  String? get scopeKey => account.value;
  @override
  Future<List<StudyCacheEntry>> entries() async => account.value == 'a'
      ? [
          StudyCacheEntry(
              video: _video,
              complete: true,
              receivedBytes: 20,
              totalBytes: 20,
              layout: 'dash',
              attachments: [
                for (final item in saved)
                  StudyCachedAttachment(
                      id: item.id,
                      kind: item.kind,
                      extension: item.extension,
                      title: item.title,
                      path: '/unused',
                      bytes: utf8.encode(item.text!).length)
              ])
        ]
      : [];
  @override
  Future<void> cacheAttachments(
      Video video, List<StudyCacheAttachment> attachments,
      {String? expectedScope}) async {
    if (expectedScope != scopeKey) throw StateError('Account changed');
    saved.clear();
    saved.addAll(attachments);
    revision.value++;
  }
}

class _Bili extends BilibiliService {
  bool failSubtitles = false;
  @override
  Future<void> initialize() async {}
  @override
  Future<List<BiliSubtitle>> getSubtitles(String bvid, int cid) async {
    if (failSubtitles) throw StateError('Subtitle unavailable');
    return [
      const BiliSubtitle(
          id: 'en',
          language: 'en',
          label: 'English',
          url: 'https://unused.test')
    ];
  }

  @override
  Future<List<BiliSubtitleCue>> getSubtitleBody(BiliSubtitle subtitle) async =>
      [const BiliSubtitleCue(from: 0.125, to: 1.75, content: 'Hello offline')];
  @override
  Future<String> getDanmakuXml(int cid) async =>
      '<i><d p="1,1,25,16777215">Hi</d></i>';
}

void main() {
  testWidgets(
      'optional subtitle resolution errors remain visible after list refresh',
      (tester) async {
    final cache = _Cache();
    final bili = _Bili()..failSubtitles = true;
    final controller =
        StudyController(api: _Api(), bilibili: bili, mediaCache: cache);
    addTearDown(controller.onDelete.call);
    addTearDown(cache.dispose);
    addTearDown(bili.dispose);
    await tester.pumpWidget(
        GetMaterialApp(home: StudyOfflineView(controller: controller)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('\u5b57\u5e55\u4e0e\u5f39\u5e55'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('\u66f4\u65b0\u5b57\u5e55\u4e0e\u5f39\u5e55'));
    await tester.pumpAndSettle();
    expect(cache.saved.single.kind, 'danmaku');
    expect(
        find.textContaining('\u5b57\u5e55\u672a\u7f13\u5b58'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [320.0, 800.0, 1440.0]) {
    testWidgets('attachments refresh as SRT/XML with no overflow at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final cache = _Cache();
      final bili = _Bili();
      final controller =
          StudyController(api: _Api(), bilibili: bili, mediaCache: cache);
      addTearDown(controller.onDelete.call);
      addTearDown(cache.dispose);
      addTearDown(bili.dispose);
      await tester.pumpWidget(
          GetMaterialApp(home: StudyOfflineView(controller: controller)));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('\u5b57\u5e55\u4e0e\u5f39\u5e55'));
      await tester.pumpAndSettle();
      expect(find.text('\u6682\u65e0\u79bb\u7ebf\u9644\u4ef6'), findsOneWidget);
      await tester.tap(find.text('\u66f4\u65b0\u5b57\u5e55\u4e0e\u5f39\u5e55'));
      await tester.pumpAndSettle();
      expect(cache.saved.length, 2);
      expect(cache.saved.first.id, 'bili:subtitle:en');
      expect(cache.saved.last.id, 'bili:danmaku:123');
      expect(cache.saved.first.text, contains('00:00:00,125 --> 00:00:01,750'));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('\u5b57\u5e55\u4e0e\u5f39\u5e55'));
      await tester.pumpAndSettle();
      expect(find.text('English'), findsOneWidget);
      expect(tester.takeException(), isNull);
      cache.account.value = 'b';
      await tester.pumpAndSettle();
      expect(find.text('English'), findsNothing);
      expect(find.text('\u66f4\u65b0\u5b57\u5e55\u4e0e\u5f39\u5e55'),
          findsNothing);
      expect(find.text('\u8d26\u53f7\u5df2\u5207\u6362'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }
}
