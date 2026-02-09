import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class StoredTone {
  final String uri;
  final String name;

  const StoredTone({required this.uri, required this.name});
}

class ToneStorage {
  // Avoid trying to persist huge audio files as "tones".
  static const int maxToneBytes = 5 * 1024 * 1024;

  static const MethodChannel _toneChannel = MethodChannel(
    'com.example.conquerors_court/tones',
  );

  static String _guessMimeType(String fileName) {
    final lower = fileName.trim().toLowerCase();
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.aac')) return 'audio/aac';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    if (lower.endsWith('.flac')) return 'audio/flac';
    return 'audio/*';
  }

  static Future<String?> _importAndroidNotificationTone({
    required String key,
    required String displayName,
    required Uint8List bytes,
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      final uri = await _toneChannel.invokeMethod<String>(
        'importNotificationTone',
        <String, dynamic>{
          'key': key,
          'display_name': displayName,
          'displayName': displayName,
          'bytes': bytes,
          'mime': _guessMimeType(displayName),
        },
      );
      final cleaned = (uri ?? '').trim();
      return cleaned.isEmpty ? null : cleaned;
    } catch (_) {
      return null;
    }
  }

  static Future<Directory> _toneBaseDir() async {
    // Android notification channels can only play sounds that the OS can read.
    // Prefer an external app directory on Android so file:// URIs are readable.
    if (Platform.isAndroid) {
      try {
        final dirs = await getExternalStorageDirectories(
          type: StorageDirectory.notifications,
        );
        if (dirs != null && dirs.isNotEmpty) return dirs.first;
      } catch (_) {}

      try {
        final dir = await getExternalStorageDirectory();
        if (dir != null) return dir;
      } catch (_) {}
    }

    return getApplicationSupportDirectory();
  }

  static String _deriveExt({
    required String name,
    required String fallbackPath,
  }) {
    var ext = '';
    final dotName = name.lastIndexOf('.');
    if (dotName > 0 && dotName < name.length - 1) {
      ext = name.substring(dotName + 1).trim();
    }
    if (ext.isEmpty) {
      final cleanedPath = fallbackPath.split('?').first.trim();
      final dotPath = cleanedPath.lastIndexOf('.');
      if (dotPath > 0 && dotPath < cleanedPath.length - 1) {
        ext = cleanedPath.substring(dotPath + 1).trim();
      }
    }
    ext = ext.replaceAll('.', '');
    return ext;
  }

  static Future<String> _toneOutputPath({
    required String key,
    required String fileName,
    required String fallbackPath,
  }) async {
    final safeKey = key.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final ext = _deriveExt(name: fileName, fallbackPath: fallbackPath);
    final outName = ext.isEmpty ? safeKey : '$safeKey.$ext';

    final base = await _toneBaseDir();
    final toneDir = Directory('${base.path}${Platform.pathSeparator}tones');
    await toneDir.create(recursive: true);
    return '${toneDir.path}${Platform.pathSeparator}$outName';
  }

  static Future<StoredTone?> storePickedTone({
    required String key,
    required PlatformFile file,
  }) async {
    final displayNameRaw = file.name.trim();
    final displayName = displayNameRaw.isEmpty ? 'tone' : displayNameRaw;

    Uint8List? bytes = file.bytes;
    if (bytes == null) {
      final pickedPath = (file.path ?? '').trim();
      if (pickedPath.isNotEmpty) {
        try {
          final src = File(pickedPath);
          final size = await src.length();
          if (size <= maxToneBytes) {
            bytes = await src.readAsBytes();
          }
        } catch (_) {}
      }
    }

    if (Platform.isAndroid && bytes != null) {
      if (bytes.length > maxToneBytes) return null;
      final imported = await _importAndroidNotificationTone(
        key: key,
        displayName: displayName,
        bytes: bytes,
      );
      if (imported != null) {
        // Use the MediaStore content:// URI so Android channels can actually
        // play the sound, and so the OS can access it while locked.
        return StoredTone(uri: imported, name: displayName);
      }
    }

    final outPath = await _toneOutputPath(
      key: key,
      fileName: displayName,
      fallbackPath: (file.path ?? '').trim(),
    );

    if (bytes != null) {
      if (bytes.length > maxToneBytes) {
        return null;
      }
      await File(outPath).writeAsBytes(bytes, flush: true);
      return StoredTone(uri: outPath, name: displayName);
    }

    final pickedPath = (file.path ?? '').trim();
    if (pickedPath.isEmpty) return null;
    try {
      final src = File(pickedPath);
      final size = await src.length();
      if (size > maxToneBytes) return null;
      await src.copy(outPath);
      return StoredTone(uri: outPath, name: displayName);
    } catch (_) {
      // Fall back to the original path. It may still be playable.
      return StoredTone(uri: pickedPath, name: displayName);
    }
  }

  static bool _isFileLikeUri(String uri) {
    final u = uri.trim();
    if (u.isEmpty) return false;
    final parsed = Uri.tryParse(u);
    if (parsed == null) return true;
    if (parsed.scheme.isEmpty) return true;
    return parsed.scheme == 'file';
  }

  static Future<String?> ensureExternallyAccessibleToneUri({
    required String key,
    required String uri,
  }) async {
    final raw = uri.trim();
    if (raw.isEmpty) return null;

    // Content/resource URIs are already readable by the OS.
    final parsed = Uri.tryParse(raw);
    if (parsed != null && parsed.scheme.isNotEmpty && parsed.scheme != 'file') {
      return raw;
    }

    if (!_isFileLikeUri(raw)) return null;

    String path = raw;
    if (parsed != null && parsed.scheme == 'file') {
      try {
        path = parsed.toFilePath();
      } catch (_) {
        path = raw.replaceFirst('file://', '');
      }
    }

    final src = File(path);
    try {
      if (!await src.exists()) return null;
      final size = await src.length();
      if (size > maxToneBytes) return null;
    } catch (_) {
      return null;
    }

    // If the tone is already in an external dir, keep it.
    if (Platform.isAndroid) {
      final p = path.replaceAll('\\', '/');
      if (p.startsWith('/storage/') &&
          !p.startsWith('/storage/emulated/0/Android/data/')) {
        return path;
      }
    }

    // Copy into our external app directory so we have a stable path.
    try {
      final outPath = await _toneOutputPath(
        key: key,
        fileName: path.split(Platform.pathSeparator).last,
        fallbackPath: path,
      );
      if (outPath == path) return outPath;
      await src.copy(outPath);
      return outPath;
    } catch (_) {
      return path;
    }
  }
}
