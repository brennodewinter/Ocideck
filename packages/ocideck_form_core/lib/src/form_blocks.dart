/// The marker grammar of a form block — the **single owner** of what a marker
/// line is (FORM_INTAKE.md §4.3, and the first row of the chain in §4.9).
///
/// A marker is one HTML comment alone on a line, in the unprefixed style of
/// `<!-- toc -->` and the pentest blocks:
///
///     <!-- field id=naam type=text required max-chars=80 -->
///
/// There is no colon after the name and no `ocideck_` prefix. This file knows
/// nothing about what the attributes *mean*; it only splits a line into a name
/// and attributes, or says precisely why the line is not one.
library;

import 'form_source.dart' show FormFenceTracker;

/// The six marker names. [wire] is the spelling on disk.
enum FormMarkerName {
  form('form'),
  field('field'),
  answer('answer'),
  fieldEnd('/field'),
  notice('notice'),
  noticeEnd('/notice');

  const FormMarkerName(this.wire);
  final String wire;

  static FormMarkerName? fromWire(String wire) {
    for (final n in values) {
      if (n.wire == wire) return n;
    }
    return null;
  }
}

/// One `key=value` or bare-`key` attribute. A bare key is a **flag**: [value]
/// is null. A value (even an empty quoted one) makes it a value attribute.
class FormAttr {
  const FormAttr(this.key, this.value);

  final String key;
  final String? value;

  bool get isFlag => value == null;
}

/// What scanning one line found.
sealed class FormMarkerScan {
  const FormMarkerScan();
}

/// The line is not a marker; it is ordinary content.
class NoMarker extends FormMarkerScan {
  const NoMarker();
}

/// A well-formed marker.
class FoundMarker extends FormMarkerScan {
  const FoundMarker(this.name, this.attrs);

  final FormMarkerName name;

  /// In the order written; no key occurs twice.
  final List<FormAttr> attrs;

  bool has(String key) => attrs.any((a) => a.key == key);

  /// Whether [key] is present as a bare flag.
  bool hasFlag(String key) => attrs.any((a) => a.key == key && a.isFlag);

  /// The value of [key], or null when absent or a flag.
  String? attr(String key) {
    for (final a in attrs) {
      if (a.key == key) return a.value;
    }
    return null;
  }
}

/// The line looks like a marker but is not a valid one. Silently treating it as
/// a plain comment would make a typo quietly weaken a form, so it is reported.
class BadMarker extends FormMarkerScan {
  const BadMarker(this.name, this.reason, [this.facts = const {}]);

  /// The marker it was meant to be.
  final FormMarkerName name;

  /// A stable token: `punctuation-after-name`, `trailing-text`, `not-single-line`,
  /// `bad-attribute-key`, `empty-value`, `unterminated-quote`, `junk-after-quote`,
  /// `bad-bare-value`, `duplicate-attribute`, `unexpected-attributes`, `missing-id`.
  final String reason;
  final Map<String, Object?> facts;
}

/// A comment whose first word is a marker name in the wrong case
/// (`<!-- Field … -->`). Names are case-sensitive, so it is not a marker — but
/// it is almost certainly meant to be one, and the author is told.
class MiscasedMarker extends FormMarkerScan {
  const MiscasedMarker(this.given, this.expected);

  final String given;
  final FormMarkerName expected;
}

// A marker line: at most three leading blanks (four is a code block), a comment
// that closes on the same line, and nothing after it but blanks. A CR is not
// part of [lineText] — the caller already split on "\n" and dropped it.
final RegExp _commentLine = RegExp(r'^[ \t]{0,3}<!--((?:(?!-->).)*)-->(.*)$');
final RegExp _commentOpen = RegExp(r'^[ \t]{0,3}<!--(.*)$');
final RegExp _key = RegExp(r'[a-z][a-z0-9-]*');
final RegExp _punctuatedName = RegExp(
  r'^(/?(?:form|field|answer|notice))[:;,.]+$',
);

