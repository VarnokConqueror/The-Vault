import 'package:conquerors_court/state/chat_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('new chats get a shared secret by default', () async {
    await ChatStore.init();

    final chat = await ChatStore.createChat(title: 'Secure Chamber');

    expect((chat.sharedSecret ?? '').trim(), isNotEmpty);
    expect(ChatStore.sharedSecretFor(chat.id), equals(chat.sharedSecret));
  });

  test('joining from invite stores shared secret on the chat', () async {
    await ChatStore.init();

    final chat = await ChatStore.upsertChatFromInvite(
      chatId: 'chat-1',
      title: 'Invite Chat',
      sharedSecret: 'shared-secret-1',
    );

    expect(chat.sharedSecret, equals('shared-secret-1'));
    expect(ChatStore.sharedSecretFor('chat-1'), equals('shared-secret-1'));
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
}
