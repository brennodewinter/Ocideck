// Part of the settings_dialog library — see ../settings_dialog.dart.
//
// De invulstand van de git-bron. Spiegelt [WebdavForm], en net als daar zonder
// gedeelde basisklasse: git bewaart een forge, een eigenaar en een repository
// waar Nextcloud een submap heeft, en de sleutelhangersleutel is hier
// URL|eigenaar in plaats van URL|gebruiker. Wat écht hetzelfde is — de vraag of
// het geheim moet worden weggeschreven — zit in [KeychainSecret].
part of '../settings_dialog.dart';

/// Wat het git-paneel aan het bewerken is, tot Opslaan of Annuleren.
class GitForm {
  final TextEditingController url = TextEditingController();
  final TextEditingController owner = TextEditingController();
  final TextEditingController repo = TextEditingController();
  final KeychainSecret token = KeychainSecret();

  /// Nodig wanneer de forge op een privé- of thuisnetwerk draait.
  bool trusted = false;

  /// De soort forge bepaalt welke adapter erachter komt: de REST-API's
  /// verschillen te veel om aan de URL te raden.
  GitProvider provider = GitProvider.gitea;

  /// De branch waarop gewerkt wordt. Er is bewust géén invoerveld voor: welke
  /// branch de standaard is, weet de forge zelf beter dan de gebruiker. De
  /// verbindingstest haalt hem op en zet hem hier neer — dat is de enige manier
  /// waarop een repo met `master` in plaats van `main` ooit werkt.
  String defaultBranch = const GitRepoConfig(
    baseUrl: '',
    owner: '',
    repo: '',
  ).defaultBranch;

  /// De vingerafdruk van het certificaat dat de gebruiker heeft vertrouwd, of
  /// leeg. Geen invoerveld: die vult zich alleen via de bevestigingsdialoog.
  String pinnedCertSha256 = '';

  /// De laatste test strandde op het certificaat. Alleen dán heeft het zin de
  /// gebruiker te vragen of hij het wil vertrouwen.
  bool testCertRejected = false;

  /// Uitslag van de verbindingstest: `null` = nog niet getest.
  bool? testOk;
  String? testMessage;
  bool testing = false;

  /// De test slaagde, maar er is iets dat later pijn gaat doen — een token dat
  /// alleen mag lezen. Geen fout (de verbinding wérkt), en toch niet groen:
  /// een vinkje zou beloven dat opslaan straks lukt.
  bool testWarning = false;

  /// De identiteit waaronder het token in de sleutelhanger staat.
  static String identityOf(String baseUrl, String owner) => '$baseUrl|$owner';

  void adoptFrom(GitRepoConfig? git) {
    url.text = git?.baseUrl ?? '';
    owner.text = git?.owner ?? '';
    repo.text = git?.repo ?? '';
    trusted = git?.trustedInternal ?? false;
    provider = git?.provider ?? GitProvider.gitea;
    if (git != null) defaultBranch = git.defaultBranch;
    pinnedCertSha256 = git?.pinnedCertSha256 ?? '';
    token.rememberIdentity(identityOf(git?.baseUrl ?? '', git?.owner ?? ''));
  }

  /// Wis de uitslag. Aanroepen zodra iets verandert dat de test ongeldig maakt:
  /// een oude groene vink bij een nieuwe server is erger dan geen vink.
  void clearTestResult() {
    testOk = null;
    testMessage = null;
    testWarning = false;
    testCertRejected = false;
  }

  /// De repo zoals hij nu in de velden staat. Vult een ontbrekend schema aan:
  /// "git.example.org" zonder `https://` is de meest gemaakte invoerfout, en
  /// stranden op een onparseerbare URL is een slechter antwoord dan aanvullen.
  GitRepoConfig get config {
    var base = url.text.trim();
    if (base.isNotEmpty && !base.contains('://')) base = 'https://$base';
    return GitRepoConfig(
      baseUrl: base,
      owner: owner.text.trim(),
      repo: repo.text.trim(),
      trustedInternal: trusted,
      provider: provider,
      defaultBranch: defaultBranch,
      pinnedCertSha256: pinnedCertSha256,
    );
  }

  /// Token in de sleutelhanger, en alleen wanneer het écht nodig is (D2,
  /// §10.1). De configuratie zelf loopt via de verbindingenlijst.
  void saveSecret(SettingsNotifier notifier) {
    final current = config;
    if (!current.isConfigured) return;
    if (token.shouldWrite(identityOf(current.baseUrl, current.owner))) {
      notifier.writeGitToken(current.baseUrl, current.owner, token.field.text);
    }
  }

  void dispose() {
    url.dispose();
    owner.dispose();
    repo.dispose();
    token.dispose();
  }
}
