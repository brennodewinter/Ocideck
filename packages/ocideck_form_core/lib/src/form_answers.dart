/// Reading an answer out of its zone (FORM_INTAKE.md §4.5, "On disk").
///
/// [parseAnswer] turns the text of **one** answer zone into the typed value its
/// field type means — one line, a task list, a table with a fixed header, a row
/// of image references, a single consent box — and says when the text is not in
/// the shape the type demands (`answer-malformed`). It judges **shape only**:
/// whether `150..300` words was met, or an option is one of the listed ones, is
/// the validator's job. [extractAnswers] does it for a whole submission, against
/// the *published* form (§4.11 step 3): the submission's own copy of the rules is
/// never consulted.
library;

import 'form_answer_safety.dart' show kFormImagePathPattern;
import 'form_issue.dart';
import 'form_parser.dart';
import 'form_spec.dart';

/// One image reference in an answer: `![alt](images/name.jpg "credit")`.
class FormImageRef {
  const FormImageRef(this.path, this.alt, this.credit);

  final String path;
  final String alt;

  /// The title, which an image field with the `credit` rule treats as the credit.
  final String? credit;

  @override
  bool operator ==(Object other) =>
      other is FormImageRef &&
      other.path == path &&
      other.alt == alt &&
      other.credit == credit;

  @override
  int get hashCode => Object.hash(path, alt, credit);
}

/// The typed value of one answer — what a field type means, without the text it
/// was read from. [FormAnswer.value] gives it; `formatAnswer` writes it back.
///
/// Which members carry data depends on the type, as for [FormAnswer]. Two values
/// are equal when all five members are (lists compared element by element).
class FormAnswerValue {
  const FormAnswerValue({
    this.text,
    this.items = const [],
    this.rows = const [],
    this.images = const [],
    this.consent,
  });

  final String? text;
  final List<String> items;
  final List<List<String>> rows;
  final List<FormImageRef> images;
  final bool? consent;

  @override
  bool operator ==(Object other) =>
      other is FormAnswerValue &&
      other.text == text &&
      other.consent == consent &&
      _sameList(other.items, items) &&
      _sameList(other.images, images) &&
      other.rows.length == rows.length &&
      [
        for (var i = 0; i < rows.length; i++) _sameList(other.rows[i], rows[i]),
      ].every((same) => same);

  @override
  int get hashCode => Object.hash(
    text,
    consent,
    Object.hashAll(items),
    Object.hashAll(images),
    Object.hashAll(rows.map(Object.hashAll)),
  );

  @override
  String toString() =>
      'FormAnswerValue(text: $text, items: $items, rows: $rows, '
      'images: ${images.length}, consent: $consent)';
}

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The typed content of one answer zone.
///
/// Which members carry data depends on the type: [text] for text, prose,
/// number, date and choice; [items] for list (its items) and multichoice (the
/// checked options); [rows] for a table; [images] for an image field; [consent]
/// for a consent box. The others stay empty.
class FormAnswer {
  const FormAnswer({
    required this.fieldId,
    required this.type,
    required this.raw,
    required this.firstLine,
    required this.isEmpty,
    this.text,
    this.items = const [],
    this.rows = const [],
    this.images = const [],
    this.consent,
    this.shape = const [],
  });

  final String fieldId;
  final String type;

  /// The zone exactly as it is in the document, line endings included.
  final String raw;

  /// The 1-based document line of the zone's first line.
  final int firstLine;

  /// Nothing has been answered: no text, no checked option, no item, no row, no
  /// image. An empty answer to a field that is not required is simply fine.
  final bool isEmpty;

  final String? text;
  final List<String> items;
  final List<List<String>> rows;
  final List<FormImageRef> images;

  /// The state of the consent box; null when there is no valid box.
  final bool? consent;

  /// `answer-malformed` problems found while reading: each says which `reason`
  /// and on which `line`.
  final List<FormProblem> shape;

