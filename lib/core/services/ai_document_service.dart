import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AiDocumentSettings {
  const AiDocumentSettings({
    this.endpoint = 'http://192.168.1.9:11434/v1/chat/completions',
    this.model = '',
    this.apiKey = '',
  });

  final String endpoint;
  final String model;
  final String apiKey;
}

abstract interface class AiDocumentSettingsRepository {
  Future<AiDocumentSettings> load();
  Future<void> save(AiDocumentSettings settings);
}

class SecureAiDocumentSettingsRepository
    implements AiDocumentSettingsRepository {
  SecureAiDocumentSettingsRepository({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _endpointKey = 'ai.endpoint';
  static const _modelKey = 'ai.model';
  static const _apiKey = 'ai.api_key';

  @override
  Future<AiDocumentSettings> load() async => AiDocumentSettings(
    endpoint:
        await _storage.read(key: _endpointKey) ??
        const AiDocumentSettings().endpoint,
    model: await _storage.read(key: _modelKey) ?? '',
    apiKey: await _storage.read(key: _apiKey) ?? '',
  );

  @override
  Future<void> save(AiDocumentSettings settings) async {
    await _storage.write(key: _endpointKey, value: settings.endpoint.trim());
    await _storage.write(key: _modelKey, value: settings.model.trim());
    if (settings.apiKey.trim().isEmpty) {
      await _storage.delete(key: _apiKey);
    } else {
      await _storage.write(key: _apiKey, value: settings.apiKey.trim());
    }
  }
}

class AiDocumentService {
  const AiDocumentService();
  static const maxImageBytes = 8 * 1024 * 1024;
  static const _maxErrorBytes = 8 * 1024;
  static const _maxResponseBytes = 256 * 1024;

  static Uri validateEndpoint(String value, {String apiKey = ''}) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        !uri.path.endsWith('/chat/completions') ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const AiDocumentException('请输入有效的 Chat Completions 接口地址。');
    }
    if (uri.scheme == 'http' && !_isPrivateHost(uri.host)) {
      throw const AiDocumentException('HTTP 仅允许内网地址；公网服务请使用 HTTPS。');
    }
    if (uri.scheme == 'http' &&
        apiKey.trim().isNotEmpty &&
        !_isLoopbackHost(uri.host)) {
      throw const AiDocumentException('发送 API Key 必须使用 HTTPS；HTTP 仅允许本机回环地址。');
    }
    return uri;
  }

  static bool _isPrivateHost(String host) {
    if (host == '::1') return true;
    final parts = host.split('.');
    final octets = parts.map(int.tryParse).toList();
    if (octets.length != 4 ||
        octets.any((item) => item == null || item > 255)) {
      return host == 'localhost';
    }
    final first = octets[0]!;
    final second = octets[1]!;
    return first == 10 ||
        first == 127 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }

  static bool _isLoopbackHost(String host) =>
      host == 'localhost' || host == '127.0.0.1' || host == '::1';

  Future<bool> checkOllamaVisionCapability({
    required AiDocumentSettings settings,
  }) async {
    final chatUri = validateEndpoint(settings.endpoint);
    if (!_isPrivateHost(chatUri.host)) {
      throw const AiDocumentException('模型能力检查只支持局域网或本机 Ollama 地址。');
    }
    final model = settings.model.trim();
    if (model.isEmpty) {
      throw const AiDocumentException('请先填写模型名称。');
    }

    final uri = chatUri.replace(path: '/api/show', query: null, fragment: null);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client.postUrl(uri);
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'model': model}));
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final bytes = await _readLimited(
        response,
        64 * 1024,
      ).timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiDocumentException(
          'Ollama 模型信息查询失败（HTTP ${response.statusCode}）；请确认服务地址和模型名。',
        );
      }
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final capabilities = decoded['capabilities'];
      if (capabilities is! List) {
        throw const AiDocumentException('Ollama 未返回模型能力信息，无法确认是否支持图像输入。');
      }
      return capabilities.whereType<String>().contains('vision');
    } on TimeoutException {
      throw const AiDocumentException('查询 Ollama 模型信息超时，请检查局域网连接。');
    } on SocketException {
      throw const AiDocumentException('无法连接 Ollama 模型信息接口，请检查地址和局域网连接。');
    } on FormatException {
      throw const AiDocumentException('Ollama 返回的模型信息格式无效。');
    } finally {
      client.close(force: true);
    }
  }

  Future<String> recognizeImage({
    required AiDocumentSettings settings,
    required List<int> imageBytes,
    required String fileName,
  }) async {
    final uri = validateEndpoint(settings.endpoint, apiKey: settings.apiKey);
    if (settings.model.trim().isEmpty) {
      throw const AiDocumentException('请填写支持图像输入的模型名称。');
    }
    if (imageBytes.isEmpty || imageBytes.length > maxImageBytes) {
      throw const AiDocumentException('图像为空或超过 8 MiB；请先裁剪页面后重试。');
    }
    final extension = fileName.toLowerCase().split('.').last;
    final mimeType = switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(uri);
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      if (settings.apiKey.trim().isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${settings.apiKey.trim()}',
        );
      }
      request.write(
        jsonEncode({
          'model': settings.model.trim(),
          'stream': false,
          'max_tokens': 1600,
          'messages': [
            {
              'role': 'system',
              'content':
                  '你是文档识别助手。忠实提取图片中可辨认的文字，保留标题和列表结构；不确定处标记为[不清晰]，不得猜测缺失内容。最后用简短条目总结文档主题。',
            },
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': '请识别并总结这张扫描页面。只报告图像中实际可见的内容。'},
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:$mimeType;base64,${base64Encode(imageBytes)}',
                  },
                },
              ],
            },
          ],
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 90),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final bytes = await _readLimited(
          response,
          _maxErrorBytes,
        ).timeout(const Duration(seconds: 90));
        final detail = _errorMessage(bytes, settings.apiKey);
        throw AiDocumentException(
          'AI 服务返回 HTTP ${response.statusCode}${detail == null ? '' : '：$detail'}。',
        );
      }
      final bytes = await _readLimited(
        response,
        _maxResponseBytes,
      ).timeout(const Duration(seconds: 90));
      final body = utf8.decode(bytes);
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final choices = decoded['choices'] as List<dynamic>? ?? const [];
      final message = choices.isEmpty
          ? null
          : (choices.first as Map<String, dynamic>)['message'];
      final content = message is Map<String, dynamic>
          ? message['content'] as String?
          : null;
      if (content == null || content.trim().isEmpty) {
        throw const AiDocumentException('AI 服务没有返回识别结果。');
      }
      return content.trim();
    } on TimeoutException {
      throw const AiDocumentException('图像识别超时，请检查模型服务后重试。');
    } on SocketException {
      throw const AiDocumentException('无法连接 AI 服务，请检查地址和局域网连接。');
    } on FormatException {
      throw const AiDocumentException('AI 服务返回的数据格式无效。');
    } finally {
      client.close(force: true);
    }
  }

  Future<List<int>> _readLimited(HttpClientResponse response, int limit) async {
    final builder = BytesBuilder(copy: false);
    var remaining = limit;
    await for (final chunk in response) {
      final count = chunk.length < remaining ? chunk.length : remaining;
      builder.add(chunk.sublist(0, count));
      remaining -= count;
      if (remaining == 0) break;
    }
    return builder.takeBytes();
  }

  String? _errorMessage(List<int> bytes, String apiKey) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      final error = decoded is Map<String, dynamic> ? decoded['error'] : null;
      final value = error is Map<String, dynamic>
          ? error['message']
          : decoded is Map<String, dynamic>
          ? decoded['message']
          : null;
      if (value is! String || value.trim().isEmpty) return null;
      var message = value.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
      if (apiKey.trim().isNotEmpty) {
        message = message.replaceAll(apiKey.trim(), '[已隐藏凭据]');
      }
      if (message.length > 240) message = '${message.substring(0, 240)}…';
      return message;
    } on FormatException {
      return null;
    }
  }
}

class AiDocumentException implements Exception {
  const AiDocumentException(this.message);
  final String message;
  @override
  String toString() => message;
}
