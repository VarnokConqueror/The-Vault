import 'package:conquerors_court/models/chat_thread.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('direct chat threads report Vault transport', () {
    final thread = ChatThread(
      id: 'dm-1',
      title: 'Direct',
      createdAt: DateTime.utc(2026, 4, 4),
      contactId: 'alice',
    );

    expect(thread.isDirectThread, isTrue);
    expect(thread.transport, equals(ChatTransport.vaultDirect));
  });

  test('group chat threads report Vault group transport', () {
    final thread = ChatThread(
      id: 'group-1',
      title: 'Group',
      createdAt: DateTime.utc(2026, 4, 4),
    );

    expect(thread.isDirectThread, isFalse);
    expect(thread.transport, equals(ChatTransport.vaultGroup));
  });
}
