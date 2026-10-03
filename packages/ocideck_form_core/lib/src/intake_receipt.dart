/// The receipt a respondent keeps after an upload (`docs/design/INTAKE_PROTOCOL.md` §4.3, §4.4;
/// FORM_INTAKE.md §5.8): what the server said it received, and the **withdrawal secret** that is
/// the only way to ask the server to delete it again.
///
/// The respondent's own data, in their own folder: a small JSON file, `<name>.receipt.json`. It
/// holds the server's host (so that a withdrawal needs nothing else), the form, the arrival note and
/// the secret. It is **not** a proof against the server — the note is unsigned, the server would sign
/// anything (§5.7) — only something to quote and something to withdraw with.
///
/// Read strictly: exactly these members, in the grammars of the protocol. A file that is anything
/// else is not a receipt, and the secret in it is never used to guess at what it was meant to be.
library;

import 'dart:convert';

import 'form_bundle.dart' show isValidApiHost;
import 'form_package.dart' show isValidFormId;
import 'intake_protocol.dart';

/// The receipt version this engine reads and writes.
const int kIntakeReceiptVersion = 1;

/// The suffix of a receipt file next to a submission: `kook-abcdef.receipt.json`.
const String kIntakeReceiptSuffix = '.receipt.json';

/// A receipt: [note] is what the server answered; [withdrawalSecret] is what withdraws it.
class IntakeReceipt {
  const IntakeReceipt({
    required this.host,
    required this.fid,
    required this.withdrawalSecret,
    required this.note,
  });

  /// The server the submission went to, lower-case, with its port if it has one.
  final String host;

  /// The form it belongs to.
  final String fid;

  /// The 52-character secret whose hash went with the upload.
  final String withdrawalSecret;

  final IntakeArrivalNote note;

  /// The submission's id, from the note.
  String get sid => note.sid;

  Map<String, Object?> toJson() => {
    'v': kIntakeReceiptVersion,
    'host': host,
    'fid': fid,
    'withdrawal_secret': withdrawalSecret,
    'note': note.toJson(),
  };

  String toJsonText() => const JsonEncoder.withIndent('  ').convert(toJson());
}

/// The receipt in [text], or `null` if it is not exactly one.
IntakeReceipt? parseIntakeReceipt(String text) {
  final json = intakeJsonObject(text);
  if (json == null ||
      json.length != 5 ||
      json['v'] != kIntakeReceiptVersion ||
      !json.keys.every(
        (k) =>
            const {'v', 'host', 'fid', 'withdrawal_secret', 'note'}.contains(k),
      )) {
    return null;
  }
  final host = json['host'];
  final fid = json['fid'];
  final secret = json['withdrawal_secret'];
  final noteJson = json['note'];
  if (host is! String || !isValidApiHost(host)) return null;
  if (fid is! String || !isValidFormId(fid)) return null;
  if (secret is! String || !isValidWithdrawalSecret(secret)) return null;
  if (noteJson is! Map<String, Object?> ||
      noteJson.length != 4 ||
      !noteJson.keys.every(
        (k) => const {'sid', 'at', 'ciphertext_sha256', 'contact'}.contains(k),
      )) {
    return null;
  }
  final note = parseIntakeArrivalNote(jsonEncode(noteJson));
  if (note == null) return null;
  return IntakeReceipt(
    host: host,
    fid: fid,
    withdrawalSecret: secret,
    note: note,
  );
}
