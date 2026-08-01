import 'dart:convert';

/// A cryptographic **provenance signature** on a distributed deck (COLLABORATION
/// Phase 2 "Blok C"; `docs/design/PROVENANCE_SIGNATURE.md`). Distinct from the
/// visible, human [DocumentSignature]: this is an Ed25519 signature by the
/// owner's collaboration identity over the deck's seal hash, so a recipient who
/// verified that identity's fingerprint out-of-band can confirm the exact deck
/// came from that holder.
///
/// It is *herkomstbewijs*, not an eIDAS electronic signature (jurist condition):
/// a self-generated key with no third-party identity binding. Lives in the
/// `.seal.json` sidecar, never in the `.md` (opaque → beside the file).
class ProvenanceSignature {
  /// The signature algorithm; only `ed25519` today.
  final String alg;

  /// The literal domain tag that was signed — see `kProvenancePreimageTag`. Kept
  /// so a third party reads it straight from the file and rebuilds the preimage.
  final String preimage;

  /// The signer's Ed25519 identity public key. Self-supplied (it travels here),
  /// so it proves authorship only once pinned out-of-band (Blok A).
  final List<int> identityKey;

  /// The Ed25519 signature over the preimage.
  final List<int> signature;

  /// When it was signed (ISO-8601 UTC). Signed too, so it cannot be altered
  /// without breaking the signature.
  final String signedAt;

  const ProvenanceSignature({
    required this.alg,
    required this.preimage,
    required this.identityKey,
    required this.signature,
    required this.signedAt,
  });

  bool get isEmpty => identityKey.isEmpty || signature.isEmpty;
  bool get isNotEmpty => !isEmpty;

  Map<String, Object?> toJson() => {
    'alg': alg,
    'preimage': preimage,
    'identity_key': base64.encode(identityKey),
    'signature': base64.encode(signature),
    'signed_at': signedAt,
  };

  /// Decode a block written by [toJson], or null when a required field is
  /// missing or malformed — a broken provenance block must degrade to "no
  /// signature", never poison the surrounding seal (security-architect condition).
  static ProvenanceSignature? fromJson(Object? data) {
    if (data is! Map) return null;
    final alg = data['alg'];
    final preimage = data['preimage'];
    final identityKey = data['identity_key'];
    final signature = data['signature'];
    final signedAt = data['signed_at'];
    if (alg is! String ||
        preimage is! String ||
        identityKey is! String ||
        signature is! String ||
        signedAt is! String) {
      return null;
    }
    try {
      return ProvenanceSignature(
        alg: alg,
        preimage: preimage,
        identityKey: base64.decode(identityKey),
        signature: base64.decode(signature),
        signedAt: signedAt,
      );
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ProvenanceSignature &&
      other.alg == alg &&
      other.preimage == preimage &&
      other.signedAt == signedAt &&
      base64.encode(other.identityKey) == base64.encode(identityKey) &&
      base64.encode(other.signature) == base64.encode(signature);

  @override
  int get hashCode =>
      Object.hash(alg, preimage, signedAt, base64.encode(identityKey));
}
