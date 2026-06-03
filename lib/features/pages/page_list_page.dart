import 'package:flutter/material.dart';

import '../../models/scan_page.dart';
import 'page_thumbnail_card.dart';

class PageListPage extends StatelessWidget {
  const PageListPage({
    required this.pages,
    required this.onPreview,
    required this.onRotate,
    required this.onRecrop,
    required this.onDelete,
    required this.onReorder,
    super.key,
  });

  final List<ScanPage> pages;
  final ValueChanged<ScanPage> onPreview;
  final ValueChanged<ScanPage> onRotate;
  final ValueChanged<ScanPage> onRecrop;
  final ValueChanged<ScanPage> onDelete;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    if (pages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.document_scanner_outlined, size: 72),
              const SizedBox(height: 12),
              Text(
                '先拍摄或导入文档页面，再生成本地 PDF。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 180),
      itemCount: pages.length,
      onReorder: onReorder,
      itemBuilder: (context, index) {
        final page = pages[index];
        return Container(
          key: ValueKey(page.id),
          child: PageThumbnailCard(
            page: page,
            index: index,
            onPreview: () => onPreview(page),
            onRotate: () => onRotate(page),
            onRecrop: () => onRecrop(page),
            onDelete: () => onDelete(page),
          ),
        );
      },
    );
  }
}
