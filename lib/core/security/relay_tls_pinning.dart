import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'constant_time.dart';
import '../links/vault_links.dart';
import '../relay/relay_config.dart';

class RelayTlsPinning {
  static final Map<String, Set<String>> _pinsByHost = _buildPinsByHost();
  static final Map<String, DateTime> _verifiedAuthorities =
      <String, DateTime>{};

  static bool get enabled => _pinsByHost.isNotEmpty;

  static Future<void> verifyUri(Uri uri) async {
    if (uri.scheme != 'https' && uri.scheme != 'wss') return;
    final pins = _pinsByHost[uri.host.toLowerCase()];
    if (pins == null || pins.isEmpty) return;

    final authority = '${uri.host}:${_portForUri(uri)}';
    final now = DateTime.now();
    final cachedUntil = _verifiedAuthorities[authority];
    if (cachedUntil != null && cachedUntil.isAfter(now)) {
      return;
    }

    final socket = await SecureSocket.connect(
      uri.host,
      _portForUri(uri),
      timeout: const Duration(seconds: 10),
    );

    try {
      final cert = socket.peerCertificate;
      if (cert == null) {
        throw const HandshakeException(
          'Relay certificate pinning could not read the peer certificate.',
        );
      }
      final presentedPin = _pinForCertificate(cert);
      final matchesPin = pins.any(
        (candidate) => ConstantTime.equalsUtf8(candidate, presentedPin),
      );
      if (!matchesPin) {
        throw HandshakeException(
          'Relay certificate pin mismatch for ${uri.host}.',
        );
      }
      _verifiedAuthorities[authority] = now.add(const Duration(minutes: 10));
    } finally {
      await socket.close();
    }
  }

  static int _portForUri(Uri uri) {
    if (uri.hasPort && uri.port != 0) return uri.port;
    return uri.scheme == 'https' || uri.scheme == 'wss' ? 443 : 80;
  }

  static String _pinForCertificate(X509Certificate cert) {
    final pemBody = cert.pem
        .split('\n')
        .map((line) => line.trim())
        .where(
          (line) =>
              line.isNotEmpty &&
              !line.startsWith('-----BEGIN') &&
              !line.startsWith('-----END'),
        )
        .join();
    final derBytes = base64.decode(pemBody);
    return sha256.convert(derBytes).toString().toUpperCase();
  }

  static String _normalizePin(String raw) {
    return raw.replaceAll(RegExp(r'[^A-Fa-f0-9]'), '').toUpperCase();
  }

  static Map<String, Set<String>> _buildPinsByHost() {
    final map = <String, Set<String>>{};
    final relayHost = Uri.parse(RelayConfig.baseUrl).host.toLowerCase();
    final relayPins = RelayConfig.relayCertSha256
        .split(',')
        .map(_normalizePin)
        .where((value) => value.isNotEmpty)
        .toSet();
    if (relayHost.isNotEmpty && relayPins.isNotEmpty) {
      map[relayHost] = relayPins;
    }

    final siteHost = Uri.parse(VaultLinks.downloadSiteUrl).host.toLowerCase();
    final sitePins = VaultLinks.siteCertSha256
        .split(',')
        .map(_normalizePin)
        .where((value) => value.isNotEmpty)
        .toSet();
    if (siteHost.isNotEmpty && sitePins.isNotEmpty) {
      map[siteHost] = sitePins;
    }
    return map;
  }
}
