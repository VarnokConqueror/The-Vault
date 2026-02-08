class ContactAppearance {
  final String contactId;
  final String? toneUri;

  const ContactAppearance({
    required this.contactId,
    this.toneUri,
  });

  Map<String, dynamic> toJson() => {
        'toneUri': toneUri,
      };

  static ContactAppearance fromJson(String contactId, Map<String, dynamic> json) {
    return ContactAppearance(
      contactId: contactId,
      toneUri: (json['toneUri'] as String?)?.toString(),
    );
  }
}
