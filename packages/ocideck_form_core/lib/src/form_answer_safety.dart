/// What an answer may contain (FORM_INTAKE.md §4.6, rules 1–5).
///
/// An answer is Markdown — but a *restricted* Markdown, because a submission is
/// untrusted input that other people open in other tools: a remote image makes
/// every tool that opens the file phone home, raw HTML or a `javascript:` link is
/// a way to run something, and a marker-shaped line could forge the structure of
/// the form. The rules are a **whitelist** and they are the first line of
/// defence; the safety scanner of the app, a blacklist for executable content,
/// only backs them up.
library;

import 'form_blocks.dart';
import 'form_issue.dart';
import 'form_source.dart';

/// The name grammar of an image in an answer (FORM_INTAKE.md §5.4): inside
/// `images/`, lower-case, one level, a known extension.
final RegExp kFormImagePath = RegExp(
  r'^images/[a-z0-9-]{1,64}\.(?:jpg|png|webp|heic)$',
);

final RegExp _escape = RegExp(r'\\[!-/:-@\[-`{-~]');

// Raw HTML as CommonMark knows it: an opening or closing tag, a comment, a
// declaration, a processing instruction, and the two autolink forms (which are
// angle-bracketed too, and are refused so that a link is always `[text](dest)`).
final RegExp _html = RegExp(
  r'<(?:/?[A-Za-z][A-Za-z0-9-]*(?:\s[^<>]*)?/?>|!--|![A-Za-z\[]|\?'
  r'|[A-Za-z][A-Za-z0-9+.-]*:[^\s<>]*>|[^\s@<>]+@[^\s@<>]+>)',
);

const String _dest = r'(<[^>]*>|[^\s)]*)';
const String _title = r'(?:\s+"[^"]*")?';
final RegExp _inlineImage = RegExp('!\\[[^\\]]*\\]\\(\\s*$_dest$_title\\s*\\)');
final RegExp _referenceImage = RegExp(r'!\[[^\]]*\](?!\()');
final RegExp _imageOpener = RegExp(r'!\[[^\]]*\]\(');
final RegExp _linkOpener = RegExp(r'(?<!!)\[[^\]]*\]\(');
final RegExp _inlineLink = RegExp(
  '(?<!!)\\[[^\\]]*\\]\\(\\s*$_dest$_title\\s*\\)',
);
final RegExp _definition = RegExp(r'^[ \t]{0,3}\[(?!\^)[^\]]+\]:[ \t]*(\S*)');
final RegExp _allowedLink = RegExp(
  r'^(?:https:|mailto:)',
  caseSensitive: false,
);

/// Every way the text of one answer zone breaks rules 1–5, in line order.
///
/// [zone] is the zone's text; [firstLine] is the 1-based document line of its
/// first line, so each problem can point at the line to fix. Never throws.
List<FormProblem> answerSafetyIssues(
  String zone, {
  int firstLine = 1,
  String? fieldId,
}) {
  final problems = <FormProblem>[];
  void add(FormIssueCode code, int index, Map<String, Object?> facts) =>
      problems.add(
        FormProblem(
          code,
          line: firstLine + index,
          fieldId: fieldId,
          facts: facts,
        ),
      );

  final lines = zone.replaceAll('\r\n', '\n').split('\n');
  final fence = FormFenceTracker();
  int? fenceOpenedAt;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final wasInFence = fence.inFence;

    // Rule 1 holds everywhere, in a fence or out of it.
    final scan = scanMarkerLine(line);
    if (scan is FoundMarker || scan is BadMarker) {
      add(FormIssueCode.answerContainsMarker, i, {
        'marker': scan is FoundMarker
            ? scan.name.wire
            : (scan as BadMarker).name.wire,
      });
      // A marker-shaped line can neither open nor close a fence, so the tracker
      // has nothing to learn from it.
      continue;
    }

    final isCode = fence.isCode(line);
    if (!wasInFence && fence.inFence) fenceOpenedAt = i;
    if (isCode) continue;

    var text = _withoutCode(line);

    // Images, then links: each full construct is judged by its destination and
    // then blanked, so the angle brackets of `<dest>` are never mistaken for HTML.
    text = text.replaceAllMapped(_inlineImage, (m) {
      final dest = _unwrap(m.group(1)!);
      if (!kFormImagePath.hasMatch(dest)) {
        add(FormIssueCode.answerBadImage, i, {'dest': dest});
      }
      return ' ';
    });
    text = text.replaceAllMapped(_inlineLink, (m) {
      final dest = _unwrap(m.group(1)!);
      if (!_allowedLink.hasMatch(dest)) {
        add(FormIssueCode.answerBadLink, i, {'dest': dest});
      }
      return ' ';
    });
    // What is left of an opener `![x](` or `[x](` did not form a valid
    // construct (a space in the destination, no closing parenthesis). A strict
    // reader may show it as plain text, a lenient one as an image or a link, so it
    // is refused rather than guessed at.
    if (_imageOpener.hasMatch(text)) {
      add(FormIssueCode.answerBadImage, i, {'reason': 'malformed'});
    }
    if (_linkOpener.hasMatch(text)) {
      add(FormIssueCode.answerBadLink, i, {'reason': 'malformed'});
    }
    if (_referenceImage.hasMatch(text)) {
      add(FormIssueCode.answerBadImage, i, {'reason': 'reference-image'});
    }
    final html = _html.firstMatch(text);
    if (html != null) {
      add(FormIssueCode.answerContainsHtml, i, {
        'snippet': _snippet(html.group(0)!),
      });
    }
    final definition = _definition.firstMatch(text);
    if (definition != null) {
      final dest = _unwrap(definition.group(1)!);
      if (!_allowedLink.hasMatch(dest)) {
        add(FormIssueCode.answerBadLink, i, {'dest': dest});
      }
    }
  }

  if (fence.inFence && fenceOpenedAt != null) {
    add(FormIssueCode.answerUnclosedFence, fenceOpenedAt, const {});
  }
  return problems;
}

/// `<dest>` → `dest`.
String _unwrap(String dest) => dest.startsWith('<') && dest.endsWith('>')
    ? dest.substring(1, dest.length - 1)
    : dest;

String _snippet(String s) => s.length <= 60 ? s : '${s.substring(0, 60)}…';

/// [line] with backslash escapes and inline code spans blanked out, so that
/// `\<b>` and `` `<b>` `` are text rather than HTML. A backtick run that never
/// closes on the line is left alone — it hides nothing.
String _withoutCode(String line) {
  final s = line.replaceAll(_escape, '  ');
  if (!s.contains('`')) return s;
  final out = StringBuffer();
  var i = 0;
  while (i < s.length) {
    if (s[i] != '`') {
      out.write(s[i]);
      i++;
      continue;
    }
    var n = 0;
    while (i + n < s.length && s[i + n] == '`') {
      n++;
    }
    final close = _findRun(s, n, i + n);
    if (close < 0) {
      out.write(s.substring(i, i + n));
      i += n;
    } else {
      out.write(' ');
      i = close + n;
    }
  }
  return out.toString();
}

/// The index of the next run of exactly [n] backticks at or after [from], or -1.
int _findRun(String s, int n, int from) {
  var i = from;
  while (i < s.length) {
    if (s[i] != '`') {
      i++;
      continue;
    }
    var run = 0;
    while (i + run < s.length && s[i + run] == '`') {
      run++;
    }
    if (run == n) return i;
    i += run;
  }
  return -1;
}
