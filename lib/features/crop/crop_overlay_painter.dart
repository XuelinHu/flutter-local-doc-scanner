import 'package:flutter/material.dart';

class CropOverlayPainter extends CustomPainter {
  const CropOverlayPainter({
    required this.corners,
    required this.imageRect,
  });

  final List<Offset> corners;
  final Rect imageRect;

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) {
      return;
    }

    final documentPath = Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();

    final overlay = Path()
      ..addRect(imageRect)
      ..addPath(documentPath, Offset.zero)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      overlay,
      Paint()..color = const Color(0x66000000),
    );

    canvas.drawPath(
      documentPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF36F0CA),
    );
  }

  @override
  bool shouldRepaint(covariant CropOverlayPainter oldDelegate) {
    return oldDelegate.corners != corners || oldDelegate.imageRect != imageRect;
  }
}
