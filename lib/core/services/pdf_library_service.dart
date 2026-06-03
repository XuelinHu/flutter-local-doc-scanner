import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../../models/pdf_document_record.dart';
import '../constants/app_constants.dart';
import 'local_storage_service.dart';

class PdfLibraryData {
  const PdfLibraryData({
    required this.documents,
    required this.recentNames,
  });

  final List<PdfDocumentRecord> documents;
  final List<String> recentNames;
}

class PdfLibraryService {
  PdfLibraryService();

  final LocalStorageService _storage = LocalStorageService.instance;
  static const _uuid = Uuid();

  Future<PdfLibraryData> loadLibrary() async {
    final file = await _storage.getPdfLibraryFile();
    if (!await file.exists()) {
      return const PdfLibraryData(
        documents: <PdfDocumentRecord>[],
        recentNames: <String>[],
      );
    }

    final raw = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    final docsJson = (raw['documents'] as List<Object?>? ?? <Object?>[])
        .map((item) => Map<String, Object?>.from(item! as Map))
        .toList();
    final namesJson = (raw['recentNames'] as List<Object?>? ?? <Object?>[])
        .map((item) => item.toString())
        .toList();

    final documents = docsJson
        .map(PdfDocumentRecord.fromJson)
        .where((doc) => File(doc.filePath).existsSync())
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return PdfLibraryData(
      documents: documents,
      recentNames: namesJson.take(AppConstants.maxRecentPdfNames).toList(),
    );
  }

  Future<PdfDocumentRecord> saveDocumentRecord({
    required String name,
    required File file,
    required int pageCount,
  }) async {
    final library = await loadLibrary();
    final record = PdfDocumentRecord(
      id: _uuid.v4(),
      name: name,
      filePath: file.path,
      pageCount: pageCount,
      createdAt: DateTime.now(),
    );

    final documents = <PdfDocumentRecord>[
      record,
      ...library.documents.where((item) => item.filePath != file.path),
    ];
    final recentNames = _mergeRecentNames(name, library.recentNames);
    await _writeLibrary(documents: documents, recentNames: recentNames);
    return record;
  }

  Future<void> deleteDocument(PdfDocumentRecord document) async {
    final library = await loadLibrary();
    final file = File(document.filePath);
    if (await file.exists()) {
      await file.delete();
    }

    final documents =
        library.documents.where((item) => item.id != document.id).toList();
    await _writeLibrary(
      documents: documents,
      recentNames: library.recentNames,
    );
  }

  List<String> _mergeRecentNames(String name, List<String> recentNames) {
    final normalized = name.trim();
    final merged = <String>[
      normalized,
      ...recentNames.where((item) => item != normalized),
    ];
    return merged.take(AppConstants.maxRecentPdfNames).toList();
  }

  Future<void> _writeLibrary({
    required List<PdfDocumentRecord> documents,
    required List<String> recentNames,
  }) async {
    final file = await _storage.getPdfLibraryFile();
    final payload = <String, Object?>{
      'documents': documents.map((item) => item.toJson()).toList(),
      'recentNames': recentNames.take(AppConstants.maxRecentPdfNames).toList(),
    };
    await file.writeAsString(jsonEncode(payload), flush: true);
  }
}
