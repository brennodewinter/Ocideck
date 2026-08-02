import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/storage_connection.dart';
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

  /// Keychain key for a Matrix access token, namespaced and keyed on the
  /// homeserver + user id so two accounts (or a WebDAV/git entry on the same
  /// host) never collide. The token authenticates the collaboration session
  /// (`docs/design/SELF_ENCRYPTED_RELAY.md` §8).
  static String matrixTokenKey(String homeserver, String userId) {
    final normalized = homeserver.trim().replaceAll(RegExp(r'/+$'), '');
    return 'matrix_token::$normalized::${userId.trim()}';
  }

  Future<void> writeMatrixToken(
    String homeserver,
    String userId,
    String token,
  ) async {
    _requireStorage('writeMatrixToken');
    try {
      await _storage.write(
        key: matrixTokenKey(homeserver, userId),
        value: token,
      );
    } catch (e) {
      logError('SecretStore.writeMatrixToken: keychain write failed', e);
      rethrow;
    }
  }

  Future<String?> readMatrixToken(String homeserver, String userId) async {
    if (!_canStore) return null;
    try {
      return await _storage.read(key: matrixTokenKey(homeserver, userId));
    } catch (e) {
      logError('SecretStore.readMatrixToken: keychain read failed', e);
      return null;
    }
  }

  Future<void> deleteMatrixToken(String homeserver, String userId) async {
    if (!_canStore) return;
    try {
      await _storage.delete(key: matrixTokenKey(homeserver, userId));
    } catch (e) {
      logWarning('SecretStore.deleteMatrixToken: keychain delete failed', e);
    }
  }

  /// Keychain key for an XMPP account password, keyed on the WebSocket endpoint +
  /// bare JID so two accounts/servers never collide (F2, `NATIVE_CALLS.md` §5).
  /// The password authenticates the XMPP stream (SASL); it never touches prefs.
  static String xmppPasswordKey(String serverUrl, String jid) {
    final normalized = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return 'xmpp_password::$normalized::${jid.trim()}';
  }

  Future<void> writeXmppPassword(
    String serverUrl,
    String jid,
    String password,
  ) async {
    _requireStorage('writeXmppPassword');
    try {
      await _storage.write(
        key: xmppPasswordKey(serverUrl, jid),
        value: password,
      );
    } catch (e) {
      logError('SecretStore.writeXmppPassword: keychain write failed', e);
      rethrow;
    }
  }

  Future<String?> readXmppPassword(String serverUrl, String jid) async {
    if (!_canStore) return null;
    try {
      return await _storage.read(key: xmppPasswordKey(serverUrl, jid));
    } catch (e) {
      logError('SecretStore.readXmppPassword: keychain read failed', e);
      return null;
    }
  }

  Future<void> deleteXmppPassword(String serverUrl, String jid) async {
    if (!_canStore) return;
    try {
      await _storage.delete(key: xmppPasswordKey(serverUrl, jid));
    } catch (e) {
      logWarning('SecretStore.deleteXmppPassword: keychain delete failed', e);
    }
  }

  /// Keychain key for the collaboration **device key material** (the Ed25519
  /// identity + X25519 agreement seeds), keyed on the homeserver + user id. These
  /// private seeds must never touch the prefs domain (§4.3); losing them only
  /// costs a device its identity, which re-onboarding regenerates.
  static String collabDeviceSeedsKey(String homeserver, String userId) {
    final normalized = homeserver.trim().replaceAll(RegExp(r'/+$'), '');
    return 'collab_devseeds::$normalized::${userId.trim()}';
  }

  Future<void> writeCollabDeviceSeeds(
    String homeserver,
    String userId,
    String seeds,
  ) async {
    _requireStorage('writeCollabDeviceSeeds');
    try {
      await _storage.write(
        key: collabDeviceSeedsKey(homeserver, userId),
        value: seeds,
      );
    } catch (e) {
      logError('SecretStore.writeCollabDeviceSeeds: keychain write failed', e);
      rethrow;
    }
  }

  Future<String?> readCollabDeviceSeeds(
    String homeserver,
    String userId,
  ) async {
    if (!_canStore) return null;
    try {
      return await _storage.read(key: collabDeviceSeedsKey(homeserver, userId));
    } catch (e) {
      logError('SecretStore.readCollabDeviceSeeds: keychain read failed', e);
      return null;
    }
  }

  Future<void> deleteCollabDeviceSeeds(String homeserver, String userId) async {
    if (!_canStore) return;
    try {
      await _storage.delete(key: collabDeviceSeedsKey(homeserver, userId));
    } catch (e) {
      logWarning(
        'SecretStore.deleteCollabDeviceSeeds: keychain delete failed',
        e,
      );
    }
  }

  /// Keychain key for the collaboration **device trust store**: the peer
  /// identity keys this local account has pinned as verified (trust-on-first-use,
  /// SELF_ENCRYPTED_RELAY §5.3, COLLABORATION Phase 2 Blok A). Keyed on the local
  /// homeserver + user id, so each account keeps its own pins.
  ///
  /// Unlike the device seeds these values are **public** keys, not secrets — but
  /// they are co-located in the keychain so the collaboration layer has one
  /// persistence mechanism rather than two, and so a pin cannot be silently
  /// rewritten from the plain prefs domain.
  static String collabTrustKey(String homeserver, String userId) {
    final normalized = homeserver.trim().replaceAll(RegExp(r'/+$'), '');
    return 'collab_trust::$normalized::${userId.trim()}';
  }

  Future<void> writeCollabTrust(
    String homeserver,
    String userId,
    String trust,
  ) async {
    _requireStorage('writeCollabTrust');
    try {
      await _storage.write(
        key: collabTrustKey(homeserver, userId),
        value: trust,
      );
    } catch (e) {
      logError('SecretStore.writeCollabTrust: keychain write failed', e);
      rethrow;
    }
  }

  Future<String?> readCollabTrust(String homeserver, String userId) async {
    if (!_canStore) return null;
    try {
      return await _storage.read(key: collabTrustKey(homeserver, userId));
    } catch (e) {
      logError('SecretStore.readCollabTrust: keychain read failed', e);
      return null;
    }
  }

  Future<void> deleteCollabTrust(String homeserver, String userId) async {
    if (!_canStore) return;
    try {
      await _storage.delete(key: collabTrustKey(homeserver, userId));
    } catch (e) {
      logWarning('SecretStore.deleteCollabTrust: keychain delete failed', e);
    }
  }

  /// Keychain-sleutel voor "je eigen gegevens" van de privacycontrole.
  ///
  /// Eén entry, want het gaat over de gebruiker van deze installatie en niet
  /// over een server. Geen wachtwoord, maar wel het enige veld in de
  /// instellingen dat naam, e-mailadres en telefoonnummer van een natuurlijke
  /// persoon bevat — en dat hoort niet in het onversleutelde prefs-domein te
  /// staan in een app die er zelf op controleert.
  static const privacyOwnIdentityKey = 'privacy_own_identity';

  /// Schrijf "je eigen gegevens" weg; leeg wist de entry. `false` bij een
  /// mislukte schrijf, zodat de aanroeper de prefs-migratie kan uitstellen in
  /// plaats van de gegevens kwijt te raken.
  Future<bool> writePrivacyOwnIdentity(String value) async {
    try {
      if (value.trim().isEmpty) {
        await _storage.delete(key: privacyOwnIdentityKey);
      } else {
        await _storage.write(key: privacyOwnIdentityKey, value: value);
      }
      return true;
    } catch (e) {
      logError('SecretStore.writePrivacyOwnIdentity: keychain write failed', e);
      return false;
    }
  }

  Future<String?> readPrivacyOwnIdentity() async {
    try {
      return await _storage.read(key: privacyOwnIdentityKey);
    } catch (e) {
      logError('SecretStore.readPrivacyOwnIdentity: keychain read failed', e);
      return null;
    }
  }

  Future<void> deletePrivacyOwnIdentity() async {
    try {
      await _storage.delete(key: privacyOwnIdentityKey);
    } catch (e) {
      logWarning(
        'SecretStore.deletePrivacyOwnIdentity: keychain delete failed',
        e,
      );
    }
  }

  /// Wis het geheim dat bij elk van [connections] hoort.
  ///
  /// Voor het terugzetten naar de begintoestand. Bewust gekeyd op de
  /// verbindingen die er op dát moment zijn, en niet op "alles in de sleutelbos
  /// met ons voorvoegsel": een sleutelbos is van de gebruiker, en een lijst
  /// waarvan wij denken dat hij van ons is, is precies de lijst waarmee je per
  /// ongeluk het wachtwoord van iets anders wist.
  ///
  /// Best effort per entry: een sleutelbos die weigert mag het terugzetten niet
  /// laten stranden.
  Future<void> deleteSecretsOf(Iterable<StorageConnection> connections) async {
    for (final connection in connections) {
      switch (connection) {
        case WebdavConnection(:final server):
          await deleteWebdavPassword(server.baseUrl, server.username);
        case S3Connection(:final bucket):
          await deleteS3SecretKey(bucket.endpoint, bucket.accessKeyId);
        case GitConnection(:final repo):
          await deleteGitToken(repo.baseUrl, repo.owner);
        case LocalConnection():
          break; // een map heeft geen geheim
      }
    }
  }
}
