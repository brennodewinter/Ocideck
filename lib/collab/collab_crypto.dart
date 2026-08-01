// The end-to-end encryption seam of the collaboration layer
// (`docs/design/SELF_ENCRYPTED_RELAY.md` §4, phase P-A). This is the **only** file
// in the module that touches `package:cryptography`; every other layer sees the
// small value types below and never a primitive.
//
// The scheme is deliberately *minimal* — the chain-review's binding condition
// (`assurance/ketenkeuring-self-encrypted-relay.md`, condition 1). It is a group
// **key-wrapping** design, **not** a ratchet:
//
//   • Each device holds a long-term Ed25519 identity keypair (signing) and an
//     X25519 agreement keypair. The X25519 public key is signed by the Ed25519
//     key so a relay cannot substitute it (§5.3 homeserver key substitution).
//   • The authority mints one random AEAD **session key** per **epoch** and hands
//     it to each member with an authenticated sealed box (ephemeral-X25519 ECDH →
//     HKDF → XChaCha20-Poly1305, signed by the authority's Ed25519 key).
//   • Record payloads (ops/locks/chat) are sealed under the epoch's session key
//     with XChaCha20-Poly1305; the associated data binds room, event type, epoch
//     and sender so a valid ciphertext cannot be replayed into another context.
//
// XChaCha20-Poly1305 (192-bit nonce) is chosen over AES-GCM so a *random* nonce
// per message is safe, sidestepping GCM's catastrophic nonce-reuse failure
// (design §4.2). No per-message forward secrecy is claimed: keys rotate per epoch
// (on membership change), not per message. That is the deliberate, documented
// trade against Megolm — acceptable because sessions are ephemeral (P2) and small
// (P3). See the design's threat model (§4.1) for what this does and does not
// defend.
//
// **Red lines** (do not cross without a new chain-review): no bespoke primitives,
// no custom KDF beyond standard HKDF usage, no ratchet, one crypto file so review
// has a single surface.
//
// Everything here is pure-Dart `package:cryptography` (no `cryptography_flutter`),
// so it runs identically under `flutter test`, on the desktop targets and on web.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

// One instance of each algorithm; they are stateless and cheap to share.
final _x25519 = X25519();
final _ed25519 = Ed25519();
final _aead = Xchacha20.poly1305Aead();

Hkdf _hkdf(int outputLength) =>
    Hkdf(hmac: Hmac.sha256(), outputLength: outputLength);

/// The Poly1305 authentication tag length appended to every ciphertext.
const _tagBytes = 16;

/// Envelope format version, carried in the sealed record and the AAD so a future
/// format change is unambiguous and cannot be confused with this one.
const _envelopeVersion = 1;

/// Thrown by [CollabCrypto.open] / [CollabCrypto.installEpochKey] on **any**
/// failure — a bad tag, a wrong sender, an AAD/context mismatch, a missing
/// required signature, or an epoch whose key this device does not hold. The
/// caller drops the event fail-closed; on [reason] `unknown-epoch` it requests a
/// fresh key share rather than skipping the op stream.
class CollabCryptoException implements Exception {
  const CollabCryptoException(this.reason);

  /// A short machine key (`bad-tag`, `unknown-epoch`, `sender-mismatch`,
  /// `bad-signature`, `missing-signature`, `bad-wrap`, `wrong-recipient`).
  final String reason;

  @override
  String toString() => 'CollabCryptoException($reason)';
}

/// This device's private key material. Generate a fresh one with [generate], or
/// rebuild a known one from seeds with [fromSeeds] (the deterministic path the
/// tests and a keychain restore use). The private keys never leave this object.
class CollabDeviceKeys {
  CollabDeviceKeys._(this.deviceId, this._identity, this._agreement);

  /// A stable id for this device within a session (e.g. `<matrixUserId>:<devId>`).
  final String deviceId;

  final SimpleKeyPair _identity; // Ed25519 — signing / identity
  final SimpleKeyPair _agreement; // X25519 — key agreement

  /// A fresh random device identity.
  static Future<CollabDeviceKeys> generate({required String deviceId}) async {
    final identity = await _ed25519.newKeyPair();
    final agreement = await _x25519.newKeyPair();
    return CollabDeviceKeys._(deviceId, identity, agreement);
  }

