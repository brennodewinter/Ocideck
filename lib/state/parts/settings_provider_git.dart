// Part of the settings_provider library — see ../settings_provider.dart.
// Split out for navigability (de git-repository als deck-bron); alle imports
// leven in het hoofdbestand.
part of '../settings_provider.dart';

/// De git-repository als deck-bron. Spiegelt bewust [setWebdavServer] en
/// [readWebdavPassword]: de configuratie mag in prefs, het geheim nooit.
extension SettingsNotifierGit on SettingsNotifier {
  /// Bewaar het personal access token in de keychain, gekeyd op de repo. Een
  /// leeg token wist de entry: een publieke repo lezen mag zonder. Geeft `true`
  /// bij succes — spiegelt daarmee [setWebdavPassword] en [setS3SecretKey].
  Future<bool> writeGitToken(String baseUrl, String owner, String token) async {
    try {
      if (token.isEmpty) {
        await _secrets.deleteGitToken(baseUrl, owner);
      } else {
        await _secrets.writeGitToken(baseUrl, owner, token);
      }
      return true;
    } catch (e) {
      // Nooit laten ontsnappen als onafgevangen async-fout: een setter wordt
      // vanuit een onChanged aangeroepen die niets afwacht. Wél melden — een
      // stil verloren token kost de gebruiker later een zoektocht.
      _reportSecretFailure('writeGitToken', e);
      return false;
    }
  }

  Future<String?> readGitToken(String baseUrl, String owner) =>
      _secrets.readGitToken(baseUrl, owner);
}
