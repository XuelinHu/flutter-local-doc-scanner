import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';

class LocalStorageService {
  LocalStorageService({
    Future<Directory> Function()? cacheDirectoryProvider,
    Future<Directory> Function()? documentsDirectoryProvider,
  }) : _cacheDirectoryProvider = cacheDirectoryProvider,
       _documentsDirectoryProvider = documentsDirectoryProvider;

  static final instance = LocalStorageService();
  static const _uuid = Uuid();

  final Future<Directory> Function()? _cacheDirectoryProvider;
  final Future<Directory> Function()? _documentsDirectoryProvider;

  Future<Directory> get _cacheDir =>
      _cacheDirectoryProvider?.call() ?? getTemporaryDirectory();

  Future<Directory> get _docsDir =>
      _documentsDirectoryProvider?.call() ?? getApplicationDocumentsDirectory();

  Future<String> getCacheDirectoryPath() async {
    final directory = await _cacheDir;
    return directory.path;
  }

  Future<String> importImageToApp(String sourcePath) async {
    final bytes = await File(sourcePath).readAsBytes();
    final extension = path.extension(sourcePath).isEmpty
        ? '.jpg'
        : path.extension(sourcePath);
    return writeTempBytes(
      bytes: bytes,
      prefix: AppConstants.outputImagePrefix,
      extension: extension,
    );
  }

  Future<String> writeTempBytes({
    required Uint8List bytes,
    required String prefix,
    required String extension,
  }) async {
    final directory = await _cacheDir;
    final file = File(
      path.join(directory.path, '$prefix${_uuid.v4()}$extension'),
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> deleteTempImage(String filePath) async {
    final directory = await _cacheDir;
    final absoluteDirectory = path.normalize(path.absolute(directory.path));
    final absoluteFile = path.normalize(path.absolute(filePath));
    if (path.dirname(absoluteFile) != absoluteDirectory ||
        !path
            .basename(absoluteFile)
            .startsWith(AppConstants.outputImagePrefix)) {
      return;
    }

    final file = File(absoluteFile);
    if (await file.exists()) await file.delete();
  }

  Future<void> cleanupStaleTempImages({
    DateTime? now,
    Duration maxAge = const Duration(hours: 24),
  }) async {
    final directory = await _cacheDir;
    if (!await directory.exists()) return;
    final cutoff = (now ?? DateTime.now()).subtract(maxAge);
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File ||
          !path
              .basename(entity.path)
              .startsWith(AppConstants.outputImagePrefix)) {
        continue;
      }
      try {
        if ((await entity.lastModified()).isBefore(cutoff)) {
          await entity.delete();
        }
      } on FileSystemException {
        // A cache entry may disappear between listing and cleanup.
      }
    }
  }

  Future<String> createOutputPdfPath() async {
    final directory = await _docsDir;
    return path.join(
      directory.path,
      '${AppConstants.outputPdfPrefix}${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  Future<String> createNamedPdfPath(String rawName) async {
    final directory = await _docsDir;
    final safeName = _sanitizeFileName(rawName);
    var candidate = path.join(directory.path, '$safeName.pdf');
    var suffix = 2;
    while (await File(candidate).exists()) {
      candidate = path.join(directory.path, '${safeName}_$suffix.pdf');
      suffix += 1;
    }
    return candidate;
  }

  Future<File> getPdfLibraryFile() async {
    final directory = await _docsDir;
    return File(path.join(directory.path, AppConstants.pdfLibraryFileName));
  }

  String sanitizeName(String rawName) => _sanitizeFileName(rawName);

  String _sanitizeFileName(String rawName) {
    final cleaned = rawName
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) {
      return '${AppConstants.outputPdfPrefix}${DateTime.now().millisecondsSinceEpoch}';
    }
    return cleaned;
  }
}
