import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/chat_message.dart';
import '../relay/relay_client.dart';
import '../../state/message_store.dart';
import '../vault/vault_bridge.dart';
import '../vault/windows_vault_helper_bridge.dart';
import 'outbox_queue.dart';
import 'vault_outbound_transport_service.dart';

class OutboxService {
  OutboxService._();

  static final OutboxService instance = OutboxService._();

  final Set<String> _inFlightKeys = <String>{};
  Timer? _retryTimer;

  Future<void> start() async {
    if (_retryTimer != null) return;
    _retryTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_drainDueEntries());
    });
    unawaited(_drainDueEntries(force: true));
  }

  void stop() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<void> enqueueChatMessage(ChatMessage message) async {
    if (!VaultOutboundTransportService.instance.supportsMessage(message)) {
      return;
    }
    await MessageStore.markQueued(message.chatId, message.id);
    await OutboxQueue.upsert(
      OutboxEntry(chatId: message.chatId, messageId: message.id),
    );
    unawaited(
      _dispatchEntry(
        OutboxEntry(chatId: message.chatId, messageId: message.id),
        force: true,
      ),
    );
  }

  Future<void> enqueueRelayMessage(RelayMessage message) async {
    await OutboxQueue.upsert(
      OutboxEntry(
        chatId: message.chatId,
        messageId: message.id,
        relayPayload: RelayClient.payloadMapForMessage(message),
      ),
    );
    unawaited(
      _dispatchEntry(
        OutboxEntry(
          chatId: message.chatId,
          messageId: message.id,
          relayPayload: RelayClient.payloadMapForMessage(message),
        ),
        force: true,
      ),
    );
  }

  Future<void> _drainDueEntries({bool force = false}) async {
    final entries = await OutboxQueue.loadAll();
    final now = DateTime.now();
    for (final entry in entries) {
      if (force || _isRetryDue(entry, now)) {
        unawaited(_dispatchEntry(entry, force: force));
      }
    }
  }

  Future<void> _dispatchEntry(OutboxEntry entry, {bool force = false}) async {
    final key = entry.key;
    if (!_inFlightKeys.add(key)) return;
    try {
      if (entry.isRelayAction) {
        await _dispatchRelayEntry(entry, force: force);
        return;
      }
      final message = MessageStore.getMessage(entry.chatId, entry.messageId);
      if (message == null) {
        await OutboxQueue.remove(
          chatId: entry.chatId,
          messageId: entry.messageId,
        );
        return;
      }
      if (message.submittedAt != null ||
          message.deliveredAt != null ||
          message.readAt != null) {
        await OutboxQueue.remove(
          chatId: entry.chatId,
          messageId: entry.messageId,
        );
        return;
      }
      if (!VaultOutboundTransportService.instance.supportsMessage(message)) {
        await MessageStore.markFailed(
          entry.chatId,
          entry.messageId,
          error: 'Queued message type is not supported yet.',
          retryCount: entry.retryCount,
        );
        await OutboxQueue.remove(
          chatId: entry.chatId,
          messageId: entry.messageId,
        );
        return;
      }
      if (!force && !_isRetryDue(entry, DateTime.now())) {
        return;
      }

      final attemptNumber = entry.retryCount + 1;
      final attemptAt = DateTime.now();

      if (entry.retryCount > 0 &&
          !kIsWeb &&
          Platform.isWindows &&
          defaultVaultBridgeConfigured) {
        try {
          await WindowsVaultHelperBridge.restartHelper();
        } catch (_) {}
      }

      await MessageStore.markRetrying(
        entry.chatId,
        entry.messageId,
        retryCount: attemptNumber,
        retryingAt: attemptAt,
      );

      final result = await VaultOutboundTransportService.instance
          .sendChatMessage(message);

      if (result == VaultMessageTransportResult.sent) {
        await MessageStore.markSubmitted(
          entry.chatId,
          entry.messageId,
          submittedAt: DateTime.now(),
        );
        await OutboxQueue.remove(
          chatId: entry.chatId,
          messageId: entry.messageId,
        );
        return;
      }

      await OutboxQueue.upsert(
        entry.copyWith(retryCount: attemptNumber, lastRetryAt: attemptAt),
      );
      await MessageStore.markFailed(
        entry.chatId,
        entry.messageId,
        error: _errorTextFor(result),
        retryCount: attemptNumber,
        failedAt: attemptAt,
      );
    } finally {
      _inFlightKeys.remove(key);
    }
  }

  Future<void> _dispatchRelayEntry(
    OutboxEntry entry, {
    bool force = false,
  }) async {
    if (!force && !_isRetryDue(entry, DateTime.now())) {
      return;
    }
    final relayPayload = entry.relayPayload;
    if (relayPayload == null) {
      await OutboxQueue.remove(
        chatId: entry.chatId,
        messageId: entry.messageId,
      );
      return;
    }
    final relayMessage = RelayClient.relayMessageFromPayloadMap(relayPayload);
    if (relayMessage == null) {
      await OutboxQueue.remove(
        chatId: entry.chatId,
        messageId: entry.messageId,
      );
      return;
    }

    final attemptNumber = entry.retryCount + 1;
    final attemptAt = DateTime.now();

    if (entry.retryCount > 0 &&
        !kIsWeb &&
        Platform.isWindows &&
        defaultVaultBridgeConfigured) {
      try {
        await WindowsVaultHelperBridge.restartHelper();
      } catch (_) {}
    }

    final result = await VaultOutboundTransportService.instance.sendRelayAction(
      relayMessage,
    );
    if (result == VaultMessageTransportResult.sent) {
      await OutboxQueue.remove(
        chatId: entry.chatId,
        messageId: entry.messageId,
      );
      return;
    }

    await OutboxQueue.upsert(
      entry.copyWith(retryCount: attemptNumber, lastRetryAt: attemptAt),
    );
  }

  bool _isRetryDue(OutboxEntry entry, DateTime now) {
    final lastRetryAt = entry.lastRetryAt;
    if (lastRetryAt == null) {
      return true;
    }
    return now.difference(lastRetryAt) >= _retryDelayFor(entry.retryCount);
  }

  Duration _retryDelayFor(int retryCount) {
    if (retryCount <= 0) {
      return Duration.zero;
    }
    if (retryCount == 1) {
      return const Duration(seconds: 5);
    }
    if (retryCount == 2) {
      return const Duration(seconds: 15);
    }
    if (retryCount == 3) {
      return const Duration(seconds: 30);
    }
    if (retryCount == 4) {
      return const Duration(minutes: 1);
    }
    return const Duration(minutes: 2);
  }

  String _errorTextFor(VaultMessageTransportResult result) {
    switch (result) {
      case VaultMessageTransportResult.unavailable:
        return 'Waiting for Vault transport to come online.';
      case VaultMessageTransportResult.failed:
        return 'Message not sent yet. The Vault will keep trying.';
      case VaultMessageTransportResult.sent:
        return '';
    }
  }
}
