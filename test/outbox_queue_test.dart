import 'package:conquerors_court/core/outbox/outbox_queue.dart';
import 'package:conquerors_court/core/relay/relay_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('outbox entry round-trips through json', () {
    final lastRetryAt = DateTime.parse('2026-04-19T12:34:56.000Z');
    final entry = OutboxEntry(
      chatId: 'chat_1',
      messageId: 'msg_1',
      retryCount: 4,
      lastRetryAt: lastRetryAt,
    );

    final restored = OutboxEntry.fromJson(entry.toJson());

    expect(restored, isNotNull);
    expect(restored!.chatId, 'chat_1');
    expect(restored.messageId, 'msg_1');
    expect(restored.retryCount, 4);
    expect(restored.lastRetryAt, lastRetryAt);
    expect(restored.key, 'chat_1::msg_1');
  });

  test('outbox entry preserves queued relay payload', () {
    final relayMessage = RelayMessage(
      id: 'receipt_1',
      chatId: 'chat_1',
      senderId: 'user_1',
      senderName: 'Varnok',
      type: RelayMessage.typeReceipt,
      body: '',
      receiptKind: RelayMessage.receiptKindDelivered,
      receiptMessageId: 'msg_9',
      createdAt: DateTime.parse('2026-04-19T12:35:56.000Z'),
    );
    final entry = OutboxEntry(
      chatId: 'chat_1',
      messageId: 'receipt_1',
      relayPayload: RelayClient.payloadMapForMessage(relayMessage),
    );

    final restored = OutboxEntry.fromJson(entry.toJson());

    expect(restored, isNotNull);
    expect(restored!.isRelayAction, isTrue);
    final decoded = RelayClient.relayMessageFromPayloadMap(
      restored.relayPayload,
    );
    expect(decoded, isNotNull);
    expect(decoded!.id, 'receipt_1');
    expect(decoded.type, RelayMessage.typeReceipt);
    expect(decoded.receiptKind, RelayMessage.receiptKindDelivered);
    expect(decoded.receiptMessageId, 'msg_9');
  });
}
