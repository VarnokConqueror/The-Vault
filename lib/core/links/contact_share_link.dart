import '../vault/vault_models.dart';

class ParsedContactLink {
  final String contactId;
  final String displayName;
  final String? vaultUserId;
  final int? vaultDeviceId;

  const ParsedContactLink({
    required this.contactId,
    this.displayName = '',
    this.vaultUserId,
    this.vaultDeviceId,
  });

  bool get isValid => contactId.trim().isNotEmpty;

  VaultAddress? get vaultAddress {
    final userId = vaultUserId?.trim();
    final deviceId = vaultDeviceId;
    if (userId == null || userId.isEmpty || deviceId == null || deviceId <= 0) {
      return null;
    }
    return VaultAddress(userId: userId, deviceId: deviceId);
  }
}

ParsedContactLink parseContactLink(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return const ParsedContactLink(contactId: '');
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null || (!uri.hasScheme && !trimmed.contains('/'))) {
    return ParsedContactLink(contactId: trimmed);
  }

  final displayName =
      (uri.queryParameters['displayName'] ?? uri.queryParameters['name'] ?? '')
          .trim();
  final userId = (uri.queryParameters['userId'] ?? '').trim();
  final deviceId = int.tryParse(
    (uri.queryParameters['deviceId'] ??
            uri.queryParameters['vaultDeviceId'] ??
            uri.queryParameters['signalDeviceId'] ??
            '')
        .trim(),
  );
  final queryId =
      (uri.queryParameters['id'] ?? uri.queryParameters['contactId'] ?? '')
          .trim();

  if (queryId.isNotEmpty) {
    return ParsedContactLink(
      contactId: queryId,
      displayName: displayName,
      vaultUserId: userId.isEmpty ? null : userId,
      vaultDeviceId: deviceId,
    );
  }

  if (userId.isNotEmpty) {
    return ParsedContactLink(
      contactId: userId,
      displayName: displayName,
      vaultUserId: userId,
      vaultDeviceId: deviceId,
    );
  }

  if (uri.pathSegments.isNotEmpty) {
    final candidate = uri.pathSegments.last.trim();
    if (candidate.isNotEmpty &&
        candidate.toLowerCase() != 'contact' &&
        candidate.toLowerCase() != 'join') {
      return ParsedContactLink(
        contactId: candidate,
        displayName: displayName,
        vaultUserId: userId.isEmpty ? null : userId,
        vaultDeviceId: deviceId,
      );
    }
  }

  return ParsedContactLink(contactId: trimmed, displayName: displayName);
}

String buildProfileInviteLink({
  required String userId,
  required String displayName,
  int? deviceId,
}) {
  final cleanUserId = userId.trim();
  final cleanDisplayName = displayName.trim().isEmpty
      ? 'Conquered'
      : displayName.trim();
  return Uri.https('vault.theconquerorscourt.com', '/contact', {
    'id': cleanUserId,
    'userId': cleanUserId,
    'displayName': cleanDisplayName,
    if (deviceId != null && deviceId > 0) 'vaultDeviceId': '$deviceId',
  }).toString();
}