/// Splits [lineText] (one line, no line ending) into a marker, or says why not.
FormMarkerScan scanMarkerLine(String lineText) {
  final closed = _commentLine.firstMatch(lineText);
  if (closed == null) {
    // Not closed on this line. Only a comment that *starts* like a marker is
    // worth a diagnosis; a multi-line prose comment is none of our business.
    final open = _commentOpen.firstMatch(lineText);
    if (open == null) return const NoMarker();
    final first = _firstToken(open.group(1)!);
    final name = first == null ? null : FormMarkerName.fromWire(first);
    return name == null ? const NoMarker() : BadMarker(name, 'not-single-line');
  }

  final inner = closed.group(1)!;
  final trailing = closed.group(2)!;
  final first = _firstToken(inner);
  if (first == null) return const NoMarker();

  final name = FormMarkerName.fromWire(first);
  if (name == null) {
    for (final n in FormMarkerName.values) {
      if (n.wire != first && n.wire == first.toLowerCase()) {
        return MiscasedMarker(first, n);
      }
    }
    final punctuated = _punctuatedName.firstMatch(first);
    if (punctuated != null) {
      return BadMarker(
        FormMarkerName.fromWire(punctuated.group(1)!)!,
        'punctuation-after-name',
      );
    }
    return const NoMarker();
  }

  if (trailing.trim().isNotEmpty) return BadMarker(name, 'trailing-text');

  final rest = inner.substring(inner.indexOf(first) + first.length);
  final attrs = <FormAttr>[];
  final failure = _readAttrs(rest, attrs);
  if (failure != null) return BadMarker(name, failure.$1, failure.$2);

  return _checkAllowedAttrs(name, attrs);
}

/// The first whitespace-delimited word of [inner], or null if it is blank.
String? _firstToken(String inner) {
  final trimmed = inner.trimLeft();
  if (trimmed.isEmpty) return null;
  final end = trimmed.indexOf(RegExp(r'[ \t]'));
  return end < 0 ? trimmed : trimmed.substring(0, end);
}

bool _isBlank(String ch) => ch == ' ' || ch == '\t';

/// Reads `key`, `key=bare` and `key="quoted"` attributes from [rest] into
/// [out]. Returns null on success, or `(reason, facts)` for the first problem.
(String, Map<String, Object?>)? _readAttrs(String rest, List<FormAttr> out) {
  var i = 0;
  final seen = <String>{};
  while (true) {
    while (i < rest.length && _isBlank(rest[i])) {
      i++;
    }
    if (i >= rest.length) return null;

    final keyMatch = _key.matchAsPrefix(rest, i);
    if (keyMatch == null) {
      return ('bad-attribute-key', {'at': rest.substring(i, i + 1)});
    }
    final key = keyMatch.group(0)!;
    i = keyMatch.end;
    if (!seen.add(key)) return ('duplicate-attribute', {'key': key});

    if (i >= rest.length || _isBlank(rest[i])) {
      out.add(FormAttr(key, null));
      continue;
    }
    if (rest[i] != '=') {
      return ('bad-attribute-key', {'at': rest.substring(i, i + 1)});
    }
    i++; // the "="

    if (i >= rest.length || _isBlank(rest[i])) {
      return ('empty-value', {'key': key});
    }
    if (rest[i] == '"') {
      final close = rest.indexOf('"', i + 1);
      if (close < 0) return ('unterminated-quote', {'key': key});
      out.add(FormAttr(key, rest.substring(i + 1, close)));
      i = close + 1;
      if (i < rest.length && !_isBlank(rest[i])) {
        return ('junk-after-quote', {'key': key});
      }
    } else {
      final start = i;
      while (i < rest.length && !_isBlank(rest[i])) {
        i++;
      }
      final bare = rest.substring(start, i);
      if (bare.contains('"') || bare.contains('=')) {
        return ('bad-bare-value', {'key': key});
      }
      out.add(FormAttr(key, bare));
    }
  }
}

/// Enforces which markers may carry attributes at all.
FormMarkerScan _checkAllowedAttrs(FormMarkerName name, List<FormAttr> attrs) {
  switch (name) {
    case FormMarkerName.form:
    case FormMarkerName.field:
      return FoundMarker(name, attrs);
    case FormMarkerName.answer:
    case FormMarkerName.notice:
    case FormMarkerName.noticeEnd:
      return attrs.isEmpty
          ? FoundMarker(name, attrs)
          : BadMarker(name, 'unexpected-attributes');
    case FormMarkerName.fieldEnd:
      final hasId = attrs.any((a) => a.key == 'id' && !a.isFlag);
      if (!hasId) return BadMarker(name, 'missing-id');
      return attrs.length == 1
          ? FoundMarker(name, attrs)
          : BadMarker(name, 'unexpected-attributes');
  }
}

