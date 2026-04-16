import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

class ChatCipher {
  static const List<int> _magic = <int>[0x43, 0x43, 0x45, 0x31]; // "CCE1"
  static const int _algoIdChaCha20Poly1305 = 0x01;

  static final _cipher = Chacha20.poly1305Aead().toSync();

  static String generateSharedSecret() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static bool hasSharedSecret(String? value) => (value ?? '').trim().isNotEmpty;

  static bool looksEncryptedEnvelope(Uint8List data) {
    if (data.length < _magic.length) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (data[i] != _magic[i]) {
        return false;
      }
    }
    return true;
  }

  static Uint8List encrypt(
    Uint8List clearText, {
    required String sharedSecret,
  }) {
    final secretKey = SecretKeyData(
      Uint8List.fromList(_deriveKey(sharedSecret)),
      overwriteWhenDestroyed: true,
    );
    final nonce = _cipher.newNonce();
    final secretBox = _cipher.encryptSync(
      clearText,
      secretKey: secretKey,
      nonce: nonce,
    );
    final cipherAndMac = Uint8List(
      secretBox.cipherText.length + secretBox.mac.bytes.length,
    );
    cipherAndMac.setRange(0, secretBox.cipherText.length, secretBox.cipherText);
    cipherAndMac.setRange(
      secretBox.cipherText.length,
      cipherAndMac.length,
      secretBox.mac.bytes,
    );

    final out = Uint8List(
      _magic.length + 1 + 1 + nonce.length + cipherAndMac.length,
    );
    var offset = 0;
    out.setRange(offset, offset + _magic.length, _magic);
    offset += _magic.length;
    out[offset++] = _algoIdChaCha20Poly1305;
    out[offset++] = nonce.length;
    out.setRange(offset, offset + nonce.length, nonce);
    offset += nonce.length;
    out.setRange(offset, offset + cipherAndMac.length, cipherAndMac);
    return out;
  }

  static Uint8List decrypt(Uint8List envelope, {required String sharedSecret}) {
    const headerBytes = 4 + 1 + 1;
    if (envelope.length < headerBytes) {
      throw const FormatException('Encrypted chat payload is too short');
    }
    if (!looksEncryptedEnvelope(envelope)) {
      throw const FormatException('Unsupported encrypted chat envelope');
    }

    final algoId = envelope[4];
    final nonceLength = envelope[5];
    if (nonceLength <= 0) {
      throw const FormatException('Invalid nonce length in chat payload');
    }
    if (algoId != _algoIdChaCha20Poly1305) {
      throw FormatException('Unsupported chat cipher algorithm id: $algoId');
    }
    if (nonceLength != _cipher.nonceLength) {
      throw FormatException(
        'Unexpected nonce length for chat payload: $nonceLength',
      );
    }

    final nonceStart = headerBytes;
    final nonceEnd = nonceStart + nonceLength;
    if (envelope.length < nonceEnd) {
      throw const FormatException('Truncated nonce in chat payload');
    }

    final macLength = _cipher.macAlgorithm.macLength;
    final cipherAndMacLength = envelope.length - nonceEnd;
    if (cipherAndMacLength < macLength) {
      throw const FormatException('Truncated ciphertext in chat payload');
    }

    final cipherTextEnd = envelope.length - macLength;
    final secretKey = SecretKeyData(
      Uint8List.fromList(_deriveKey(sharedSecret)),
      overwriteWhenDestroyed: true,
    );
    final clear = _cipher.decryptSync(
      SecretBox(
        envelope.sublist(nonceEnd, cipherTextEnd),
        nonce: envelope.sublist(nonceStart, nonceEnd),
        mac: Mac(envelope.sublist(cipherTextEnd)),
      ),
      secretKey: secretKey,
    );
    return Uint8List.fromList(clear);
  }

  static List<int> _deriveKey(String sharedSecret) {
    final normalized = sharedSecret.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Chat shared secret is required');
    }

    List<int> secretBytes;
    try {
      secretBytes = base64Url.decode(_normalizeBase64Url(normalized));
    } catch (_) {
      secretBytes = utf8.encode(normalized);
    }
    return sha256.convert(secretBytes).bytes;
  }

  static String _normalizeBase64Url(String input) {
    final remainder = input.length % 4;
    if (remainder == 0) return input;
    return '$input${'=' * (4 - remainder)}';
  }
}