  /// The typed value, without the text it was read from.
  FormAnswerValue get value => FormAnswerValue(
    text: text,
    items: items,
    rows: rows,
    images: images,
    consent: consent,
  );
}

/// The answers of a submission, and what is wrong with its structure.
class FormAnswers {
  const FormAnswers(this.byId, this.structure);

  /// By field id, in the order of the published form. A field the submission
  /// lacks has no entry (and a `field-missing` in [structure]).
  final Map<String, FormAnswer> byId;

  /// Problems with the shape of the submission as a whole: a missing or extra
  /// field, a damaged structure, a form version that is not the published one.
  final List<FormProblem> structure;
}

// ── parseAnswer ─────────────────────────────────────────────────────────────

/// Reads [zone], the text of the answer zone of [field], whose first line is
/// document line [firstLine].
FormAnswer parseAnswer(FormFieldSpec field, String zone, {int firstLine = 1}) {
  final lines = zone.replaceAll('\r\n', '\n').split('\n');
  final shape = <FormProblem>[];

  void malformed(String reason, int index) => shape.add(
    FormProblem(
      FormIssueCode.answerMalformed,
      line: firstLine + index,
      fieldId: field.id,
      facts: {'reason': reason},
    ),
  );

  FormAnswer build({
    required bool isEmpty,
    String? text,
    List<String> items = const [],
    List<List<String>> rows = const [],
    List<FormImageRef> images = const [],
    bool? consent,
  }) => FormAnswer(
    fieldId: field.id,
    type: field.type,
    raw: zone,
    firstLine: firstLine,
    isEmpty: isEmpty,
    text: text,
    items: items,
    rows: rows,
    images: images,
    consent: consent,
    shape: shape,
  );

  final indexes = [
    for (var i = 0; i < lines.length; i++)
      if (lines[i].trim().isNotEmpty) i,
  ];

  switch (field.type) {
    case 'prose':
      final text = lines.join('\n').trim();
      return build(isEmpty: text.isEmpty, text: text);
    case 'text':
    case 'number':
    case 'date':
    case 'choice':
      if (indexes.length > 1) malformed('one-line', indexes[1]);
      final text = lines.join('\n').trim();
      return build(isEmpty: text.isEmpty, text: text);
    case 'multichoice':
      final checked = _readMultichoice(lines, indexes, malformed);
      return build(isEmpty: checked.isEmpty, items: checked);
    case 'list':
      final items = _readList(lines, indexes, field.flag('ordered'), malformed);
      return build(isEmpty: items.isEmpty, items: items);
    case 'table':
      final rows = _readTable(
        lines,
        indexes,
        field.list('columns') ?? const [],
        malformed,
      );
      return build(isEmpty: rows.isEmpty, rows: rows);
    case 'image':
      final images = _readImages(lines, indexes, malformed);
      return build(isEmpty: images.isEmpty, images: images);
    case 'consent':
      final box = _readConsent(lines, indexes, malformed);
      return build(isEmpty: false, consent: box);
  }
  return build(isEmpty: zone.trim().isEmpty, text: zone.trim());
}

typedef _Malformed = void Function(String reason, int lineIndex);

final RegExp _task = RegExp(r'^[-*+][ \t]+\[([ xX])\][ \t]+(\S.*)$');

List<String> _readMultichoice(
  List<String> lines,
  List<int> indexes,
  _Malformed malformed,
) {
  final checked = <String>[];
  for (final i in indexes) {
    final m = _task.firstMatch(lines[i].trim());
    if (m == null) {
      malformed('not-a-task-list', i);
    } else if (m.group(1) != ' ' && !checked.contains(m.group(2)!.trim())) {
      checked.add(m.group(2)!.trim());
    }
  }
  return checked;
}

final RegExp _bullet = RegExp(r'^[-*+](?:[ \t]+(.*))?$');
final RegExp _numbered = RegExp(r'^[0-9]{1,9}[.)](?:[ \t]+(.*))?$');

