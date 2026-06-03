import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/scan_page.dart';
import 'local_storage_service.dart';

class PdfService {
  PdfService();

  final LocalStorageService _storage = LocalStorageService.instance;

  Future<File> generatePdf({
    required List<ScanPage> pages,
    required String documentName,
  }) async {
    final pdf = pw.Document();

    for (final page in pages) {
      final imageBytes = await File(page.processedImagePath).readAsBytes();
      final image = pw.MemoryImage(imageBytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) {
            return pw.Center(
              child: pw.Image(
                image,
                fit: pw.BoxFit.contain,
              ),
            );
          },
        ),
      );
    }

    final outputPath = await _storage.createNamedPdfPath(documentName);
    final file = File(outputPath);
    await file.writeAsBytes(await pdf.save(), flush: true);
    return file;
  }
}
