import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/scan_page.dart';

class PageThumbnailCard extends StatelessWidget {
  const PageThumbnailCard({
    required this.page,
    required this.index,
    required this.onPreview,
    required this.onRotate,
    required this.onRecrop,
    required this.onDelete,
    super.key,
  });

  final ScanPage page;
  final int index;
  final VoidCallback onPreview;
  final VoidCallback onRotate;
  final VoidCallback onRecrop;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: GestureDetector(
                onTap: onPreview,
                child: Image.file(
                  File(page.processedImagePath),
                  width: 84,
                  height: 112,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '第 ${index + 1} 页',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text('模式：${page.scanMode.label}'),
                  const SizedBox(height: 4),
                  Text('旋转：${page.rotation}°'),
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  onPressed: onRotate,
                  icon: const Icon(Icons.rotate_90_degrees_ccw_outlined),
                ),
                IconButton(
                  onPressed: onRecrop,
                  icon: const Icon(Icons.crop_outlined),
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.drag_handle),
          ],
        ),
      ),
    );
  }
}
