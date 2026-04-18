import 'dart:typed_data';

import 'package:conquerors_court/core/media/media_cipher.dart';
import 'package:conquerors_court/state/security_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SecureStorageMock.install();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SecureStorageMock.reset();
    await SecurityStore.init();
    await MediaCipher.init();
  });

  test('roundtrip encrypt/decrypt returns original bytes', () {
    final clear = Uint8List.fromList(List<int>.generate(256, (i) => i & 0xff));

    final encrypted = MediaCipher.encrypt(clear);
    final decrypted = MediaCipher.decrypt(encrypted);

    expect(decrypted, equals(clear));
  });

  test('tampering ciphertext causes decrypt to fail', () {
    final clear = Uint8List.fromList(
      List<int>.generate(64, (i) => (i * 3) & 0xff),
    );
    final encrypted = MediaCipher.encrypt(clear);
    final tampered = Uint8List.fromList(encrypted);

    tampered[tampered.length - 1] ^= 0x01;

    expect(() => MediaCipher.decrypt(tampered), throwsA(anything));
  });

  test('attachment key roundtrip returns original bytes', () {
    final clear = Uint8List.fromList(
      List<int>.generate(192, (i) => (255 - i) & 0xff),
    );
    final attachmentKey = MediaCipher.generateAttachmentKey();

    final encrypted = MediaCipher.encrypt(clear, keyBytes: attachmentKey);
    final decrypted = MediaCipher.decrypt(encrypted, keyBytes: attachmentKey);

    expect(decrypted, equals(clear));
  });

  test('wrong attachment key fails to decrypt', () {
    final clear = Uint8List.fromList(
      List<int>.generate(96, (i) => (i * 7) & 0xff),
    );
    final attachmentKey = MediaCipher.generateAttachmentKey();
    final wrongKey = MediaCipher.generateAttachmentKey();

    final encrypted = MediaCipher.encrypt(clear, keyBytes: attachmentKey);

    expect(
      () => MediaCipher.decrypt(encrypted, keyBytes: wrongKey),
      throwsA(anything),
    );
  });
}
