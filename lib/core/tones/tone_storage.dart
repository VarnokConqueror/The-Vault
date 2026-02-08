import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

class StoredTone {
  final String uri;
  final String name;

  const StoredTone({
    required this.uri,
    required this.name,
  });
}

class ToneStorage {
  // Avoid trying to persist huge audio files as "tones".
  static const int maxToneBytes = 5 * 1024 * 1024;

  static Future<StoredTone?> storePickedTone({
    required String key,
    required PlatformFile file,
  }) async {
    final displayNameRaw = file.name.trim();
    final displayName = displayNameRaw.isEmpty ? 'tone' : displayNameRaw;

    var ext = (file.extension ?? '').trim();
    ext = ext.replaceAll('.', '');
    if (ext.isEmpty) {
      final dot = displayName.lastIndexOf('.');
      if (dot > 0 && dot < displayName.length - 1) {
        ext = displayName.substring(dot + 1).trim();
      }
    }

    final safeKey = key.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final outName = ext.isEmpty ? safeKey : '$safeKey.$ext';

    final support = await getApplicationSupportDirectory();
    final toneDir =
        Directory('${support.path}${Platform.pathSeparator}tones');
    await toneDir.create(recursive: true);
    final outPath = '${toneDir.path}${Platform.pathSeparator}$outName';

    final Uint8List? bytes = file.bytes;
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
      await File(pickedPath).copy(outPath);
      return StoredTone(uri: outPath, name: displayName);
    } catch (_) {
      // Fall back to the original path. It may still be playable.
      return StoredTone(uri: pickedPath, name: displayName);
    }
  }
}