List<String> _readList(
  List<String> lines,
  List<int> indexes,
  bool ordered,
  _Malformed malformed,
) {
  final items = <String?>[]; // null: an empty item, kept only to hold its place
  for (final i in indexes) {
    final raw = lines[i];
    final trimmed = raw.trim();
    final isContinuation = raw.startsWith(' ') || raw.startsWith('\t');
    final bullet = isContinuation ? null : _bullet.firstMatch(trimmed);
    final number = isContinuation ? null : _numbered.firstMatch(trimmed);
    if (bullet != null || number != null) {
      if (ordered && bullet != null) {
        malformed('unordered-item', i);
      } else if (!ordered && number != null) {
        malformed('ordered-item', i);
      }
      final text = (bullet ?? number)!.group(1)?.trim() ?? '';
      items.add(text.isEmpty ? null : text);
    } else if (isContinuation && items.isNotEmpty && items.last != null) {
      items[items.length - 1] = '${items.last}\n$trimmed';
    } else if (isContinuation && items.isNotEmpty) {
      items[items.length - 1] = trimmed; // text under an empty item
    } else {
      malformed('not-a-list', i);
    }
  }
  return items.nonNulls.toList();
}

final RegExp _ruleCell = RegExp(r'^:?-+:?$');

List<String> _cells(String line) {
  var s = line.trim();
  if (s.startsWith('|')) s = s.substring(1);
  if (s.endsWith('|') && !s.endsWith(r'\|')) s = s.substring(0, s.length - 1);
  final cells = <String>[];
  final cell = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (s[i] == r'\' && i + 1 < s.length && s[i + 1] == '|') {
      cell.write('|');
      i++;
    } else if (s[i] == '|') {
      cells.add(cell.toString().trim());
      cell.clear();
    } else {
      cell.write(s[i]);
    }
  }
  cells.add(cell.toString().trim());
  return cells;
}

List<List<String>> _readTable(
  List<String> lines,
  List<int> indexes,
  List<String> columns,
  _Malformed malformed,
) {
  if (indexes.isEmpty) return const [];
  final headerAt = indexes.first;
  if (!lines[headerAt].contains('|')) {
    malformed('not-a-table', headerAt);
    return const [];
  }
  final header = _cells(lines[headerAt]);
  if (header.length != columns.length ||
      [
        for (var i = 0; i < columns.length; i++) header[i] == columns[i],
      ].contains(false)) {
    malformed('header-mismatch', headerAt);
    return const [];
  }
  if (indexes.length < 2) return const [];
  final ruleAt = indexes[1];
  final rule = _cells(lines[ruleAt]);
  if (rule.length != columns.length || !rule.every(_ruleCell.hasMatch)) {
    malformed('rule-row', ruleAt);
    return const [];
  }
  final rows = <List<String>>[];
  for (final i in indexes.skip(2)) {
    final cells = _cells(lines[i]);
    if (cells.length != columns.length) {
      malformed('row-shape', i);
    } else if (cells.any((c) => c.isNotEmpty)) {
      rows.add(cells);
    }
  }
  return rows;
}

final RegExp _anyImage = RegExp(r'!\[[^\]]*\]\([^)]*\)?');

final RegExp _image = RegExp(
  '!\\[([^\\]]*)\\]\\(\\s*<?($kFormImagePathPattern)>?'
  '(?:\\s+"([^"]*)")?\\s*\\)',
);

List<FormImageRef> _readImages(
  List<String> lines,
  List<int> indexes,
  _Malformed malformed,
) {
  final images = <FormImageRef>[];
  final seen = <String>{};
  for (final i in indexes) {
    final line = lines[i].trim();
    for (final m in _image.allMatches(line)) {
      final path = m.group(2)!;
      if (!seen.add(path)) {
        malformed('duplicate-image', i);
        continue;
      }
      images.add(FormImageRef(path, m.group(1)!, m.group(3)));
    }
    // What is left once every valid image is taken out. A malformed image
    // construct may remain — the safety rules report it as a bad image — but
    // anything else is text in an image field.
    final rest = line.replaceAll(_image, '').replaceAll(_anyImage, '');
    if (rest.trim().isNotEmpty) malformed('not-an-image', i);
  }
  return images;
}

