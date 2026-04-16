import 'dart:typed_data';

import 'package:conquerors_court/core/e2ee/chat_cipher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat cipher roundtrip returns original bytes', () {
    final clear = Uint8List.fromList(
      List<int>.generate(512, (i) => (i * 17) & 0xff),
    );
    final secret = ChatCipher.generateSharedSecret();

    final encrypted = ChatCipher.encrypt(clear, sharedSecret: secret);
    final decrypted = ChatCipher.decrypt(encrypted, sharedSecret: secret);

    expect(ChatCipher.looksEncryptedEnvelope(encrypted), isTrue);
    expect(decrypted, equals(clear));
  });

  test('wrong shared secret fails to decrypt', () {
    final clear = Uint8List.fromList(
      List<int>.generate(64, (i) => (i * 7) & 0xff),
    );
    final encrypted = ChatCipher.encrypt(
      clear,
      sharedSecret: ChatCipher.generateSharedSecret(),
    );

    expect(
      () => ChatCipher.decrypt(
        encrypted,
        sharedSecret: ChatCipher.generateSharedSecret(),
      ),
      throwsA(anything),
    );
  });
}
