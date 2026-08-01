// The device trust store for real-time collaboration (COLLABORATION Phase 2,
// "Blok A"; SELF_ENCRYPTED_RELAY.md §5.3). It remembers which peer identity keys
// this account has pinned as verified, so a collaborator you compared once —
// reading the fingerprint aloud, over a channel you trust — stays verified across
// sessions and app restarts instead of showing up as an "unverified new device"
// every time.
//
// The binding check (identity key signs the agreement key) already defeats a
// relay that swaps *one* key; what it cannot catch is a homeserver that
// consistently substitutes *both* keys for a device it fully impersonates. Only a
// human comparing the identity-key fingerprint can — and this store is what makes
// that human act durable. It also turns the dangerous case into a loud one: a
// device we pinned that later presents a *different* identity key is a
// [TrustState.mismatch], not a silent re-pin.
//
// The pinned values are **public** keys, not secrets. They live in the keychain
// only so the collaboration layer keeps one persistence mechanism (beside the
// device seeds) and a pin cannot be rewritten from the plain prefs domain.

import 'dart:convert';

import '../services/secret_store.dart';
import 'collab_participant.dart';

/// A pin identifies a *device*, not just a user: one user may run several
/// devices, each with its own identity key, and each is pinned independently.
String _pinId(String userId, String deviceId) => '$userId\u0000$deviceId';

/// Persists and evaluates pinned peer identities for one local account.
///
/// Load once ([load]) so [evaluate] can stay synchronous — the verification
/// dialog reads trust while it builds its rows. [pin] and [unpin] update both the
/// in-memory map and the keychain.
class CollabTrustStore {
  CollabTrustStore(this._secrets, this._homeserver, this._userId);

  final SecretStore _secrets;
  final String _homeserver;
  final String _userId;

  /// Pin id → base64 of the pinned identity key. Empty until [load] runs (and an
  /// account that never pinned anyone stays empty — every peer is then
  /// [TrustState.unverified], the honest default).
  final Map<String, String> _pins = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// Read the persisted pins into memory. A missing or corrupt blob leaves the
  /// store empty rather than throwing: a lost trust store must degrade to
  /// "nothing verified yet", never to a session that will not open.
  Future<void> load() async {
    final stored = await _secrets.readCollabTrust(_homeserver, _userId);
    _pins.clear();
    if (stored != null && stored.isNotEmpty) {
      try {
        final data = jsonDecode(stored);
        if (data is Map) {
          data.forEach((key, value) {
            if (key is String && value is String) _pins[key] = value;
          });
        }
      } on FormatException {
        // Corrupt store — treat as no pins. See the class comment.
      }
    }
    _loaded = true;
  }

  /// Where [identityKey] for `userId`/`deviceId` stands against the pins. The
  /// self device is never evaluated here (the caller marks it verified). An
  /// unpinned device is [TrustState.unverified]; a pinned device presenting the
  /// same key is [TrustState.verified]; a pinned device presenting a *different*
  /// key is [TrustState.mismatch].
  TrustState evaluate(String userId, String deviceId, List<int> identityKey) {
    final pinned = _pins[_pinId(userId, deviceId)];
    if (pinned == null) return TrustState.unverified;
    return pinned == base64.encode(identityKey)
        ? TrustState.verified
        : TrustState.mismatch;
  }

  /// True once this exact identity is pinned for this device.
  bool isPinned(String userId, String deviceId, List<int> identityKey) =>
      evaluate(userId, deviceId, identityKey) == TrustState.verified;

  /// Pin [identityKey] as the verified identity for `userId`/`deviceId`,
  /// overwriting any earlier pin — used both for a first verification and to
  /// deliberately re-pin a device whose key genuinely changed (a re-onboarded
  /// peer). Persists immediately.
  Future<void> pin(
    String userId,
    String deviceId,
    List<int> identityKey,
  ) async {
    _pins[_pinId(userId, deviceId)] = base64.encode(identityKey);
    await _persist();
  }

  /// Remove the pin for `userId`/`deviceId` (back to [TrustState.unverified]).
  Future<void> unpin(String userId, String deviceId) async {
    if (_pins.remove(_pinId(userId, deviceId)) != null) await _persist();
  }

  Future<void> _persist() =>
      _secrets.writeCollabTrust(_homeserver, _userId, jsonEncode(_pins));
}
