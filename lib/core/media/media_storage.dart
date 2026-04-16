import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'media_cipher.dart';

class MediaStorage {
  static Future<Directory> _baseDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/attachments');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  static Future<String> storeEncryptedBytes({
    required String id,
    required Uint8List bytes,
  }) async {
    final dir = await _baseDir();
    final file = File('${dir.path}/$id.bin');
    final encrypted = MediaCipher.encrypt(bytes);
    await file.writeAsBytes(encrypted, flush: true);
    return file.path;
  }

  static Future<String> storeEncryptedBytesRaw({
    required String id,
    required Uint8List encryptedBytes,
  }) async {
    final dir = await _baseDir();
    final file = File('${dir.path}/$id.bin');
    await file.writeAsBytes(encryptedBytes, flush: true);
    return file.path;
  }

  static Future<Uint8List?> readDecryptedBytes(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final data = await file.readAsBytes();
      return MediaCipher.decrypt(Uint8List.fromList(data));
    } catch (_) {
      return null;
    }
  }

  static Future<String?> materializeDecryptedTempFile({
    required String encryptedPath,
    required String id,
    String? extension,
  }) async {
    try {
      final bytes = await readDecryptedBytes(encryptedPath);
      if (bytes == null) return null;
      final root = await getTemporaryDirectory();
      final dir = Directory('${root.path}/vault-preview');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final normalizedExt = (() {
        final raw = (extension ?? '').trim();
        if (raw.isEmpty) return 'bin';
        return raw.startsWith('.') ? raw.substring(1) : raw;
      })();
      final file = File('${dir.path}/$id.$normalizedExt');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> readVideoThumbnailBytes({
    required String encryptedPath,
    required String id,
    String? extension,
  }) async {
    try {
      final root = await getTemporaryDirectory();
      final dir = Directory('${root.path}/vault-preview-thumbs');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final file = File('${dir.path}/$id.jpg');
      if (file.existsSync()) {
        return await file.readAsBytes();
      }

      final previewPath = await materializeDecryptedTempFile(
        encryptedPath: encryptedPath,
        id: id,
        extension: extension,
      );
      if (previewPath == null) {
        return null;
      }

      final bytes = await VideoThumbnail.thumbnailData(
        video: previewPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 960,
        quality: 76,
      );
      if (bytes == null || bytes.isEmpty) {
        return null;
      }

      await file.writeAsBytes(bytes, flush: true);
      return bytes;
    } catch (_) {
      return null;
    }
  }
}