// ── Blocks, for the surfaces that treat a form block as one atomic unit ──────

/// The three things OciDeck's reader and visual editor carry as one block:
/// the `form` marker, a whole field (its markers, label, guidance and answer
/// zone), and the `notice` region (FORM_INTAKE.md §4.9).
enum FormBlockKind { header, field, notice }

/// The kind of block that starts at [line], or null when it starts none.
FormBlockKind? formBlockKind(String line) {
  final scan = scanMarkerLine(_withoutCr(line));
  if (scan is! FoundMarker) return null;
  return switch (scan.name) {
    FormMarkerName.form => FormBlockKind.header,
    FormMarkerName.field => FormBlockKind.field,
    FormMarkerName.notice => FormBlockKind.notice,
    _ => null,
  };
}

/// How many lines the block that opens at `lineAt(0)` spans, or null when that
/// line opens none or its block never closes (an unclosed block is not a block:
/// it stays visible as text, so a half-destroyed form looks destroyed).
///
/// [lineAt] answers "what is the line [offset] lines further on" and null past
/// the end, so a caller that holds a list of lines and one that holds a
/// look-ahead parser (the Markdown parser of the visual editor) use the very same
/// rule. A field ends at the `/field` marker with **its own id**, whatever
/// fences or other markers lie in between — exactly where `parseForm` ends its
/// answer zone. The look-ahead is bounded by [maxLines] so a document full of
/// unclosed fields cannot cost quadratic time.
int? formBlockLength(
  String? Function(int offset) lineAt, {
  int maxLines = 50000,
}) {
  final first = lineAt(0);
  if (first == null) return null;
  final scan = scanMarkerLine(_withoutCr(first));
  if (scan is! FoundMarker) return null;

  switch (scan.name) {
    case FormMarkerName.form:
      return 1;
    case FormMarkerName.field:
      final id = scan.attr('id');
      if (id == null || id.isEmpty) return null;
      return _lengthUntil(lineAt, maxLines, (m) {
        return m.name == FormMarkerName.fieldEnd && m.attr('id') == id;
      });
    case FormMarkerName.notice:
      return _lengthUntil(
        lineAt,
        maxLines,
        (m) => m.name == FormMarkerName.noticeEnd,
      );
    default:
      return null;
  }
}

int? _lengthUntil(
  String? Function(int offset) lineAt,
  int maxLines,
  bool Function(FoundMarker) closes,
) {
  for (var offset = 1; offset < maxLines; offset++) {
    final line = lineAt(offset);
    if (line == null) return null;
    final scan = scanMarkerLine(_withoutCr(line));
    if (scan is FoundMarker && closes(scan)) return offset + 1;
  }
  return null;
}

String _withoutCr(String line) =>
    line.endsWith('\r') ? line.substring(0, line.length - 1) : line;

/// A field block taken apart for display: the template-owned [label] (label,
/// guidance, and for a consent field the consent text) and the [answer] zone.
typedef FormFieldBlockParts = ({String label, String answer});

/// Splits the text of one field block — the lines from its `field` marker to its
/// `/field` marker — into label and answer, without the three marker lines.
///
/// The answer marker is the first `answer` marker that is not inside fenced code
/// (a fence in the label hides it, as everywhere else); an answer zone is
/// everything after it up to the closing marker. A block with no answer marker
/// has an empty answer. Never throws.
FormFieldBlockParts splitFieldBlock(String block) {
  final lines = block.split('\n');
  var end = lines.length;
  if (end > 1) {
    final last = scanMarkerLine(_withoutCr(lines.last));
    if (last is FoundMarker && last.name == FormMarkerName.fieldEnd) end--;
  }
  final fence = FormFenceTracker();
  var answerAt = -1;
  for (var i = 1; i < end; i++) {
    if (fence.isCode(_withoutCr(lines[i]))) continue;
    final scan = scanMarkerLine(_withoutCr(lines[i]));
    if (scan is FoundMarker && scan.name == FormMarkerName.answer) {
      answerAt = i;
      break;
    }
  }
  if (answerAt < 0) {
    return (label: lines.sublist(1.clamp(0, end), end).join('\n'), answer: '');
  }
  return (
    label: lines.sublist(1, answerAt).join('\n'),
    answer: lines.sublist(answerAt + 1, end).join('\n'),
  );
}