  /// Rebuild a device identity from its two 32-byte seeds — deterministic, so a
  /// restored keychain (or a test vector) reproduces the same device exactly.
  static Future<CollabDeviceKeys> fromSeeds({
    required String deviceId,
    required List<int> ed25519Seed,
    required List<int> x25519Seed,
  }) async {
    final identity = await _ed25519.newKeyPairFromSeed(ed25519Seed);
    final agreement = await _x25519.newKeyPairFromSeed(x25519Seed);
    return CollabDeviceKeys._(deviceId, identity, agreement);
  }

  /// The raw Ed25519 identity public key — what a provenance block carries and
  /// what [deviceFingerprint] renders.
  Future<List<int>> identityKeyBytes() async =>
      (await _identity.extractPublicKey()).bytes;

  /// Sign a deck's **provenance** (COLLABORATION Phase 2 "Blok C";
  /// `docs/design/PROVENANCE_SIGNATURE.md`): the owner attests that this exact
  /// sealed deck — identified by [hash] under [algo]/[form], at [signedAt] —
  /// came from this identity. The preimage is domain-separated and built *here*
  /// (see [provenancePreimage]); this method never signs caller-chosen bytes, so
  /// the identity key cannot be turned into a signing oracle across the other
  /// message types it signs (§8, security-architect condition).
  Future<List<int>> signProvenance({
    required String form,
    required String algo,
    required String hash,
    required String signedAt,
  }) async {
    final sig = await _ed25519.sign(
      provenancePreimage(
        form: form,
        algo: algo,
        hash: hash,
        signedAt: signedAt,
      ),
      keyPair: _identity,
    );
    return sig.bytes;
  }

  /// The public half others need, with the X25519 key signed by the identity key
  /// so a relay cannot swap it (§4.3, §5.3).
  Future<DevicePublicKeys> publicKeys() async {
    final identityPub = await _identity.extractPublicKey();
    final agreementPub = await _agreement.extractPublicKey();
    final binding = _deviceBindingMessage(deviceId, agreementPub.bytes);
    final sig = await _ed25519.sign(binding, keyPair: _identity);
    return DevicePublicKeys(
      deviceId: deviceId,
      identityKey: identityPub.bytes,
      agreementKey: agreementPub.bytes,
      agreementSignature: sig.bytes,
    );
  }
}

/// The domain tag for a provenance signature, signed as the first array element
/// so this signature can never be confused with the device-binding, record or
/// key-wrap messages the same identity key also signs. Every signed message is a
/// JSON array (all begin with `[` — the separation is not in the first *byte* but
/// in the first *element*): `["rec",…]`, `["wrap",…]`, the device-binding tag,
/// and `["ocideck-provenance-v1",…]` here — those tags are disjoint, so no
/// cross-protocol confusion is reachable. It is also the literal `preimage` value
/// written in the `.seal.json` provenance block, so a third party reconstructs
/// the signed bytes verbatim. See `docs/design/PROVENANCE_SIGNATURE.md` §2/§3.
const String kProvenancePreimageTag = 'ocideck-provenance-v1';

/// The exact bytes a provenance signature covers: a JSON array (structured
/// encoding, not ad-hoc concatenation, so a delimiter can never be injected) of
/// the domain tag and the seal's own fields. Reproducible with any SHA-512 and
/// Ed25519 tool — no OciDeck needed to verify.
List<int> provenancePreimage({
  required String form,
  required String algo,
  required String hash,
  required String signedAt,
}) => utf8.encode(
  jsonEncode([kProvenancePreimageTag, form, algo, hash, signedAt]),
);

/// Verify a provenance signature against the [identityKey] that produced it.
/// Returns false on any mismatch rather than throwing, so a caller can render a
/// plain "invalid" state. The [identityKey] is self-supplied (it travels in the
/// block), so a true result proves only *this deck was signed by the holder of
/// this key* — meaningful authorship needs that key pinned out-of-band (Blok A).
Future<bool> verifyProvenance({
  required List<int> identityKey,
  required List<int> signature,
  required String form,
  required String algo,
  required String hash,
  required String signedAt,
}) {
  return _ed25519.verify(
    provenancePreimage(form: form, algo: algo, hash: hash, signedAt: signedAt),
    signature: Signature(
      signature,
      publicKey: SimplePublicKey(identityKey, type: KeyPairType.ed25519),
    ),
  );
}