final RegExp _box = RegExp(r'^-[ \t]+\[([ xX])\]$');

bool? _readConsent(
  List<String> lines,
  List<int> indexes,
  _Malformed malformed,
) {
  if (indexes.isEmpty) {
    malformed('consent-box-missing', 0);
    return null;
  }
  final m = indexes.length == 1
      ? _box.firstMatch(lines[indexes.first].trim())
      : null;
  if (m == null) {
    malformed('consent-box', indexes.first);
    return null;
  }
  return m.group(1) != ' ';
}

// ── extractAnswers ──────────────────────────────────────────────────────────

/// A submission read as far as its structure goes: its [spec] when it is a form
/// this engine can read, otherwise the `structure-damaged` problem that says why.
/// Exactly one of the two is set.
typedef SubmissionStructure = ({FormSpec? spec, FormProblem? damaged});

/// Parses [markdown] and says whether it is a readable form (FORM_INTAKE.md §4.4).
SubmissionStructure readSubmissionStructure(String markdown) {
  FormProblem damaged(String reason, [Map<String, Object?> facts = const {}]) =>
      FormProblem(
        FormIssueCode.structureDamaged,
        facts: {'reason': reason, ...facts},
      );

  switch (parseForm(markdown)) {
    case NotAForm():
      return (spec: null, damaged: damaged('not-a-form'));
    case BrokenForm(:final problems):
      return (
        spec: null,
        damaged: damaged('broken', {
          'problems': problems.take(5).map((p) => p.code.wireName).join(','),
          'line': problems.first.line,
        }),
      );
    case ParsedForm(canFill: false):
      return (spec: null, damaged: damaged('rules-too-new'));
    case ParsedForm(:final spec):
      return (spec: spec, damaged: null);
  }
}

/// Reads the answers of [markdown] — a draft or a submission — against the
/// **published** form [spec].
///
/// The submission is parsed to find where its answer zones are; its own copy of
/// the rules (the attributes in its markers) is *never* used to decide what is
/// required or how long an answer may be: a modified or merely old client could
/// have weakened them. Structural trouble comes back as problems, not as an
/// exception: `structure-damaged` when it is not a form this engine can read,
/// `field-missing`, `field-not-in-form`, and the warning `form-version-mismatch`.
FormAnswers extractAnswers(FormSpec spec, String markdown) {
  final read = readSubmissionStructure(markdown);
  final submission = read.spec;
  if (submission == null) return FormAnswers(const {}, [read.damaged!]);

  if (submission.id != spec.id) {
    return FormAnswers(const {}, [
      FormProblem(
        FormIssueCode.structureDamaged,
        facts: {
          'reason': 'form-id',
          'published': spec.id,
          'submission': submission.id,
        },
      ),
    ]);
  }

  final structure = <FormProblem>[];
  if (submission.version != spec.version) {
    structure.add(
      FormProblem(
        FormIssueCode.formVersionMismatch,
        facts: {'published': spec.version, 'submission': submission.version},
      ),
    );
  }
  final answers = <String, FormAnswer>{};
  for (final field in spec.fields) {
    final theirs = submission.fieldById(field.id);
    if (theirs == null) {
      structure.add(FormProblem(FormIssueCode.fieldMissing, fieldId: field.id));
      continue;
    }
    answers[field.id] = parseAnswer(
      field,
      markdown.substring(theirs.zone.start, theirs.zone.end),
      firstLine: theirs.answer.line + 1,
    );
  }
  for (final theirs in submission.fields) {
    if (spec.fieldById(theirs.id) == null) {
      structure.add(
        FormProblem(
          FormIssueCode.fieldNotInForm,
          line: theirs.open.line,
          fieldId: theirs.id,
        ),
      );
    }
  }
  return FormAnswers(answers, structure);
}
