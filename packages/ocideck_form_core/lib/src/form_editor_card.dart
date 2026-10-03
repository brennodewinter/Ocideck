/// The editor card (FORM_INTAKE.md §5.1, §7.6): what a new editor hands to the owner of a form so
/// the owner can list them in the bundle — a name, the `age` recipient their sealed submissions
/// are opened with, their Ed25519 public key, and the `kid` that follows from the recipient.
///
/// **The fingerprint covers the whole card**, not the signing key alone. The owner checks it by
/// another road (read aloud, said on the phone) and types it back; if it covered only the key, whoever
/// carried the card could swap the `age` recipient for their own and keep the key — every submission
/// would then be sealed to the wrong person under a fingerprint that still matched.
///
/// A card is not signed. It does not have to prove that its maker holds the keys: a card whose keys
/// nobody holds only costs the owner a recipient that cannot open anything, and the fingerprint is
/// what ties the card to the person who read it out.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import 'form_base32.dart';
import 'form_bundle.dart';
import 'form_jcs.dart';
import 'form_seal.dart';

/// Prefixes the bytes the fingerprint is taken over, so it cannot be confused with the SHA-256 of
/// anything else (a signing key's fingerprint is the SHA-256 of the bare key).
const String kEditorCardTag = 'ocideck-editor-card-v1\n';

/// The card version this engine reads and writes.
const int kFormEditorCardVersion = 1;

/// The most characters of card text read. A card is a few hundred; this is not a limit anyone meets.
const int kFormMaxEditorCardChars = 4096;

/// An editor card.
class FormEditorCard {
  const FormEditorCard({
    required this.name,
    required this.age,
    required this.sign,
    required this.kid,
  });

  /// What the owner and the respondent are shown for this editor.
  final String name;

  /// The `age1…` recipient submissions are sealed to.
  final String age;

  /// The Ed25519 public key, base32.
  final String sign;

  /// [organiserKid] of [age].
  final String kid;

  Map<String, Object?> toJson() => {
    'v': kFormEditorCardVersion,
    'name': name,
    'age': age,
    'sign': sign,
    'kid': kid,
  };

  /// The card as text, ready to be pasted: canonical JSON on one line.
  String toText() => canonicalJson(toJson());

  /// The fingerprint of the whole card, 52 characters of base32: the SHA-256 of the tag and the
  /// canonical JSON. It does not depend on how the card was written down, only on what is in it.
  String get fingerprint => base32Encode(
    crypto.sha256.convert(utf8.encode('$kEditorCardTag${toText()}')).bytes,
  );
}

/// Why a card was not accepted.
enum FormEditorCardIssue {
  /// Not JSON, not an object, too long, or with a key a card does not have.
  notACard,

  /// `v` is not the version this engine reads.
  unsupportedVersion,

  /// The name is empty, over 80 characters, or holds a control character.
  badName,

  /// `age` is not an `age1…` X25519 recipient.
  badAge,

  /// `sign` is not a 32-byte Ed25519 public key in base32.
  badSign,

  /// `kid` is not the key id of `age`.
  badKid,
}

/// The outcome of [parseFormEditorCard].
sealed class FormEditorCardResult {
  const FormEditorCardResult();
}

/// A card that is one.
class FormEditorCardParsed extends FormEditorCardResult {
  const FormEditorCardParsed(this.card);

  final FormEditorCard card;
}

/// A card that is not, and why.
class FormEditorCardRefused extends FormEditorCardResult {
  const FormEditorCardRefused(this.issue);

  final FormEditorCardIssue issue;
}

/// Whether [name] is a name a card can carry: not empty once trimmed, at most 80 characters, no
/// control characters — the same rule as an organiser's name in a bundle.
bool isValidEditorName(String name) =>
    name.trim().isNotEmpty &&
    name.length <= 80 &&
    !name.codeUnits.any((c) => c < 0x20 || c == 0x7f);

/// Makes the card of an editor: [name], the `age1…` recipient [age] and the 32-byte Ed25519 public
/// key [signPublicKey]. Throws [ArgumentError] for a name, recipient or key that cannot be on a
/// card — the caller has these from its own key, so a refusal is a bug, not input.
FormEditorCard createFormEditorCard({
  required String name,
  required String age,
  required List<int> signPublicKey,
}) {
  final trimmed = name.trim();
  if (!isValidEditorName(trimmed)) throw ArgumentError.value(name, 'name');
  if (!isAgeRecipient(age)) throw ArgumentError.value(age, 'age');
  if (signPublicKey.length != 32) {
    throw ArgumentError.value(signPublicKey.length, 'signPublicKey');
  }
  return FormEditorCard(
    name: trimmed,
    age: age,
    sign: base32Encode(signPublicKey),
    kid: organiserKid(age),
  );
}

/// Reads [text] as a card. Never throws. The name is taken as written, trimmed; nothing else is
/// forgiven — a card with a key it does not have, or a `kid` that is not the key id of its `age`, is
/// not a card, because the fingerprint would then vouch for something nobody made.
FormEditorCardResult parseFormEditorCard(String text) {
  if (text.length > kFormMaxEditorCardChars) {
    return const FormEditorCardRefused(FormEditorCardIssue.notACard);
  }
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    return const FormEditorCardRefused(FormEditorCardIssue.notACard);
  }
  if (json is! Map ||
      json.keys.any(
        (k) => !const {'v', 'name', 'age', 'sign', 'kid'}.contains(k),
      )) {
    return const FormEditorCardRefused(FormEditorCardIssue.notACard);
  }
  if (json['v'] != kFormEditorCardVersion) {
    return FormEditorCardRefused(
      json.containsKey('v') && json['v'] is int
          ? FormEditorCardIssue.unsupportedVersion
          : FormEditorCardIssue.notACard,
    );
  }
  final name = json['name'];
  final age = json['age'];
  final sign = json['sign'];
  final kid = json['kid'];
  if (name is! String || !isValidEditorName(name) || name != name.trim()) {
    // Spaces round the name are refused, not trimmed: the fingerprint is taken over what is
    // written, and a card that reads one way and hashes another cannot be checked by ear.
    return const FormEditorCardRefused(FormEditorCardIssue.badName);
  }
  if (age is! String || !isAgeRecipient(age)) {
    return const FormEditorCardRefused(FormEditorCardIssue.badAge);
  }
  final key = sign is String ? base32Decode(sign) : null;
  if (key == null || key.length != 32) {
    return const FormEditorCardRefused(FormEditorCardIssue.badSign);
  }
  if (kid is! String || kid != organiserKid(age)) {
    return const FormEditorCardRefused(FormEditorCardIssue.badKid);
  }
  return FormEditorCardParsed(
    FormEditorCard(
      name: name.trim(),
      age: age,
      sign: base32Encode(key),
      kid: kid,
    ),
  );
}
