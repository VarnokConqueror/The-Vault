import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

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
}
