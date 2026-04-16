import 'package:flutter_test/flutter_test.dart';

import 'package:conquerors_court/core/invites/vault_chat_invite.dart';

void main() {
  test('builds https invite links for Vault group invites', () {
    final invite = VaultChatInvite(
      chatId: 'chat-123',
      title: 'War Room',
      sharedSecret: 'secret-123',
      transport: 'vault_group',
    );

    final uri = invite.toUri();

    expect(uri.scheme, equals('https'));
    expect(uri.host, equals('vault.theconquerorscourt.com'));
    expect(uri.path, equals('/join'));
    expect(uri.queryParameters['chatId'], equals('chat-123'));
    expect(uri.queryParameters['title'], equals('War Room'));
    expect(uri.queryParameters['sharedSecret'], equals('secret-123'));
    expect(uri.queryParameters['transport'], equals('vault_group'));
  });

  test('parses legacy json invites', () {
    const raw =
        '{"type":"cc-chat","chatId":"chat-legacy","title":"Council","sharedSecret":"s1"}';

    final parsed = VaultChatInvite.parse(raw);

    expect(parsed, isNotNull);
    expect(parsed!.chatId, equals('chat-legacy'));
    expect(parsed.title, equals('Council'));
    expect(parsed.sharedSecret, equals('s1'));
  });

  test('parses https invite links', () {
    const raw =
        'https://vault.theconquerorscourt.com/join?chatId=chat-456&title=Night%20Court&sharedSecret=key-456';

    final parsed = VaultChatInvite.parse(raw);

    expect(parsed, isNotNull);
    expect(parsed!.chatId, equals('chat-456'));
    expect(parsed.title, equals('Night Court'));
    expect(parsed.sharedSecret, equals('key-456'));
  });

  test('ignores bare join route without chat id', () {
    const raw = 'https://vault.theconquerorscourt.com/join';

    final parsed = VaultChatInvite.parse(raw);

    expect(parsed, isNull);
  });
}
