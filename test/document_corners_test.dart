import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_doc_scanner/models/document_corners.dart';

void main() {
  const imageSize = Size(1000, 1400);

  test('default corners form a valid document region', () {
    final corners = DocumentCorners.defaultForSize(imageSize);

    expect(corners.isValid(imageSize: imageSize), isTrue);
  });

  test('clamps detected corners to image bounds', () {
    final corners = DocumentCorners.fromMap(
      <String, Object?>{
        'topLeft': <String, num>{'x': -20, 'y': 50},
        'topRight': <String, num>{'x': 900, 'y': 50},
        'bottomRight': <String, num>{'x': 900, 'y': 1500},
        'bottomLeft': <String, num>{'x': -20, 'y': 1300},
      },
      imageSize,
    );

    expect(corners.topLeft.dx, 0);
    expect(corners.bottomRight.dy, imageSize.height);
    expect(corners.isValid(imageSize: imageSize), isTrue);
  });

  test('rejects a crossed quadrilateral', () {
    const corners = DocumentCorners(
      topLeft: Offset(100, 100),
      topRight: Offset(900, 1300),
      bottomRight: Offset(900, 100),
      bottomLeft: Offset(100, 1300),
    );

    expect(corners.isValid(imageSize: imageSize), isFalse);
  });
}
