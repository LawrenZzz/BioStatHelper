import 'package:bio_stat_helper/core/services/bilibili_service.dart';
import 'package:bio_stat_helper/core/services/study_offline_assets.dart';
import 'package:bio_stat_helper/shared/models/video_model.dart';
import 'package:flutter_test/flutter_test.dart';

class _Bili extends BilibiliService {
  bool failSubtitle = false;
  @override
  Future<List<BiliSubtitle>> getSubtitles(String bvid, int cid) async => [
        const BiliSubtitle(
            id: 'zh', language: 'zh', label: 'Chinese', url: 'unused')
      ];
  @override
  Future<List<BiliSubtitleCue>> getSubtitleBody(BiliSubtitle subtitle) async {
    if (failSubtitle) throw StateError('subtitle unavailable');
    return [const BiliSubtitleCue(from: 1, to: 2, content: 'Hello')];
  }

  @override
  Future<String> getDanmakuXml(int cid) async => '<i></i>';
}

void main() {
  test('SRT conversion keeps millisecond timing and skips invalid intervals',
      () {
    final srt = biliCuesToSrt([
      const BiliSubtitleCue(
          from: 0.125, to: 1.875, content: 'Line one\n\nLine two'),
      const BiliSubtitleCue(from: -1, to: 1, content: 'negative'),
      const BiliSubtitleCue(from: 2, to: 1, content: 'reversed'),
      const BiliSubtitleCue(from: double.nan, to: 1, content: 'invalid'),
      const BiliSubtitleCue(from: 3600, to: 3601, content: 'Hour'),
    ]);
    expect(
        srt,
        '1\n00:00:00,125 --> 00:00:01,875\nLine one\nLine two\n\n'
        '2\n01:00:00,000 --> 01:00:01,000\nHour\n');
  });

  for (final fail in [false, true]) {
    test('danmaku caching is independent of subtitle failure ($fail)',
        () async {
      final bili = _Bili()..failSubtitle = fail;
      addTearDown(bili.dispose);
      final warnings = <String>[];
      final video = Video.fromJson({
        'id': 1,
        'title': 'Lesson',
        'source': 'bilibili',
        'source_data': {'bvid': 'BV1234567890', 'cid': 42},
      });
      final attachments =
          await biliOfflineAttachments(bili, video, warning: warnings.add);
      expect(attachments.map((a) => a.id),
          fail ? ['bili:danmaku:42'] : ['bili:subtitle:zh', 'bili:danmaku:42']);
      expect(warnings.isNotEmpty, fail);
    });
  }
}
