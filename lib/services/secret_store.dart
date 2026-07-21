import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/log.dart';

/// Of dit platform een sleutelbos heeft waar een geheim werkelijk veilig in kan.
///
/// **Op het web is dat er niet, en dat is geen detail.** De webkant van
/// `flutter_secure_storage` versleutelt met AES-GCM, maar bewaart de sleutel —
/// zonder `WebOptions.wrapKey` — met `exportKey('raw')` in diezelfde
/// `localStorage` als de cijfertekst. Sleutel en slot in één la: elk script op
/// die pagina leest het geheim terug. Een git-token, een S3-secret, een
/// WebDAV-wachtwoord of een AI-sleutel is daar dus niet beschermd, hoe het ook
/// heet.
///
/// Daarom slaat OciDeck op het web geen enkel geheim op. Weigeren is hier de
/// eerlijke uitkomst: het alternatief is een belofte die de opslag niet waar
/// kan maken, en `docs/PRIVACY.md` doet die belofte met zoveel woorden.
bool get platformCanStoreSecrets => !kIsWeb;

/// Wordt geworpen wanneer er een geheim weggeschreven wordt op een platform
/// zonder sleutelbos. Draagt geen geheim mee — alleen wélk geheim het betrof.
class SecretStoreUnsupported implements Exception {
  const SecretStoreUnsupported(this.label);

  /// De aanroep die geweigerd is, bijvoorbeeld `writeGitToken`. Nooit de waarde.
  final String label;

  @override
  String toString() =>
      'SecretStoreUnsupported: $label — dit platform heeft geen sleutelbos';
}

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
///
/// **Fail-closed zonder sleutelbos** (zie [platformCanStoreSecrets]). Deze
/// klasse is de enige plek waar dat hoeft te worden afgedwongen, want ze is de
/// enige weg naar de opslag:
///
///   * schrijven werpt [SecretStoreUnsupported] — nooit stilzwijgend elders
///     neerzetten;
///   * lezen geeft `null`, want er staat werkelijk niets;
///   * wissen doet niets en slaagt, want er valt niets te wissen.
///
/// De interface vraagt [platformCanStoreSecrets] zélf op en zegt het vooraf;
/// deze laag is het vangnet, niet de melding.
class SecretStore {
  SecretStore({FlutterSecureStorage? storage, bool? canStore})
    : _storage = storage ?? const FlutterSecureStorage(),
      _canStore = canStore ?? platformCanStoreSecrets;

  final FlutterSecureStorage _storage;

  /// Injecteerbaar, zodat de weigering toetsbaar is zonder een webbrowser.
  final bool _canStore;

  /// Of geheimen op dit platform bewaard kunnen worden.
  bool get canStore => _canStore;

  /// De poort vóór elke schrijfactie.
  void _requireStorage(String label) {
    if (!_canStore) throw SecretStoreUnsupported(label);
  }

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
    _requireStorage('writeWebdavPassword');
    try {
      await _storage.write(key: webdavKey(baseUrl, username), value: password);
    } catch (e) {
      logError('SecretStore.writeWebdavPassword: keychain write failed', e);
      rethrow;
    }
  }

  Future<String?> readWebdavPassword(String baseUrl, String username) async {
    if (!_canStore) return null;
    try {
      return await _storage.read(key: webdavKey(baseUrl, username));
    } catch (e) {
      logError('SecretStore.readWebdavPassword: keychain read failed', e);
      return null;
    }
  }

  Future<void> deleteWebdavPassword(String baseUrl, String username) async {
    if (!_canStore) return;
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
    _requireStorage('writeAiApiKey');
    try {
      await _storage.write(key: aiApiKeyKey(baseUrl), value: apiKey);
    } catch (e) {
      logError('SecretStore.writeAiApiKey: keychain write failed', e);
      rethrow;
    }
  }

  Future<String?> readAiApiKey(String baseUrl) async {
    if (!_canStore) return null;
    try {
      return await _storage.read(key: aiApiKeyKey(baseUrl));
    } catch (e) {
      logError('SecretStore.readAiApiKey: keychain read failed', e);
      return null;
    }
  }

  Future<void> deleteAiApiKey(String baseUrl) async {
    if (!_canStore) return;
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
    _requireStorage('writeS3SecretKey');
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
    if (!_canStore) return null;
    try {
      return await _storage.read(key: s3SecretKeyKey(endpoint, accessKeyId));
    } catch (e) {
      logError('SecretStore.readS3SecretKey: keychain read failed', e);
      return null;
    }
  }

  Future<void> deleteS3SecretKey(String endpoint, String accessKeyId) async {
    if (!_canStore) return;
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
    _requireStorage('writeGitToken');
    try {
      await _storage.write(key: gitTokenKey(baseUrl, owner), value: token);
    } catch (e) {
      logError('SecretStore.writeGitToken: keychain write failed', e);
      rethrow;
    }
  }

  Future<String?> readGitToken(String baseUrl, String owner) async {
    if (!_canStore) return null;
    try {
      return await _storage.read(key: gitTokenKey(baseUrl, owner));
    } catch (e) {
      logError('SecretStore.readGitToken: keychain read failed', e);
      return null;
    }
  }

  Future<void> deleteGitToken(String baseUrl, String owner) async {
    if (!_canStore) return;
    try {
      await _storage.delete(key: gitTokenKey(baseUrl, owner));
    } catch (e) {
      // Wissen mag nooit fataal zijn: log en ga door.
      logWarning('SecretStore.deleteGitToken: keychain delete failed', e);
    }
  }
}
