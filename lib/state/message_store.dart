import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';
import 'identity_store.dart';

class MessageStore {
  static const _prefsKey = 'cc_messages_v1';

  static final ValueNotifier<List<ChatMessage>> messagesNotifier =
      ValueNotifier<List<ChatMessage>>(<ChatMessage>[]);

  static List<ChatMessage> get messages =>
      List.unmodifiable(messagesNotifier.value);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);

    if (raw == null || raw.trim().isEmpty) {
      messagesNotifier.value = <ChatMessage>[];
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        messagesNotifier.value = <ChatMessage>[];
        return;
      }

      final loaded = _parseMessages(decoded);
      if (loaded == null) {
        messagesNotifier.value = <ChatMessage>[];
        return;
      }

      loaded.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      messagesNotifier.value = loaded;
    } catch (_) {
      messagesNotifier.value = <ChatMessage>[];
    }
  }

  static List<ChatMessage> getMessagesForChat(String chatId) {
    final id = chatId.trim();
    if (id.isEmpty) return <ChatMessage>[];

    final filtered = messagesNotifier.value
        .where((m) => m.chatId == id)
        .toList();
    filtered.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return filtered;
  }

  static Future<ChatMessage?> addMessage({
    required String chatId,
    required String senderId,
    required String body,
    String? id,
    String type = ChatMessage.typeText,
    String? stickerPackId,
    String? stickerId,
    String? stickerVariant,
    String? attachmentId,
    String? attachmentName,
    String? attachmentMime,
    int? attachmentSize,
    String? attachmentPath,
    bool? attachmentInline,
    String? voicePath,
    String? voiceMime,
    int? voiceDurationMs,
  }) async {
    final chat = chatId.trim();
    final sender = senderId.trim();
    final text = body.trim();

    final msgType = type.trim().isEmpty ? ChatMessage.typeText : type.trim();
    final isVoice = msgType == ChatMessage.typeVoice;
    final isSticker = msgType == ChatMessage.typeSticker;
    final isAttachment = msgType == ChatMessage.typeAttachment;

    if (chat.isEmpty || sender.isEmpty) return null;
    if (!isVoice && text.isEmpty) return null;
    if (isVoice && (voicePath ?? '').trim().isEmpty) return null;
    if (isSticker &&
        ((stickerPackId ?? '').trim().isEmpty ||
            (stickerId ?? '').trim().isEmpty)) {
      return null;
    }
    if (isAttachment &&
        ((attachmentId ?? '').trim().isEmpty ||
            (attachmentPath ?? '').trim().isEmpty)) {
      return null;
    }

    final messageIdRaw = (id ?? '').trim();
    final messageId = messageIdRaw.isEmpty
        ? '${DateTime.now().millisecondsSinceEpoch}_$chat'
        : messageIdRaw;

    final message = ChatMessage(
      id: messageId,
      chatId: chat,
      senderId: sender,
      type: msgType,
      body: isVoice ? (text.isEmpty ? 'Voice message' : text) : text,
      stickerPackId:
          (stickerPackId ?? '').trim().isEmpty ? null : stickerPackId!.trim(),
      stickerId:
          (stickerId ?? '').trim().isEmpty ? null : stickerId!.trim(),
      stickerVariant: (stickerVariant ?? '').trim().isEmpty
          ? null
          : stickerVariant!.trim(),
      attachmentId:
          (attachmentId ?? '').trim().isEmpty ? null : attachmentId!.trim(),
      attachmentName: (attachmentName ?? '').trim().isEmpty
          ? null
          : attachmentName!.trim(),
      attachmentMime: (attachmentMime ?? '').trim().isEmpty
          ? null
          : attachmentMime!.trim(),
      attachmentSize: attachmentSize,
      attachmentPath: (attachmentPath ?? '').trim().isEmpty
          ? null
          : attachmentPath!.trim(),
      attachmentInline: attachmentInline,
      voicePath: (voicePath ?? '').trim().isEmpty ? null : voicePath!.trim(),
      voiceMime: (voiceMime ?? '').trim().isEmpty ? null : voiceMime!.trim(),
      voiceDurationMs: voiceDurationMs,
      createdAt: DateTime.now(),
    );

    final next = <ChatMessage>[...messagesNotifier.value, message];
    next.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    messagesNotifier.value = next;
    await _save();
    return message;
  }

  static Future<ChatMessage?> addIncomingMessage({
    required String chatId,
    required String senderId,
    required String body,
    required DateTime createdAt,
    String? id,
    String type = ChatMessage.typeText,
    String? stickerPackId,
    String? stickerId,
    String? stickerVariant,
    String? attachmentId,
    String? attachmentName,
    String? attachmentMime,
    int? attachmentSize,
    String? attachmentPath,
    bool? attachmentInline,
    String? voicePath,
    String? voiceMime,
    int? voiceDurationMs,
  }) async {
    final trimmedChat = chatId.trim();
    final trimmedSender = senderId.trim();
    final text = body.trim();

    final msgType = type.trim().isEmpty ? ChatMessage.typeText : type.trim();
    final isVoice = msgType == ChatMessage.typeVoice;
    final isSticker = msgType == ChatMessage.typeSticker;
    final isAttachment = msgType == ChatMessage.typeAttachment;

    if (trimmedChat.isEmpty || trimmedSender.isEmpty) {
      return null;
    }
    if (!isVoice && text.isEmpty) return null;
    if (isVoice && (voicePath ?? '').trim().isEmpty) return null;
    if (isSticker &&
        ((stickerPackId ?? '').trim().isEmpty ||
            (stickerId ?? '').trim().isEmpty)) {
      return null;
    }
    if (isAttachment &&
        ((attachmentId ?? '').trim().isEmpty ||
            (attachmentPath ?? '').trim().isEmpty)) {
      return null;
    }

    final message = ChatMessage(
      id: (id == null || id.trim().isEmpty)
          ? '${createdAt.millisecondsSinceEpoch}_$trimmedChat'
          : id.trim(),
      chatId: trimmedChat,
      senderId: trimmedSender,
      type: msgType,
      body: isVoice ? (text.isEmpty ? 'Voice message' : text) : text,
      stickerPackId:
          (stickerPackId ?? '').trim().isEmpty ? null : stickerPackId!.trim(),
      stickerId:
          (stickerId ?? '').trim().isEmpty ? null : stickerId!.trim(),
      stickerVariant: (stickerVariant ?? '').trim().isEmpty
          ? null
          : stickerVariant!.trim(),
      attachmentId:
          (attachmentId ?? '').trim().isEmpty ? null : attachmentId!.trim(),
      attachmentName: (attachmentName ?? '').trim().isEmpty
          ? null
          : attachmentName!.trim(),
      attachmentMime: (attachmentMime ?? '').trim().isEmpty
          ? null
          : attachmentMime!.trim(),
      attachmentSize: attachmentSize,
      attachmentPath: (attachmentPath ?? '').trim().isEmpty
          ? null
          : attachmentPath!.trim(),
      attachmentInline: attachmentInline,
      voicePath: (voicePath ?? '').trim().isEmpty ? null : voicePath!.trim(),
      voiceMime: (voiceMime ?? '').trim().isEmpty ? null : voiceMime!.trim(),
      voiceDurationMs: voiceDurationMs,
      createdAt: createdAt,
    );

    final next = <ChatMessage>[...messagesNotifier.value, message];
    next.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    messagesNotifier.value = next;
    await _save();
    return message;
  }

  static String exportMessagesJson() {
    final payload = messagesNotifier.value.map((m) => m.toJson()).toList();
    return jsonEncode(payload);
  }

  static Future<bool> importMessagesJson(String rawJson) async {
    final trimmed = rawJson.trim();
    if (trimmed.isEmpty) return false;

    if (trimmed.length > 200000) return false;

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! List) return false;

      final loaded = _parseMessages(decoded);
      if (loaded == null) return false;

      loaded.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      messagesNotifier.value = loaded;
      await _save();
      return true;
    } catch (_) {
      return false;
    }
  }

  static List<ChatMessage>? _parseMessages(List<dynamic> decoded) {
    final loaded = <ChatMessage>[];

    for (final item in decoded) {
      if (item is! Map) return null;
      final message = ChatMessage.fromJson(Map<String, dynamic>.from(item));
      if (message.id.trim().isEmpty ||
          message.chatId.trim().isEmpty ||
          message.senderId.trim().isEmpty) {
        return null;
      }
      loaded.add(message);
    }

    return loaded;
  }

  static bool _isSelfSender(String senderId) {
    final s = senderId.trim();
    if (s.isEmpty) return false;
    if (s == 'local') return true;
    final myId = IdentityStore.publicId.trim();
    return myId.isNotEmpty && s == myId;
  }

  static Future<bool> applyReceipt({
    required String chatId,
    required String messageId,
    required String kind,
    required DateTime receiptAt,
  }) async {
    final chat = chatId.trim();
    final id = messageId.trim();
    final normalizedKind = kind.trim().toLowerCase();
    if (chat.isEmpty || id.isEmpty) return false;
    if (normalizedKind != 'delivered' && normalizedKind != 'read') return false;

    final current = messagesNotifier.value;
    final idx = current.indexWhere(
      (m) => m.chatId == chat && m.id == id && _isSelfSender(m.senderId),
    );
    if (idx < 0) return false;

    final existing = current[idx];
    final nextDelivered = existing.deliveredAt ?? receiptAt;
    final nextRead = normalizedKind == 'read' ? (existing.readAt ?? receiptAt) : existing.readAt;

    if (existing.deliveredAt == nextDelivered && existing.readAt == nextRead) {
      return true;
    }

    final updated = ChatMessage(
      id: existing.id,
      chatId: existing.chatId,
      senderId: existing.senderId,
      type: existing.type,
      body: existing.body,
      stickerPackId: existing.stickerPackId,
      stickerId: existing.stickerId,
      stickerVariant: existing.stickerVariant,
      attachmentId: existing.attachmentId,
      attachmentName: existing.attachmentName,
      attachmentMime: existing.attachmentMime,
      attachmentSize: existing.attachmentSize,
      attachmentPath: existing.attachmentPath,
      attachmentInline: existing.attachmentInline,
      voicePath: existing.voicePath,
      voiceMime: existing.voiceMime,
      voiceDurationMs: existing.voiceDurationMs,
      deliveredAt: nextDelivered,
      readAt: nextRead,
      createdAt: existing.createdAt,
    );

    final next = <ChatMessage>[...current];
    next[idx] = updated;
    next.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    messagesNotifier.value = next;
    await _save();
    return true;
  }

  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = messagesNotifier.value.map((m) => m.toJson()).toList();
    await prefs.setString(_prefsKey, jsonEncode(payload));
  }
}
