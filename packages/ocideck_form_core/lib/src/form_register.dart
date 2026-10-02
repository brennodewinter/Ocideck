/// The register of an organiser's submissions: `overview.md` (FORM_INTAKE.md §7.3).
///
/// One Markdown table that the Inbox maintains and that the editors may also edit by
/// hand — it is a plain file that survives OciDeck. State lives *here* and nowhere
/// else (there is no `status.json`): a row per submission, keyed by its random id.
///
/// ```
/// | sid | naam | received | status | consent | withdrawn | delete-after |
/// |---|---|---|---|---|---|---|
/// | abc… | Sari | 2026-10-04 | received | 2026-10-04 | | |
/// ```
///
/// The register never *loses* what a person wrote in it. A table it cannot read — a
/// row with too few cells, a sid twice, a header without `status` — is reported as
/// damaged and left alone, never rewritten from what could be understood; text before
/// and after the table is kept as it was. Cells that come from a submission are
/// escaped so an answer can never turn into a link, an image or a table break.
library;

import 'form_answers.dart';
import 'form_package.dart';
import 'form_review.dart';
import 'form_spec.dart';

/// The file name of the register inside a workspace (§7.1).
const String kFormRegisterFile = 'overview.md';

/// The states a form has when it names none (§7.3).
const List<String> kDefaultFormStates = [
  'received',
  'maker-check-sent',
  'maker-approved',
  'edited',
  'laid-out',
];

/// What a row says after its submission was deleted: the minimal record (§7.3).
const String kFormStateDeleted = 'deleted';

/// What a row says while its submission has an error against the published form
/// (§4.11, §7.2): it is in the collection — the editors can work on it in
/// `submission.edit.md` — but nothing is accepted silently, and compile selects only
/// what an editor has moved on to a state of the form's own.
const String kFormStateNeedsFixing = 'needs-fixing';

/// The fixed columns, by the name in the table's header.
const String _sid = 'sid';
const String _received = 'received';
const String _status = 'status';
const String _consent = 'consent';
const String _withdrawn = 'withdrawn';
const String _deleteAfter = 'delete-after';

const List<String> _fixed = [
  _sid,
  _received,
  _status,
  _consent,
  _withdrawn,
  _deleteAfter,
];

/// The states [spec] allows, in its order: the ones it names, else the default.
List<String> formStatesOf(FormSpec spec) =>
    spec.states.isEmpty ? kDefaultFormStates : spec.states;

/// One submission in the register.
class FormRegisterRow {
  const FormRegisterRow(this.cells);

  /// The value in every column, by the name in the header — the columns the
  /// register knows and any a person added.
  final Map<String, String> cells;

  String get sid => cells[_sid] ?? '';
  String get received => cells[_received] ?? '';
  String get status => cells[_status] ?? '';

  /// The day the respondent gave consent, or empty when the form asks for none.
  String get consent => cells[_consent] ?? '';

  /// The day the respondent withdrew the submission, or empty.
  String get withdrawn => cells[_withdrawn] ?? '';

  /// The day after which an unused submission is to be deleted, or empty.
  String get deleteAfter => cells[_deleteAfter] ?? '';

  String valueOf(String column) => cells[column] ?? '';

  bool get isWithdrawn => withdrawn.isNotEmpty;
  bool get isDeleted => status == kFormStateDeleted;

  FormRegisterRow _with(Map<String, String> changes) =>
      FormRegisterRow({...cells, ...changes});
}

/// The result of reading `overview.md`.
sealed class FormRegisterRead {
  const FormRegisterRead();
}

class FormRegisterParsed extends FormRegisterRead {
  const FormRegisterParsed(this.register);

  final FormRegister register;
}

/// A register that cannot be read as it stands. Nothing is to be written over it.
class FormRegisterDamaged extends FormRegisterRead {
  const FormRegisterDamaged(this.reason, {this.line});

  /// Why, in a short English phrase for a log.
  final String reason;

  /// The 1-based line of the problem, when it is about one.
  final int? line;

  @override
  String toString() => line == null ? reason : '$reason (line $line)';
}

/// The register: a header, a row per submission and the text around the table.
class FormRegister {
  const FormRegister._(this.columns, this.rows, this._before, this._after);

