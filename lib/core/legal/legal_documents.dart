class LegalSection {
  final String title;
  final List<String> paragraphs;
  final List<String> bullets;

  const LegalSection({
    required this.title,
    this.paragraphs = const <String>[],
    this.bullets = const <String>[],
  });
}

class LegalDocument {
  final String title;
  final String subtitle;
  final String lastUpdated;
  final List<LegalSection> sections;
  final String closingLine;

  const LegalDocument({
    required this.title,
    required this.subtitle,
    required this.lastUpdated,
    required this.sections,
    required this.closingLine,
  });
}

const vaultPrivacyPolicyDocument = LegalDocument(
  title: 'The Privacy Covenant',
  subtitle: 'The Privacy Covenant',
  lastUpdated: 'April 4, 2026',
  sections: <LegalSection>[
    LegalSection(
      title: 'I. The Sacred Vow',
      paragraphs: <String>[
        "Within The Vault, your privacy is held as sacred as the most guarded sigils in our royal archives. This Privacy Covenant explains how we collect, protect, and honor the information you entrust to us as you move through the spaces of our kingdom.",
        'We believe that trust is the foundation of any enduring reign, and we are committed to preserving the confidence you place in us.',
      ],
    ),
    LegalSection(
      title: 'II. The Scrolls We Collect',
      paragraphs: <String>[
        'To serve you within our kingdom, we gather the following knowledge:',
        'Information You Provide',
      ],
      bullets: <String>[
        'Identity Details: the display name you choose, your local Vault identifier, and any support communications you send to us',
        'Contact and Court Records: the contacts you choose to save, group memberships you create or join, and chat titles you set',
        'Messages and Media: text messages, stickers, attachments, voice notes, and calling information you choose to send through the Vault',
        'Security and Preference Settings: notification choices, mute settings, call permissions, lock preferences, and other choices you make within the app',
      ],
    ),
    LegalSection(
      title: 'III. How We Use Your Knowledge',
      paragraphs: <String>[
        'The information entrusted to us serves the following noble purposes:',
      ],
      bullets: <String>[
        'creating and maintaining your Vault identity within the Court',
        'routing your messages, attachments, voice notes, and calls to the recipients you choose',
        'delivering notifications and keeping your chats and groups in order',
        'protecting the security and integrity of the Vault',
        'investigating abuse, fraud, misuse, or unlawful conduct',
        'improving and refining our services for the benefit of our subjects',
        'fulfilling legal obligations as required by governing authorities',
      ],
    ),
    LegalSection(
      title: 'IV. The Sharing of Secrets',
      paragraphs: <String>[
        'Your personal information is guarded within our walls. We do not sell, trade, or rent your personal data to outside kingdoms. However, we may share information with:',
      ],
      bullets: <String>[
        'Service Allies: trusted partners who help us operate the Vault, such as cloud hosting providers, push-notification providers, relay and voice infrastructure providers, and other technical service partners bound by strict confidentiality oaths',
        'Legal Authorities: when required by law or when necessary to protect the safety, rights, and security of our subjects and our realm',
        "Business Succession: in the event of a merger, acquisition, restructuring, or transfer of the kingdom's operations, your information may pass to the lawful successor",
      ],
    ),
    LegalSection(
      title: 'V. The Fortress - Data Security',
      paragraphs: <String>[
        'We employ robust fortifications to protect your information, including:',
      ],
      bullets: <String>[
        'encryption of protected data in transit',
        'encryption of cryptographic materials and protected media where our defenses call for it',
        'secure authentication and app-lock protections',
        'limited access to sensitive information on a need-to-know basis',
        'regular review and reinforcement of our defenses',
      ],
    ),
    LegalSection(
      title: 'VI. Your Royal Rights',
      paragraphs: <String>[
        'As a subject of our kingdom, you possess the following rights:',
      ],
      bullets: <String>[
        'Right of Access: request a copy of the information we hold about you',
        'Right of Correction: request correction of inaccurate information',
        'Right of Deletion: request the removal of your personal data from our archives',
        'Right of Portability: receive your data in a structured, commonly used format where applicable',
        'Right to Withdraw: opt out of certain data processing activities',
        'Right to Object: object to processing of your personal information in certain circumstances',
      ],
    ),
    LegalSection(
      title: 'VII. The Cookies of the Court',
      paragraphs: <String>[
        "The Vault mobile app does not rely on traditional browser cookies to function. However, if you access a web experience, hosted support page, or privacy page belonging to the Court, the kingdom may use cookies, local storage, or similar browser tokens for purposes such as:",
      ],
      bullets: <String>[
        'Essential Tokens: required for the basic functioning of the web experience',
        'Preference Tokens: remember your settings and choices',
        "Analytics Tokens: help us understand how subjects use our web properties",
      ],
    ),
    LegalSection(
      title: 'VIII. The Young Nobles',
      paragraphs: <String>[
        'The Vault is not directed to children under 13, and we do not knowingly collect personal information from children under 13. If we discover that a young noble has provided us with personal information in violation of applicable law, we will take swift action to remove it from our archives.',
      ],
    ),
    LegalSection(
      title: 'IX. Retention of the Scrolls',
      paragraphs: <String>[
        'We retain your personal information only for as long as necessary to fulfill the purposes described in this Covenant, to operate the Vault, to meet legal obligations, or to resolve disputes and enforce our agreements. Certain delivery envelopes and relay records may be retained temporarily until messages are delivered, acknowledged, expired, or no longer needed. When information is no longer required, it shall be securely destroyed or anonymized where appropriate.',
      ],
    ),
    LegalSection(
      title: 'X. Amendments to This Covenant',
      paragraphs: <String>[
        'This Privacy Covenant may be updated from time to time to reflect changes in our practices, technologies, or legal obligations. Significant changes will be announced through our official channels, and the updated date will be reflected at the top of this document.',
      ],
    ),
    LegalSection(
      title: 'XI. Contacting the Royal Guard',
      paragraphs: <String>[
        'For questions, concerns, or to exercise your privacy rights, you may contact our Privacy Steward at:',
        'privacy@theconquerorscourt.com',
        'Or reach us at:',
        'contact@theconquerorscourt.com',
      ],
    ),
    LegalSection(
      title: 'XII. California Subjects',
      paragraphs: <String>[
        'If you are a resident of the Kingdom of California, you may have additional rights under the California Consumer Privacy Act and related laws. You may request disclosure of the categories and specific pieces of personal information we have collected about you, and you may request deletion of your personal information, subject to lawful exceptions. We do not sell personal information, and we do not share personal information for cross-context behavioral advertising as those terms are defined by applicable California law.',
      ],
    ),
  ],
  closingLine: 'Sealed by the authority of The Vault',
);

