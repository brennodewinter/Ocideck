/// Writing an answer back into its zone (FORM_INTAKE.md §4.1, §4.10): the inverse
/// of [parseAnswer].
///
/// The fill view changes **only the bytes inside an answer zone** and leaves every
/// other byte of the file alone — CRLF, trailing spaces, an absent final newline,
/// a BOM. [formatAnswer] turns the typed value of one field into the text of its
/// zone; [applyAnswer] puts that text in the document and hands back the document
/// together with its freshly parsed spec, *or refuses* when the result would no
/// longer be the same form. The refusal is the point: an answer that contains a
/// line such as `<!-- /field id=naam -->` would end its own zone early and move
/// every field below it, and nothing the respondent can type may change what the
/// form *is*.
library;

import 'form_answers.dart';
import 'form_blocks.dart';
import 'form_issue.dart';
import 'form_parser.dart';
import 'form_spec.dart';

/// The text of one zone for [value], in the shape [parseAnswer] reads back.
///
/// [eol] is the line ending of the document the zone goes into; every line of the
/// zone, the last one too, ends with it. A value that is empty gives the *skeleton*
/// of its type — a blank line, a table with only its header, a consent box that is
/// not ticked, a multichoice with every option unticked — so a plain-Markdown
/// reader still sees where the answer goes.
///
/// Values are written **as given** except where the type's own shape would break:
/// a single-line type collapses line breaks to spaces, a table cell and a list item
/// lose their blank lines, a `|` in a cell is escaped, an image's alternative text
/// and credit lose the characters that would end them. Whether the content is
/// *allowed* (no marker line, no raw HTML, §4.6) is for the safety rules and the
/// validator, not for the writer.
String formatAnswer(
  FormFieldSpec field,
  FormAnswerValue value, {
  String eol = '\n',
}) {
  final lines = switch (field.type) {
    'text' || 'number' || 'date' || 'choice' => _oneLine(value.text ?? ''),
    'multichoice' => _multichoice(field, value.items),
    'list' => _list(value.items, field.flag('ordered')),
    'table' => _table(field.list('columns') ?? const [], value.rows),
    'image' => _images(value.images),
    'consent' => [value.consent == true ? '- [x]' : '- [ ]'],
    _ => _prose(value.text ?? ''),
  };
  if (lines.isEmpty) return eol;
  return '${lines.join(eol)}$eol';
}

List<String> _split(String text) => text.replaceAll('\r\n', '\n').split('\n');

List<String> _prose(String text) {
  final lines = _split(text);
  var first = 0;
  var last = lines.length;
  while (first < last && lines[first].trim().isEmpty) {
    first++;
  }
  while (last > first && lines[last - 1].trim().isEmpty) {
    last--;
  }
  return [
    for (var i = first; i < last; i++)
      // The first line's indent goes too: `parseAnswer` trims the whole zone, so
      // an indent kept here would be gone after one read and the value would
      // change under the respondent's hands.
      i == first ? lines[i].trim() : lines[i].trimRight(),
  ];
}

/// One line: every run of line breaks and blanks around them becomes one space.
List<String> _oneLine(String text) {
  final line = _split(
    text,
  ).map((l) => l.trim()).where((l) => l.isNotEmpty).join(' ');
  return line.isEmpty ? const [] : [line];
}

List<String> _multichoice(FormFieldSpec field, List<String> checked) {
  final options = field.list('options') ?? const <String>[];
  final single = [for (final c in checked) _oneLineText(c)];
  return [
    for (final option in options)
      '- [${single.contains(option) ? 'x' : ' '}] $option',
    // Own text of an `other` field: not one of the options, so it has no box of
    // its own in the template — it is added as a ticked one.
    for (final extra in single.toSet())
      if (extra.isNotEmpty && !options.contains(extra)) '- [x] $extra',
  ];
}

String _oneLineText(String text) => _oneLine(text).join();

List<String> _list(List<String> items, bool ordered) {
  final lines = <String>[];
  var n = 0;
  for (final item in items) {
    final parts = _split(
      item,
    ).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (parts.isEmpty) continue;
    n++;
    lines.add('${ordered ? '$n.' : '-'} ${parts.first}');
    for (final more in parts.skip(1)) {
      lines.add('  $more');
    }
  }
  return lines;
}

String _cell(String value) => _oneLineText(value).replaceAll('|', r'\|');

String _row(List<String> cells) => '| ${cells.join(' | ')} |';

