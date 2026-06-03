class PdfDocumentRecord {
  const PdfDocumentRecord({
    required this.id,
    required this.name,
    required this.filePath,
    required this.pageCount,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String filePath;
  final int pageCount;
  final DateTime createdAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'filePath': filePath,
      'pageCount': pageCount,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory PdfDocumentRecord.fromJson(Map<String, Object?> json) {
    return PdfDocumentRecord(
      id: json['id']! as String,
      name: json['name']! as String,
      filePath: json['filePath']! as String,
      pageCount: json['pageCount']! as int,
      createdAt: DateTime.parse(json['createdAt']! as String),
    );
  }
}
