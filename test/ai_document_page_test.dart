import 'package:flutter/material.dart';
import 'package:flutter_local_doc_scanner/core/services/ai_document_service.dart';
import 'package:flutter_local_doc_scanner/features/ai/ai_document_page.dart';
import 'package:flutter_local_doc_scanner/models/scan_page.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySettings implements AiDocumentSettingsRepository {
  _MemorySettings([this.settings = const AiDocumentSettings()]);

  final AiDocumentSettings settings;
  AiDocumentSettings? saved;

  @override
  Future<AiDocumentSettings> load() async => settings;

  @override
  Future<void> save(AiDocumentSettings settings) async {
    saved = settings;
  }
}

class _RecordingAiService extends AiDocumentService {
  AiDocumentSettings? receivedSettings;
  List<int>? receivedImage;
  String? receivedFileName;

  @override
  Future<bool> checkOllamaVisionCapability({
    required AiDocumentSettings settings,
  }) async => true;

  @override
  Future<String> recognizeImage({
    required AiDocumentSettings settings,
    required List<int> imageBytes,
    required String fileName,
  }) async {
    receivedSettings = settings;
    receivedImage = imageBytes;
    receivedFileName = fileName;
    return '本地扫描页识别结果';
  }
}

void main() {
  testWidgets('AI page explains image upload and empty draft state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiDocumentPage(
            pages: const [],
            settingsRepository: _MemorySettings(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI 文档识别'), findsOneWidget);
    expect(find.text('先拍摄或导入一页扫描图片。'), findsOneWidget);
    expect(find.text('仅在点击上传后发送当前选中的扫描页。图像可能包含个人信息。'), findsOneWidget);
    expect(find.text('视觉模型名称'), findsOneWidget);
    expect(find.text('检查视觉能力'), findsOneWidget);
  });

  testWidgets('model capability check does not load or upload a scan page', (
    tester,
  ) async {
    final service = _RecordingAiService();
    final settings = _MemorySettings(
      const AiDocumentSettings(
        endpoint: 'http://192.168.1.9:11434/v1/chat/completions',
        model: 'vision-test',
        apiKey: 'test-key',
      ),
    );
    var imageLoads = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiDocumentPage(
            pages: [
              ScanPage(
                id: 'page-1',
                originalImagePath: '/local/page.png',
                processedImagePath: '/local/page.png',
                createdAt: DateTime.utc(2026),
                rotation: 0,
                scanMode: ScanMode.originalColor,
              ),
            ],
            settingsRepository: settings,
            service: service,
            loadImageBytes: (_) async {
              imageLoads++;
              return [1, 2, 3];
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('检查视觉能力'));
    await tester.pumpAndSettle();

    expect(find.text('模型支持图像输入。'), findsOneWidget);
    expect(imageLoads, 0);
    expect(service.receivedImage, isNull);
    expect(settings.saved, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'selected scan page uploads on tap and renders recognition result',
    (tester) async {
      final service = _RecordingAiService();
      final settings = _MemorySettings(
        AiDocumentSettings(
          endpoint: 'http://127.0.0.1:11434/v1/chat/completions',
          model: 'vision-test',
          apiKey: 'test-key',
        ),
      );
      String? loadedPath;
      List<int>? loadedBytes;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AiDocumentPage(
              pages: [
                ScanPage(
                  id: 'page-1',
                  originalImagePath: '/local/page.png',
                  processedImagePath: '/local/page.png',
                  createdAt: DateTime.utc(2026),
                  rotation: 0,
                  scanMode: ScanMode.originalColor,
                ),
              ],
              settingsRepository: settings,
              service: service,
              loadImageBytes: (path) async {
                loadedPath = path;
                loadedBytes = [1, 2, 3];
                return loadedBytes!;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('第 1 页'), findsOneWidget);
      expect(find.text('识别结果'), findsNothing);
      expect(service.receivedImage, isNull);
      expect(loadedPath, isNull);

      await tester.scrollUntilVisible(
        find.text('上传此页并识别文字'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('上传此页并识别文字'));
      await tester.pumpAndSettle();

      expect(loadedPath, '/local/page.png');
      expect(service.receivedSettings?.model, 'vision-test');
      expect(service.receivedSettings?.apiKey, 'test-key');
      expect(service.receivedImage, [1, 2, 3]);
      expect(service.receivedFileName, 'page.png');
      await tester.scrollUntilVisible(
        find.byType(SelectableText),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        '本地扫描页识别结果',
      );
      expect(settings.saved, isNotNull);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('rejects a LAN HTTP key before saving or loading a scan', (
    tester,
  ) async {
    final settings = _MemorySettings(
      const AiDocumentSettings(
        endpoint: 'http://192.168.1.9:8999/v1/chat/completions',
        model: 'vision-test',
        apiKey: 'test-key',
      ),
    );
    var imageLoads = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiDocumentPage(
            pages: [
              ScanPage(
                id: 'page-1',
                originalImagePath: '/local/page.png',
                processedImagePath: '/local/page.png',
                createdAt: DateTime.utc(2026),
                rotation: 0,
                scanMode: ScanMode.originalColor,
              ),
            ],
            settingsRepository: settings,
            loadImageBytes: (_) async {
              imageLoads++;
              return [1, 2, 3];
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('上传此页并识别文字'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('上传此页并识别文字'));
    await tester.pumpAndSettle();

    expect(
      find.text('发送 API Key 必须使用 HTTPS；HTTP 仅允许本机回环地址。'),
      findsOneWidget,
    );
    expect(settings.saved, isNull);
    expect(imageLoads, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