/// The public keys of a device, as published to a room. [agreementSignature] is
/// the identity key's Ed25519 signature over the agreement key, binding the two
/// (§4.3). Always [verifyBinding] before trusting the agreement key.
class DevicePublicKeys {
  const DevicePublicKeys({
    required this.deviceId,
    required this.identityKey,
    required this.agreementKey,
    required this.agreementSignature,
  });

  final String deviceId;
  final List<int> identityKey; // Ed25519 public
  final List<int> agreementKey; // X25519 public
  final List<int> agreementSignature; // Ed25519 over the binding message

  SimplePublicKey get _identityPub =>
      SimplePublicKey(identityKey, type: KeyPairType.ed25519);
  SimplePublicKey get _agreementPub =>
      SimplePublicKey(agreementKey, type: KeyPairType.x25519);

  /// True when the agreement key is genuinely signed by the identity key for
  /// **this** device id — the check that defeats a relay swapping the X25519 key.
  Future<bool> verifyBinding() {
    final binding = _deviceBindingMessage(deviceId, agreementKey);
    return _ed25519.verify(
      binding,
      signature: Signature(agreementSignature, publicKey: _identityPub),
    );
  }

  Map<String, Object?> toJson() => {
    'device': deviceId,
    'ik': base64.encode(identityKey),
    'ak': base64.encode(agreementKey),
    'aksig': base64.encode(agreementSignature),
  };

  factory DevicePublicKeys.fromJson(Map<String, Object?> json) =>
      DevicePublicKeys(
        deviceId: _string(json, 'device'),
        identityKey: _b64(json, 'ik'),
        agreementKey: _b64(json, 'ak'),
        agreementSignature: _b64(json, 'aksig'),
      );
}

/// A sealed record payload: the ciphertext of an op/lock/chat envelope under an
/// epoch's session key, plus the context needed to open it. Wire form is
/// [toContent]; it is what rides in a relay event's `content`.
class SealedEnvelope {
  const SealedEnvelope({
    required this.epoch,
    required this.nonce,
    required this.ciphertext,
    required this.senderDevice,
    this.signature,
    this.version = _envelopeVersion,
  });

  final int version;
  final int epoch;
  final List<int> nonce;
  final List<int> ciphertext; // AEAD ciphertext with the 16-byte tag appended
  final String senderDevice;
  final List<int>? signature; // Ed25519 over (aad || nonce || ciphertext)

  Map<String, Object?> toContent() => {
    'v': version,
    'epoch': epoch,
    'alg': 'xchacha20-poly1305',
    'nonce': base64.encode(nonce),
    'ct': base64.encode(ciphertext),
    'sender': senderDevice,
    if (signature != null) 'sig': base64.encode(signature!),
  };

  factory SealedEnvelope.fromContent(Map<String, Object?> content) {
    final rawSig = content['sig'];
    return SealedEnvelope(
      version: _int(content, 'v'),
      epoch: _int(content, 'epoch'),
      nonce: _b64(content, 'nonce'),
      ciphertext: _b64(content, 'ct'),
      senderDevice: _string(content, 'sender'),
      signature: rawSig == null ? null : base64.decode(rawSig as String),
    );
  }
}

/// One session key wrapped for one recipient (§4.3). An authenticated sealed box:
/// [ephemeralKey] is a per-wrap X25519 public key, [ciphertext] is the wrapped
/// key under the ECDH-derived wrap key, and [signature] is the authority's
/// Ed25519 signature proving the wrap really came from it.
class WrappedKey {
  const WrappedKey({
    required this.epoch,
    required this.recipientDevice,
    required this.senderDevice,
    required this.ephemeralKey,
    required this.nonce,
    required this.ciphertext,
    required this.signature,
  });

  final int epoch;
  final String recipientDevice;
  final String senderDevice;
  final List<int> ephemeralKey; // X25519 public, per wrap
  final List<int> nonce;
  final List<int> ciphertext; // wrapped session key with tag appended
  final List<int> signature; // Ed25519 over the wrap by the authority

