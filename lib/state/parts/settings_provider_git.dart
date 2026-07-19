// Part of the settings_provider library — see ../settings_provider.dart.
// Split out for navigability (de git-repository als deck-bron); alle imports
// leven in het hoofdbestand.
part of '../settings_provider.dart';

/// De git-repository als deck-bron. Spiegelt bewust [setWebdavServer] en
/// [readWebdavPassword]: de configuratie mag in prefs, het geheim nooit.
extension SettingsNotifierGit on SettingsNotifier {
  /// Bewaar het personal access token in de keychain, gekeyd op de repo. Een
  /// leeg token wist de entry: een publieke repo lezen mag zonder.
  Future<void> writeGitToken(String baseUrl, String owner, String token) async {
    try {
      if (token.isEmpty) {
        await _secrets.deleteGitToken(baseUrl, owner);
      } else {
        await _secrets.writeGitToken(baseUrl, owner, token);
      }
    } catch (e) {
      // Nooit laten ontsnappen als onafgevangen async-fout: een setter wordt
      // vanuit een onChanged aangeroepen die niets afwacht.
      logError('SettingsNotifier.writeGitToken: keychain write failed', e);
    }
  }

  Future<String?> readGitToken(String baseUrl, String owner) =>
      _secrets.readGitToken(baseUrl, owner);
}
