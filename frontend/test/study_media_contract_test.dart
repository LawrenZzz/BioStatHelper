import 'package:bio_stat_helper/core/services/api_client.dart';
import 'package:bio_stat_helper/app/modules/video/views/study_widgets.dart';
import 'package:bio_stat_helper/shared/models/project_model.dart';
import 'package:bio_stat_helper/shared/models/video_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  test('NAS study metadata survives detail merge and serialization', () {
    final video = Video.fromJson({
      'id': 42,
      'title': 'NAS课程',
      'study_item_id': 8,
      'source': 'nas',
      'source_data': {'position_seconds': 180},
      'duration_seconds': 600,
    });
    final merged = video.copyWith(sidecars: const [], progressPercent: 30);
    final restored = Video.fromJson(merged.toJson());
    expect(restored.studyItemId, 8);
    expect(restored.source, 'nas');
    expect(restored.sourceData['position_seconds'], 180);
    expect(restored.progressPercent, 30);
  });

  test('online parts retain stable IDs without a fake NAS video endpoint', () {
    final video = Video.fromJson({
      'id': -8,
      'study_item_id': 8,
      'source': 'bilibili',
      'source_data': {
        'bvid': 'BV17x411w7KC',
        'cid': 123,
        'position_seconds': 35
      },
    });
    final restored = Video.fromJson(video.copyWith(isFavorite: true).toJson());
    expect(restored.id, -8);
    expect(restored.sourceData['cid'], 123);
    expect(restored.isFavorite, isTrue);
  });

  test('legacy NAS videos retain compatible defaults', () {
    final video = Video.fromJson({'id': 1});
    expect(video.source, 'nas');
    expect(video.studyItemId, isNull);
    expect(video.sourceData, isEmpty);
  });

  test('NAS credentials are scoped to the exact backend origin', () {
    final api = ApiClient();
    final origin = Uri.parse(api.baseUrl);
    expect(api.isBackendUrl('/videos/1'), isTrue);
    expect(api.isBackendUrl('${origin.origin}/api/v1/videos/1'), isTrue);
    expect(api.isBackendUrl('https://www.bilibili.com'), isFalse);
    expect(
        api.isBackendUrl(
            '${origin.scheme}://${origin.host}.evil.test:${origin.port}/'),
        isFalse);
    expect(api.isBackendUrl(origin.replace(port: origin.port + 1).toString()),
        isFalse);
    expect(api.isBackendUrl('file:///video.mp4'), isFalse);
  });

  testWidgets('thumbnail credentials never cross backend ports or origins',
      (tester) async {
    final api = ApiClient();
    final oldToken = api.token;
    addTearDown(() => api.setToken(oldToken));
    api.setToken('thumbnail-test-token');
    final origin = Uri.parse(api.baseUrl);
    final targets = <String, bool>{
      '${origin.origin}/static/cover.jpg': true,
      '${origin.replace(port: origin.port + 1).origin}/cover.jpg': false,
      '${origin.replace(scheme: origin.scheme == 'http' ? 'https' : 'http').origin}/cover.jpg':
          false,
      'https://www.bilibili.com/cover.jpg': false,
    };
    for (final entry in targets.entries) {
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: StudyThumbnail(entry.key))));
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as NetworkImage).headers?['Authorization'],
          entry.value ? 'Bearer thumbnail-test-token' : isNull);
    }
  });

  test(
      'imported unknown CDISC is not displayed as a confirmed non-CDISC project',
      () {
    BiostatProject project({required bool cdisc, String description = ''}) =>
        BiostatProject(
            id: 1,
            name: '项目',
            isCdisc: cdisc,
            description: description,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026));
    expect(
        project(cdisc: false, description: '[snapshot:cdisc-unconfirmed]')
            .cdiscLabel,
        'CDISC 待确认');
    expect(project(cdisc: false).cdiscLabel, '非CDISC');
    expect(
        project(cdisc: true, description: '[snapshot:cdisc-unconfirmed]')
            .cdiscLabel,
        'CDISC');
  });
}
