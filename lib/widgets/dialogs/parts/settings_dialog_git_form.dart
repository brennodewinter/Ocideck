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

  /// De identiteit waaronder het token in de sleutelhanger staat.
  static String identityOf(String baseUrl, String owner) => '$baseUrl|$owner';

  void adoptFrom(GitRepoConfig? git) {
    url.text = git?.baseUrl ?? '';
    owner.text = git?.owner ?? '';
    repo.text = git?.repo ?? '';
    trusted = git?.trustedInternal ?? false;
    provider = git?.provider ?? GitProvider.gitea;
    token.rememberIdentity(identityOf(git?.baseUrl ?? '', git?.owner ?? ''));
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
    );
  }

  /// Config bij de instellingen, token in de sleutelhanger — dat tweede alleen
  /// wanneer het écht nodig is (D2, §10.1).
  void save(SettingsNotifier notifier) {
    final current = config;
    if (!current.isConfigured) {
      notifier.setGitRepo(null);
      return;
    }
    notifier.setGitRepo(current);
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
