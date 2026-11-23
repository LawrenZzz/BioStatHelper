import 'package:flutter/material.dart';

import '../../core/services/api_client.dart';
import '../models/video_model.dart';

class VideoThumbnailPreview extends StatelessWidget {
  final Video video;
  final double width;
  final double height;
  final double borderRadius;
  final bool showDuration;

  const VideoThumbnailPreview({
    super.key,
    required this.video,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 8,
    this.showDuration = true,
  });

  @override
  Widget build(BuildContext context) {
    final compact = width < 96 || height < 58;
    final playButtonSize = compact ? 28.0 : 38.0;
    final playIconSize = compact ? 21.0 : 28.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (video.thumbnailUrl.isNotEmpty)
              Image.network(
                _thumbnailUrl(video.thumbnailUrl),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _GeneratedThumbnail(video: video),
              )
            else
              _GeneratedThumbnail(video: video),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.42),
                  ],
                ),
              ),
            ),
            Center(
              child: Container(
                width: playButtonSize,
                height: playButtonSize,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.86),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Theme.of(context).colorScheme.primary,
                  size: playIconSize,
                ),
              ),
            ),
            if (video.episodeNumber != null && !compact)
              Positioned(
                left: 8,
                top: 8,
                child: _OverlayLabel(text: '第${video.episodeNumber}集'),
              ),
            if (showDuration)
              Positioned(
                right: 8,
                bottom: 8,
                child: _OverlayLabel(text: video.formattedDuration),
              ),
          ],
        ),
      ),
    );
  }

  String _thumbnailUrl(String value) {
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }

    final apiBase = Uri.parse(ApiClient().baseUrl);
    final origin = '${apiBase.scheme}://${apiBase.authority}';
    if (value.startsWith('/')) return '$origin$value';
    return '$origin/$value';
  }
}

class _GeneratedThumbnail extends StatelessWidget {
  final Video video;

  const _GeneratedThumbnail({required this.video});

  @override
  Widget build(BuildContext context) {
    final colors = _palette(context, video.title);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: CustomPaint(
        painter: _PreviewLinePainter(
          lineColor: Colors.white.withValues(alpha: 0.56),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.topLeft,
            child: Text(
              video.nasCategoryPath.isNotEmpty
                  ? video.nasCategoryPath.split('/').last
                  : video.category,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                shadows: const [
                  Shadow(
                    color: Colors.black38,
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Color> _palette(BuildContext context, String seed) {
    final hash = seed.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
    final palettes = [
      [const Color(0xFF0B6B94), const Color(0xFF2CB1BC)],
      [const Color(0xFF1E3A8A), const Color(0xFF38BDF8)],
      [const Color(0xFF0F766E), const Color(0xFF67E8F9)],
      [const Color(0xFF155E75), const Color(0xFF60A5FA)],
      [Theme.of(context).colorScheme.primary, const Color(0xFF22D3EE)],
    ];
    return palettes[hash % palettes.length];
  }
}

class _PreviewLinePainter extends CustomPainter {
  final Color lineColor;

  const _PreviewLinePainter({required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    path.moveTo(size.width * 0.06, size.height * 0.68);
    path.cubicTo(
      size.width * 0.24,
      size.height * 0.18,
      size.width * 0.38,
      size.height * 0.88,
      size.width * 0.55,
      size.height * 0.42,
    );
    path.cubicTo(
      size.width * 0.68,
      size.height * 0.10,
      size.width * 0.82,
      size.height * 0.58,
      size.width * 0.96,
      size.height * 0.30,
    );
    canvas.drawPath(path, paint);

    final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.72);
    for (final point in [
      Offset(size.width * 0.22, size.height * 0.40),
      Offset(size.width * 0.55, size.height * 0.42),
      Offset(size.width * 0.82, size.height * 0.44),
    ]) {
      canvas.drawCircle(point, 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PreviewLinePainter oldDelegate) {
    return oldDelegate.lineColor != lineColor;
  }
}

class _OverlayLabel extends StatelessWidget {
  final String text;

  const _OverlayLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
