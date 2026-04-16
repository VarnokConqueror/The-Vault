import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../models/chat_message.dart';
import '../../state/message_store.dart';
import '../relay/relay_client.dart';
import 'attachment_assembler.dart';
import 'media_storage.dart';

enum IncomingAttachmentIngestStatus {
  completed,
  storedPartial,
  invalidPermanent,
  retryableFailure,
}

class IncomingAttachmentIngestResult {
  const IncomingAttachmentIngestResult._({required this.status, this.message});

  final IncomingAttachmentIngestStatus status;
  final ChatMessage? message;

  bool get shouldAck =>
      status != IncomingAttachmentIngestStatus.retryableFailure;

  static IncomingAttachmentIngestResult completed(ChatMessage message) =>
      IncomingAttachmentIngestResult._(
        status: IncomingAttachmentIngestStatus.completed,
        message: message,
      );

  static const IncomingAttachmentIngestResult storedPartial =
      IncomingAttachmentIngestResult._(
        status: IncomingAttachmentIngestStatus.storedPartial,
      );

  static const IncomingAttachmentIngestResult invalidPermanent =
      IncomingAttachmentIngestResult._(
        status: IncomingAttachmentIngestStatus.invalidPermanent,
      );

  static const IncomingAttachmentIngestResult retryableFailure =
      IncomingAttachmentIngestResult._(
        status: IncomingAttachmentIngestStatus.retryableFailure,
      );
}

class IncomingAttachmentIngest {
  static const int _maxRetryableFailures = 3;

  static Future<IncomingAttachmentIngestResult> ingestChunk(
    RelayMessage relayMessage, {
    required String resolvedChatId,
  }) async {
    final attachmentId = (relayMessage.attachmentId ?? '').trim();
    final chunkB64 = (relayMessage.attachmentChunkB64 ?? '').trim();
    final chunkIndex = relayMessage.attachmentChunkIndex ?? -1;
    final chunkCount = relayMessage.attachmentChunkCount ?? -1;
    if (attachmentId.isEmpty ||
        chunkB64.isEmpty ||
        chunkIndex < 0 ||
        chunkCount <= 0) {
      return IncomingAttachmentIngestResult.invalidPermanent;
    }

    Uint8List chunkBytes;
    try {
      chunkBytes = base64Decode(chunkB64);
    } catch (_) {
      return IncomingAttachmentIngestResult.invalidPermanent;
    }

    try {
      await AttachmentAssembler.storeChunk(
        attachmentId: attachmentId,
        index: chunkIndex,
        bytes: chunkBytes,
      );
    } catch (_) {
      return IncomingAttachmentIngestResult.retryableFailure;
    }

    return _tryAssembleIncomingAttachment(
      attachmentId,
      resolvedChatId: resolvedChatId,
    );
  }

  static Future<IncomingAttachmentIngestResult> ingestManifest(
    RelayMessage relayMessage, {
    required String resolvedChatId,
  }) async {
    final attachmentId = (relayMessage.attachmentId ?? '').trim();
    if (attachmentId.isEmpty) {
      return IncomingAttachmentIngestResult.invalidPermanent;
    }

    try {
      await AttachmentAssembler.storeManifest(
        attachmentId: attachmentId,
        manifest: _attachmentManifestData(relayMessage),
      );
    } catch (_) {
      return IncomingAttachmentIngestResult.retryableFailure;
    }

    return _tryAssembleIncomingAttachment(
      attachmentId,
      resolvedChatId: resolvedChatId,
    );
  }

  static Map<String, dynamic> _attachmentManifestData(
    RelayMessage relayMessage,
  ) {
    return <String, dynamic>{
      'messageId': relayMessage.id,
      'senderId': relayMessage.senderId,
      'body': relayMessage.body,
      'createdAt': relayMessage.createdAt.toIso8601String(),
      'attachmentName': relayMessage.attachmentName,
      'attachmentMime': relayMessage.attachmentMime,
      'attachmentSize': relayMessage.attachmentSize,
      'attachmentHash': relayMessage.attachmentHash,
      'attachmentChunkCount': relayMessage.attachmentChunkCount,
      'attachmentInline': relayMessage.attachmentInline,
      'replyToMessageId': relayMessage.replyToMessageId,
      'replyToSenderId': relayMessage.replyToSenderId,
      'replyToType': relayMessage.replyToType,
      'replyToPreview': relayMessage.replyToPreview,
    };
  }

