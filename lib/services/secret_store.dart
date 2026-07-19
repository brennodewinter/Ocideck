import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/log.dart';

/// Eén plek voor app-geheimen in de OS-keychain (macOS/iOS Keychain, op andere
/// platforms de veilige backend van `flutter_secure_storage`). De rest van de
/// app hoeft zo niets van de keychain te weten en er belandt nooit een geheim
/// in het onversleutelde prefs-domein.
///
/// Bewaart het WebDAV/Nextcloud-app-wachtwoord, de optionele API-sleutel van een
/// AI-backend, en het personal access token van een git-forge. Elke sleutel is
/// afgeleid van de genormaliseerde server-URL plus de identiteit erbinnen
/// (gebruiker, respectievelijk repo-eigenaar), zodat meerdere accounts en
/// servers naast elkaar kunnen bestaan zonder elkaar te overschrijven.
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

  /// Keychain-sleutel voor de optionele API-sleutel van een AI-backend, gekeyd
  /// op de genormaliseerde basis-URL zodat verschillende backends naast elkaar
  /// kunnen bestaan.
  static String aiApiKeyKey(String baseUrl) {
    final normalized = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return 'ai_api_key::$normalized';
  }

  Future<void> writeAiApiKey(String baseUrl, String apiKey) async {
    try {
      await _storage.write(key: aiApiKeyKey(baseUrl), value: apiKey);
    } catch (e) {
      logError('SecretStore.writeAiApiKey: keychain write failed', e);
      rethrow;
    }
  }

  Future<String?> readAiApiKey(String baseUrl) async {
    try {
      return await _storage.read(key: aiApiKeyKey(baseUrl));
    } catch (e) {
      logError('SecretStore.readAiApiKey: keychain read failed', e);
      return null;
    }
  }

  Future<void> deleteAiApiKey(String baseUrl) async {
    try {
      await _storage.delete(key: aiApiKeyKey(baseUrl));
    } catch (e) {
      logWarning('SecretStore.deleteAiApiKey: keychain delete failed', e);
    }
  }

  /// Keychain-sleutel voor de secret access key van een S3-bron, gekeyd op het
  /// genormaliseerde endpoint plus de access key id. Twee buckets op hetzelfde
  /// endpoint met dezelfde sleutel delen daardoor één entry, wat klopt: het ís
  /// dezelfde sleutel.
  static String s3SecretKeyKey(String endpoint, String accessKeyId) {
    final normalized = endpoint.trim().replaceAll(RegExp(r'/+$'), '');
    return 's3_secret::$normalized::${accessKeyId.trim()}';
  }

  Future<void> writeS3SecretKey(
    String endpoint,
    String accessKeyId,
    String secretKey,
  ) async {
    try {
      await _storage.write(
        key: s3SecretKeyKey(endpoint, accessKeyId),
        value: secretKey,
      );
    } catch (e) {
      logError('SecretStore.writeS3SecretKey: keychain write failed', e);
      rethrow;
    }
  }

  Future<String?> readS3SecretKey(String endpoint, String accessKeyId) async {
    try {
      return await _storage.read(key: s3SecretKeyKey(endpoint, accessKeyId));
    } catch (e) {
      logError('SecretStore.readS3SecretKey: keychain read failed', e);
      return null;
    }
  }

  Future<void> deleteS3SecretKey(String endpoint, String accessKeyId) async {
    try {
      await _storage.delete(key: s3SecretKeyKey(endpoint, accessKeyId));
    } catch (e) {
      // Wissen mag nooit fataal zijn: log en ga door.
      logWarning('SecretStore.deleteS3SecretKey: keychain delete failed', e);
    }
  }

  /// Keychain-sleutel voor het personal access token van een git-forge, gekeyd
  /// op genormaliseerde basis-URL + eigenaar. Eén token per repo-eigenaar, zodat
  /// een account op twee forges — of twee organisaties op één forge — naast
  /// elkaar kunnen bestaan.
  static String gitTokenKey(String baseUrl, String owner) {
    final normalized = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return 'git_pat::$normalized::${owner.trim()}';
  }

  Future<void> writeGitToken(String baseUrl, String owner, String token) async {
    try {
      await _storage.write(key: gitTokenKey(baseUrl, owner), value: token);
    } catch (e) {
      logError('SecretStore.writeGitToken: keychain write failed', e);
      rethrow;
    }
  }

  Future<String?> readGitToken(String baseUrl, String owner) async {
    try {
      return await _storage.read(key: gitTokenKey(baseUrl, owner));
    } catch (e) {
      logError('SecretStore.readGitToken: keychain read failed', e);
      return null;
    }
  }

  Future<void> deleteGitToken(String baseUrl, String owner) async {
    try {
      await _storage.delete(key: gitTokenKey(baseUrl, owner));
    } catch (e) {
      // Wissen mag nooit fataal zijn: log en ga door.
      logWarning('SecretStore.deleteGitToken: keychain delete failed', e);
    }
  }
}
