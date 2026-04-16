import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class AttachmentAssemblyState {
  const AttachmentAssemblyState({
    required this.attachmentId,
    required this.chunkIndexes,
    required this.manifestPresent,
    required this.updatedAt,
    required this.failureCount,
  });

  final String attachmentId;
  final Set<int> chunkIndexes;
  final bool manifestPresent;
  final DateTime updatedAt;
  final int failureCount;

  int get receivedChunkCount => chunkIndexes.length;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'attachmentId': attachmentId,
    'chunkIndexes': chunkIndexes.toList()..sort(),
    'manifestPresent': manifestPresent,
    'updatedAt': updatedAt.toIso8601String(),
    'failureCount': failureCount,
  };

  AttachmentAssemblyState copyWith({
    Set<int>? chunkIndexes,
    bool? manifestPresent,
    DateTime? updatedAt,
    int? failureCount,
  }) {
    return AttachmentAssemblyState(
      attachmentId: attachmentId,
      chunkIndexes: chunkIndexes ?? this.chunkIndexes,
      manifestPresent: manifestPresent ?? this.manifestPresent,
      updatedAt: updatedAt ?? this.updatedAt,
      failureCount: failureCount ?? this.failureCount,
    );
  }

  static AttachmentAssemblyState initial(String attachmentId) =>
      AttachmentAssemblyState(
        attachmentId: attachmentId,
        chunkIndexes: <int>{},
        manifestPresent: false,
        updatedAt: DateTime.now().toUtc(),
        failureCount: 0,
      );

  static AttachmentAssemblyState? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final attachmentId = (json['attachmentId'] ?? '').toString().trim();
    if (attachmentId.isEmpty) return null;
    final rawChunkIndexes = json['chunkIndexes'];
    final chunkIndexes = <int>{};
    if (rawChunkIndexes is List) {
      for (final item in rawChunkIndexes) {
        if (item is int) {
          chunkIndexes.add(item);
          continue;
        }
        if (item is String) {
          final parsed = int.tryParse(item.trim());
          if (parsed != null) {
            chunkIndexes.add(parsed);
          }
        }
      }
    }
    final manifestPresent = json['manifestPresent'] == true;
    final updatedAt =
        DateTime.tryParse((json['updatedAt'] ?? '').toString()) ??
        DateTime.now().toUtc();
    final failureCount = switch (json['failureCount']) {
      final int value => value,
      final double value => value.toInt(),
      final String value => int.tryParse(value.trim()) ?? 0,
      _ => 0,
    };
    return AttachmentAssemblyState(
      attachmentId: attachmentId,
      chunkIndexes: chunkIndexes,
      manifestPresent: manifestPresent,
      updatedAt: updatedAt.toUtc(),
      failureCount: failureCount < 0 ? 0 : failureCount,
    );
  }
}

class AttachmentAssembler {
  static Future<Directory> _tempDir() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/attachments/tmp');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  static Future<File> _stateFile(String attachmentId) async {
    final dir = await _tempDir();
    return File('${dir.path}/$attachmentId.state.json');
  }

  static Future<AttachmentAssemblyState> _loadState(String attachmentId) async {
    final file = await _stateFile(attachmentId);
    if (!file.existsSync()) {
      return AttachmentAssemblyState.initial(attachmentId);
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      return AttachmentAssemblyState.fromJson(decoded) ??
          AttachmentAssemblyState.initial(attachmentId);
    } catch (_) {
      return AttachmentAssemblyState.initial(attachmentId);
    }
  }

  static Future<void> _saveState(AttachmentAssemblyState state) async {
    final file = await _stateFile(state.attachmentId);
    await file.writeAsString(jsonEncode(state.toJson()), flush: true);
  }

  static Future<AttachmentAssemblyState> state({
    required String attachmentId,
  }) async {
    return _loadState(attachmentId);
  }

  static Future<void> storeChunk({
    required String attachmentId,
    required int index,
    required Uint8List bytes,
  }) async {
    final dir = await _tempDir();
    final file = File('${dir.path}/$attachmentId.$index.part');
    await file.writeAsBytes(bytes, flush: true);
    final current = await _loadState(attachmentId);
    final nextChunkIndexes = <int>{...current.chunkIndexes, index};
    await _saveState(
      current.copyWith(
        chunkIndexes: nextChunkIndexes,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  static Future<void> storeManifest({
    required String attachmentId,
    required Map<String, dynamic> manifest,
  }) async {
    final dir = await _tempDir();
    final file = File('${dir.path}/$attachmentId.manifest.json');
    await file.writeAsString(jsonEncode(manifest), flush: true);
    final current = await _loadState(attachmentId);
    await _saveState(
      current.copyWith(
        manifestPresent: true,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  static Future<Map<String, dynamic>?> readManifest({
    required String attachmentId,
  }) async {
    final dir = await _tempDir();
    final file = File('${dir.path}/$attachmentId.manifest.json');
    if (!file.existsSync()) return null;
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  static Future<int> recordFailure({required String attachmentId}) async {
    final current = await _loadState(attachmentId);
    final next = current.copyWith(
      failureCount: current.failureCount + 1,
      updatedAt: DateTime.now().toUtc(),
    );
    await _saveState(next);
    return next.failureCount;
  }

  static Future<void> clearFailures({required String attachmentId}) async {
    final current = await _loadState(attachmentId);
    if (current.failureCount == 0) return;
    await _saveState(
      current.copyWith(failureCount: 0, updatedAt: DateTime.now().toUtc()),
    );
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
    final manifestFile = File('${dir.path}/$attachmentId.manifest.json');
    if (manifestFile.existsSync()) {
      try {
        await manifestFile.delete();
      } catch (_) {}
    }
    final stateFile = await _stateFile(attachmentId);
    if (stateFile.existsSync()) {
      try {
        await stateFile.delete();
      } catch (_) {}
    }
  }
}
