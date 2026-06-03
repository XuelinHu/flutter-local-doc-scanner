import 'dart:io';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

class PdfPreviewPage extends StatelessWidget {
  const PdfPreviewPage({
    required this.pdfFile,
    this.title,
    super.key,
  });

  final File pdfFile;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title ?? 'PDF 预览'),
        actions: [
          IconButton(
            onPressed: () => SharePlus.instance.share(
              ShareParams(
                files: [XFile(pdfFile.path)],
                text: '本地扫描 PDF',
              ),
            ),
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: PdfPreview(
        canChangePageFormat: false,
        canDebug: false,
        build: (_) => pdfFile.readAsBytes(),
      ),
    );
  }
}
