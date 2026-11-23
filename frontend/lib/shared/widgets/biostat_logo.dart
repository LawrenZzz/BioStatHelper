import 'package:flutter/material.dart';

class BiostatLogo extends StatelessWidget {
  const BiostatLogo({
    super.key,
    this.size = 44,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFEAF4FF),
          borderRadius: BorderRadius.circular(size * 0.22),
          border: Border.all(color: const Color(0xFFB8D8F7), width: 1),
        ),
        child: const CustomPaint(
          painter: _BiostatLogoPainter(),
        ),
      ),
    );
  }
}

class _BiostatLogoPainter extends CustomPainter {
  const _BiostatLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final blue = Paint()
      ..color = const Color(0xFF1565C0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final teal = Paint()
      ..color = const Color(0xFF00897B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.055
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final axis = Paint()
      ..color = const Color(0xFF1565C0).withValues(alpha: 0.78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.045
      ..strokeCap = StrokeCap.round;

    final nodeBlue = Paint()
      ..color = const Color(0xFF1565C0)
      ..style = PaintingStyle.fill;
    final nodeTeal = Paint()
      ..color = const Color(0xFF00897B)
      ..style = PaintingStyle.fill;

    canvas.drawLine(
      Offset(size.width * 0.23, size.height * 0.79),
      Offset(size.width * 0.77, size.height * 0.79),
      axis,
    );

    final curve = Path()
      ..moveTo(size.width * 0.22, size.height * 0.68)
      ..cubicTo(
        size.width * 0.34,
        size.height * 0.48,
        size.width * 0.43,
        size.height * 0.44,
        size.width * 0.52,
        size.height * 0.58,
      )
      ..cubicTo(
        size.width * 0.61,
        size.height * 0.72,
        size.width * 0.68,
        size.height * 0.43,
        size.width * 0.82,
        size.height * 0.38,
      );
    canvas.drawPath(curve, blue);

    final molecule = Path()
      ..moveTo(size.width * 0.30, size.height * 0.34)
      ..cubicTo(
        size.width * 0.39,
        size.height * 0.24,
        size.width * 0.49,
        size.height * 0.24,
        size.width * 0.57,
        size.height * 0.34,
      )
      ..cubicTo(
        size.width * 0.66,
        size.height * 0.44,
        size.width * 0.74,
        size.height * 0.42,
        size.width * 0.80,
        size.height * 0.33,
      );
    canvas.drawPath(molecule, teal);

    canvas.drawCircle(Offset(size.width * 0.30, size.height * 0.34),
        size.width * 0.055, nodeBlue);
    canvas.drawCircle(Offset(size.width * 0.55, size.height * 0.33),
        size.width * 0.055, nodeTeal);
    canvas.drawCircle(Offset(size.width * 0.78, size.height * 0.34),
        size.width * 0.055, nodeBlue);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
