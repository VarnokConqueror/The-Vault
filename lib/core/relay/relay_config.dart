import 'dart:math';

class RelayConfig {
  static const String baseUrl = String.fromEnvironment(
    'RELAY_BASE_URL',
    defaultValue: 'https://relay.theconquerorscourt.com',
  );

  static const String relayToken = String.fromEnvironment(
    'RELAY_TOKEN',
    defaultValue: '',
  );

  static const bool relayTokenEnabled = bool.fromEnvironment(
    'RELAY_TOKEN_ENABLED',
    defaultValue: false,
  );

  static const String relayAuthHeader = 'X-Court-Relay-Token';

  static String get relayTokenTrimmed => relayToken.trim();

  static bool get shouldAttachRelayToken =>
      relayTokenEnabled && relayTokenTrimmed.isNotEmpty;

  static String get maskedRelayToken {
    final token = relayTokenTrimmed;
    if (token.isEmpty) return '<empty>';
    final prefixLen = min(4, token.length);
    return '${token.substring(0, prefixLen)}...len=${token.length}';
  }
}
