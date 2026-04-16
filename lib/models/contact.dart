class Contact {
  final String id; // stable local id (we'll use publicId for now)
  final String displayName; // local label/nickname
  final String handle; // short fingerprint-ish label
  final DateTime addedAt;

  Contact({
    required this.id,
    required this.displayName,
    required this.handle,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'handle': handle,
        'addedAt': addedAt.toIso8601String(),
      };

  static Contact fromJson(Map<String, dynamic> json) {
    return Contact(
      id: (json['id'] ?? '').toString(),
      displayName: (json['displayName'] ?? 'Unknown').toString(),
      handle: (json['handle'] ?? '').toString(),
      addedAt: DateTime.tryParse((json['addedAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
