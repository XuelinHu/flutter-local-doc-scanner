import 'package:flutter/material.dart';

class DocumentBorderPainter extends CustomPainter {
  const DocumentBorderPainter({
    required this.corners,
    this.strokeColor = const Color(0xFF00D3B6),
    this.fillColor = const Color(0x2200D3B6),
  });

  final List<Offset> corners;
  final Color strokeColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) {
      return;
    }

    final path = Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..color = fillColor,
    );

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = strokeColor,
    );

    for (final point in corners) {
      canvas.drawCircle(
        point,
        7,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        point,
        7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = strokeColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant DocumentBorderPainter oldDelegate) {
    return oldDelegate.corners != corners ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.fillColor != fillColor;
  }
}