const vaultTermsOfServiceDocument = LegalDocument(
  title: 'The Covenant of Use',
  subtitle: 'The Covenant of Use',
  lastUpdated: 'April 4, 2026',
  sections: <LegalSection>[
    LegalSection(
      title: 'I. The Oath of Entry',
      paragraphs: <String>[
        'Welcome to The Vault. By entering the Court, installing the app, or using any of its messaging, calling, or media features, you agree to be bound by this Covenant of Use.',
        'If you do not accept these terms, you must not use the Vault.',
      ],
    ),
    LegalSection(
      title: 'II. Who May Enter the Vault',
      paragraphs: <String>[
        'You may use the Vault only if you are legally permitted to do so under the laws that govern you and if you are old enough to consent to these terms in your jurisdiction.',
        'You are responsible for the devices, accounts, and persons through which you access the Vault.',
      ],
    ),
    LegalSection(
      title: 'III. Your Identity and Your Devices',
      paragraphs: <String>[
        'You may choose the display name and identifiers by which you are known within the Court. You are responsible for keeping your devices, app locks, PINs, and recovery materials secure.',
        'If you lose control of a device or knowingly share access with another person, you assume the risks that follow from that choice.',
      ],
    ),
    LegalSection(
      title: 'IV. The Messages and Media You Send',
      paragraphs: <String>[
        'The Vault allows you to send messages, attachments, stickers, voice notes, and calling signals. You retain responsibility for what you send, store, or share through the service.',
      ],
      bullets: <String>[
        'you must have the right to share any content you send',
        'you must not use the Vault to harass, threaten, impersonate, extort, or exploit others',
        'you must not send unlawful, abusive, fraudulent, or infringing content through the service',
      ],
    ),
    LegalSection(
      title: 'V. Forbidden Conduct Within the Court',
      paragraphs: <String>[
        'You may not misuse the Vault or its infrastructure. Forbidden conduct includes, without limitation:',
      ],
      bullets: <String>[
        'attempting to break, reverse engineer, overload, or interfere with the service or its security features',
        'using automation, scraping, or abusive traffic to disrupt other users or the relay',
        'sending malware, exploit payloads, or deceptive files',
        'using the service to violate another person’s privacy, safety, or legal rights',
      ],
    ),
    LegalSection(
      title: 'VI. The Vault\'s Protections and Their Limits',
      paragraphs: <String>[
        'We build the Vault to protect communications, but no earthly system can promise invulnerability. Service interruptions, software defects, compromised devices, hostile networks, and user error can all weaken the protections of the realm.',
        'Where Vault-protected messaging is active, message content is intended to be encrypted in transit. Even so, the operation of the service may still require the handling of certain routing, timing, device, and delivery metadata.',
      ],
    ),
    LegalSection(
      title: 'VII. Feedback, Suggestions, and Petitions',
      paragraphs: <String>[
        'If you submit feedback, ideas, bug reports, or suggestions to the Court, you grant us permission to review and use them to improve the Vault without owing compensation to you.',
        'If you choose to submit feedback anonymously, we may be unable to respond directly to you.',
      ],
    ),
    LegalSection(
      title: 'VIII. Suspension, Banishment, and Departure',
      paragraphs: <String>[
        'We may limit, suspend, or terminate access to the Vault if we reasonably believe you have violated this Covenant, endangered the service, or used the Court for unlawful or abusive ends.',
        'You may stop using the Vault at any time. Removal of the app from your device does not necessarily erase data already stored on your device or already transmitted to other recipients.',
      ],
    ),
    LegalSection(
      title: 'IX. Changes to the Court',
      paragraphs: <String>[
        'We may alter, improve, pause, or remove features of the Vault from time to time. We may also amend this Covenant as the service evolves or as law requires.',
        'When material changes are made, the updated date shall be changed and the revised Covenant shall govern future use.',
      ],
    ),
    LegalSection(
      title: 'X. Disclaimers of Warranty',
      paragraphs: <String>[
        'To the fullest extent permitted by law, the Vault is provided on an "as is" and "as available" basis. We do not promise uninterrupted availability, perfect delivery, flawless security, or freedom from defects.',
      ],
    ),
    LegalSection(
      title: 'XI. Limits of Liability',
      paragraphs: <String>[
        'To the fullest extent permitted by law, The Conqueror\'s Court and its operators shall not be liable for indirect, incidental, consequential, special, exemplary, or punitive damages arising from or related to your use of the Vault.',
        'Nothing in this Covenant excludes liability that cannot lawfully be excluded under applicable law.',
      ],
    ),
    LegalSection(
      title: 'XII. Contacting the Court',
      paragraphs: <String>[
        'For questions about this Covenant of Use, you may contact the Court at:',
        'contact@theconquerorscourt.com',
      ],
    ),
  ],
  closingLine: 'Sealed by the authority of The Vault',
);
