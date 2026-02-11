import 'dart:typed_data';

import 'package:conquerors_court/core/media/media_cipher.dart';
import 'package:conquerors_court/state/security_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SecurityStore.init();
    await MediaCipher.init();
  });

  test('roundtrip encrypt/decrypt returns original bytes', () {
    final clear = Uint8List.fromList(
      List<int>.generate(256, (i) => i & 0xff),
    );

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
}