  /// A register for [spec]: `sid`, the columns the form names in `overview=`, then
  /// the fixed ones (§7.3).
  factory FormRegister.empty(FormSpec spec) => FormRegister._(
    [
      _sid,
      ...spec.overview,
      _received,
      _status,
      _consent,
      _withdrawn,
      _deleteAfter,
    ],
    const [],
    '',
    '',
  );

  /// The names in the header, in order.
  final List<String> columns;
  final List<FormRegisterRow> rows;

  final String _before;
  final String _after;

  FormRegisterRow? row(String sid) {
    for (final r in rows) {
      if (r.sid == sid) return r;
    }
    return null;
  }

  FormRegister _rows(List<FormRegisterRow> next) =>
      FormRegister._(columns, next, _before, _after);

  FormRegister _change(String sid, Map<String, String> changes) =>
      _rows([for (final r in rows) r.sid == sid ? r._with(changes) : r]);

  /// The register with the overview columns of [spec] present: any it lacks is added
  /// before `received`, empty for the rows already there. A form that changes its
  /// `overview=` adds a column; it never removes one a person may have filled.
  FormRegister withOverviewOf(FormSpec spec) {
    final missing = [
      for (final id in spec.overview)
        if (!columns.contains(id)) id,
    ];
    if (missing.isEmpty) return this;
    final at = columns.indexOf(_received);
    return FormRegister._(
      [...columns.sublist(0, at), ...missing, ...columns.sublist(at)],
      [
        for (final r in rows) r._with({for (final id in missing) id: ''}),
      ],
      _before,
      _after,
    );
  }

  /// The register with a row for the submission [review] accepted, or `null` when its
  /// id is already in it: a submission is never entered twice, and an existing row is
  /// never overwritten.
  ///
  /// The overview columns take the first line of the answer, as plain text; the
  /// state is the first of the form's — or `needs-fixing` when the review found an
  /// error; the consent day is the one the manifest records.
  FormRegister? withSubmission(
    FormReview review, {
    required String received,
    String deleteAfter = '',
  }) {
    final spec = review.spec;
    final answers = review.answers;
    if (spec == null || answers == null) return null;
    final sid = review.manifest.submissionId;
    if (row(sid) != null) return null;
    final register = withOverviewOf(spec);
    final consent = review.manifest.consent;
    final cells = {
      _sid: sid,
      for (final id in spec.overview) id: _flat(_summary(answers.byId[id])),
      _received: received,
      _status: review.acceptable
          ? formStatesOf(spec).first
          : kFormStateNeedsFixing,
      _consent: consent.isEmpty ? '' : consent.first.accepted,
      _deleteAfter: deleteAfter,
    };
    return register._rows([...register.rows, FormRegisterRow(cells)]);
  }

  /// The register with [sid] in [status], or `null` when there is no such row, the
  /// submission was deleted, or [status] is not one of [states].
  FormRegister? withStatus(String sid, String status, List<String> states) {
    final current = row(sid);
    if (current == null || current.isDeleted || !states.contains(status)) {
      return null;
    }
    return _change(sid, {_status: status});
  }

  /// The register with [sid] marked withdrawn on [day] (`YYYY-MM-DD`). Compile
  /// honours it unconditionally (§7.3). `null` when there is no such row.
  FormRegister? withWithdrawal(String sid, String day) =>
      row(sid) == null ? null : _change(sid, {_withdrawn: day});

  /// The register with [sid] reduced to the **minimal record** (§7.3): state
  /// `deleted`, the id, the received and consent days and the withdrawal stay; every
  /// overview column is emptied except the ones in [keep] (the form's `keep-record`),
  /// and the reminder goes. `null` when there is no such row.
  FormRegister? withDeletion(String sid, {List<String> keep = const []}) {
    final current = row(sid);
    if (current == null) return null;
    final spec = columns.where((c) => !_fixed.contains(c));
    return _change(sid, {
      _status: kFormStateDeleted,
      _deleteAfter: '',
      for (final c in spec)
        if (!keep.contains(c)) c: '',
    });
  }

