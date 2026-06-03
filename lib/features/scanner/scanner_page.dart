import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/local_storage_service.dart';
import '../../core/services/document_scan_channel.dart';
import '../../core/utils/image_utils.dart';
import '../../core/utils/permission_utils.dart';
import '../../models/document_corners.dart';
import '../../models/scan_page.dart';
import '../crop/crop_page.dart';
import 'document_border_painter.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({
    required this.cameras,
    this.autoCropEnabled = true,
    this.initialScanMode = ScanMode.colorEnhanced,
    super.key,
  });

  final List<CameraDescription> cameras;
  final bool autoCropEnabled;
  final ScanMode initialScanMode;

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  static const _uuid = Uuid();

  final ImagePicker _picker = ImagePicker();
  final LocalStorageService _storage = LocalStorageService.instance;
  final List<ScanPage> _capturedPages = [];
  final Set<String> _processingPageIds = {};
  final Set<String> _manuallyEditedPageIds = {};

  CameraController? _controller;
  LiveDocumentDetection? _liveDetection;
  DateTime _lastLiveDetectionAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _liveDetectionInFlight = false;
  int _liveDetectionMisses = 0;
  bool _permissionDenied = false;
  bool _initializing = true;
  bool _busy = false;
  FlashMode _flashMode = FlashMode.off;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    final granted = await PermissionUtils.ensureCameraPermission();
    if (!mounted) {
      return;
    }

    if (!granted) {
      setState(() {
        _permissionDenied = true;
        _initializing = false;
      });
      return;
    }

    if (widget.cameras.isEmpty) {
      setState(() => _initializing = false);
      return;
    }

    final camera = widget.cameras.firstWhere(
      (item) => item.lensDirection == CameraLensDirection.back,
      orElse: () => widget.cameras.first,
    );

    final controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      fps: 15,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await controller.initialize();
    await controller.setFlashMode(_flashMode);
    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _controller = controller;
      _initializing = false;
    });
    if (widget.autoCropEnabled) {
      await controller.startImageStream(_detectPreviewFrame);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildModernScanner();
  }

  // Kept temporarily as a fallback while the redesigned scanner is validated.
  // ignore: unused_element
  Widget _buildLegacyScanner() {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _initializing
            ? const Center(child: CircularProgressIndicator())
            : _permissionDenied
            ? _buildMessage('未授予相机权限，请在系统设置中开启。')
            : controller == null || !controller.value.isInitialized
            ? _buildMessage('当前设备未检测到可用相机。')
            : LayoutBuilder(
                builder: (context, constraints) {
                  final guideCorners = _guideCorners(constraints.biggest);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(controller),
                      CustomPaint(
                        painter: DocumentBorderPainter(
                          corners: guideCorners,
                          strokeColor: const Color(0xFF36F0CA),
                          fillColor: const Color(0x1100D3B6),
                        ),
                      ),
                      _buildTopBar(),
                      _buildBottomBar(),
                      if (_busy)
                        Container(
                          color: const Color(0x55000000),
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  Widget _buildModernScanner() {
    final controller = _controller;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F0),
      appBar: AppBar(
        title: const Text(
          '扫描文档',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          onPressed: _busy ? null : _closeScanner,
          icon: const Icon(Icons.close),
        ),
        actions: [
          if (_capturedPages.isNotEmpty)
            TextButton(
              onPressed: _busy || _processingPageIds.isNotEmpty
                  ? null
                  : () => Navigator.of(context).pop(_capturedPages),
              child: Text(
                _processingPageIds.isNotEmpty
                    ? '处理中 (${_processingPageIds.length})'
                    : '完成并导出 (${_capturedPages.length})',
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            if (_initializing)
              const Center(child: CircularProgressIndicator())
            else if (_permissionDenied)
              _buildMessage('未授予相机权限，请在系统设置中开启。')
            else if (controller == null || !controller.value.isInitialized)
              _buildMessage('当前设备未检测到可用相机。')
            else
              ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: math.min(
                        MediaQuery.sizeOf(context).height * 0.43,
                        430,
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CameraPreview(controller),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              return CustomPaint(
                                painter: DocumentBorderPainter(
                                  corners: _previewCorners(constraints.biggest),
                                  strokeColor: Colors.white70,
                                  fillColor: const Color(0x11000000),
                                ),
                              );
                            },
                          ),
                          const Center(
                            child: Text(
                              '将文档放入框内',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildScannerIconButton(
                        Icons.photo_library_outlined,
                        _importFromGallery,
                      ),
                      GestureDetector(
                        onTap: _busy ? null : _capturePhoto,
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF8400),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF111111),
                              width: 3,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 8,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                        ),
                      ),
                      _buildScannerIconButton(
                        _flashMode == FlashMode.torch
                            ? Icons.flash_on_rounded
                            : Icons.flash_off_rounded,
                        _toggleFlash,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '最近扫描',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  if (_capturedPages.isEmpty)
                    Row(
                      children: List.generate(
                        3,
                        (index) => Expanded(
                          child: Container(
                            height: 64,
                            margin: EdgeInsets.only(right: index == 2 ? 0 : 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE7E8E5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.description_outlined,
                                color: Colors.grey.shade500,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: 76,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _capturedPages.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          return GestureDetector(
                            onTap: () => _editCapturedPage(index),
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.file(
                                    File(
                                      _capturedPages[index].processedImagePath,
                                    ),
                                    width: 64,
                                    height: 76,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const Positioned(
                                  right: 3,
                                  bottom: 3,
                                  child: CircleAvatar(
                                    radius: 10,
                                    backgroundColor: Color(0xCCFFFFFF),
                                    child: Icon(Icons.edit_outlined, size: 12),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  if (_capturedPages.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _showCapturedPagesEditor,
                        icon: const Icon(Icons.edit_outlined),
                        label: Text('编辑已拍图片 (${_capturedPages.length})'),
                      ),
                    ),
                  ],
                ],
              ),
            if (_busy)
              Container(
                color: const Color(0x55000000),
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerIconButton(IconData icon, VoidCallback onPressed) {
    return IconButton.filledTonal(
      onPressed: _busy ? null : onPressed,
      style: IconButton.styleFrom(backgroundColor: const Color(0xFFE7E8E5)),
      icon: Icon(icon, size: 20),
    );
  }

  void _closeScanner() {
    Navigator.of(context).pop();
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: Row(
        children: [
          IconButton.filledTonal(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
          const Spacer(),
          IconButton.filledTonal(
            onPressed: _busy ? null : _toggleFlash,
            icon: Icon(
              _flashMode == FlashMode.torch
                  ? Icons.flash_on_rounded
                  : Icons.flash_off_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 18,
      child: Row(
        children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: _busy ? null : _importFromGallery,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('导入'),
            ),
          ),
          const SizedBox(width: 16),
          GestureDetector(
            onTap: _busy ? null : _capturePhoto,
            child: Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: const Color(0xFF005A6F), width: 6),
              ),
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Text(
              '先对准纸张，再保留彩色原件',
              textAlign: TextAlign.right,
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
    );
  }

  List<Offset> _guideCorners(Size size) {
    final rect = Rect.fromLTWH(
      size.width * 0.1,
      size.height * 0.16,
      size.width * 0.8,
      size.height * 0.62,
    );
    return [
      Offset(rect.left + 18, rect.top),
      Offset(rect.right, rect.top + 20),
      Offset(rect.right - 20, rect.bottom),
      Offset(rect.left, rect.bottom - 18),
    ];
  }

  List<Offset> _previewCorners(Size viewportSize) {
    final detection = _liveDetection;
    if (detection == null) {
      return _guideCorners(viewportSize);
    }

    final sourceSize = detection.imageSize;
    final scale = math.max(
      viewportSize.width / sourceSize.width,
      viewportSize.height / sourceSize.height,
    );
    final offset = Offset(
      (viewportSize.width - sourceSize.width * scale) / 2,
      (viewportSize.height - sourceSize.height * scale) / 2,
    );
    return detection.corners.points
        .map((point) => Offset(point.dx * scale, point.dy * scale) + offset)
        .toList();
  }

  Future<void> _detectPreviewFrame(CameraImage image) async {
    if (_liveDetectionInFlight || !mounted || image.planes.isEmpty) {
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastLiveDetectionAt) <
        const Duration(milliseconds: 450)) {
      return;
    }

    final controller = _controller;
    if (controller == null) {
      return;
    }

    _lastLiveDetectionAt = now;
    _liveDetectionInFlight = true;
    try {
      final plane = image.planes.first;
      final detection = await DocumentScanChannel.instance.detectPreviewFrame(
        bytes: plane.bytes,
        width: image.width,
        height: image.height,
        rowStride: plane.bytesPerRow,
        rotationDegrees: controller.description.sensorOrientation,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        if (detection == null) {
          _liveDetectionMisses += 1;
          if (_liveDetectionMisses >= 3) {
            _liveDetection = null;
          }
        } else {
          _liveDetection = detection;
          _liveDetectionMisses = 0;
        }
      });
    } finally {
      _liveDetectionInFlight = false;
    }
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }

    final nextMode = _flashMode == FlashMode.torch
        ? FlashMode.off
        : FlashMode.torch;
    await controller.setFlashMode(nextMode);
    if (!mounted) {
      return;
    }
    setState(() => _flashMode = nextMode);
  }

  Future<void> _capturePhoto() async {
    final controller = _controller;
    if (controller == null || _busy) {
      return;
    }

    setState(() => _busy = true);
    try {
      final file = await controller.takePicture();
      final importedPath = await _storage.importImageToApp(file.path);
      final page = ScanPage(
        id: _uuid.v4(),
        originalImagePath: importedPath,
        processedImagePath: importedPath,
        createdAt: DateTime.now(),
        rotation: 0,
        scanMode: widget.initialScanMode,
      );
      setState(() => _capturedPages.add(page));
      _processCapturedPage(page);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('拍照失败：$error')));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _processCapturedPage(ScanPage page) async {
    setState(() => _processingPageIds.add(page.id));
    try {
      final imageSize = await ImageUtils.readImageSize(page.originalImagePath);
      final detected = widget.autoCropEnabled
          ? await DocumentScanChannel.instance.detectDocument(
              imagePath: page.originalImagePath,
              imageSize: imageSize,
            )
          : null;
      final processedPath = await ImageUtils.processDocument(
        imagePath: page.originalImagePath,
        corners: detected ?? DocumentCorners.defaultForSize(imageSize),
        mode: widget.initialScanMode,
      );
      if (!mounted) {
        return;
      }
      final index = _capturedPages.indexWhere((item) => item.id == page.id);
      if (index >= 0 && !_manuallyEditedPageIds.contains(page.id)) {
        setState(() {
          _capturedPages[index] = _capturedPages[index].copyWith(
            processedImagePath: processedPath,
          );
        });
      }
    } catch (_) {
      // Keep the original image available for manual editing if auto processing fails.
    } finally {
      if (mounted) {
        setState(() => _processingPageIds.remove(page.id));
      }
    }
  }

  Future<void> _showCapturedPagesEditor() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _capturedPages.length,
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) {
                    newIndex -= 1;
                  }
                  setState(() {
                    final page = _capturedPages.removeAt(oldIndex);
                    _capturedPages.insert(newIndex, page);
                  });
                  setSheetState(() {});
                },
                itemBuilder: (context, index) {
                  final page = _capturedPages[index];
                  return ListTile(
                    key: ValueKey(page.id),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(page.processedImagePath),
                        width: 48,
                        height: 60,
                        fit: BoxFit.cover,
                      ),
                    ),
                    title: Text('第 ${index + 1} 张'),
                    subtitle: Text(page.scanMode.label),
                    trailing: const Icon(Icons.drag_handle),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _editCapturedPage(index);
                    },
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _editCapturedPage(int index) async {
    if (_busy || index >= _capturedPages.length) {
      return;
    }
    var currentIndex = index;
    while (mounted && currentIndex < _capturedPages.length) {
      final page = _capturedPages[currentIndex];
      final result = await Navigator.of(context).push<CropPageResult>(
        MaterialPageRoute(
          builder: (_) => CropPage(
            originalImagePath: page.originalImagePath,
            initialScanMode: page.scanMode,
            autoDetect: widget.autoCropEnabled,
            showWorkflowActions: true,
            hasNextPage: currentIndex + 1 < _capturedPages.length,
          ),
        ),
      );
      if (!mounted || result == null) {
        return;
      }
      setState(() {
        _manuallyEditedPageIds.add(page.id);
        _capturedPages[currentIndex] = result.page.copyWith(
          id: page.id,
          createdAt: page.createdAt,
        );
      });
      if (result.action != CropCompletionAction.nextPage) {
        return;
      }
      currentIndex += 1;
    }
  }

  Future<void> _importFromGallery() async {
    if (_busy) {
      return;
    }

    setState(() => _busy = true);
    try {
      final files = await _picker.pickMultiImage(imageQuality: 100);
      final pages = <ScanPage>[];
      for (final file in files) {
        final importedPath = await _storage.importImageToApp(file.path);
        pages.add(
          ScanPage(
            id: _uuid.v4(),
            originalImagePath: importedPath,
            processedImagePath: importedPath,
            createdAt: DateTime.now(),
            rotation: 0,
            scanMode: widget.initialScanMode,
          ),
        );
      }

      if (!mounted) {
        return;
      }

      if (pages.isNotEmpty) {
        Navigator.of(context).pop(pages);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入图片失败：$error')));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}
