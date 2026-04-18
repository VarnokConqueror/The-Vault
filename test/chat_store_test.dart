import 'package:conquerors_court/core/security/local_security_material.dart';
import 'package:conquerors_court/state/chat_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecureStorageMock.install();
    SecureStorageMock.reset();
  });

  test('new chats get a shared secret by default', () async {
    await ChatStore.init();

    final chat = await ChatStore.createChat(title: 'Secure Chamber');
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cc_chats_v1') ?? '';

    expect((chat.sharedSecret ?? '').trim(), isNotEmpty);
    expect(ChatStore.sharedSecretFor(chat.id), equals(chat.sharedSecret));
    expect(
      await LocalSecurityMaterial.readChatSharedSecret(chat.id),
      equals(chat.sharedSecret),
    );
    expect(raw, isNot(contains('sharedSecret')));
    expect(raw, isNot(contains(chat.sharedSecret!)));
  });

  test('joining from invite stores shared secret on the chat', () async {
    await ChatStore.init();

    final chat = await ChatStore.upsertChatFromInvite(
      chatId: 'chat-1',
      title: 'Invite Chat',
      sharedSecret: 'shared-secret-1',
    );
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cc_chats_v1') ?? '';

    expect(chat.sharedSecret, equals('shared-secret-1'));
    expect(ChatStore.sharedSecretFor('chat-1'), equals('shared-secret-1'));
    expect(
      await LocalSecurityMaterial.readChatSharedSecret('chat-1'),
      equals('shared-secret-1'),
    );
    expect(raw, isNot(contains('shared-secret-1')));
  });

  test('ensureSharedSecret upgrades legacy chat once', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cc_chats_v1':
          '{"version":1,"chats":[{"id":"legacy","title":"Legacy","createdAt":"2026-04-03T00:00:00.000"}]}',
    });
    await ChatStore.init();

    final generated = await ChatStore.ensureSharedSecret('legacy');
    final generatedAgain = await ChatStore.ensureSharedSecret('legacy');

    expect((generated ?? '').trim(), isNotEmpty);
    expect(generatedAgain, equals(generated));
    expect(ChatStore.sharedSecretFor('legacy'), equals(generated));
  });

  test('legacy embedded shared secrets migrate into secure storage', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'cc_chats_v1':
          '{"version":1,"chats":[{"id":"legacy","title":"Legacy","createdAt":"2026-04-03T00:00:00.000","sharedSecret":"legacy-secret"}]}',
    });

    await ChatStore.init();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cc_chats_v1') ?? '';

    expect(ChatStore.sharedSecretFor('legacy'), equals('legacy-secret'));
    expect(
      await LocalSecurityMaterial.readChatSharedSecret('legacy'),
      equals('legacy-secret'),
    );
    expect(raw, isNot(contains('legacy-secret')));
  });

  test('tampered persisted chat payload is rejected', () async {
    await ChatStore.init();
    await ChatStore.createChat(title: 'Secure Chamber');

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cc_chats_v1') ?? '';
    final tampered = raw.replaceFirst('Secure Chamber', 'Compromised Chamber');
    await prefs.setString('cc_chats_v1', tampered);

    await ChatStore.init();

    expect(ChatStore.chats, isEmpty);
  });
}
