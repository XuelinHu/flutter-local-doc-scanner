import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../models/document_corners.dart';
import '../../models/scan_page.dart';
import '../constants/app_constants.dart';
import '../services/document_scan_channel.dart';
import '../services/local_storage_service.dart';

class ImageUtils {
  ImageUtils._();

  static final _storage = LocalStorageService.instance;

  static Future<Size> readImageSize(String imagePath) async {
    final nativeInfo = await DocumentScanChannel.instance.getImageInfo(imagePath);
    if (nativeInfo != null) {
      return Size(nativeInfo.width, nativeInfo.height);
    }

    final decoded = await _decode(imagePath);
    final normalized = img.bakeOrientation(decoded);
    return Size(normalized.width.toDouble(), normalized.height.toDouble());
  }

  static Future<String> prepareEditableImage(String imagePath) async {
    final outputDir = await _storage.getCacheDirectoryPath();
    final nativePreview = await DocumentScanChannel.instance.createPreviewImage(
      imagePath: imagePath,
      outputDir: outputDir,
    );
    if (nativePreview != null) {
      return nativePreview;
    }

    final bytes = await compute(_normalizePreviewBytes, imagePath);
    return _storage.writeTempBytes(
      bytes: bytes,
      prefix: AppConstants.outputImagePrefix,
      extension: '.jpg',
    );
  }

  static Future<String> processDocument({
    required String imagePath,
    required DocumentCorners corners,
    required ScanMode mode,
  }) async {
    final outputDir = await _storage.getCacheDirectoryPath();
    final nativePath = await DocumentScanChannel.instance.processDocument(
      imagePath: imagePath,
      outputDir: outputDir,
      corners: corners,
      mode: mode,
    );
    if (nativePath != null) {
      return nativePath;
    }

    final bytes = await compute(
      _processDocumentBytes,
      <String, Object>{
        'imagePath': imagePath,
        'topLeftX': corners.topLeft.dx,
        'topLeftY': corners.topLeft.dy,
        'topRightX': corners.topRight.dx,
        'topRightY': corners.topRight.dy,
        'bottomRightX': corners.bottomRight.dx,
        'bottomRightY': corners.bottomRight.dy,
        'bottomLeftX': corners.bottomLeft.dx,
        'bottomLeftY': corners.bottomLeft.dy,
        'mode': mode.index,
      },
    );

    return _storage.writeTempBytes(
      bytes: bytes,
      prefix: AppConstants.outputImagePrefix,
      extension: '.jpg',
    );
  }

  static Future<String> rotate90(String imagePath) async {
    final outputDir = await _storage.getCacheDirectoryPath();
    final nativePath = await DocumentScanChannel.instance.rotateImage(
      imagePath: imagePath,
      outputDir: outputDir,
    );
    if (nativePath != null) {
      return nativePath;
    }

    final bytes = await compute(_rotate90Bytes, imagePath);
    return _storage.writeTempBytes(
      bytes: bytes,
      prefix: AppConstants.outputImagePrefix,
      extension: '.jpg',
    );
  }

  static img.Image _applyScanMode(img.Image source, ScanMode mode) {
    switch (mode) {
      case ScanMode.originalColor:
        return source;
      case ScanMode.colorEnhanced:
        final adjusted = img.adjustColor(
          source,
          contrast: 1.08,
          saturation: 1.06,
          brightness: 1.03,
          gamma: 0.98,
        );
        return img.contrast(adjusted, contrast: 112);
      case ScanMode.blackWhite:
        final gray = img.grayscale(source);
        return img.contrast(gray, contrast: 135);
    }
  }

  static Future<img.Image> _decode(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception('无法读取图片内容');
    }
    return decoded;
  }

  static int _edgeLength(
    Offset topLeft,
    Offset topRight,
    Offset bottomLeft,
    Offset bottomRight, {
    required bool horizontal,
  }) {
    final first = horizontal
        ? (topRight - topLeft).distance
        : (bottomLeft - topLeft).distance;
    final second = horizontal
        ? (bottomRight - bottomLeft).distance
        : (bottomRight - topRight).distance;

    return math.max(first, second).round().clamp(300, 4000);
  }
}

Uint8List _normalizePreviewBytes(String imagePath) {
  final bytes = File(imagePath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw Exception('无法读取图片内容');
  }
  final normalized = img.bakeOrientation(decoded);
  final resized = _resizeToMaxSide(normalized, 1600);
  return Uint8List.fromList(img.encodeJpg(resized, quality: 88));
}

Uint8List _rotate90Bytes(String imagePath) {
  final bytes = File(imagePath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw Exception('无法读取图片内容');
  }
  final normalized = img.bakeOrientation(decoded);
  final rotated = img.copyRotate(normalized, angle: 90);
  return Uint8List.fromList(img.encodeJpg(rotated, quality: 96));
}

Uint8List _processDocumentBytes(Map<String, Object> raw) {
  final imagePath = raw['imagePath']! as String;
  final bytes = File(imagePath).readAsBytesSync();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw Exception('无法读取图片内容');
  }

  final normalized = img.bakeOrientation(decoded);
  final corners = DocumentCorners(
    topLeft: Offset(raw['topLeftX']! as double, raw['topLeftY']! as double),
    topRight: Offset(raw['topRightX']! as double, raw['topRightY']! as double),
    bottomRight: Offset(
      raw['bottomRightX']! as double,
      raw['bottomRightY']! as double,
    ),
    bottomLeft: Offset(
      raw['bottomLeftX']! as double,
      raw['bottomLeftY']! as double,
    ),
  ).clamp(Size(normalized.width.toDouble(), normalized.height.toDouble()));

  final targetWidth = ImageUtils._edgeLength(
    corners.topLeft,
    corners.topRight,
    corners.bottomLeft,
    corners.bottomRight,
    horizontal: true,
  );
  final targetHeight = ImageUtils._edgeLength(
    corners.topLeft,
    corners.topRight,
    corners.bottomLeft,
    corners.bottomRight,
    horizontal: false,
  );

  var rectified = img.copyRectify(
    normalized,
    topLeft: img.Point(corners.topLeft.dx, corners.topLeft.dy),
    topRight: img.Point(corners.topRight.dx, corners.topRight.dy),
    bottomLeft: img.Point(corners.bottomLeft.dx, corners.bottomLeft.dy),
    bottomRight: img.Point(corners.bottomRight.dx, corners.bottomRight.dy),
    interpolation: img.Interpolation.linear,
    toImage: img.Image(width: targetWidth, height: targetHeight),
  );

  rectified = ImageUtils._applyScanMode(
    rectified,
    ScanMode.values[raw['mode']! as int],
  );
  return Uint8List.fromList(img.encodeJpg(rectified, quality: 92));
}

img.Image _resizeToMaxSide(img.Image source, int maxSide) {
  final longest = math.max(source.width, source.height);
  if (longest <= maxSide) {
    return source;
  }
  final scale = maxSide / longest;
  return img.copyResize(
    source,
    width: (source.width * scale).round(),
    height: (source.height * scale).round(),
    interpolation: img.Interpolation.linear,
  );
}
