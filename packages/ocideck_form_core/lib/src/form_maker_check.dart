/// The maker check (FORM_INTAKE.md §7.4): before a contribution is published, the
/// maker is sent what it will look like and asked whether it is right. The pure half
/// is here — which address the maker gave, and a mail link that cannot be turned into
/// something else by what the respondent typed. The document and the sending are the
/// app's.
///
/// The check is an **integrity control**, not a courtesy: an anonymous respondent
/// cannot be authenticated (§5.7), so an answer that comes back from the address the
/// submission gave is the only confirmation that the maker is who the submission says.
library;

import 'form_answers.dart';
import 'form_patterns.dart';
import 'form_spec.dart';

/// The address the maker gave: the first field with `pattern=email` (only a `text`
/// field has one) whose answer is filled in and really is an address. A field that is empty, or whose
/// answer is not an address, is passed over — the submission was judged before it
/// was accepted, so what is left is a form with no such field or an optional one the
/// maker left blank, and the organiser types the address.
String? makerAddressOf(FormSpec spec, FormAnswers answers) {
  for (final field in spec.fields) {
    // Only a `text` field can carry a `pattern`; on any other type it is an unknown
    // rule and is not in `rules`.
    if (field.text('pattern') != 'email') continue;
    final text = answers.byId[field.id]?.text;
    if (text != null && isMailableAddress(text)) return text;
  }
  return null;
}

/// Whether [address] is one a mail link may carry: an address by the form's `email`
/// pattern, and no control character — the pattern bars blanks and `,;<>` but not a
/// NUL, which a mail client would hand on as part of the address.
bool isMailableAddress(String address) {
  if (!matchesFormPattern('email', address)) return false;
  for (final unit in address.codeUnits) {
    if (unit < 0x20 || unit == 0x7f) return false;
  }
  return true;
}

/// A `mailto:` link for the maker check. The address is **percent-encoded around
/// its `@`**: the form's pattern lets `?`, `&`, `#` and `%` through in the local part,
/// and a link that carried them as they are would let a respondent add a `bcc`, a
/// subject or a body to the organiser's draft by choosing what to type as their
/// address. [subject] and [body] are encoded with `%20`, not `+` — a mail client
/// reads a `+` as a plus sign.
///
/// Throws [ArgumentError] for an address that is not [isMailableAddress].
String makerCheckMailLink({
  required String address,
  required String subject,
  required String body,
}) {
  if (!isMailableAddress(address)) {
    throw ArgumentError.value(address, 'address', 'not a mailable address');
  }
  // The pattern allows exactly one `@`, so this is the only one.
  final at = address.indexOf('@');
  final to =
      '${Uri.encodeComponent(address.substring(0, at))}@'
      '${Uri.encodeComponent(address.substring(at + 1))}';
  return 'mailto:$to?subject=${Uri.encodeComponent(subject)}'
      '&body=${Uri.encodeComponent(body)}';
}
