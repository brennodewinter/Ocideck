// Reference allocation for image callouts — IMAGE_CALLOUTS.md §6.1.
//
// The allocator picks the next free letter (A–Z), skipping any letter that
// already occurs as trailing prose on the slide. This prevents the
// allocator from manufacturing the collision that §2.6 has to report.

import '../models/image_callout.dart';

/// Allocates the next free reference letter (A–Z), skipping letters already
/// used by existing callouts and letters that appear as trailing `(X)` prose
/// on the slide's bullets.
///
/// Returns null when all 26 letters are taken (§8: 26 references max).
String? nextFreeReference(Set<String> usedByCallouts, Set<String> usedByProse) {
  for (var i = 0; i < 26; i++) {
    final letter = String.fromCharCode(65 + i);
    if (!usedByCallouts.contains(letter) && !usedByProse.contains(letter)) {
      return letter;
    }
  }
  return null;
}

/// Extracts trailing `(A)` reference letters from a list of bullet strings.
/// A trailing reference is `(` + one uppercase letter + `)` at the end of
/// the bullet, preceded by a space (§2.1).
Set<String> trailingReferenceLetters(List<String> bullets) {
  final letters = <String>{};
  for (final bullet in bullets) {
    final trimmed = bullet.trimRight();
    // Match "(A)" at the end: space + ( + [A-Z] + )
    final match = RegExp(r'\s\(([A-Z])\)$').firstMatch(trimmed);
    if (match != null) {
      letters.add(match.group(1)!);
    }
  }
  return letters;
}

/// The set of reference letters already used by existing callouts on a slide.
Set<String> calloutLetters(Iterable<ImageCallout> callouts) =>
    callouts.map((c) => c.reference).toSet();