  static MessageReplyPreview? _replyPreviewFromManifestData(
    Map<String, dynamic> data,
  ) {
    final messageId = (data['replyToMessageId'] ?? '').toString().trim();
    final senderId = (data['replyToSenderId'] ?? '').toString().trim();
    if (messageId.isEmpty || senderId.isEmpty) {
      return null;
    }
    final replyType = (data['replyToType'] ?? '').toString().trim();
    return MessageReplyPreview(
      messageId: messageId,
      senderId: senderId,
      type: replyType.isEmpty ? ChatMessage.typeText : replyType,
      previewText: (data['replyToPreview'] ?? '').toString(),
    );
  }

  static int _manifestInt(dynamic raw) {
    if (raw is int) return raw;
    if (raw is double) return raw.toInt();
    if (raw is String) {
      return int.tryParse(raw.trim()) ?? 0;
    }
    return 0;
  }

  static Future<IncomingAttachmentIngestResult> _retryableFailure(
    String attachmentId, {
    int? totalChunks,
  }) async {
    final failures = await AttachmentAssembler.recordFailure(
      attachmentId: attachmentId,
    );
    if (failures < _maxRetryableFailures) {
      return IncomingAttachmentIngestResult.retryableFailure;
    }
    if (totalChunks != null && totalChunks > 0) {
      await AttachmentAssembler.cleanup(
        attachmentId: attachmentId,
        totalChunks: totalChunks,
      );
    }
    return IncomingAttachmentIngestResult.invalidPermanent;
  }

  static Future<IncomingAttachmentIngestResult> _tryAssembleIncomingAttachment(
    String attachmentId, {
    required String resolvedChatId,
  }) async {
    final manifest = await AttachmentAssembler.readManifest(
      attachmentId: attachmentId,
    );
    if (manifest == null) {
      return IncomingAttachmentIngestResult.storedPartial;
    }

    final chunkCount = _manifestInt(manifest['attachmentChunkCount']);
    if (chunkCount <= 0) {
      await AttachmentAssembler.cleanup(
        attachmentId: attachmentId,
        totalChunks: 0,
      );
      return IncomingAttachmentIngestResult.invalidPermanent;
    }

    final ready = await AttachmentAssembler.hasAllChunks(
      attachmentId: attachmentId,
      totalChunks: chunkCount,
    );
    if (!ready) {
      return IncomingAttachmentIngestResult.storedPartial;
    }

    final assembled = await AttachmentAssembler.assemble(
      attachmentId: attachmentId,
      totalChunks: chunkCount,
    );
    if (assembled == null || assembled.isEmpty) {
      return _retryableFailure(attachmentId, totalChunks: chunkCount);
    }

    final expectedHash = (manifest['attachmentHash'] ?? '').toString().trim();
    if (expectedHash.isNotEmpty) {
      final actualHash = sha256.convert(assembled).toString();
      if (actualHash != expectedHash) {
        return _retryableFailure(attachmentId, totalChunks: chunkCount);
      }
    }

    String path;
    try {
      path = await MediaStorage.storeEncryptedBytesRaw(
        id: attachmentId,
        encryptedBytes: assembled,
      );
    } catch (_) {
      return _retryableFailure(attachmentId, totalChunks: chunkCount);
    }

    final message = await MessageStore.addIncomingMessage(
      chatId: resolvedChatId,
      senderId: (manifest['senderId'] ?? '').toString().trim(),
      body: (() {
        final value = (manifest['body'] ?? '').toString();
        return value.trim().isEmpty ? 'Attachment' : value;
      })(),
      createdAt:
          DateTime.tryParse((manifest['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      id: (manifest['messageId'] ?? '').toString().trim(),
      type: ChatMessage.typeAttachment,
      attachmentId: attachmentId,
      attachmentName: (manifest['attachmentName'] ?? '').toString(),
      attachmentMime: (manifest['attachmentMime'] ?? '').toString(),
      attachmentSize: _manifestInt(manifest['attachmentSize']),
      attachmentPath: path,
      attachmentInline: manifest['attachmentInline'] is bool
          ? manifest['attachmentInline'] as bool
          : true,
      replyTo: _replyPreviewFromManifestData(manifest),
    );
    if (message == null) {
      return _retryableFailure(attachmentId, totalChunks: chunkCount);
    }

    await AttachmentAssembler.cleanup(
      attachmentId: attachmentId,
      totalChunks: chunkCount,
    );
    return IncomingAttachmentIngestResult.completed(message);
  }
}