  Map<String, Object?> toJson() => {
    'epoch': epoch,
    'to': recipientDevice,
    'from': senderDevice,
    'epk': base64.encode(ephemeralKey),
    'nonce': base64.encode(nonce),
    'ct': base64.encode(ciphertext),
    'sig': base64.encode(signature),
  };

  factory WrappedKey.fromJson(Map<String, Object?> json) => WrappedKey(
    epoch: _int(json, 'epoch'),
    recipientDevice: _string(json, 'to'),
    senderDevice: _string(json, 'from'),
    ephemeralKey: _b64(json, 'epk'),
    nonce: _b64(json, 'nonce'),
    ciphertext: _b64(json, 'ct'),
    signature: _b64(json, 'sig'),
  );
}

/// The result of an authority [CollabCrypto.rekey]: the new [epoch] and one
/// [WrappedKey] per member to distribute.
class RekeyResult {
  const RekeyResult({required this.epoch, required this.wraps});

  final int epoch;
  final List<WrappedKey> wraps;
}

/// The session E2EE for one device. Holds this device's keys and the set of
/// per-epoch session keys; seals outbound record envelopes and opens inbound
/// ones. Pure logic over primitives — no network, no Matrix — so it is driven in
/// tests against known-answer vectors and needs no server.
///
/// State: a map of `epoch -> session key bytes`, and the current epoch. The
/// authority advances the epoch via [rekey]; a member installs an epoch key from
/// a wrap via [installEpochKey].
class CollabCrypto {
  CollabCrypto(this._keys);

  final CollabDeviceKeys _keys;
  final Map<int, List<int>> _epochKeys = {};
  int? _currentEpoch;

  String get deviceId => _keys.deviceId;

  /// The highest epoch whose key this device holds, or `null` before any key.
  int? get currentEpoch => _currentEpoch;

  bool hasEpoch(int epoch) => _epochKeys.containsKey(epoch);

  /// Seal [envelope] for the current epoch. [room] and [type] are bound into the
  /// AEAD associated data so the ciphertext cannot be replayed into another room
  /// or event type. [signed] adds the Ed25519 signature that authoritative ops
  /// carry (proving the op came from this device — P3 anti-impersonation).
  Future<SealedEnvelope> seal(
    Map<String, Object?> envelope, {
    required String room,
    required String type,
    required bool signed,
  }) async {
    final epoch = _currentEpoch;
    if (epoch == null) {
      throw const CollabCryptoException('no-epoch');
    }
    final key = SecretKey(_epochKeys[epoch]!);
    final aad = _recordAad(_envelopeVersion, room, type, epoch, deviceId);
    final nonce = _aead.newNonce();
    final box = await _aead.encrypt(
      utf8.encode(jsonEncode(envelope)),
      secretKey: key,
      nonce: nonce,
      aad: aad,
    );
    final ciphertext = _concat([box.cipherText, box.mac.bytes]);
    List<int>? signature;
    if (signed) {
      final sig = await _ed25519.sign(
        _concat([aad, nonce, ciphertext]),
        keyPair: _keys._identity,
      );
      signature = sig.bytes;
    }
    return SealedEnvelope(
      epoch: epoch,
      nonce: nonce,
      ciphertext: ciphertext,
      senderDevice: deviceId,
      signature: signature,
    );
  }

  /// Open [sealed], verifying its context and (if present or [requireSignature])
  /// its signature against [sender]. Throws [CollabCryptoException] fail-closed on
  /// any failure. The caller passes the same [room]/[type] the transport received
  /// the event under; a mismatch fails the tag.
  Future<Map<String, Object?>> open(
    SealedEnvelope sealed, {
    required String room,
    required String type,
    required DevicePublicKeys sender,
    bool requireSignature = false,
  }) async {
    if (sealed.senderDevice != sender.deviceId) {
      throw const CollabCryptoException('sender-mismatch');
    }
    final aad = _recordAad(
      sealed.version,
      room,
      type,
      sealed.epoch,
      sealed.senderDevice,
    );
    await _verifyRecordSignature(sealed, aad, sender, requireSignature);
    final keyBytes = _epochKeys[sealed.epoch];
    if (keyBytes == null) {
      throw const CollabCryptoException('unknown-epoch');
    }
    final plain = await _openBox(
      keyBytes,
      sealed.nonce,
      sealed.ciphertext,
      aad,
      'bad-tag',
    );
    final decoded = jsonDecode(utf8.decode(plain));
    if (decoded is! Map<String, Object?>) {
      throw const CollabCryptoException('bad-plaintext');
    }
    return decoded;
  }

