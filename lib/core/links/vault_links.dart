class VaultLinks {
  // Swap this single URL later if you move to a hosted button or another provider.
  static const String donateUrl =
      'https://www.paypal.com/biz/profile/varnoksystemsllc';
  static const String donateLabel =
      'Donate to The Vault • premium features later';
  static const String downloadSiteUrl = 'https://vault.theconquerorscourt.com/';
  static const String siteCertSha256 = String.fromEnvironment(
    'VAULT_SITE_CERT_SHA256',
    defaultValue:
        '9C94315F1559FA87749E19AE6FDFBFAE058295172E23E4C4E7C791BBB49C3372',
  );
  static const String updateManifestUrl =
      '${downloadSiteUrl}downloads/latest.json';

  static const String supportEmail = 'support@theconquerorscourt.com';
}
