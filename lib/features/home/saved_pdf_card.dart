import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/pdf_document_record.dart';

class SavedPdfCard extends StatelessWidget {
  const SavedPdfCard({
    required this.document,
    required this.onOpen,
    required this.onShare,
    required this.onDelete,
    super.key,
  });

  final PdfDocumentRecord document;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final file = File(document.filePath);
    final sizeText = file.existsSync()
        ? '${(file.lengthSync() / 1024 / 1024).toStringAsFixed(1)} MB'
        : '文件缺失';
    final date = document.createdAt.toLocal();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE4F0FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.description_outlined, color: Color(0xFF1976D2)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(document.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        '${date.month}月${date.day}日 · ${document.pageCount} 页 · $sizeText',
                        style: const TextStyle(color: Color(0xFF8A8A8A), fontSize: 11),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.chevron_right_rounded, color: Color(0xFFB8B9B6)),
                  onSelected: (value) {
                    switch (value) {
                      case 'open':
                        onOpen();
                      case 'share':
                        onShare();
                      case 'delete':
                        onDelete();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'open', child: Text('打开')),
                    PopupMenuItem(value: 'share', child: Text('分享')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
