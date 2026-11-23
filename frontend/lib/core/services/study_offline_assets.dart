import '../../shared/models/video_model.dart';
import 'bilibili_service.dart';
import 'study_media_cache.dart';

Future<List<StudyCacheAttachment>> biliOfflineAttachments(
    BilibiliService bili, Video video,
    {void Function(String)? warning}) async {
  final result = <StudyCacheAttachment>[];
  final bvid = '${video.sourceData['bvid'] ?? ''}';
  final cid = int.tryParse('${video.sourceData['cid']}') ?? 0;
  try {
    final subtitles = await bili.getSubtitles(bvid, cid);
    for (final track in subtitles.take(32)) {
      try {
        final cues = await bili.getSubtitleBody(track);
        result.add(StudyCacheAttachment.text(
            id: 'bili:subtitle:${track.id}',
            kind: 'subtitle',
            extension: '.srt',
            title: track.label,
            text: biliCuesToSrt(cues)));
      } catch (_) {
        warning?.call('部分字幕未缓存，可联网后重试');
      }
    }
  } catch (_) {
    warning?.call('字幕未缓存，可联网后重试');
  }
  try {
    final xml = await bili.getDanmakuXml(cid);
    result.add(StudyCacheAttachment.text(
        id: 'bili:danmaku:$cid',
        kind: 'danmaku',
        extension: '.xml',
        title: '弹幕',
        text: xml));
  } catch (_) {
    warning?.call('弹幕未缓存，可联网后重试');
  }
  return result;
}

String biliCuesToSrt(List<BiliSubtitleCue> cues) {
  String time(double seconds) {
    final ms = (seconds * 1000).round();
    String pad(int n, int digits) => n.toString().padLeft(digits, '0');
    return '${pad(ms ~/ 3600000, 2)}:${pad(ms ~/ 60000 % 60, 2)}:${pad(ms ~/ 1000 % 60, 2)},${pad(ms % 1000, 3)}';
  }

  var index = 0;
  return cues
      .where((cue) =>
          cue.from.isFinite &&
          cue.to.isFinite &&
          cue.from >= 0 &&
          cue.to > cue.from)
      .map((cue) =>
          '${++index}\n${time(cue.from)} --> ${time(cue.to)}\n${cue.content.replaceAll(RegExp(r'\n\s*\n'), '\n')}\n')
      .join('\n');
}
