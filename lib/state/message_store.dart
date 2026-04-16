import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';
import 'identity_store.dart';

class MessageStore {
  static const _prefsKey = 'cc_messages_v1';
  static const _pendingReceiptsPrefsKey = 'cc_message_receipts_v1';

  static final ValueNotifier<List<ChatMessage>> messagesNotifier =
      ValueNotifier<List<ChatMessage>>(<ChatMessage>[]);
  static final Map<String, _PendingReceipt> _pendingReceipts =
      <String, _PendingReceipt>{};

  static List<ChatMessage> get messages =>
      List.unmodifiable(messagesNotifier.value);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    List<ChatMessage> loaded = <ChatMessage>[];

    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          loaded = _parseMessages(decoded) ?? <ChatMessage>[];
        }
      } catch (_) {}
    }

    loaded.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    messagesNotifier.value = loaded;
    _loadPendingReceipts(prefs.getString(_pendingReceiptsPrefsKey));
    if (_applyPendingReceiptsToCurrentMessages()) {
      await _save();
    }
    await _savePendingReceipts();
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

  static ChatMessage? getMessage(String chatId, String messageId) {
    final chat = chatId.trim();
    final id = messageId.trim();
    if (chat.isEmpty || id.isEmpty) return null;
    for (final message in messagesNotifier.value) {
      if (message.chatId == chat && message.id == id) {
        return message;
      }
    }
    return null;
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
    MessageReplyPreview? replyTo,
    List<MessageReaction> reactions = const <MessageReaction>[],
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

    final message = _applyPendingReceiptsToMessage(
      ChatMessage(
        id: messageId,
        chatId: chat,
        senderId: sender,
        type: msgType,
        body: isVoice ? (text.isEmpty ? 'Voice message' : text) : text,
        stickerPackId: (stickerPackId ?? '').trim().isEmpty
            ? null
            : stickerPackId!.trim(),
        stickerId: (stickerId ?? '').trim().isEmpty ? null : stickerId!.trim(),
        stickerVariant: (stickerVariant ?? '').trim().isEmpty
            ? null
            : stickerVariant!.trim(),
        attachmentId: (attachmentId ?? '').trim().isEmpty
            ? null
            : attachmentId!.trim(),
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
        replyTo: replyTo,
        reactions: reactions,
        createdAt: DateTime.now(),
      ),
    );

    final next = <ChatMessage>[...messagesNotifier.value, message];
    next.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    messagesNotifier.value = next;
    await _save();
    await _savePendingReceipts();
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
    MessageReplyPreview? replyTo,
    List<MessageReaction> reactions = const <MessageReaction>[],
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

    final message = _applyPendingReceiptsToMessage(
      ChatMessage(
        id: (id == null || id.trim().isEmpty)
            ? '${createdAt.millisecondsSinceEpoch}_$trimmedChat'
            : id.trim(),
        chatId: trimmedChat,
        senderId: trimmedSender,
        type: msgType,
        body: isVoice ? (text.isEmpty ? 'Voice message' : text) : text,
        stickerPackId: (stickerPackId ?? '').trim().isEmpty
            ? null
            : stickerPackId!.trim(),
        stickerId: (stickerId ?? '').trim().isEmpty ? null : stickerId!.trim(),
        stickerVariant: (stickerVariant ?? '').trim().isEmpty
            ? null
            : stickerVariant!.trim(),
        attachmentId: (attachmentId ?? '').trim().isEmpty
            ? null
            : attachmentId!.trim(),
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
        replyTo: replyTo,
        reactions: reactions,
        createdAt: createdAt,
      ),
    );

    final next = <ChatMessage>[...messagesNotifier.value, message];
    next.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    messagesNotifier.value = next;
    await _save();
    await _savePendingReceipts();
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
    final publicId = IdentityStore.publicId.trim();
    if (publicId.isNotEmpty && s == publicId) return true;
    final userId = IdentityStore.userId.trim();
    return userId.isNotEmpty && s == userId;
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
    final idx = _findReceiptMatchIndex(current, chatId: chat, messageId: id);
    if (idx < 0) {
      _bufferPendingReceipt(chat, id, normalizedKind, receiptAt);
      await _savePendingReceipts();
      return false;
    }

    final existing = current[idx];
    final matchedChatId = existing.chatId.trim();
    final nextDelivered = existing.deliveredAt ?? receiptAt;
    final nextRead = normalizedKind == 'read'
        ? (existing.readAt ?? receiptAt)
        : existing.readAt;

    if (existing.deliveredAt == nextDelivered && existing.readAt == nextRead) {
      return true;
    }

    final updated = existing.copyWith(
      deliveredAt: nextDelivered,
      readAt: nextRead,
    );

    final next = <ChatMessage>[...current];
    next[idx] = updated;
    next.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    messagesNotifier.value = next;
    _pendingReceipts.remove(_pendingReceiptKey(chat, id));
    if (matchedChatId.isNotEmpty && matchedChatId != chat) {
      _pendingReceipts.remove(_pendingReceiptKey(matchedChatId, id));
    }
    await _save();
    await _savePendingReceipts();
    return true;
  }

  static int _findReceiptMatchIndex(
    List<ChatMessage> current, {
    required String chatId,
    required String messageId,
  }) {
    final exact = current.indexWhere(
      (m) =>
          m.chatId == chatId && m.id == messageId && _isSelfSender(m.senderId),
    );
    if (exact >= 0) return exact;
    final byMessageId = <int>[];
    for (var index = 0; index < current.length; index++) {
      final message = current[index];
      if (message.id != messageId || !_isSelfSender(message.senderId)) {
        continue;
      }
      byMessageId.add(index);
      if (byMessageId.length > 1) {
        return -1;
      }
    }
    return byMessageId.isEmpty ? -1 : byMessageId.single;
  }

  static String _pendingReceiptKey(String chatId, String messageId) =>
      '${chatId.trim()}::${messageId.trim()}';

  static void _loadPendingReceipts(String? raw) {
    _pendingReceipts.clear();
    final trimmed = (raw ?? '').trim();
    if (trimmed.isEmpty) return;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! List) return;
      for (final item in decoded) {
        if (item is! Map) continue;
        final receipt = _PendingReceipt.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (receipt == null) continue;
        _pendingReceipts[_pendingReceiptKey(
              receipt.chatId,
              receipt.messageId,
            )] =
            receipt;
      }
    } catch (_) {}
  }

  static Future<void> _savePendingReceipts() async {
    final prefs = await SharedPreferences.getInstance();
    if (_pendingReceipts.isEmpty) {
      await prefs.remove(_pendingReceiptsPrefsKey);
      return;
    }
    final payload = _pendingReceipts.values
        .map((receipt) => receipt.toJson())
        .toList(growable: false);
    await prefs.setString(_pendingReceiptsPrefsKey, jsonEncode(payload));
  }

  static void _bufferPendingReceipt(
    String chatId,
    String messageId,
    String kind,
    DateTime receiptAt,
  ) {
    final key = _pendingReceiptKey(chatId, messageId);
    final existing = _pendingReceipts[key];
    _pendingReceipts[key] =
        (existing ?? _PendingReceipt(chatId: chatId, messageId: messageId))
            .merge(kind: kind, receiptAt: receiptAt);
  }

  static ChatMessage _applyPendingReceiptsToMessage(ChatMessage message) {
    if (!_isSelfSender(message.senderId)) return message;
    final key = _pendingReceiptKey(message.chatId, message.id);
    var pending = _pendingReceipts.remove(key);
    if (pending == null) {
      final matchingKeys = _pendingReceipts.entries
          .where((entry) => entry.value.messageId == message.id)
          .map((entry) => entry.key)
          .toList(growable: false);
      if (matchingKeys.length == 1) {
        pending = _pendingReceipts.remove(matchingKeys.single);
      }
    }
    if (pending == null) return message;
    return message.copyWith(
      deliveredAt: message.deliveredAt ?? pending.deliveredAt,
      readAt: message.readAt ?? pending.readAt,
    );
  }

  static bool _applyPendingReceiptsToCurrentMessages() {
    if (_pendingReceipts.isEmpty) return false;
    var changed = false;
    final next = <ChatMessage>[];
    for (final message in messagesNotifier.value) {
      final updated = _applyPendingReceiptsToMessage(message);
      changed = changed || !identical(updated, message);
      next.add(updated);
    }
    if (changed) {
      next.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      messagesNotifier.value = next;
    }
    return changed;
  }

  static Future<bool> applyReaction({
    required String chatId,
    required String messageId,
    required String senderId,
    required String emoji,
    required String action,
    DateTime? reactedAt,
  }) async {
    final chat = chatId.trim();
    final id = messageId.trim();
    final sender = senderId.trim();
    final emojiValue = emoji.trim();
    final normalizedAction = action.trim().toLowerCase();
    if (chat.isEmpty || id.isEmpty || sender.isEmpty || emojiValue.isEmpty) {
      return false;
    }
    if (normalizedAction != 'add' && normalizedAction != 'remove') {
      return false;
    }

    final current = messagesNotifier.value;
    final idx = current.indexWhere((m) => m.chatId == chat && m.id == id);
    if (idx < 0) return false;

    final existing = current[idx];
    final alreadyPresent = existing.reactions.any(
      (reaction) => reaction.senderId == sender && reaction.emoji == emojiValue,
    );

    if (normalizedAction == 'add' && alreadyPresent) {
      return true;
    }
    if (normalizedAction == 'remove' && !alreadyPresent) {
      return true;
    }

    final nextReactions = <MessageReaction>[
      for (final reaction in existing.reactions)
        if (!(reaction.senderId == sender && reaction.emoji == emojiValue))
          reaction,
    ];
    if (normalizedAction == 'add') {
      nextReactions.add(
        MessageReaction(
          emoji: emojiValue,
          senderId: sender,
          createdAt: reactedAt ?? DateTime.now(),
        ),
      );
      nextReactions.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    final next = <ChatMessage>[...current];
    next[idx] = existing.copyWith(reactions: nextReactions);
    messagesNotifier.value = next;
    await _save();
    return true;
  }

  static Future<bool> removeMessage({
    required String chatId,
    required String messageId,
  }) async {
    final chat = chatId.trim();
    final id = messageId.trim();
    if (chat.isEmpty || id.isEmpty) return false;

    final current = messagesNotifier.value;
    final next = <ChatMessage>[
      for (final message in current)
        if (!(message.chatId == chat && message.id == id)) message,
    ];
    if (next.length == current.length) return false;
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

class _PendingReceipt {
  const _PendingReceipt({
    required this.chatId,
    required this.messageId,
    this.deliveredAt,
    this.readAt,
  });

  final String chatId;
  final String messageId;
  final DateTime? deliveredAt;
  final DateTime? readAt;

  _PendingReceipt merge({required String kind, required DateTime receiptAt}) {
    final normalizedKind = kind.trim().toLowerCase();
    return _PendingReceipt(
      chatId: chatId,
      messageId: messageId,
      deliveredAt: normalizedKind == 'delivered' || normalizedKind == 'read'
          ? (deliveredAt ?? receiptAt)
          : deliveredAt,
      readAt: normalizedKind == 'read' ? (readAt ?? receiptAt) : readAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'chatId': chatId,
    'messageId': messageId,
    'deliveredAt': deliveredAt?.toIso8601String(),
    'readAt': readAt?.toIso8601String(),
  };

  static _PendingReceipt? fromJson(Map<String, dynamic> json) {
    final chatId = (json['chatId'] ?? '').toString().trim();
    final messageId = (json['messageId'] ?? '').toString().trim();
    if (chatId.isEmpty || messageId.isEmpty) return null;
    return _PendingReceipt(
      chatId: chatId,
      messageId: messageId,
      deliveredAt: DateTime.tryParse(
        (json['deliveredAt'] ?? '').toString().trim(),
      ),
      readAt: DateTime.tryParse((json['readAt'] ?? '').toString().trim()),
    );
  }
}
