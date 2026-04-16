import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String?> copyProfilePhotoToAppStorage(String sourcePath) async {
  final trimmed = sourcePath.trim();
  if (trimmed.isEmpty) return null;
  final source = File(trimmed);
  if (!await source.exists()) return null;

  final root = await getApplicationDocumentsDirectory();
  final profileDir = Directory('${root.path}/profile');
  await profileDir.create(recursive: true);

  final extension = _extensionFor(trimmed);
  final target = File('${profileDir.path}/avatar$extension');
  await source.copy(target.path);
  return target.path;
}

String _extensionFor(String path) {
  final cleaned = path.split('?').first;
  final index = cleaned.lastIndexOf('.');
  if (index < 0 || index == cleaned.length - 1) {
    return '.jpg';
  }
  final ext = cleaned.substring(index).toLowerCase();
  if (ext.length > 6) return '.jpg';
  return ext;
}