  /// Authority: begin a **new epoch** with a fresh random session key and return
  /// the wraps to distribute to [members] (§4.6 — called at session start and on
  /// any membership *removal*). The first call yields epoch 0.
  Future<RekeyResult> rekey(List<DevicePublicKeys> members) async {
    final epoch = _currentEpoch == null ? 0 : _currentEpoch! + 1;
    final key = await _aead.newSecretKey();
    _epochKeys[epoch] = await key.extractBytes();
    _currentEpoch = epoch;
    final wraps = <WrappedKey>[];
    for (final member in members) {
      wraps.add(await _wrapTo(member, epoch));
    }
    return RekeyResult(epoch: epoch, wraps: wraps);
  }

  /// Authority: wrap the **current** epoch's key to a newcomer without bumping
  /// the epoch (§4.6 — a pure add: the newcomer cannot read pre-join ciphertext
  /// anyway, so a new epoch is unnecessary).
  Future<WrappedKey> wrapEpochTo(DevicePublicKeys member) async {
    final epoch = _currentEpoch;
    if (epoch == null) {
      throw const CollabCryptoException('no-epoch');
    }
    return _wrapTo(member, epoch);
  }

  /// Member: install the epoch key unwrapped from [wrap], verifying it was sent
  /// by [sender] to this device. Throws [CollabCryptoException] fail-closed on any
  /// mismatch. Advances [currentEpoch] when the installed epoch is higher.
  Future<void> installEpochKey(WrappedKey wrap, DevicePublicKeys sender) async {
    if (wrap.recipientDevice != deviceId) {
      throw const CollabCryptoException('wrong-recipient');
    }
    if (wrap.senderDevice != sender.deviceId) {
      throw const CollabCryptoException('sender-mismatch');
    }
    final wrapAad = _wrapAad(
      wrap.epoch,
      wrap.recipientDevice,
      wrap.senderDevice,
    );
    final signed = _concat([
      wrap.ephemeralKey,
      wrap.nonce,
      wrap.ciphertext,
      wrapAad,
    ]);
    final ok = await _ed25519.verify(
      signed,
      signature: Signature(wrap.signature, publicKey: sender._identityPub),
    );
    if (!ok) {
      throw const CollabCryptoException('bad-signature');
    }
    final wrapKey = await _deriveWrapKey(
      await _x25519.sharedSecretKey(
        keyPair: _keys._agreement,
        remotePublicKey: SimplePublicKey(
          wrap.ephemeralKey,
          type: KeyPairType.x25519,
        ),
      ),
      wrap.ephemeralKey,
    );
    final keyBytes = await _openBox(
      wrapKey,
      wrap.nonce,
      wrap.ciphertext,
      wrapAad,
      'bad-wrap',
    );
    _epochKeys[wrap.epoch] = keyBytes;
    if (_currentEpoch == null || wrap.epoch > _currentEpoch!) {
      _currentEpoch = wrap.epoch;
    }
  }

  // --- internals -----------------------------------------------------------

  Future<WrappedKey> _wrapTo(DevicePublicKeys member, int epoch) async {
    final ephemeral = await _x25519.newKeyPair();
    final ephemeralPub = await ephemeral.extractPublicKey();
    final shared = await _x25519.sharedSecretKey(
      keyPair: ephemeral,
      remotePublicKey: member._agreementPub,
    );
    final wrapKey = await _deriveWrapKey(shared, ephemeralPub.bytes);
    final wrapAad = _wrapAad(epoch, member.deviceId, deviceId);
    final nonce = _aead.newNonce();
    final box = await _aead.encrypt(
      _epochKeys[epoch]!,
      secretKey: SecretKey(wrapKey),
      nonce: nonce,
      aad: wrapAad,
    );
    final ciphertext = _concat([box.cipherText, box.mac.bytes]);
    final sig = await _ed25519.sign(
      _concat([ephemeralPub.bytes, nonce, ciphertext, wrapAad]),
      keyPair: _keys._identity,
    );
    return WrappedKey(
      epoch: epoch,
      recipientDevice: member.deviceId,
      senderDevice: deviceId,
      ephemeralKey: ephemeralPub.bytes,
      nonce: nonce,
      ciphertext: ciphertext,
      signature: sig.bytes,
    );
  }

