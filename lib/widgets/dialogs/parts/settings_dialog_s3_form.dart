// Part of the settings_dialog library — see ../settings_dialog.dart.
//
// De invulstand van een S3-bron. Volgt bewust dezelfde vorm als WebdavForm en
// GitForm — velden, uitslag van de verbindingstest, geheim — zonder gedeelde
// basisklasse, om dezelfde reden als daar: wat ze bewaren verschilt reëel (hier
// een endpoint, een regio en een adresseringsstijl) en dat in één type persen
// levert een basisklasse met gaten op. Alleen de sleutelhanger-boekhouding is
// gedeeld, via [KeychainSecret], want dáár is een fout duur.
part of '../settings_dialog.dart';

/// Wat het S3-paneel aan het bewerken is, tot Opslaan of Annuleren.
class S3Form {
  final TextEditingController endpoint = TextEditingController();
  final TextEditingController region = TextEditingController();
  final TextEditingController bucket = TextEditingController();
  final TextEditingController accessKeyId = TextEditingController();
  final TextEditingController root = TextEditingController();
  final KeychainSecret secret = KeychainSecret();

  /// Nodig wanneer het endpoint op een privé- of thuisnetwerk draait; zonder
  /// deze vlag weigert de SSRF-beveiliging de verbinding. Bij een zelf gehoste
  /// MinIO is dat het normale geval.
  bool trusted = false;

  /// Waar de bucketnaam in de URL landt. AWS wil hem vóór de host, de meeste
  /// zelf gehoste endpoints erachter.
  S3AddressingStyle addressingStyle = S3AddressingStyle.virtualHosted;

  /// Uitslag van de verbindingstest: `null` = nog niet getest.
  bool? testOk;
  String? testMessage;
  bool testing = false;

  /// De identiteit waaronder de secret access key in de sleutelhanger staat.
  static String identityOf(String endpoint, String accessKeyId) =>
      '$endpoint|$accessKeyId';

  void adoptFrom(S3Bucket? config) {
    endpoint.text = config?.endpoint ?? '';
    region.text = config?.region ?? 'us-east-1';
    bucket.text = config?.bucket ?? '';
    accessKeyId.text = config?.accessKeyId ?? '';
    root.text = config?.rootPath ?? '';
    trusted = config?.trustedInternal ?? false;
    addressingStyle =
        config?.addressingStyle ?? S3AddressingStyle.virtualHosted;
    secret.rememberIdentity(
      identityOf(config?.endpoint ?? '', config?.accessKeyId ?? ''),
    );
  }

  /// De bucketconfiguratie zoals hij nu in de velden staat.
  S3Bucket get config {
    var base = endpoint.text.trim();
    // "minio.voorbeeld.nl" zonder schema is de meest gemaakte invoerfout; vul
    // https:// aan in plaats van later op een ongeldige URL te stranden.
    if (base.isNotEmpty && !base.contains('://')) base = 'https://$base';
    final regionText = region.text.trim();
    return S3Bucket(
      endpoint: base,
      // Een leeg regioveld is geen fout: diensten die geen regio's kennen
      // accepteren us-east-1, en dat is minder vervelend dan een blokkade.
      region: regionText.isEmpty ? 'us-east-1' : regionText,
      bucket: bucket.text.trim(),
      accessKeyId: accessKeyId.text.trim(),
      rootPath: S3Bucket.normalizeRoot(root.text),
      addressingStyle: addressingStyle,
      trustedInternal: trusted,
    );
  }

  /// Zet de secret access key in de sleutelhanger, en alleen wanneer het écht
  /// nodig is. De configuratie zelf gaat niet hierlangs: die is onderdeel van
  /// de verbindingenlijst, die het opslag-tabblad in één keer wegschrijft.
  void saveSecret(SettingsNotifier notifier) {
    final current = config;
    if (!current.isConfigured) return;
    if (secret.shouldWrite(identityOf(current.endpoint, current.accessKeyId))) {
      notifier.setS3SecretKey(
        current.endpoint,
        current.accessKeyId,
        secret.field.text,
      );
    }
  }

  void dispose() {
    endpoint.dispose();
    region.dispose();
    bucket.dispose();
    accessKeyId.dispose();
    root.dispose();
    secret.dispose();
  }
}
