// Part of the settings_dialog library — see ../settings_dialog.dart.
//
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
part of '../settings_dialog.dart';

/// Wat het Nextcloud-paneel aan het bewerken is, tot Opslaan of Annuleren.
class WebdavForm {
  final TextEditingController url = TextEditingController();
  final TextEditingController user = TextEditingController();
  final TextEditingController root = TextEditingController();
  final KeychainSecret password = KeychainSecret();

  /// Nodig wanneer de server op een privé- of thuisnetwerk draait; zonder deze
  /// vlag weigert de SSRF-beveiliging de verbinding.
  bool trusted = false;

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
    );
  }

  /// Schrijf de bron weg: config bij de instellingen, wachtwoord in de
  /// sleutelhanger — en dat tweede alleen wanneer het écht nodig is.
  void save(SettingsNotifier notifier) {
    final current = server;
    if (!current.isConfigured) {
      notifier.setWebdavServer(null);
      return;
    }
    notifier.setWebdavServer(current);
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