List<String> _table(List<String> columns, List<List<String>> rows) {
  final body = <String>[];
  for (final row in rows) {
    final cells = [
      for (var i = 0; i < columns.length; i++)
        _cell(i < row.length ? row[i] : ''),
    ];
    if (cells.any((c) => c.isNotEmpty)) body.add(_row(cells));
  }
  return [
    _row([for (final c in columns) _cell(c)]),
    _row([for (final _ in columns) '---']),
    ...body,
  ];
}

List<String> _images(List<FormImageRef> images) => [
  for (final image in images)
    '![${_altOf(image.alt)}](${image.path}${_creditOf(image.credit)})',
];

/// The alternative text without the characters that would end it early. They go
/// *before* the blanks are tidied: taking them out afterwards can leave a blank at
/// the edge, which the next read would trim and the value would change.
String _altOf(String alt) =>
    _oneLineText(alt.replaceAll(RegExp(r'[\[\]]'), ''));

String _creditOf(String? credit) {
  if (credit == null) return '';
  final clean = _oneLineText(credit.replaceAll('"', ''));
  return clean.isEmpty ? '' : ' "$clean"';
}

// ── applyAnswer ─────────────────────────────────────────────────────────────

/// The outcome of [applyAnswer].
sealed class FormEditResult {
  const FormEditResult();
}

/// The answer is in: the new [text] of the document and its freshly parsed [spec]
/// (every offset has moved from the old one).
class FormEdited extends FormEditResult {
  const FormEdited(this.text, this.spec);

  final String text;
  final FormSpec spec;
}

/// The answer would have changed the form itself, so nothing was written. [problem]
/// says why: `answer-contains-marker` when the answer holds a marker-shaped line,
/// `structure-damaged` for anything else that no longer parses to the same form.
class FormEditRefused extends FormEditResult {
  const FormEditRefused(this.problem);

  final FormProblem problem;
}

/// The line ending of [text]: `\r\n` when its first line break is one.
String formLineEnding(String text) {
  final nl = text.indexOf('\n');
  return nl > 0 && text.codeUnitAt(nl - 1) == 13 ? '\r\n' : '\n';
}

/// Replaces the text of [fieldId]'s zone in [source] with [zone]. [spec] must be
/// the spec parsed from [source] itself; the bytes outside the zone are untouched.
String replaceAnswerZone(
  String source,
  FormSpec spec,
  String fieldId,
  String zone,
) {
  final field = spec.fieldById(fieldId);
  if (field == null) {
    throw ArgumentError.value(fieldId, 'fieldId', 'not a field of this form');
  }
  return source.replaceRange(field.zone.start, field.zone.end, zone);
}

/// Writes [value] as the answer of [fieldId] in [source] and parses the result.
///
/// Refuses ([FormEditRefused]) when the document, read again, is not a form with
/// the same fields in the same order — see the library comment for why. [spec] is
/// the spec parsed from [source].
FormEditResult applyAnswer(
  String source,
  FormSpec spec,
  String fieldId,
  FormAnswerValue value,
) {
  final field = spec.fieldById(fieldId);
  if (field == null) {
    throw ArgumentError.value(fieldId, 'fieldId', 'not a field of this form');
  }
  final zone = formatAnswer(field, value, eol: formLineEnding(source));
  final text = replaceAnswerZone(source, spec, fieldId, zone);

  // Read the document again and demand the one property that matters: the only
  // thing that changed is this zone, and it is exactly what was written. Checking
  // that the fields are still there is not enough — a fence opened in the answer
  // swallows its own closing line and leaves a form that parses, with the same
  // fields, and a zone that ends early; and a spec that is not the document's own
  // would have been written at the wrong offsets.
  final again = parseForm(text);
  if (again is ParsedForm) {
    final now = again.spec.fieldById(fieldId)?.zone;
    if (now != null &&
        text.replaceRange(now.start, now.end, _zoneOf(source, field)) ==
            source) {
      return FormEdited(text, again.spec);
    }
  }
  return FormEditRefused(
    _hasMarkerLine(zone)
        ? FormProblem(FormIssueCode.answerContainsMarker, fieldId: fieldId)
        : FormProblem(
            FormIssueCode.structureDamaged,
            fieldId: fieldId,
            facts: const {'reason': 'answer'},
          ),
  );
}

String _zoneOf(String source, FormFieldSpec field) =>
    source.substring(field.zone.start, field.zone.end);

bool _hasMarkerLine(String zone) {
  for (final line in zone.replaceAll('\r\n', '\n').split('\n')) {
    // Only a well-formed marker can end the zone or move a field; a malformed
    // one is for the safety rules, which flag it without the structure moving.
    if (scanMarkerLine(line) is FoundMarker) return true;
  }
  return false;
}
