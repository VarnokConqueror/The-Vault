import 'package:conquerors_court/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat message preserves outbound state through json', () {
    final createdAt = DateTime.parse('2026-04-19T12:00:00.000Z');
    final queuedAt = createdAt.add(const Duration(seconds: 5));
    final retryingAt = createdAt.add(const Duration(seconds: 10));
    final failedAt = createdAt.add(const Duration(seconds: 20));
    final submittedAt = createdAt.add(const Duration(seconds: 30));

    final message = ChatMessage(
      id: 'msg_1',
      chatId: 'chat_1',
      senderId: 'user_1',
      body: 'Hello',
      queuedAt: queuedAt,
      retryingAt: retryingAt,
      failedAt: failedAt,
      submittedAt: submittedAt,
      retryCount: 3,
      lastSendError: 'still retrying',
      createdAt: createdAt,
    );

    final restored = ChatMessage.fromJson(message.toJson());

    expect(restored.queuedAt, queuedAt);
    expect(restored.retryingAt, retryingAt);
    expect(restored.failedAt, failedAt);
    expect(restored.submittedAt, submittedAt);
    expect(restored.retryCount, 3);
    expect(restored.lastSendError, 'still retrying');
  });

  test('chat message copyWith can clear outbound state', () {
    final createdAt = DateTime.parse('2026-04-19T12:00:00.000Z');
    final message = ChatMessage(
      id: 'msg_2',
      chatId: 'chat_2',
      senderId: 'user_2',
      body: 'Hello again',
      queuedAt: createdAt,
      retryingAt: createdAt,
      failedAt: createdAt,
      submittedAt: createdAt,
      retryCount: 2,
      lastSendError: 'temporary failure',
      createdAt: createdAt,
    );

    final cleared = message.copyWith(
      queuedAt: null,
      retryingAt: null,
      failedAt: null,
      submittedAt: null,
      retryCount: null,
      lastSendError: null,
    );

    expect(cleared.queuedAt, isNull);
    expect(cleared.retryingAt, isNull);
    expect(cleared.failedAt, isNull);
    expect(cleared.submittedAt, isNull);
    expect(cleared.retryCount, isNull);
    expect(cleared.lastSendError, isNull);
  });
}
