// De invulstand van de Nextcloud-bron: de velden, de uitslag van de
// verbindingstest en het wachtwoord. Hiervóór lagen die dertien velden los in
// _SettingsDialogState, tussen de drieënzestig van alle andere onderwerpen —
// waardoor je ze alle drieënzestig in beeld moest hebben om er hier één te
// veranderen.
//
// Bewust geen gedeelde basisklasse met git en de AI-backend. Ze lijken van
// buiten op elkaar, maar wat ze bewaren verschilt reëel (hier een submap, bij
// git een forge en een eigenaar), en dat in één type persen levert een
// basisklasse op met gaten. Alleen de sleutelhanger-boekhouding is gedeeld —
// zie [KeychainSecret], want dáár is een fout duur.
import 'package:flutter/widgets.dart';

import '../../../models/webdav_settings.dart';
import '../../../state/settings_provider.dart';
import 'keychain_secret.dart';

/// Wat het Nextcloud-paneel aan het bewerken is, tot Opslaan of Annuleren.
class WebdavForm {
  final TextEditingController url = TextEditingController();
  final TextEditingController user = TextEditingController();
  final TextEditingController root = TextEditingController();
  final KeychainSecret password = KeychainSecret();

  /// Nodig wanneer de server op een privé- of thuisnetwerk draait; zonder deze
  /// vlag weigert de SSRF-beveiliging de verbinding.
  bool trusted = false;

  /// Welk padschema de server voert. Bepaalt of de server-URL alleen de
  /// origin mag zijn (Nextcloud leidt het pad af) of juist de hele DAV-wortel.
  WebdavServerKind kind = WebdavServerKind.nextcloud;

  /// De vingerafdruk van het certificaat dat de gebruiker heeft vertrouwd, of
  /// leeg. Geen invoerveld: die vult zich alleen via de bevestigingsdialoog,
  /// want een vingerafdruk overtypen is geen bewuste keuze maar een klus.
  String pinnedCertSha256 = '';

  /// De laatste test strandde op het certificaat. Alleen dán heeft het zin de
  /// gebruiker te vragen of hij het wil vertrouwen.
  bool testCertRejected = false;

  /// Uitslag van de verbindingstest: `null` = nog niet getest.
  bool? testOk;
  String? testMessage;
  bool testing = false;

  /// De identiteit waaronder het wachtwoord in de sleutelhanger staat.
  static String identityOf(String baseUrl, String username) =>
      '$baseUrl|$username';

  void adoptFrom(WebdavServer? server) {
    url.text = server?.baseUrl ?? '';
    user.text = server?.username ?? '';
    root.text = server?.rootPath ?? '';
    trusted = server?.trustedInternal ?? false;
    kind = server?.kind ?? WebdavServerKind.nextcloud;
    pinnedCertSha256 = server?.pinnedCertSha256 ?? '';
    password.rememberIdentity(
      identityOf(server?.baseUrl ?? '', server?.username ?? ''),
    );
  }

  /// De server zoals hij nu in de velden staat.
  WebdavServer get server {
    var base = url.text.trim();
    // "cloud.example.com" zonder schema is de meest gemaakte invoerfout;
    // vul https:// aan i.p.v. later op een ongeldige URL te stranden.
    if (base.isNotEmpty && !base.contains('://')) base = 'https://$base';
    return WebdavServer(
      baseUrl: base,
      username: user.text.trim(),
      rootPath: WebdavServer.normalizeRoot(root.text),
      trustedInternal: trusted,
      kind: kind,
      pinnedCertSha256: pinnedCertSha256,
    );
  }

  /// Zet het wachtwoord in de sleutelhanger, en alleen wanneer het écht nodig
  /// is. De configuratie zelf gaat niet meer hierlangs: die is onderdeel van de
  /// verbindingenlijst, die het opslag-tabblad in één keer wegschrijft.
  void saveSecret(SettingsNotifier notifier) {
    final current = server;
    if (!current.isConfigured) return;
    if (password.shouldWrite(identityOf(current.baseUrl, current.username))) {
      notifier.setWebdavPassword(
        current.baseUrl,
        current.username,
        password.field.text,
      );
    }
  }

  void dispose() {
    url.dispose();
    user.dispose();
    root.dispose();
    password.dispose();
  }
}
