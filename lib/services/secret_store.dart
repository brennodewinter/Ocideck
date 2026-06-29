import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/log.dart';

/// Eén plek voor app-geheimen in de OS-keychain (macOS/iOS Keychain, op andere
/// platforms de veilige backend van `flutter_secure_storage`). De rest van de
/// app hoeft zo niets van de keychain te weten en er belandt nooit een geheim
/// in het onversleutelde prefs-domein.
///
/// Voorlopig wordt dit alleen gebruikt voor het WebDAV/Nextcloud-app-wachtwoord;
/// de sleutel is afgeleid van server-URL + gebruikersnaam zodat meerdere
/// accounts naast elkaar kunnen bestaan.
class SecretStore {
  SecretStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// Keychain-sleutel voor het WebDAV-wachtwoord van [username] op [baseUrl].
  /// Beide worden genormaliseerd zodat een triviale variatie (trailing slash,
  /// hoofdletters in de host) niet stilletjes een tweede entry maakt.
  static String webdavKey(String baseUrl, String username) {
    final normalized = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return 'webdav_pw::$normalized::${username.trim()}';
  }

  Future<void> writeWebdavPassword(
    String baseUrl,
    String username,
    String password,
  ) async {
    try {
      await _storage.write(key: webdavKey(baseUrl, username), value: password);
    } catch (e) {
      logError('SecretStore.writeWebdavPassword: keychain write failed', e);
      rethrow;
    }
  }

  Future<String?> readWebdavPassword(String baseUrl, String username) async {
    try {
      return await _storage.read(key: webdavKey(baseUrl, username));
    } catch (e) {
      logError('SecretStore.readWebdavPassword: keychain read failed', e);
      return null;
    }
  }

  Future<void> deleteWebdavPassword(String baseUrl, String username) async {
    try {
      await _storage.delete(key: webdavKey(baseUrl, username));
    } catch (e) {
      // Wissen mag nooit fataal zijn: log en ga door.
      logWarning('SecretStore.deleteWebdavPassword: keychain delete failed', e);
    }
  }
}
