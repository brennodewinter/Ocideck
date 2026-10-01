/// How a form counts what a person wrote (FORM_INTAKE.md §4.7).
///
/// A counter that disagrees between the respondent's screen and the organiser's
/// import is the most predictable complaint this feature will get, so these two
/// functions are **defined**, not borrowed: `computeDocumentStats` in the app
/// counts `1.` and `[x]` as words and counts HTML tags, and it is also the
/// word counter of the document status bar, which may change for UI reasons.
/// The behaviour here is pinned by `test/fixtures/form_vectors.json`, which the
/// engine's tests, the app's widget tests and the import pipeline all read.
library;

import 'package:characters/characters.dart';

import 'form_source.dart';

/// Unicode `White_Space` plus the ZERO WIDTH SPACE: the characters words are
/// split on. (`\s` is not it: it contains U+FEFF and lacks U+0085.)
final RegExp _separator = RegExp(
  '[\u0009-\u000D \u0085   - '
  '    　​]+',
);

/// A token is a word only if it holds at least one letter or digit.
final RegExp _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

// Block markers at the start of a line, outside fenced code.
final RegExp _blockquote = RegExp(r'^[ \t]{0,3}>[ \t]?');
final RegExp _listMarker = RegExp(
  r'^[ \t]*(?:[-*+]|[0-9]{1,9}[.)])(?:[ \t]+|$)',
);
final RegExp _taskBox = RegExp(r'^\[[ xX]\](?:[ \t]+|$)');

// An image is removed whole, alt text included; its destination may hold one
// level of balanced parentheses (`images/foo(1).jpg`).
const String _destination = r'(?:[^()\s]|\([^()\s]*\))*';
final RegExp _image = RegExp(
  r'!\[[^\]]*\]\(' + _destination + r'(?:[ \t]+"[^"]*")?\)',
);

// A link keeps its text; the destination and an optional title are dropped.
final RegExp _link = RegExp(
  r'\[([^\]]*)\]\(' + _destination + r'(?:[ \t]+"[^"]*")?\)',
);

/// The number of words in [text], an answer as written in Markdown.
///
/// The text is reduced to what a reader reads — list markers (`-`, `*`, `+`,
/// `1.`, `1)`), task boxes (`[x]`, `[ ]`), blockquote `>`, the line that opens a
/// code fence, image markup, and link destinations and titles are removed (a
/// heading's `#` needs no removal: it holds no letter or digit) — then split
/// on Unicode `White_Space` and the zero-width space. A token counts **iff it
/// holds at least one letter or digit**. So `sambal-ketjap` is one word, `sambal -
/// ketjap` is two, link text counts and its URL does not, and the *content* of a
/// fenced block counts (as plain lines: there is no Markdown inside a fence).
///
/// Known limit: scripts written without spaces (Chinese, Japanese) are not
/// segmented; a run of them is one word.
int countFormWords(String text) {
  var count = 0;
  final fence = FormFenceTracker();
  for (final raw in _lines(text)) {
    final wasInFence = fence.inFence;
    final isCode = fence.isCode(raw);
    String line;
    if (isCode) {
      // The line that opens a fence is not text (its info string is no word); the
      // lines between are, as written. The closing line is only fence characters,
      // so it adds nothing either way.
      if (!wasInFence) continue;
      line = raw;
    } else {
      line = _stripBlockMarkers(raw);
      line = line
          .replaceAll(_image, ' ')
          .replaceAllMapped(_link, (m) => ' ${m.group(1)} ');
    }
    for (final token in line.split(_separator)) {
      if (token.isNotEmpty && _letterOrDigit.hasMatch(token)) count++;
    }
  }
  return count;
}

/// The number of user-perceived characters (extended grapheme clusters) in
/// [text], after normalising line endings to LF and trimming surrounding white
/// space. `'Réne'` is four characters, and a 🌶 is one — not the two UTF-16
/// units `String.length` would say. A file's line endings never change a count.
int countFormChars(String text) => _normaliseEol(text).trim().characters.length;

/// CRLF → LF, nothing else: a lone CR is white space, not a line break (the same
/// rule `FormSource` follows), and it is one character like any other.
String _normaliseEol(String text) => text.replaceAll('\r\n', '\n');

List<String> _lines(String text) => _normaliseEol(text).split('\n');

String _stripBlockMarkers(String line) {
  var s = line;
  while (_blockquote.hasMatch(s)) {
    s = s.replaceFirst(_blockquote, '');
  }
  final list = _listMarker.firstMatch(s);
  if (list != null) {
    s = s.substring(list.end);
    final task = _taskBox.firstMatch(s);
    if (task != null) s = s.substring(task.end);
  }
  return s;
}
