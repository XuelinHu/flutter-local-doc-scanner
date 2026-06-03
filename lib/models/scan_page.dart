enum ScanMode {
  originalColor('原彩'),
  colorEnhanced('彩色增强'),
  blackWhite('黑白'),
  ;

  const ScanMode(this.label);

  final String label;
}

class ScanPage {
  const ScanPage({
    required this.id,
    required this.originalImagePath,
    required this.processedImagePath,
    required this.createdAt,
    required this.rotation,
    required this.scanMode,
  });

  final String id;
  final String originalImagePath;
  final String processedImagePath;
  final DateTime createdAt;
  final int rotation;
  final ScanMode scanMode;

  ScanPage copyWith({
    String? id,
    String? originalImagePath,
    String? processedImagePath,
    DateTime? createdAt,
    int? rotation,
    ScanMode? scanMode,
  }) {
    return ScanPage(
      id: id ?? this.id,
      originalImagePath: originalImagePath ?? this.originalImagePath,
      processedImagePath: processedImagePath ?? this.processedImagePath,
      createdAt: createdAt ?? this.createdAt,
      rotation: rotation ?? this.rotation,
      scanMode: scanMode ?? this.scanMode,
    );
  }
}