  Future<void> _verifyRecordSignature(
    SealedEnvelope sealed,
    List<int> aad,
    DevicePublicKeys sender,
    bool requireSignature,
  ) async {
    final signature = sealed.signature;
    if (signature == null) {
      if (requireSignature) {
        throw const CollabCryptoException('missing-signature');
      }
      return;
    }
    final ok = await _ed25519.verify(
      _concat([aad, sealed.nonce, sealed.ciphertext]),
      signature: Signature(signature, publicKey: sender._identityPub),
    );
    if (!ok) {
      throw const CollabCryptoException('bad-signature');
    }
  }

  /// Derive the 32-byte AEAD wrap key from an ECDH shared secret. The ephemeral
  /// public key is the HKDF salt and a fixed label is the info, giving domain
  /// separation from every other use of HKDF in the app.
  Future<List<int>> _deriveWrapKey(SecretKey shared, List<int> salt) async {
    final derived = await _hkdf(32).deriveKey(
      secretKey: shared,
      nonce: salt,
      info: utf8.encode('ocideck/collab/keywrap/v1'),
    );
    return derived.extractBytes();
  }

  /// Decrypt a `[ciphertext||tag]` box, mapping an auth failure to a typed,
  /// fail-closed [CollabCryptoException] with [tagReason].
  Future<List<int>> _openBox(
    List<int> keyBytes,
    List<int> nonce,
    List<int> ciphertext,
    List<int> aad,
    String tagReason,
  ) async {
    if (ciphertext.length < _tagBytes) {
      throw CollabCryptoException(tagReason);
    }
    final split = ciphertext.length - _tagBytes;
    final box = SecretBox(
      ciphertext.sublist(0, split),
      nonce: nonce,
      mac: Mac(ciphertext.sublist(split)),
    );
    try {
      return await _aead.decrypt(box, secretKey: SecretKey(keyBytes), aad: aad);
    } on SecretBoxAuthenticationError {
      throw CollabCryptoException(tagReason);
    }
  }
}

// --- top-level helpers -----------------------------------------------------

/// The AEAD associated data for a record: an unambiguous JSON encoding of the
/// bound context. JSON (not raw concatenation) means a device id containing the
/// delimiter cannot be smuggled across fields.
List<int> _recordAad(
  int version,
  String room,
  String type,
  int epoch,
  String sender,
) => utf8.encode(jsonEncode(['rec', version, room, type, epoch, sender]));

/// The AEAD associated data for a key wrap, binding it to one epoch and the
/// exact sender/recipient pair.
List<int> _wrapAad(int epoch, String recipient, String sender) =>
    utf8.encode(jsonEncode(['wrap', epoch, recipient, sender]));

/// The message the identity key signs to vouch for an agreement key, bound to the
/// device id so a signed binding cannot be replayed under another device.
List<int> _deviceBindingMessage(String deviceId, List<int> agreementKey) =>
    utf8.encode(
      jsonEncode([
        'ocideck/device-binding/v1',
        deviceId,
        base64.encode(agreementKey),
      ]),
    );

Uint8List _concat(List<List<int>> parts) {
  var total = 0;
  for (final p in parts) {
    total += p.length;
  }
  final out = Uint8List(total);
  var offset = 0;
  for (final p in parts) {
    out.setRange(offset, offset + p.length, p);
    offset += p.length;
  }
  return out;
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw CollabCryptoException('bad-field:$key');
  }
  return value;
}

int _int(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw CollabCryptoException('bad-field:$key');
  }
  return value;
}

List<int> _b64(Map<String, Object?> json, String key) =>
    base64.decode(_string(json, key));
