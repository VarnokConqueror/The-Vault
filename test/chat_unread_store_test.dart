import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:conquerors_court/state/chat_unread_store.dart';
import 'package:conquerors_court/state/identity_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await IdentityStore.init();
    await ChatUnreadStore.init();
    ChatUnreadStore.noteChatClosed('chat-open');
    ChatUnreadStore.noteChatClosed('chat-closed');
  });

  test('open chats do not accumulate unread counts', () async {
    ChatUnreadStore.trackChatOpen('chat-open');

    final shouldNotify = await ChatUnreadStore.recordIncomingMessage(
      chatId: 'chat-open',
      senderId: 'friend-1',
      messageId: 'msg-1',
      envelopeId: 'env-1',
    );

    expect(shouldNotify, isFalse);
    expect(ChatUnreadStore.unreadForChat('chat-open'), 0);
  });

  test('duplicate envelope ids do not increment unread twice', () async {
    final first = await ChatUnreadStore.recordIncomingMessage(
      chatId: 'chat-closed',
      senderId: 'friend-2',
      messageId: 'msg-2',
      envelopeId: 'env-2',
    );
    final duplicate = await ChatUnreadStore.recordIncomingMessage(
      chatId: 'chat-closed',
      senderId: 'friend-2',
      messageId: 'msg-2b',
      envelopeId: 'env-2',
    );

    expect(first, isTrue);
    expect(duplicate, isFalse);
    expect(ChatUnreadStore.unreadForChat('chat-closed'), 1);
  });
}
