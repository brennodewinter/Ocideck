/// The named patterns a `text` field can ask for (`pattern=email`, …;
/// FORM_INTAKE.md §4.5). **Named, never free**: a regular expression an author
/// types is a denial-of-service and a support burden, and a form that carries one
/// is a form nobody can reason about. The four here are pragmatic, not RFC-perfect
/// — they reject what is plainly not an e-mail address, URL, phone number or Dutch
/// postcode and accept what people actually write — and every behaviour is pinned
/// by `test/fixtures/form_vectors.json`.
library;

/// The pattern names, in the order the registry lists them.
const List<String> kFormPatternNames = ['email', 'url', 'phone', 'postcode-nl'];

// No backtracking trap: every quantifier sits on a class that cannot also match
// the separator that follows it, so matching is linear in the input.
final RegExp _email = RegExp(r'^[^\s@,;<>]+@[^\s@.,;<>]+(?:\.[^\s@.,;<>]+)+$');

final RegExp _url = RegExp(
  r'^https?://[^\s/?#.:]+(?:\.[^\s/?#.:]+)+(?::[0-9]{1,5})?(?:[/?#][^\s]*)?$',
);

final RegExp _phoneChars = RegExp(r'^\+?[0-9 ()\-.]+$');
final RegExp _postcode = RegExp(r'^[1-9][0-9]{3} ?([A-Za-z]{2})$');

/// Whether [text] matches the pattern named [pattern]. An unknown name matches
/// nothing: a pattern this engine does not know can never be satisfied silently.
bool matchesFormPattern(String pattern, String text) {
  switch (pattern) {
    case 'email':
      return _email.hasMatch(text);
    case 'url':
      return _url.hasMatch(text);
    case 'phone':
      return _isPhone(text);
    case 'postcode-nl':
      return _isPostcodeNl(text);
    default:
      return false;
  }
}

/// A phone number: only digits, blanks, parentheses, hyphens and dots, an
/// optional leading `+`, no blank at either end, and seven to fifteen digits (the
/// E.164 ceiling).
bool _isPhone(String text) {
  if (!_phoneChars.hasMatch(text) || text != text.trim()) return false;
  var digits = 0;
  for (final unit in text.codeUnits) {
    if (unit >= 48 && unit <= 57) digits++;
  }
  return digits >= 7 && digits <= 15;
}

/// `1234 AB` or `1234AB`: four digits (not starting with 0), an optional single
/// space, two letters — except `SA`, `SD` and `SS`, which are not issued.
bool _isPostcodeNl(String text) {
  final m = _postcode.firstMatch(text);
  if (m == null) return false;
  const notIssued = {'SA', 'SD', 'SS'};
  return !notIssued.contains(m.group(1)!.toUpperCase());
}
