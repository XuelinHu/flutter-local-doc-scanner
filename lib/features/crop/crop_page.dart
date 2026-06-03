import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/document_scan_channel.dart';
import '../../core/utils/image_utils.dart';
import '../../models/document_corners.dart';
import '../../models/scan_page.dart';
import 'corner_dragger.dart';
import 'crop_overlay_painter.dart';

class CropPage extends StatefulWidget {
  const CropPage({
    required this.originalImagePath,
    this.initialScanMode = ScanMode.colorEnhanced,
    this.autoDetect = true,
    this.showWorkflowActions = false,
    this.hasNextPage = false,
    super.key,
  });

  final String originalImagePath;
  final ScanMode initialScanMode;
  final bool autoDetect;
  final bool showWorkflowActions;
  final bool hasNextPage;

  @override
  State<CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<CropPage> {
  static const _uuid = Uuid();
  static const _dragSensitivity = 1.35;

  String? _sourceImagePath;
  String? _previewImagePath;
  Size? _imageSize;
  DocumentCorners? _corners;
  DocumentCorners? _defaultCorners;
  DocumentCorners? _detectedCorners;
  ScanMode _scanMode = ScanMode.colorEnhanced;
  bool _loading = true;
  bool _processing = false;
  bool _detecting = false;

  @override
  void initState() {
    super.initState();
    _scanMode = widget.initialScanMode;
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final sourcePath = widget.originalImagePath;
      final previewPath = await ImageUtils.prepareEditableImage(
        widget.originalImagePath,
      );
      final size = await ImageUtils.readImageSize(sourcePath);
      final defaultCorners = DocumentCorners.defaultForSize(size);
      final detected = widget.autoDetect
          ? await DocumentScanChannel.instance.detectDocument(
              imagePath: sourcePath,
              imageSize: size,
            )
          : null;

      if (!mounted) {
        return;
      }

      setState(() {
        _sourceImagePath = sourcePath;
        _previewImagePath = previewPath;
        _imageSize = size;
        _defaultCorners = defaultCorners;
        _detectedCorners = detected;
        _corners = detected ?? defaultCorners;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('读取图片失败：$error')));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageSize = _imageSize;
    final corners = _corners;
    final previewImagePath = _previewImagePath;

    return Scaffold(
      appBar: AppBar(title: const Text('裁剪与校正')),
      body:
          _loading ||
              imageSize == null ||
              corners == null ||
              previewImagePath == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Column(
                  children: [
                    Expanded(
                      child: SafeArea(
                        bottom: false,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final imageRect = _imageRectFor(
                              constraints.biggest,
                              imageSize,
                            );
                            final viewportCorners = _projectToViewport(
                              corners,
                              imageRect,
                            );

                            return Container(
                              color: const Color(0xFF0F1417),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              child: Stack(
                                children: [
                                  Positioned.fromRect(
                                    rect: imageRect,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Image.file(
                                        File(previewImagePath),
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: CropOverlayPainter(
                                        corners: viewportCorners.points,
                                        imageRect: imageRect,
                                      ),
                                    ),
                                  ),
                                  for (final handle in CornerHandle.values)
                                    CornerDragger(
                                      center: viewportCorners.pointFor(handle),
                                      onPanUpdate: (details) => _onDrag(
                                        handle,
                                        details,
                                        imageRect,
                                        corners,
                                        imageSize,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    _buildBottomPanel(),
                  ],
                ),
                if (_processing || _detecting)
                  Container(
                    color: const Color(0x66000000),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(
                            _processing ? '图像处理中…' : '正在识别推荐裁剪…',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildBottomPanel() {
    final hasDetectedCorners = _detectedCorners != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(blurRadius: 18, color: Color(0x22000000))],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '扫描模式',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (hasDetectedCorners)
                  Text(
                    '已识别推荐边缘',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF0E8C84),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ScanMode.values
                  .map(
                    (mode) => ChoiceChip(
                      label: Text(mode.label),
                      selected: _scanMode == mode,
                      onSelected: (_) => setState(() => _scanMode = mode),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _detecting ? null : _recommendCrop,
                    icon: const Icon(Icons.auto_fix_high_outlined),
                    label: const Text('推荐裁剪'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _processing || _detecting ? null : _rotateImage,
                    icon: const Icon(Icons.rotate_90_degrees_ccw_outlined),
                    label: const Text('旋转 90°'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _processing || _detecting ? null : _resetCorners,
                    icon: const Icon(Icons.crop_free_outlined),
                    label: const Text('重置裁剪框'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _processing || _detecting
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('重拍'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (widget.showWorkflowActions && widget.hasNextPage) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _processing || _detecting
                      ? null
                      : () => _confirmCrop(CropCompletionAction.nextPage),
                  icon: const Icon(Icons.navigate_next),
                  label: const Text('确认裁剪（下一页）'),
                ),
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _processing || _detecting
                    ? null
                    : () => _confirmCrop(CropCompletionAction.complete),
                icon: Icon(
                  widget.showWorkflowActions
                      ? Icons.task_alt_outlined
                      : Icons.check_circle_outline,
                ),
                label: Text(widget.showWorkflowActions ? '校正完成' : '确认裁剪'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _recommendCrop() async {
    final sourceImagePath = _sourceImagePath;
    final imageSize = _imageSize;
    final defaultCorners = _defaultCorners;
    if (sourceImagePath == null ||
        imageSize == null ||
        defaultCorners == null) {
      return;
    }

    setState(() => _detecting = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      final detected = await DocumentScanChannel.instance.detectDocument(
        imagePath: sourceImagePath,
        imageSize: imageSize,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _detectedCorners = detected;
        _corners = detected ?? defaultCorners;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('推荐裁剪失败：$error')));
    } finally {
      if (mounted) {
        setState(() => _detecting = false);
      }
    }
  }

  Future<void> _rotateImage() async {
    final sourceImagePath = _sourceImagePath;
    if (sourceImagePath == null) {
      return;
    }

    setState(() => _detecting = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      final rotatedPath = await ImageUtils.rotate90(sourceImagePath);
      final previewPath = await ImageUtils.prepareEditableImage(rotatedPath);
      final size = await ImageUtils.readImageSize(rotatedPath);
      final defaultCorners = DocumentCorners.defaultForSize(size);
      final detected = await DocumentScanChannel.instance.detectDocument(
        imagePath: rotatedPath,
        imageSize: size,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _sourceImagePath = rotatedPath;
        _previewImagePath = previewPath;
        _imageSize = size;
        _defaultCorners = defaultCorners;
        _detectedCorners = detected;
        _corners = detected ?? defaultCorners;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('旋转失败：$error')));
    } finally {
      if (mounted) {
        setState(() => _detecting = false);
      }
    }
  }

  void _resetCorners() {
    final defaultCorners = _defaultCorners;
    if (defaultCorners == null) {
      return;
    }
    setState(() => _corners = defaultCorners);
  }

  Future<void> _confirmCrop(CropCompletionAction action) async {
    final corners = _corners;
    final imageSize = _imageSize;
    final sourceImagePath = _sourceImagePath;
    if (corners == null || imageSize == null || sourceImagePath == null) {
      return;
    }

    if (!corners.isValid(imageSize: imageSize)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前四角范围无效，请重新调整。')));
      return;
    }

    setState(() => _processing = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      final processedPath = await ImageUtils.processDocument(
        imagePath: sourceImagePath,
        corners: corners,
        mode: _scanMode,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(
        CropPageResult(
          action: action,
          page: ScanPage(
            id: _uuid.v4(),
            originalImagePath: sourceImagePath,
            processedImagePath: processedPath,
            createdAt: DateTime.now(),
            rotation: 0,
            scanMode: _scanMode,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('裁剪失败：$error')));
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  void _onDrag(
    CornerHandle handle,
    DragUpdateDetails details,
    Rect imageRect,
    DocumentCorners corners,
    Size imageSize,
  ) {
    final current = _projectToViewport(corners, imageRect).pointFor(handle);
    final nextViewportPoint = current + (details.delta * _dragSensitivity);
    final nextImagePoint = _viewportToImage(
      nextViewportPoint,
      imageRect,
      imageSize,
    );

    final candidate = corners.update(handle, nextImagePoint).clamp(imageSize);
    if (!candidate.isValid(imageSize: imageSize, minAreaRatio: 0.02)) {
      return;
    }

    setState(() => _corners = candidate);
  }

  Rect _imageRectFor(Size viewportSize, Size imageSize) {
    // Keep all four 48px drag targets inside the image viewport.
    final maxWidth = viewportSize.width - 72;
    final maxHeight = viewportSize.height - 72;
    final imageAspect = imageSize.width / imageSize.height;
    final availableAspect = maxWidth / maxHeight;

    late final double width;
    late final double height;

    if (imageAspect > availableAspect) {
      width = maxWidth;
      height = width / imageAspect;
    } else {
      height = maxHeight;
      width = height * imageAspect;
    }

    return Rect.fromLTWH(
      (viewportSize.width - width) / 2,
      (viewportSize.height - height) / 2,
      width,
      height,
    );
  }

  DocumentCorners _projectToViewport(DocumentCorners corners, Rect imageRect) {
    final imageSize = _imageSize!;
    Offset project(Offset point) {
      return Offset(
        imageRect.left + point.dx / imageSize.width * imageRect.width,
        imageRect.top + point.dy / imageSize.height * imageRect.height,
      );
    }

    return DocumentCorners(
      topLeft: project(corners.topLeft),
      topRight: project(corners.topRight),
      bottomRight: project(corners.bottomRight),
      bottomLeft: project(corners.bottomLeft),
    );
  }

  Offset _viewportToImage(Offset point, Rect imageRect, Size imageSize) {
    final dx =
        ((point.dx - imageRect.left) / imageRect.width) * imageSize.width;
    final dy =
        ((point.dy - imageRect.top) / imageRect.height) * imageSize.height;
    return Offset(dx, dy);
  }
}

enum CropCompletionAction { nextPage, complete }

class CropPageResult {
  const CropPageResult({required this.page, required this.action});

  final ScanPage page;
  final CropCompletionAction action;
}

extension on DocumentCorners {
  Offset pointFor(CornerHandle handle) {
    switch (handle) {
      case CornerHandle.topLeft:
        return topLeft;
      case CornerHandle.topRight:
        return topRight;
      case CornerHandle.bottomRight:
        return bottomRight;
      case CornerHandle.bottomLeft:
        return bottomLeft;
    }
  }
}
