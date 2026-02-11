import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class AttachmentAssembler {
  static Future<Directory> _tempDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/attachments/tmp');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  static Future<void> storeChunk({
    required String attachmentId,
    required int index,
    required Uint8List bytes,
  }) async {
    final dir = await _tempDir();
    final file = File('${dir.path}/$attachmentId.$index.part');
    await file.writeAsBytes(bytes, flush: true);
  }

  static Future<bool> hasAllChunks({
    required String attachmentId,
    required int totalChunks,
  }) async {
    final dir = await _tempDir();
    for (var i = 0; i < totalChunks; i++) {
      final file = File('${dir.path}/$attachmentId.$i.part');
      if (!file.existsSync()) return false;
    }
    return true;
  }

  static Future<Uint8List?> assemble({
    required String attachmentId,
    required int totalChunks,
  }) async {
    if (!await hasAllChunks(
      attachmentId: attachmentId,
      totalChunks: totalChunks,
    )) {
      return null;
    }
    final dir = await _tempDir();
    final buffer = BytesBuilder();
    for (var i = 0; i < totalChunks; i++) {
      final file = File('${dir.path}/$attachmentId.$i.part');
      final bytes = await file.readAsBytes();
      buffer.add(bytes);
    }
    return buffer.takeBytes();
  }

  static Future<void> cleanup({
    required String attachmentId,
    required int totalChunks,
  }) async {
    final dir = await _tempDir();
    for (var i = 0; i < totalChunks; i++) {
      final file = File('${dir.path}/$attachmentId.$i.part');
      if (file.existsSync()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
  }
}

