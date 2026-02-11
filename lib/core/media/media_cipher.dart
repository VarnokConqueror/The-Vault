import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import '../../state/security_store.dart';

class MediaCipher {
  static const List<int> _magic = <int>[0x43, 0x43, 0x31]; // "CC1"
  static const int _algoIdChaCha20Poly1305 = 0x01;

  static final _cipher = Chacha20.poly1305Aead().toSync();
  static List<int> _keyBytes = const <int>[];

  static Future<void> init() async {
    _keyBytes = await _deriveKey();
  }

  static Uint8List encrypt(Uint8List data) {
    final keyBytes = _requireKey();
    final secretKey = SecretKeyData(
      Uint8List.fromList(keyBytes),
      overwriteWhenDestroyed: true,
    );
    final nonce = _cipher.newNonce();
    final secretBox = _cipher.encryptSync(
      data,
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

  static Uint8List decrypt(Uint8List data) {
    final keyBytes = _requireKey();
    const headerBytes = 3 + 1 + 1;
    if (data.length < headerBytes) {
      throw const FormatException('Media cipher payload is too short');
    }
    if (!_matchesMagic(data)) {
      throw const FormatException('Unsupported media cipher envelope');
    }

    final algoId = data[3];
    final nonceLength = data[4];
    if (nonceLength <= 0) {
      throw const FormatException('Invalid nonce length in media payload');
    }

    switch (algoId) {
      case _algoIdChaCha20Poly1305:
        final secretKey = SecretKeyData(
          Uint8List.fromList(keyBytes),
          overwriteWhenDestroyed: true,
        );
        if (nonceLength != _cipher.nonceLength) {
          throw FormatException(
            'Unexpected nonce length for algorithm: $nonceLength',
          );
        }
        final start = headerBytes;
        final nonceEnd = start + nonceLength;
        if (data.length < nonceEnd) {
          throw const FormatException('Truncated nonce in media payload');
        }

        final macLength = _cipher.macAlgorithm.macLength;
        final cipherAndMacLength = data.length - nonceEnd;
        if (cipherAndMacLength < macLength) {
          throw const FormatException('Truncated ciphertext in media payload');
        }

        final cipherTextLength = cipherAndMacLength - macLength;
        final cipherTextEnd = nonceEnd + cipherTextLength;
        final nonce = data.sublist(start, nonceEnd);
        final cipherText = data.sublist(nonceEnd, cipherTextEnd);
        final macBytes = data.sublist(cipherTextEnd, data.length);

        final clear = _cipher.decryptSync(
          SecretBox(
            cipherText,
            nonce: nonce,
            mac: Mac(macBytes),
          ),
          secretKey: secretKey,
        );
        return Uint8List.fromList(clear);
      default:
        throw FormatException('Unsupported media cipher algorithm id: $algoId');
    }
  }

  static Future<List<int>> _deriveKey() async {
    try {
      final secret = await SecurityStore.getOrCreateAuthSecret();
      return sha256.convert(utf8.encode(secret)).bytes;
    } catch (_) {
      return const <int>[];
    }
  }

  static List<int> _requireKey() {
    if (_keyBytes.length != 32) {
      throw StateError('MediaCipher is not initialized');
    }
    return _keyBytes;
  }

  static bool _matchesMagic(Uint8List data) {
    if (data.length < _magic.length) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (data[i] != _magic[i]) return false;
    }
    return true;
  }
}