  /// The register as Markdown: the text before the table, the table, the text after.
  String toMarkdown() {
    final out = StringBuffer(_before)
      ..writeln(_line([for (final c in columns) _escape(c)]))
      ..writeln(_line([for (final _ in columns) '---']));
    for (final r in rows) {
      out.writeln(_line([for (final c in columns) _escape(r.valueOf(c))]));
    }
    return '$out$_after';
  }

  /// Reads `overview.md`. A table with no `sid` and `status` column, a row whose
  /// cells do not match the header, an id outside the grammar or used twice is
  /// [FormRegisterDamaged]; so is a text with no table at all.
  static FormRegisterRead parse(String markdown) {
    final lines = markdown.replaceAll('\r\n', '\n').split('\n');
    final start = lines.indexWhere(_isTableLine);
    if (start < 0) return const FormRegisterDamaged('no table');
    if (start + 1 >= lines.length || !_isDelimiter(lines[start + 1])) {
      return FormRegisterDamaged('no delimiter row', line: start + 2);
    }
    final header = _cells(lines[start]);
    for (final name in _fixed) {
      if (!header.contains(name)) {
        return FormRegisterDamaged('no "$name" column', line: start + 1);
      }
    }
    if (header.toSet().length != header.length) {
      return FormRegisterDamaged('a column twice', line: start + 1);
    }
    final rows = <FormRegisterRow>[];
    final seen = <String>{};
    var end = start + 2;
    while (end < lines.length && _isTableLine(lines[end])) {
      final cells = _cells(lines[end]);
      if (cells.length != header.length) {
        return FormRegisterDamaged('wrong number of cells', line: end + 1);
      }
      final row = FormRegisterRow({
        for (var i = 0; i < header.length; i++) header[i]: cells[i],
      });
      if (!isValidFormId(row.sid)) {
        return FormRegisterDamaged('not a submission id', line: end + 1);
      }
      if (!seen.add(row.sid)) {
        return FormRegisterDamaged('a submission twice', line: end + 1);
      }
      rows.add(row);
      end++;
    }
    final before = start == 0 ? '' : '${lines.sublist(0, start).join('\n')}\n';
    final after = lines.sublist(end).join('\n');
    return FormRegisterParsed(FormRegister._(header, rows, before, after));
  }
}

// ── the table ───────────────────────────────────────────────────────────────

bool _isTableLine(String line) => line.trimLeft().startsWith('|');

bool _isDelimiter(String line) =>
    _isTableLine(line) &&
    _cells(line).every((c) => RegExp(r'^:?-+:?$').hasMatch(c));

String _line(List<String> cells) => '| ${cells.join(' | ')} |';

/// The cells of a table line, unescaped. A pipe splits a cell unless a backslash
/// escapes it; a backslash before any ASCII punctuation is that character.
List<String> _cells(String line) {
  var text = line.trim();
  if (text.startsWith('|')) text = text.substring(1);
  final cells = <String>[];
  final cell = StringBuffer();
  var closed = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == r'\' &&
        i + 1 < text.length &&
        _punctuation.hasMatch(text[i + 1])) {
      cell.write(text[++i]);
    } else if (c == '|') {
      cells.add(cell.toString().trim());
      cell.clear();
      closed = i == text.length - 1;
    } else {
      cell.write(c);
    }
  }
  if (!closed) cells.add(cell.toString().trim());
  return cells;
}

final RegExp _punctuation = RegExp(r'[!-/:-@\[-`{-~]');

/// A value on one line: a line break and the space around it is one space.
String _flat(String value) =>
    value.replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ').trim();

/// A value as it goes in a cell: on one line, with every character that Markdown
/// could read as something else escaped, so an answer stays text.
String _escape(String value) => _flat(
  value,
).replaceAllMapped(RegExp(r'[\\|`*_\[\]<>!&#~]'), (m) => '\\${m[0]}');

/// What an answer shows in the register: its text up to the first line break, the
/// chosen options or the items of a list on one line; nothing for a table, a photo or
/// a consent.
String _summary(FormAnswer? answer) {
  if (answer == null) return '';
  if (answer.items.isNotEmpty) return answer.items.join(', ');
  return (answer.text ?? '').split('\n').first;
}
