import 'dart:io';

import 'package:path_provider/path_provider.dart';

class VoiceNoteStorage {
  static Future<Directory> _baseDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}voice_notes');
    await dir.create(recursive: true);
    return dir;
  }

  static String _extForMime(String? mime) {
    final m = (mime ?? '').trim().toLowerCase();
    if (m.contains('3gp') || m.contains('3gpp')) return '3gp';
    if (m.contains('amr')) return 'amr';
    if (m.contains('ogg')) return 'ogg';
    if (m.contains('opus')) return 'opus';
    if (m.contains('mp4') || m.contains('m4a') || m.contains('aac')) return 'm4a';
    if (m.contains('wav')) return 'wav';
    return 'bin';
  }

  static String _safeFileStem(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return 'voice';
    return cleaned.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }

  static Future<String> pathForId({
    required String id,
    String? mime,
  }) async {
    final dir = await _baseDir();
    final stem = _safeFileStem(id);
    final ext = _extForMime(mime);
    return '${dir.path}${Platform.pathSeparator}$stem.$ext';
  }

  static Future<String?> storeBytes({
    required String id,
    required List<int> bytes,
    String? mime,
  }) async {
    if (bytes.isEmpty) return null;
    final path = await pathForId(id: id, mime: mime);
    try {
      final f = File(path);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes, flush: true);
      return f.path;
    } catch (_) {
      return null;
    }
  }
}
