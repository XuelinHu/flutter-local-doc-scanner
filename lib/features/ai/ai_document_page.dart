import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/services/ai_document_service.dart';
import '../../models/scan_page.dart';

class AiDocumentPage extends StatefulWidget {
  const AiDocumentPage({
    required this.pages,
    this.settingsRepository,
    this.service = const AiDocumentService(),
    this.loadImageBytes = _loadImageBytes,
    super.key,
  });

  final List<ScanPage> pages;
  final AiDocumentSettingsRepository? settingsRepository;
  final AiDocumentService service;
  final Future<List<int>> Function(String path) loadImageBytes;

  @override
  State<AiDocumentPage> createState() => _AiDocumentPageState();
}

class _AiDocumentPageState extends State<AiDocumentPage> {
  late final AiDocumentSettingsRepository _settingsRepository;
  final _endpoint = TextEditingController();
  final _model = TextEditingController();
  final _apiKey = TextEditingController();
  int _selectedIndex = 0;
  bool _loadingSettings = true;
  bool _sending = false;
  String? _error;
  String _result = '';

  @override
  void initState() {
    super.initState();
    _settingsRepository =
        widget.settingsRepository ?? SecureAiDocumentSettingsRepository();
    _loadSettings();
  }

  @override
  void didUpdateWidget(covariant AiDocumentPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedIndex >= widget.pages.length) {
      _selectedIndex = widget.pages.isEmpty ? 0 : widget.pages.length - 1;
    }
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _settingsRepository.load();
      _endpoint.text = settings.endpoint;
      _model.text = settings.model;
      _apiKey.text = settings.apiKey;
    } catch (_) {
      _error = '无法读取本机 AI 配置。';
    }
    if (mounted) setState(() => _loadingSettings = false);
  }

  AiDocumentSettings get _settings => AiDocumentSettings(
    endpoint: _endpoint.text,
    model: _model.text,
    apiKey: _apiKey.text,
  );

  Future<void> _saveSettings() async {
    try {
      AiDocumentService.validateEndpoint(_endpoint.text);
      if (_model.text.trim().isEmpty) {
        throw const AiDocumentException('请填写支持图像输入的模型名称。');
      }
      await _settingsRepository.save(_settings);
      if (mounted) {
        setState(() => _error = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('AI 连接配置已安全保存到本机。')));
      }
    } on AiDocumentException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '保存 AI 配置失败。');
    }
  }

  Future<void> _recognize() async {
    if (_sending || widget.pages.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
      _result = '';
    });
    try {
      await _settingsRepository.save(_settings);
      final page = widget.pages[_selectedIndex];
      final result = await widget.service.recognizeImage(
        settings: _settings,
        imageBytes: await widget.loadImageBytes(page.processedImagePath),
        fileName: Uri.file(page.processedImagePath).pathSegments.last,
      );
      if (mounted) setState(() => _result = result);
    } on AiDocumentException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '图像识别失败，请检查图片和模型配置。');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.pages.isEmpty ? null : widget.pages[_selectedIndex];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 30),
      children: [
        Text('AI 文档识别', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        const Text('仅在点击上传后发送当前选中的扫描页。图像可能包含个人信息。'),
        const SizedBox(height: 16),
        if (_loadingSettings)
          const LinearProgressIndicator()
        else ...[
          TextField(
            controller: _endpoint,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Chat Completions 地址',
              hintText: 'http://192.168.1.9:11434/v1/chat/completions',
            ),
          ),
          TextField(
            controller: _model,
            decoration: const InputDecoration(
              labelText: '视觉模型名称',
              hintText: '填写已部署的多模态模型',
            ),
          ),
          TextField(
            controller: _apiKey,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'API Key（本机安全存储，可留空）'),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _sending ? null : _saveSettings,
              icon: const Icon(Icons.lock_outline),
              label: const Text('保存连接'),
            ),
          ),
        ],
        const Divider(height: 24),
        if (widget.pages.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('先拍摄或导入一页扫描图片。')),
          )
        else ...[
          Wrap(
            spacing: 8,
            children: [
              for (var index = 0; index < widget.pages.length; index++)
                ChoiceChip(
                  label: Text('第 ${index + 1} 页'),
                  selected: _selectedIndex == index,
                  onSelected: _sending
                      ? null
                      : (_) => setState(() {
                          _selectedIndex = index;
                          _result = '';
                        }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (page != null)
            Container(
              height: 250,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.file(
                File(page.processedImagePath),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    const Center(child: Text('无法预览此页图片。')),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _sending || _loadingSettings ? null : _recognize,
            icon: _sending
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.document_scanner_outlined),
            label: Text(_sending ? '正在识别' : '上传此页并识别文字'),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_result.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('识别结果', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          SelectableText(_result),
        ],
      ],
    );
  }
}

Future<List<int>> _loadImageBytes(String imagePath) async {
  final file = File(imagePath);
  if (!await file.exists()) {
    throw const AiDocumentException('扫描图片已不存在，请重新导入或拍摄。');
  }
  if (await file.length() > AiDocumentService.maxImageBytes) {
    throw const AiDocumentException('图片超过 8 MiB；请先裁剪或降低扫描分辨率。');
  }
  return file.readAsBytes();
}
