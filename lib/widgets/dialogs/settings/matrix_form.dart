// De invulstand van het Matrix-samenwerkaccount. Spiegelt [GitForm]: de
// niet-geheime configuratie (homeserver, user-id, device-id, de SSRF-houding)
// gaat naar de instellingen, het access-token via [KeychainSecret] versleuteld
// naar de sleutelhanger. De sleutelhangersleutel is hier `homeserver|user-id`,
// gelijk aan wat `SettingsNotifier.setMatrixToken`/`matrixToken` gebruikt.
//
// Anders dan git bewaart dit één account (app-globaal, geen lijst), en het
// device-id is niet vrij te kiezen: het moet het device-id van het token zijn,
// want de sleutel-uitwisseling adresseert een to-device-bericht op
// `user-id:device-id` (SELF_ENCRYPTED_RELAY.md §4.3). Daarom vult de
// verbindingstest het uit `whoami` in plaats van het de gebruiker te laten raden.
import 'package:flutter/widgets.dart';

import '../../../models/matrix_settings.dart';
import '../../../state/settings_provider.dart';
import 'keychain_secret.dart';

/// Wat het Matrix-paneel aan het bewerken is, tot Opslaan of Annuleren.
class MatrixForm {
  final TextEditingController homeserver = TextEditingController();
  final TextEditingController userId = TextEditingController();
  final TextEditingController deviceId = TextEditingController();
  final KeychainSecret token = KeychainSecret();

  /// Nodig wanneer de homeserver op een privé- of thuisnetwerk draait.
  bool trusted = false;

  /// De vingerafdruk van het certificaat dat de gebruiker heeft vertrouwd, of
  /// leeg. Geen invoerveld: die vult zich alleen via de bevestigingsdialoog.
  String pinnedCertSha256 = '';

  /// Uitslag van de verbindingstest: `null` = nog niet getest.
  bool? testOk;
  String? testMessage;
  bool testing = false;

  /// De identiteit waaronder het token in de sleutelhanger staat.
  static String identityOf(String homeserver, String userId) =>
      '$homeserver|$userId';

  void adoptFrom(MatrixServer? account) {
    homeserver.text = account?.homeserverUrl ?? '';
    userId.text = account?.userId ?? '';
    deviceId.text = account?.deviceId ?? '';
    trusted = account?.trustedInternal ?? false;
    pinnedCertSha256 = account?.pinnedCertSha256 ?? '';
    token.rememberIdentity(
      identityOf(account?.homeserverUrl ?? '', account?.userId ?? ''),
    );
  }

  /// Wis de uitslag. Aanroepen zodra iets verandert dat de test ongeldig maakt.
  void clearTestResult() {
    testOk = null;
    testMessage = null;
  }

  /// Het account zoals het nu in de velden staat. Vult een ontbrekend schema aan:
  /// "matrix.example.org" zonder `https://` is de meest gemaakte invoerfout, en
  /// stranden op een onparseerbare URL is een slechter antwoord dan aanvullen.
  MatrixServer get config {
    var base = homeserver.text.trim();
    if (base.isNotEmpty && !base.contains('://')) base = 'https://$base';
    return MatrixServer(
      homeserverUrl: base,
      userId: userId.text.trim(),
      deviceId: deviceId.text.trim(),
      trustedInternal: trusted,
      pinnedCertSha256: pinnedCertSha256,
    );
  }

  /// Token in de sleutelhanger, en alleen wanneer het écht nodig is (§8, §10.1).
  /// De configuratie zelf gaat via [SettingsNotifier.setMatrixAccount]. De
  /// keychain-schrijfactie loopt door na het sluiten (fout wordt daar gelogd en
  /// via een eigen melding getoond), net als bij de git- en WebDAV-formulieren.
  void saveSecret(SettingsNotifier notifier) {
    final current = config;
    // De sleutelhanger-identiteit is homeserver|user-id; het device-id hoort er
    // niet bij en komt vaak pas ná de login terug. Daarom bewaken we hier op de
    // identiteitsvelden, niet op de (sinds #1043 device-id-strenge) isConfigured.
    if (current.homeserverUrl.trim().isEmpty || current.userId.trim().isEmpty) {
      return;
    }
    if (token.shouldWrite(identityOf(current.homeserverUrl, current.userId))) {
      notifier.setMatrixToken(
        current.homeserverUrl,
        current.userId,
        token.field.text,
      );
    }
  }

  void dispose() {
    homeserver.dispose();
    userId.dispose();
    deviceId.dispose();
    token.dispose();
  }
}
