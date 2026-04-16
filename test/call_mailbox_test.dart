import 'package:flutter_test/flutter_test.dart';

import 'package:conquerors_court/core/calls/call_mailbox.dart';

void main() {
  test('direct call mailbox ids are symmetric', () {
    final ab = directCallMailboxId(localUserId: 'alice', peerUserId: 'bob');
    final ba = directCallMailboxId(localUserId: 'bob', peerUserId: 'alice');

    expect(ab, equals('call:alice::bob'));
    expect(ba, equals(ab));
  });

  test('call inbox mailbox ids are prefixed and trimmed', () {
    expect(callInboxMailboxId('  varnok  '), equals('call-inbox:varnok'));
  });
}
