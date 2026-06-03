import 'dart:math' as math;
import 'dart:ui';

enum CornerHandle {
  topLeft,
  topRight,
  bottomRight,
  bottomLeft,
}

class DocumentCorners {
  const DocumentCorners({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  final Offset topLeft;
  final Offset topRight;
  final Offset bottomRight;
  final Offset bottomLeft;

  List<Offset> get points => [topLeft, topRight, bottomRight, bottomLeft];

  DocumentCorners update(CornerHandle handle, Offset value) {
    switch (handle) {
      case CornerHandle.topLeft:
        return copyWith(topLeft: value);
      case CornerHandle.topRight:
        return copyWith(topRight: value);
      case CornerHandle.bottomRight:
        return copyWith(bottomRight: value);
      case CornerHandle.bottomLeft:
        return copyWith(bottomLeft: value);
    }
  }

  DocumentCorners copyWith({
    Offset? topLeft,
    Offset? topRight,
    Offset? bottomRight,
    Offset? bottomLeft,
  }) {
    return DocumentCorners(
      topLeft: topLeft ?? this.topLeft,
      topRight: topRight ?? this.topRight,
      bottomRight: bottomRight ?? this.bottomRight,
      bottomLeft: bottomLeft ?? this.bottomLeft,
    );
  }

  DocumentCorners clamp(Size imageSize) {
    Offset clampPoint(Offset point) {
      return Offset(
        point.dx.clamp(0, imageSize.width),
        point.dy.clamp(0, imageSize.height),
      );
    }

    return DocumentCorners(
      topLeft: clampPoint(topLeft),
      topRight: clampPoint(topRight),
      bottomRight: clampPoint(bottomRight),
      bottomLeft: clampPoint(bottomLeft),
    );
  }

  bool isValid({
    required Size imageSize,
    double minAreaRatio = 0.05,
  }) {
    final area = polygonArea.abs();
    if (area < imageSize.width * imageSize.height * minAreaRatio) {
      return false;
    }

    for (var index = 0; index < points.length; index++) {
      final current = points[index];
      final next = points[(index + 1) % points.length];
      if ((next - current).distance < 20) {
        return false;
      }
    }

    return _isConvex(points);
  }

  double get polygonArea {
    double area = 0;
    for (var index = 0; index < points.length; index++) {
      final current = points[index];
      final next = points[(index + 1) % points.length];
      area += current.dx * next.dy - next.dx * current.dy;
    }
    return area / 2;
  }

  static bool _isConvex(List<Offset> points) {
    int? sign;
    for (var index = 0; index < points.length; index++) {
      final a = points[index];
      final b = points[(index + 1) % points.length];
      final c = points[(index + 2) % points.length];
      final cross = _cross(b - a, c - b);
      if (cross.abs() < 1e-3) {
        continue;
      }
      final currentSign = cross > 0 ? 1 : -1;
      sign ??= currentSign;
      if (sign != currentSign) {
        return false;
      }
    }
    return true;
  }

  static double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;

  static DocumentCorners defaultForSize(
    Size imageSize, {
    double horizontalInsetRatio = 0.08,
    double verticalInsetRatio = 0.1,
  }) {
    final insetX = imageSize.width * horizontalInsetRatio;
    final insetY = imageSize.height * verticalInsetRatio;
    final skew = math.min(imageSize.width, imageSize.height) * 0.03;

    return DocumentCorners(
      topLeft: Offset(insetX + skew, insetY),
      topRight: Offset(imageSize.width - insetX, insetY + skew),
      bottomRight: Offset(
        imageSize.width - insetX - skew,
        imageSize.height - insetY,
      ),
      bottomLeft: Offset(insetX, imageSize.height - insetY - skew),
    );
  }

  factory DocumentCorners.fromMap(
    Map<Object?, Object?> raw,
    Size imageSize,
  ) {
    Offset readPoint(String key) {
      final value = raw[key];
      if (value is! Map) {
        return Offset.zero;
      }
      final x = (value['x'] as num?)?.toDouble() ?? 0;
      final y = (value['y'] as num?)?.toDouble() ?? 0;
      return Offset(x, y);
    }

    return DocumentCorners(
      topLeft: readPoint('topLeft'),
      topRight: readPoint('topRight'),
      bottomRight: readPoint('bottomRight'),
      bottomLeft: readPoint('bottomLeft'),
    ).clamp(imageSize);
  }
}
