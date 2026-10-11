import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter_local_doc_scanner/core/services/ai_document_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('requires HTTPS for public endpoints and limits images to 8 MiB', () {
    expect(
      () => AiDocumentService.validateEndpoint(
        'http://api.example.com/v1/chat/completions',
      ),
      throwsA(isA<AiDocumentException>()),
    );
    expect(
      AiDocumentService.validateEndpoint(
        'http://192.168.1.9:11434/v1/chat/completions',
      ).host,
      '192.168.1.9',
    );
  });

  test(
    'sends the selected image to a multimodal OpenAI-compatible endpoint',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final handler = () async {
        await for (final request in server) {
          final body =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;
          expect(
            request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer image-key',
          );
          expect(body['model'], 'vision-test');
          final messages = body['messages'] as List<dynamic>;
          final content =
              (messages[1] as Map<String, dynamic>)['content'] as List<dynamic>;
          final image =
              (content[1] as Map<String, dynamic>)['image_url']
                  as Map<String, dynamic>;
          expect(image['url'], 'data:image/png;base64,AQID');
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': '识别结果'},
                  },
                ],
              }),
            );
          await request.response.close();
          break;
        }
      }();

      final answer = await const AiDocumentService().recognizeImage(
        settings: AiDocumentSettings(
          endpoint: 'http://127.0.0.1:${server.port}/v1/chat/completions',
          model: 'vision-test',
          apiKey: 'image-key',
        ),
        imageBytes: [1, 2, 3],
        fileName: 'page.png',
      );
      await handler;
      await server.close(force: true);
      expect(answer, '识别结果');
    },
  );

  test('rejects oversized image before making a request', () async {
    expect(
      () => const AiDocumentService().recognizeImage(
        settings: const AiDocumentSettings(model: 'vision-test'),
        imageBytes: List<int>.filled(AiDocumentService.maxImageBytes + 1, 0),
        fileName: 'page.jpg',
      ),
      throwsA(isA<AiDocumentException>()),
    );
  });

  test('shows a sanitized provider error for rate limits', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final handler = () async {
      final request = await server.first;
      request.response
        ..statusCode = HttpStatus.tooManyRequests
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'error': {
              'message': 'quota exhausted with secret-key\nretry later',
            },
          }),
        );
      await request.response.close();
    }();

    final future = const AiDocumentService().recognizeImage(
      settings: AiDocumentSettings(
        endpoint: 'http://127.0.0.1:${server.port}/v1/chat/completions',
        model: 'vision-test',
        apiKey: 'secret-key',
      ),
      imageBytes: [1, 2, 3],
      fileName: 'page.png',
    );
    await expectLater(
      future,
      throwsA(
        isA<AiDocumentException>()
            .having((error) => error.message, 'message', contains('HTTP 429'))
            .having(
              (error) => error.message,
              'message',
              contains('quota exhausted with [已隐藏凭据] retry later'),
            )
            .having(
              (error) => error.message,
              'message',
              isNot(contains('secret-key')),
            ),
      ),
    );
    await handler;
    await server.close(force: true);
  });

  test(
    'does not follow redirects from the configured model endpoint',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final paths = <String>[];
      final requestHandled = Completer<void>();
      final subscription = server.listen((request) async {
        paths.add(request.uri.path);
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '/capture');
        await request.response.close();
        requestHandled.complete();
      });

      await expectLater(
        const AiDocumentService().recognizeImage(
          settings: AiDocumentSettings(
            endpoint: 'http://127.0.0.1:${server.port}/v1/chat/completions',
            model: 'vision-test',
            apiKey: 'secret-key',
          ),
          imageBytes: [1, 2, 3],
          fileName: 'page.png',
        ),
        throwsA(
          isA<AiDocumentException>().having(
            (error) => error.message,
            'message',
            contains('HTTP 302'),
          ),
        ),
      );
      await requestHandled.future;
      expect(paths, ['/v1/chat/completions']);
      await subscription.cancel();
      await server.close(force: true);
    },
  );
}
