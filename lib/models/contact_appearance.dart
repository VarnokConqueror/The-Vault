class ContactAppearance {
  final String contactId;
  final String? toneUri;
  final String? toneName;

  const ContactAppearance({
    required this.contactId,
    this.toneUri,
    this.toneName,
  });

  Map<String, dynamic> toJson() => {
        'toneUri': toneUri,
        'toneName': toneName,
      };

  static ContactAppearance fromJson(String contactId, Map<String, dynamic> json) {
    return ContactAppearance(
      contactId: contactId,
      toneUri: (json['toneUri'] as String?)?.toString(),
      toneName: (json['toneName'] as String?)?.toString(),
    );
  }
}
