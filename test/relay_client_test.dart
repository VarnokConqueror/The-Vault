import 'dart:convert';
import 'dart:typed_data';

import 'package:conquerors_court/core/e2ee/chat_cipher.dart';
import 'package:conquerors_court/core/relay/relay_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RelayEnvelope makeEnvelopeFromPayload(
    Map<String, dynamic> payload, {
    required String envelopeId,
    required DateTime createdAt,
    String? sharedSecret,
  }) {
    final clearBytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final rawBytes = (sharedSecret ?? '').trim().isEmpty
        ? clearBytes
        : ChatCipher.encrypt(clearBytes, sharedSecret: sharedSecret!.trim());
    return RelayEnvelope(
      envelopeId: envelopeId,
      payloadB64: base64Encode(rawBytes),
      createdAt: createdAt,
    );
  }

  test('decodePayload reads legacy plaintext envelopes', () {
    final envelope = makeEnvelopeFromPayload(
      <String, dynamic>{
        'chatId': 'chat-1',
        'senderId': 'alice',
        'senderName': 'Alice',
        'body': 'hello',
        'messageId': 'msg-1',
        'type': 'text',
        'createdAt': '2026-04-03T00:00:00.000Z',
      },
      envelopeId: 'msg-1',
      createdAt: DateTime.utc(2026, 4, 3),
    );

    final decoded = RelayClient.decodePayload(envelope);

    expect(decoded.retryable, isFalse);
    expect(decoded.message, isNotNull);
    expect(decoded.message!.body, equals('hello'));
    expect(decoded.message!.chatId, equals('chat-1'));
  });

  test('decodePayload decrypts encrypted envelopes with the chat secret', () {
    final sharedSecret = ChatCipher.generateSharedSecret();
    final envelope = makeEnvelopeFromPayload(
      <String, dynamic>{
        'chatId': 'chat-2',
        'senderId': 'bob',
        'senderName': 'Bob',
        'body': 'secret hello',
        'messageId': 'msg-2',
        'type': 'text',
        'createdAt': '2026-04-03T00:00:00.000Z',
      },
      envelopeId: 'msg-2',
      createdAt: DateTime.utc(2026, 4, 3),
      sharedSecret: sharedSecret,
    );

    final decoded = RelayClient.decodePayload(
      envelope,
      sharedSecret: sharedSecret,
    );

    expect(decoded.retryable, isFalse);
    expect(decoded.encrypted, isTrue);
    expect(decoded.message, isNotNull);
    expect(decoded.message!.body, equals('secret hello'));
  });

  test(
    'decodePayload defers encrypted envelopes when the secret is missing',
    () {
      final envelope = makeEnvelopeFromPayload(
        <String, dynamic>{
          'chatId': 'chat-3',
          'senderId': 'eve',
          'senderName': 'Eve',
          'body': 'locked',
          'messageId': 'msg-3',
          'type': 'text',
          'createdAt': '2026-04-03T00:00:00.000Z',
        },
        envelopeId: 'msg-3',
        createdAt: DateTime.utc(2026, 4, 3),
        sharedSecret: ChatCipher.generateSharedSecret(),
      );

      final decoded = RelayClient.decodePayload(envelope);

      expect(decoded.retryable, isTrue);
      expect(decoded.encrypted, isTrue);
      expect(decoded.message, isNull);
    },
  );

  test('encode/decode preserves direct peer routing metadata', () {
    final message = RelayMessage(
      id: 'msg-4',
      chatId: 'direct:alice',
      senderId: 'me',
      senderName: 'Me',
      directPeerId: 'alice',
      body: 'hello from another device',
      createdAt: DateTime.utc(2026, 4, 4, 12, 0),
    );

    final decoded = RelayClient.decodePayloadBytes(
      RelayClient.encodeClearPayloadBytes(message),
      fallbackCreatedAt: DateTime.utc(2026, 4, 4, 12, 0),
      fallbackEnvelopeId: 'msg-4',
    );

    expect(decoded.message, isNotNull);
    expect(decoded.message!.directPeerId, equals('alice'));
    expect(decoded.message!.chatId, equals('direct:alice'));
  });

  test('encode/decode preserves attachment manifest metadata', () {
    final message = RelayMessage(
      id: 'attach-1',
      chatId: 'direct:bob',
      senderId: 'alice',
      senderName: 'Alice',
      directPeerId: 'bob',
      type: RelayMessage.typeAttachmentManifest,
      body: 'Attachment: cat.gif',
      attachmentId: 'attach-1',
      attachmentName: 'cat.gif',
      attachmentMime: 'image/gif',
      attachmentSize: 123456,
      attachmentHash: 'deadbeef',
      attachmentChunkCount: 7,
      replyToMessageId: 'msg-older',
      replyToSenderId: 'bob',
      replyToType: RelayMessage.typeText,
      replyToPreview: 'earlier line',
      createdAt: DateTime.utc(2026, 4, 10, 14, 30),
    );

    final decoded = RelayClient.decodePayloadBytes(
      RelayClient.encodeClearPayloadBytes(message),
      fallbackCreatedAt: DateTime.utc(2026, 4, 10, 14, 30),
      fallbackEnvelopeId: 'attach-1',
    );

    expect(decoded.message, isNotNull);
    expect(decoded.message!.type, equals(RelayMessage.typeAttachmentManifest));
    expect(decoded.message!.attachmentId, equals('attach-1'));
    expect(decoded.message!.attachmentHash, equals('deadbeef'));
    expect(decoded.message!.attachmentChunkCount, equals(7));
    expect(decoded.message!.replyToMessageId, equals('msg-older'));
    expect(decoded.message!.replyToSenderId, equals('bob'));
  });
}
