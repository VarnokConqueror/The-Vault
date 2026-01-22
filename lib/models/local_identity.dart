import 'dart:convert';
import 'dart:math';

class LocalIdentity {
  final String publicId; // local "address" / identifier
  final String displayName;

  LocalIdentity({
    required this.publicId,
    required this.displayName,
  });

  Map<String, dynamic> toJson() => {
        'publicId': publicId,
        'displayName': displayName,
      };

  static LocalIdentity fromJson(Map<String, dynamic> json) {
    return LocalIdentity(
      publicId: (json['publicId'] ?? '').toString(),
      displayName: (json['displayName'] ?? 'Anonymous').toString(),
    );
  }

  static String generatePublicId({int bytes = 18}) {
    final rnd = Random.secure();
    final data = List<int>.generate(bytes, (_) => rnd.nextInt(256));
    return base64UrlEncode(data).replaceAll('=', '');
  }
}
