import 'dart:io';

import 'package:flutter_local_doc_scanner/core/services/local_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory cacheDirectory;
  late LocalStorageService storage;

  setUp(() async {
    cacheDirectory = await Directory.systemTemp.createTemp('scanner-cache-');
    storage = LocalStorageService(
      cacheDirectoryProvider: () async => cacheDirectory,
    );
  });

  tearDown(() async {
    await cacheDirectory.delete(recursive: true);
  });

  test(
    'deletes only app-owned image files directly inside the cache directory',
    () async {
      final image = File('${cacheDirectory.path}/scan_page_draft.jpg');
      final unrelated = File('${cacheDirectory.path}/other-cache.bin');
      final nestedDirectory = await Directory(
        '${cacheDirectory.path}/nested',
      ).create();
      final outside = File('${nestedDirectory.path}/scan_page_outside.jpg');
      await image.writeAsBytes([1]);
      await unrelated.writeAsBytes([2]);
      await outside.writeAsBytes([3]);

      await storage.deleteTempImage(image.path);
      await storage.deleteTempImage(unrelated.path);
      await storage.deleteTempImage(outside.path);

      expect(await image.exists(), isFalse);
      expect(await unrelated.exists(), isTrue);
      expect(await outside.exists(), isTrue);
    },
  );

  test(
    'startup cleanup removes only scan images older than the retention window',
    () async {
      final now = DateTime.utc(2026, 10, 12);
      final stale = File('${cacheDirectory.path}/scan_page_stale.jpg');
      final fresh = File('${cacheDirectory.path}/scan_page_fresh.jpg');
      final unrelated = File('${cacheDirectory.path}/scan_document.pdf');
      await stale.writeAsBytes([1]);
      await fresh.writeAsBytes([2]);
      await unrelated.writeAsBytes([3]);
      await stale.setLastModified(now.subtract(const Duration(hours: 25)));
      await fresh.setLastModified(now.subtract(const Duration(hours: 1)));

      await storage.cleanupStaleTempImages(now: now);

      expect(await stale.exists(), isFalse);
      expect(await fresh.exists(), isTrue);
      expect(await unrelated.exists(), isTrue);
    },
  );
}
