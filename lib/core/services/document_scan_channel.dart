import 'package:flutter/services.dart';

import '../../models/document_corners.dart';
import '../../models/scan_page.dart';
import '../constants/app_constants.dart';

class DocumentScanChannel {
  DocumentScanChannel._();

  static final instance = DocumentScanChannel._();
  static const _channel = MethodChannel(AppConstants.channelName);

  Future<DocumentCorners?> detectDocument({
    required String imagePath,
    required Size imageSize,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'detectDocument',
        <String, Object?>{'imagePath': imagePath},
      );

      if (result == null) {
        return null;
      }

      final corners = DocumentCorners.fromMap(result, imageSize);
      return corners.isValid(imageSize: imageSize, minAreaRatio: 0.03)
          ? corners
          : null;
    } on PlatformException {
      return null;
    }
  }

  Future<LiveDocumentDetection?> detectPreviewFrame({
    required Uint8List bytes,
    required int width,
    required int height,
    required int rowStride,
    required int rotationDegrees,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'detectPreviewFrame',
        <String, Object?>{
          'bytes': bytes,
          'width': width,
          'height': height,
          'rowStride': rowStride,
          'rotationDegrees': rotationDegrees,
        },
      );
      if (result == null) {
        return null;
      }

      final imageSize = Size(
        (result['imageWidth'] as num).toDouble(),
        (result['imageHeight'] as num).toDouble(),
      );
      final corners = DocumentCorners.fromMap(result, imageSize);
      return corners.isValid(imageSize: imageSize, minAreaRatio: 0.08)
          ? LiveDocumentDetection(corners: corners, imageSize: imageSize)
          : null;
    } on PlatformException {
      return null;
    }
  }

  Future<ImageInfoResult?> getImageInfo(String imagePath) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getImageInfo',
        <String, Object?>{'imagePath': imagePath},
      );
      if (result == null) {
        return null;
      }
      return ImageInfoResult(
        width: (result['width'] as num).toDouble(),
        height: (result['height'] as num).toDouble(),
      );
    } on PlatformException {
      return null;
    }
  }

  Future<String?> createPreviewImage({
    required String imagePath,
    required String outputDir,
    int maxSide = 1600,
  }) async {
    try {
      return _channel.invokeMethod<String>(
        'createPreviewImage',
        <String, Object?>{
          'imagePath': imagePath,
          'outputDir': outputDir,
          'maxSide': maxSide,
        },
      );
    } on PlatformException {
      return null;
    }
  }

  Future<String?> processDocument({
    required String imagePath,
    required String outputDir,
    required DocumentCorners corners,
    required ScanMode mode,
    int maxSide = 3508,
  }) async {
    try {
      return _channel.invokeMethod<String>('processDocument', <String, Object?>{
        'imagePath': imagePath,
        'outputDir': outputDir,
        'maxSide': maxSide,
        'mode': mode.name,
        'topLeftX': corners.topLeft.dx,
        'topLeftY': corners.topLeft.dy,
        'topRightX': corners.topRight.dx,
        'topRightY': corners.topRight.dy,
        'bottomRightX': corners.bottomRight.dx,
        'bottomRightY': corners.bottomRight.dy,
        'bottomLeftX': corners.bottomLeft.dx,
        'bottomLeftY': corners.bottomLeft.dy,
      });
    } on PlatformException {
      return null;
    }
  }

  Future<String?> rotateImage({
    required String imagePath,
    required String outputDir,
  }) async {
    try {
      return _channel.invokeMethod<String>('rotateImage', <String, Object?>{
        'imagePath': imagePath,
        'outputDir': outputDir,
      });
    } on PlatformException {
      return null;
    }
  }
}

class LiveDocumentDetection {
  const LiveDocumentDetection({required this.corners, required this.imageSize});

  final DocumentCorners corners;
  final Size imageSize;
}

class ImageInfoResult {
  const ImageInfoResult({required this.width, required this.height});

  final double width;
  final double height;
}
