Future<String?> copyProfilePhotoToAppStorage(String sourcePath) async {
  final trimmed = sourcePath.trim();
  return trimmed.isEmpty ? null : trimmed;
}
