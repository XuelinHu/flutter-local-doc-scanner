import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/local_storage_service.dart';
import '../ai/ai_document_page.dart';
import '../../core/services/document_scan_channel.dart';
import '../../core/services/pdf_library_service.dart';
import '../../core/services/pdf_service.dart';
import '../../core/utils/image_utils.dart';
import '../../core/utils/local_pagination.dart';
import '../../models/document_corners.dart';
import '../../models/pdf_document_record.dart';
import '../../models/scan_page.dart';
import '../crop/crop_page.dart';
import '../pages/page_list_page.dart';
import '../pdf_preview/pdf_preview_page.dart';
import '../pdf_preview/save_pdf_sheet.dart';
import '../scanner/scanner_page.dart';
import 'saved_pdf_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({required this.cameras, this.pdfLibraryService, super.key});

  final List<CameraDescription> cameras;
  final PdfLibraryService? pdfLibraryService;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _uuid = Uuid();
  static const _documentsPerPage = 10;

  final ImagePicker _picker = ImagePicker();
  final PdfService _pdfService = PdfService();
  late final PdfLibraryService _pdfLibraryService;
  final LocalStorageService _storage = LocalStorageService.instance;

  final List<ScanPage> _pages = <ScanPage>[];
  List<PdfDocumentRecord> _documents = <PdfDocumentRecord>[];
  List<String> _recentNames = <String>[];
  bool _busy = false;
  bool _loadingLibrary = true;
  int _backgroundProcessingTotal = 0;
  int _backgroundProcessingDone = 0;
  int _selectedTab = 0;
  int _documentPage = 1;
  String _searchText = '';
  bool _autoCropEnabled = true;
  bool _enhanceEnabled = true;

  @override
  void initState() {
    super.initState();
    _pdfLibraryService = widget.pdfLibraryService ?? PdfLibraryService();
    _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    final library = await _pdfLibraryService.loadLibrary();
    if (!mounted) {
      return;
    }
    setState(() {
      _documents = library.documents;
      _recentNames = library.recentNames;
      _loadingLibrary = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _buildModernScaffold();
  }

  // Kept temporarily as a fallback while the redesigned dashboard is validated.
  // ignore: unused_element
  Widget _buildLegacyScaffold() {
    return Scaffold(
      appBar: AppBar(title: const Text('本地文档扫描')),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              if (_backgroundProcessingTotal > _backgroundProcessingDone)
                SliverToBoxAdapter(child: _buildBackgroundProcessingBanner()),
              SliverToBoxAdapter(child: _buildDraftTitle()),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: _pages.isEmpty ? 220 : 420,
                  child: PageListPage(
                    pages: _pages,
                    onPreview: _previewPage,
                    onRotate: _rotatePage,
                    onRecrop: _recropPage,
                    onDelete: _deletePage,
                    onReorder: _reorderPages,
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _buildLibraryTitle()),
              if (_loadingLibrary)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (_documents.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 120),
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('还没有已保存的 PDF 文档。'),
                      ),
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: _documents.length,
                  itemBuilder: (context, index) {
                    final document = _documents[index];
                    return SavedPdfCard(
                      document: document,
                      onOpen: () => _openDocument(document),
                      onShare: () => _shareDocument(document),
                      onDelete: () => _deleteDocument(document),
                    );
                  },
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
          _buildBottomActions(),
          if (_busy)
            Container(
              color: const Color(0x33000000),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF005A6F), Color(0xFF0E8C84)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '安卓离线扫描工作台',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '当前待生成 ${_pages.length} 页，已保存 ${_documents.length} 个 PDF 文档。',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftTitle() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        '当前待生成文档',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildBackgroundProcessingBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: LinearProgressIndicator(
        value: _backgroundProcessingTotal == 0
            ? null
            : _backgroundProcessingDone / _backgroundProcessingTotal,
      ),
    );
  }

  Widget _buildLibraryTitle() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        '历史 PDF 文档',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildBottomActions() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _openScanner,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('拍照扫描'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : _importFromGallery,
                  icon: const Icon(Icons.collections_outlined),
                  label: const Text('导入相册'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _generatePdf,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存 PDF'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernScaffold() {
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: switch (_selectedTab) {
              1 => _buildDocumentLibrary(),
              3 => AiDocumentPage(pages: _pages),
              4 => _buildSettings(),
              _ => _buildModernHome(),
            },
          ),
          if (_busy)
            Container(
              color: const Color(0x33000000),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 68,
        selectedIndex: _selectedTab,
        indicatorColor: const Color(0xFFFFE1BF),
        onDestinationSelected: (index) {
          if (index == 2) {
            _openScanner();
            return;
          }
          setState(() => _selectedTab = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder_rounded),
            label: '文档',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_a_photo_outlined),
            selectedIcon: Icon(Icons.add_a_photo_rounded),
            label: '扫描',
          ),
          NavigationDestination(
            icon: Icon(Icons.document_scanner_outlined),
            selectedIcon: Icon(Icons.document_scanner_rounded),
            label: 'AI识别',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: '设置',
          ),
        ],
      ),
    );
  }

  Widget _buildModernHome() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      children: [
        _buildModernHeader('扫描专家'),
        const SizedBox(height: 16),
        _buildSearchField(),
        const SizedBox(height: 18),
        Row(
          children: [
            _buildStatCard(
              '${_documents.length}',
              '文档',
              const Color(0xFF1976D2),
            ),
            const SizedBox(width: 8),
            _buildStatCard(
              '${_documents.fold<int>(0, (sum, item) => sum + item.pageCount)}',
              '页数',
              const Color(0xFF18A957),
            ),
            const SizedBox(width: 8),
            _buildStatCard(_librarySizeText(), '空间', const Color(0xFFFF8400)),
          ],
        ),
        if (_backgroundProcessingTotal > _backgroundProcessingDone)
          _buildBackgroundProcessingBanner(),
        const SizedBox(height: 16),
        Row(
          children: [
            _buildQuickAction(
              Icons.document_scanner_outlined,
              '扫描文档',
              _openScanner,
              highlighted: true,
            ),
            const SizedBox(width: 8),
            _buildQuickAction(Icons.image_outlined, '导入', _importFromGallery),
            const SizedBox(width: 8),
            _buildQuickAction(
              Icons.picture_as_pdf_outlined,
              '生成 PDF',
              _generatePdf,
            ),
          ],
        ),
        if (_pages.isNotEmpty) ...[
          const SizedBox(height: 22),
          _buildSectionHeader('待生成', action: '${_pages.length} 页'),
          const SizedBox(height: 10),
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _pages.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final page = _pages[index];
                return GestureDetector(
                  onTap: () => _recropPage(page),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(page.processedImagePath),
                      width: 82,
                      fit: BoxFit.cover,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 22),
        _buildSectionHeader(
          '最近文档',
          action: '查看全部',
          onTap: () => setState(() => _selectedTab = 1),
        ),
        const SizedBox(height: 10),
        if (_loadingLibrary)
          const Center(child: CircularProgressIndicator())
        else if (_documents.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: Text('还没有已保存的 PDF 文档')),
          )
        else
          ..._documents.take(4).map(_buildDocumentCard),
      ],
    );
  }

  Widget _buildDocumentLibrary() {
    final filteredDocuments = _documents.where((document) {
      return document.name.toLowerCase().contains(_searchText.toLowerCase());
    }).toList();
    final page = LocalPage<PdfDocumentRecord>.fromList(
      filteredDocuments,
      page: _documentPage,
      pageSize: _documentsPerPage,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      children: [
        _buildModernHeader('全部文档'),
        const SizedBox(height: 16),
        _buildSearchField(),
        const SizedBox(height: 14),
        const SizedBox(height: 4),
        if (_loadingLibrary)
          const Center(child: CircularProgressIndicator())
        else if (filteredDocuments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: Center(child: Text('没有匹配的 PDF 文档')),
          )
        else
          ...page.items.map(_buildDocumentCard),
        if (!_loadingLibrary && filteredDocuments.isNotEmpty)
          _buildDocumentPagination(page),
      ],
    );
  }

  Widget _buildDocumentPagination(LocalPage<PdfDocumentRecord> page) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${page.firstItem}-${page.lastItem} 条，共 ${page.total} 条',
              style: const TextStyle(color: Color(0xFF737373), fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: '上一页',
            onPressed: page.page > 1
                ? () => setState(() => _documentPage = page.page - 1)
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text('${page.page}/${page.totalPages}'),
          IconButton(
            tooltip: '下一页',
            onPressed: page.page < page.totalPages
                ? () => setState(() => _documentPage = page.page + 1)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Widget _buildModernHeader(String title) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
          ),
        ),
        CircleAvatar(
          radius: 18,
          backgroundColor: const Color(0xFFE7E8E5),
          child: Text(
            '${_documents.length}',
            style: const TextStyle(
              color: Color(0xFF666666),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettings() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      children: [
        _buildModernHeader('设置'),
        const SizedBox(height: 18),
        _buildSettingsTile(
          icon: Icons.crop_free_rounded,
          title: '自动推荐裁剪',
          subtitle: '拍照后自动识别文档四角',
          trailing: Switch(
            value: _autoCropEnabled,
            onChanged: (value) => setState(() => _autoCropEnabled = value),
          ),
        ),
        _buildSettingsTile(
          icon: Icons.auto_fix_high_rounded,
          title: '彩色增强',
          subtitle: '默认优化文字对比度和清晰度',
          trailing: Switch(
            value: _enhanceEnabled,
            onChanged: (value) => setState(() => _enhanceEnabled = value),
          ),
        ),
        _buildSettingsTile(
          icon: Icons.speed_rounded,
          title: '相机预览帧率',
          subtitle: '15 FPS',
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
        _buildSettingsTile(
          icon: Icons.storage_rounded,
          title: '本地存储',
          subtitle: '${_documents.length} 个 PDF · ${_librarySizeText()}',
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
        _buildSettingsTile(
          icon: Icons.info_outline_rounded,
          title: '关于扫描专家',
          subtitle: 'Android 离线文档扫描',
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF1976D2)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF8A8A8A),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      onChanged: (value) => setState(() {
        _searchText = value;
        _documentPage = 1;
      }),
      decoration: InputDecoration(
        hintText: '搜索文档名称',
        prefixIcon: const Icon(Icons.search, size: 18),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _buildStatCard(String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Color(0xFF666666), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction(
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool highlighted = false,
  }) {
    return Expanded(
      child: InkWell(
        onTap: _busy ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 76,
          decoration: BoxDecoration(
            color: highlighted ? const Color(0xFF1976D2) : Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: highlighted ? Colors.white : const Color(0xFF1976D2),
              ),
              const SizedBox(height: 7),
              Text(
                label,
                style: TextStyle(
                  color: highlighted ? Colors.white : const Color(0xFF111111),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    String title, {
    String? action,
    VoidCallback? onTap,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onTap,
            child: Text(action, style: const TextStyle(fontSize: 12)),
          ),
      ],
    );
  }

  Widget _buildDocumentCard(PdfDocumentRecord document) {
    return SavedPdfCard(
      document: document,
      onOpen: () => _openDocument(document),
      onShare: () => _shareDocument(document),
      onDelete: () => _deleteDocument(document),
    );
  }

  String _librarySizeText() {
    final bytes = _documents.fold<int>(0, (sum, item) {
      final file = File(item.filePath);
      return sum + (file.existsSync() ? file.lengthSync() : 0);
    });
    return bytes < 1024 * 1024
        ? '${(bytes / 1024).toStringAsFixed(0)} KB'
        : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Future<void> _openScanner() async {
    final pages = await Navigator.of(context).push<List<ScanPage>>(
      MaterialPageRoute(
        builder: (_) => ScannerPage(
          cameras: widget.cameras,
          autoCropEnabled: _autoCropEnabled,
          initialScanMode: _enhanceEnabled
              ? ScanMode.colorEnhanced
              : ScanMode.originalColor,
        ),
      ),
    );

    if (pages == null || pages.isEmpty || !mounted) {
      return;
    }

    final rawPages = pages
        .where((page) => page.processedImagePath == page.originalImagePath)
        .toList();
    setState(() {
      _pages.addAll(pages);
      _backgroundProcessingTotal += rawPages.length;
    });
    _processImportedPagesInBackground(rawPages);
    if (rawPages.isEmpty) {
      await _generatePdf();
    }
  }

  Future<void> _importFromGallery() async {
    setState(() => _busy = true);
    try {
      final files = await _picker.pickMultiImage(imageQuality: 100);
      final importedPages = <ScanPage>[];
      for (final file in files) {
        final importedPath = await _storage.importImageToApp(file.path);
        importedPages.add(
          ScanPage(
            id: _uuid.v4(),
            originalImagePath: importedPath,
            processedImagePath: importedPath,
            createdAt: DateTime.now(),
            rotation: 0,
            scanMode: _enhanceEnabled
                ? ScanMode.colorEnhanced
                : ScanMode.originalColor,
          ),
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _pages.addAll(importedPages);
        _backgroundProcessingTotal += importedPages.length;
      });
      _processImportedPagesInBackground(importedPages);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('相册导入失败：$error')));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _processImportedPagesInBackground(List<ScanPage> pages) async {
    for (final page in pages) {
      try {
        final imageSize = await ImageUtils.readImageSize(
          page.originalImagePath,
        );
        final detected = _autoCropEnabled
            ? await DocumentScanChannel.instance.detectDocument(
                imagePath: page.originalImagePath,
                imageSize: imageSize,
              )
            : null;
        final corners = detected ?? DocumentCorners.defaultForSize(imageSize);
        final processedPath = await ImageUtils.processDocument(
          imagePath: page.originalImagePath,
          corners: corners,
          mode: _enhanceEnabled
              ? ScanMode.colorEnhanced
              : ScanMode.originalColor,
        );

        if (!mounted) {
          return;
        }

        final index = _pages.indexWhere((item) => item.id == page.id);
        if (index >= 0) {
          setState(() {
            _pages[index] = _pages[index].copyWith(
              processedImagePath: processedPath,
              scanMode: _enhanceEnabled
                  ? ScanMode.colorEnhanced
                  : ScanMode.originalColor,
            );
          });
        }
      } finally {
        if (mounted) {
          setState(() {
            _backgroundProcessingDone += 1;
            if (_backgroundProcessingDone >= _backgroundProcessingTotal) {
              _backgroundProcessingDone = 0;
              _backgroundProcessingTotal = 0;
            }
          });
        }
      }
    }
  }

  Future<void> _generatePdf() async {
    if (_backgroundProcessingTotal > _backgroundProcessingDone) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('图片仍在后台处理中，请稍后再保存 PDF。')));
      return;
    }

    if (_pages.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前没有可生成 PDF 的页面。')));
      return;
    }

    final defaultName = _recentNames.isNotEmpty
        ? _recentNames.first
        : '扫描文档_${DateTime.now().month}${DateTime.now().day}';
    final documentName = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return SavePdfSheet(
          initialName: defaultName,
          recentNames: _recentNames,
        );
      },
    );

    if (documentName == null || documentName.trim().isEmpty) {
      return;
    }

    if (!mounted) {
      return;
    }
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final safeName = _storage.sanitizeName(documentName);
      final pdfFile = await _pdfService.generatePdf(
        pages: _pages,
        documentName: safeName,
      );
      await _pdfLibraryService.saveDocumentRecord(
        name: safeName,
        file: pdfFile,
        pageCount: _pages.length,
      );

      if (!mounted) {
        return;
      }

      await _loadLibrary();
      setState(() {
        _recentNames = [
          safeName,
          ..._recentNames.where((item) => item != safeName),
        ].take(10).toList();
        _pages.clear();
      });

      await navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => PdfPreviewPage(pdfFile: pdfFile, title: safeName),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存 PDF 失败：$error')));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _rotatePage(ScanPage page) async {
    setState(() => _busy = true);
    try {
      final rotatedPath = await ImageUtils.rotate90(page.processedImagePath);
      if (!mounted) {
        return;
      }

      final index = _pages.indexWhere((item) => item.id == page.id);
      if (index < 0) {
        return;
      }

      setState(() {
        _pages[index] = _pages[index].copyWith(
          processedImagePath: rotatedPath,
          rotation: (_pages[index].rotation + 90) % 360,
        );
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
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _recropPage(ScanPage page) async {
    final result = await Navigator.of(context).push<CropPageResult>(
      MaterialPageRoute(
        builder: (_) => CropPage(
          originalImagePath: page.originalImagePath,
          initialScanMode: page.scanMode,
          autoDetect: _autoCropEnabled,
        ),
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    final index = _pages.indexWhere((item) => item.id == page.id);
    if (index < 0) {
      return;
    }

    setState(() {
      _pages[index] = result.page.copyWith(
        id: page.id,
        createdAt: page.createdAt,
      );
    });
  }

  void _deletePage(ScanPage page) {
    setState(() => _pages.removeWhere((item) => item.id == page.id));
  }

  void _reorderPages(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final page = _pages.removeAt(oldIndex);
      _pages.insert(newIndex, page);
    });
  }

  Future<void> _previewPage(ScanPage page) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: InteractiveViewer(
            child: Image.file(File(page.processedImagePath)),
          ),
        );
      },
    );
  }

  Future<void> _openDocument(PdfDocumentRecord document) async {
    final file = File(document.filePath);
    if (!await file.exists()) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('PDF 文件不存在。')));
      return;
    }

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PdfPreviewPage(pdfFile: file, title: document.name),
      ),
    );
  }

  Future<void> _shareDocument(PdfDocumentRecord document) async {
    final file = File(document.filePath);
    if (!await file.exists()) {
      return;
    }

    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: document.name),
    );
  }

  Future<void> _deleteDocument(PdfDocumentRecord document) async {
    setState(() => _busy = true);
    try {
      await _pdfLibraryService.deleteDocument(document);
      if (!mounted) {
        return;
      }
      await _loadLibrary();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}
