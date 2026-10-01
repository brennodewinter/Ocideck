/// Reads a form template (FORM_INTAKE.md §4.3, §4.4).
///
/// [parseForm] never throws and never returns `null`: a text is either not a form
/// ([NotAForm]), a usable one ([ParsedForm]) or a form with author errors
/// ([BrokenForm]) — and the last two say *where* every part is, as offsets into
/// the string, so the fill view can change only answer zones later.
///
/// The structure is a small state machine over the lines of the body:
///
///     outside ──field──▶ label ──answer──▶ zone ──/field id=…──▶ outside
///        └─notice──▶ notice ──/notice──▶ outside
///
/// In the template-owned states a fence hides marker-shaped lines (they are
/// content) — which is also why the fence tracker is closed whenever a region
/// begins or ends: a line that is a marker was not inside a fence. In a **zone**
/// nothing hides them and nothing but the matching
/// `/field id=…` ends it, even inside a fence — structure must be deterministic
/// however an answer is written (§4.6). Whether an answer *may* contain a marker
/// line is a question for validation, not for this file.
library;

import 'form_blocks.dart';
import 'form_field_types.dart';
import 'form_issue.dart';
import 'form_rule_values.dart';
import 'form_source.dart';
import 'form_spec.dart';
import 'rules_version.dart';

/// However broken a text is, report no more than this many problems.
const int _maxProblems = 100;

final RegExp _slug = RegExp(r'^[a-z][a-z0-9-]*$');

/// Parses [markdown] as a form template.
FormParseResult parseForm(String markdown) => _FormParser(markdown).run();

enum _Mode { outside, label, zone, notice }

/// A field being read: open until its close marker is found.
class _FieldBuilder {
  _FieldBuilder(this.open, this.id, this.type, this.markerLine);

  final FormMarkerRef open;
  final String? id;
  final String? type;
  final int markerLine;

  bool valid = true;
  bool required = false;
  final Map<String, FormRuleValue> rules = {};
  final Map<String, String?> extra = {};

  FormMarkerRef? answer;
  FormMarkerRef? close;

  /// What a zone that never closed swallowed, for the diagnosis.
  int markersInZone = 0;
  final List<String> foundClosers = [];
}

/// The attributes of the `form` marker, interpreted.
class _Header {
  _Header(this.marker, this.id);

  final FormMarkerRef marker;
  final String id;
  int version = 1;
  int rules = 1;
  String? lang;
  String? controller;
  String? contact;
  String? retainUnused;
  String? closes;
  List<String> overview = const [];
  List<String> states = const [];
  List<String> keepRecord = const [];
  final Map<String, String?> extra = {};
}

class _FormParser {
  _FormParser(this._text) : _src = FormSource(_text);

  final String _text;
  final FormSource _src;

  final List<FormProblem> _problems = [];
  final FormFenceTracker _fence = FormFenceTracker();
  final List<_FieldBuilder> _fields = [];
  final Map<String, int> _idLines = {};

  _Mode _mode = _Mode.outside;
  _FieldBuilder? _cur;

  _Header? _header;
  bool _formSeen = false;
  bool _anyMarker = false;
  bool _reportedMissingForm = false;
  bool _intent = false;
  bool _tooNew = false;
  MiscasedMarker? _miscasedForm;

  FormMarkerRef? _noticeOpen;
  FormNotice? _notice;
  bool _noticeSeen = false;

  // ── problems ──────────────────────────────────────────────────────────────

  void _add(FormProblem problem) {
    if (_problems.length < _maxProblems) _problems.add(problem);
  }

  FormMarkerRef _ref(FormLine l) =>
      FormMarkerRef(l.number, l.start, l.end, l.nextStart);

  // ── the scan ──────────────────────────────────────────────────────────────

  FormParseResult run() {
    final lines = _src.lines;
    for (var i = _src.bodyStartIndex; i < lines.length && !_tooNew; i++) {
      final line = lines[i];
      if (_mode == _Mode.zone) {
        _inZone(line);
        continue;
      }
      if (_fence.isCode(line.text)) continue;
      switch (scanMarkerLine(line.text)) {
        case NoMarker():
          break;
        case MiscasedMarker m:
          _onMiscased(m, line);
        case BadMarker b:
          _onBad(b, line);
        case FoundMarker m:
          _onMarker(m, line);
      }
    }
    if (!_tooNew) _atEnd();
    return _result();
  }

  void _inZone(FormLine line) {
    final scan = scanMarkerLine(line.text);
    if (scan is! FoundMarker) return;
    final cur = _cur!;
    cur.markersInZone++;
    if (scan.name != FormMarkerName.fieldEnd) return;
    final id = scan.attr('id');
    if (cur.id == null || id == cur.id) {
      cur.close = _ref(line);
      _fields.add(cur);
      _cur = null;
      _mode = _Mode.outside;
    } else {
      cur.foundClosers.add('$id@${line.number}');
    }
  }

  void _onMiscased(MiscasedMarker m, FormLine line) {
    _add(
      FormProblem(
        FormIssueCode.unknownMarker,
        line: line.number,
        facts: {'given': m.given, 'expected': m.expected.wire},
      ),
    );
    if (m.expected == FormMarkerName.form) _miscasedForm ??= m;
  }

  void _onBad(BadMarker b, FormLine line) {
    _noteMarkerSeen(b.name);
    if (b.name == FormMarkerName.form) _formSeen = true;
    _add(
      FormProblem(
        FormIssueCode.markerMalformed,
        line: line.number,
        facts: {...b.facts, 'marker': b.name.wire, 'reason': b.reason},
      ),
    );
  }

  /// Bookkeeping common to every marker that is not `form` itself: the form
  /// marker must be first, and a structural marker with no form before it is
  /// reported once.
  void _noteMarkerSeen(FormMarkerName name, [int? lineNumber]) {
    final structural =
        name == FormMarkerName.field ||
        name == FormMarkerName.answer ||
        name == FormMarkerName.fieldEnd;
    if (structural || name == FormMarkerName.form) _intent = true;
    if (structural &&
        !_formSeen &&
        !_reportedMissingForm &&
        lineNumber != null) {
      _reportedMissingForm = true;
      _add(
        FormProblem(
          FormIssueCode.markerMisplaced,
          line: lineNumber,
          facts: {'reason': 'form-missing', 'marker': name.wire},
        ),
      );
    }
    _anyMarker = true;
  }

  void _onMarker(FoundMarker m, FormLine line) {
    if (m.name != FormMarkerName.form) _noteMarkerSeen(m.name, line.number);
    switch (m.name) {
      case FormMarkerName.form:
        _onForm(m, line);
      case FormMarkerName.field:
        _onField(m, line);
      case FormMarkerName.answer:
        _onAnswer(line);
      case FormMarkerName.fieldEnd:
        _onFieldEnd(line);
      case FormMarkerName.notice:
        _onNotice(line);
      case FormMarkerName.noticeEnd:
        _onNoticeEnd(line);
    }
  }

  // ── the form marker ───────────────────────────────────────────────────────

  void _onForm(FoundMarker m, FormLine line) {
    _intent = true;
    if (_formSeen) {
      _add(
        FormProblem(
          FormIssueCode.markerMisplaced,
          line: line.number,
          facts: {'reason': 'second-form'},
        ),
      );
      return;
    }
    if (_anyMarker) {
      _add(
        FormProblem(
          FormIssueCode.markerMisplaced,
          line: line.number,
          facts: {'reason': 'form-not-first'},
        ),
      );
    }
    _formSeen = true;
    _anyMarker = true;
    final header = _readHeader(m, line);
    _header = header;
    if (header != null &&
        !supportsFormRules(header.rules) &&
        !_problems.any((p) => p.isError)) {
      _tooNew = true;
    }
  }

  /// Interprets the attributes of the `form` marker; null when the id is
  /// unusable (the problems say why).
  _Header? _readHeader(FoundMarker m, FormLine line) {
    final at = line.number;
    void malformed(String key, String reason, [Map<String, Object?>? facts]) =>
        _add(
          FormProblem(
            FormIssueCode.ruleMalformed,
            line: at,
            facts: {'rule': key, 'reason': reason, ...?facts},
          ),
        );

    final idRaw = m.attr('id');
    if (idRaw == null) {
      _add(
        FormProblem(
          FormIssueCode.markerMalformed,
          line: at,
          facts: {
            'marker': 'form',
            'attribute': 'id',
            'reason': 'missing-attribute',
          },
        ),
      );
    } else if (!_slug.hasMatch(idRaw)) {
      _add(
        FormProblem(
          FormIssueCode.markerMalformed,
          line: at,
          facts: {
            'marker': 'form',
            'attribute': 'id',
            'reason': 'bad-id',
            'value': idRaw,
          },
        ),
      );
    }

    final header = _Header(_ref(line), idRaw ?? '');

    for (final attr in m.attrs) {
      final key = attr.key;
      if (key == 'id') continue;
      final value = attr.value;
      final known = const {
        'version',
        'rules',
        'lang',
        'controller',
        'contact',
        'retain-unused',
        'closes',
        'overview',
        'states',
        'keep-record',
      }.contains(key);
      if (!known) {
        header.extra[key] = value;
        _add(
          FormProblem(
            FormIssueCode.unknownRule,
            line: at,
            facts: {'rule': key, 'where': 'form'},
          ),
        );
        continue;
      }
      if (value == null) {
        malformed(key, 'value-required');
        continue;
      }
      switch (key) {
        case 'version':
        case 'rules':
          final n = parseRuleInt(value);
          if (n == null || n < 1) {
            malformed(key, 'not-a-positive-integer');
          } else if (key == 'version') {
            header.version = n;
          } else {
            header.rules = n;
          }
        case 'closes':
          if (isValidCalendarDate(value)) {
            header.closes = value;
          } else {
            malformed(key, 'bad-date');
          }
        case 'overview':
        case 'keep-record':
        case 'states':
          final list = parseRuleList(value, key == 'states' ? '|' : ',');
          if (list.error != null) {
            malformed(key, list.error!);
          } else if (key == 'overview') {
            header.overview = list.items!;
          } else if (key == 'keep-record') {
            header.keepRecord = list.items!;
          } else {
            header.states = list.items!;
          }
        default: // lang, controller, contact, retain-unused
          if (value.trim().isEmpty) {
            malformed(key, 'empty');
          } else {
            switch (key) {
              case 'lang':
                header.lang = value;
              case 'controller':
                header.controller = value;
              case 'contact':
                header.contact = value;
              default:
                header.retainUnused = value;
            }
          }
      }
    }
    return idRaw == null || !_slug.hasMatch(idRaw) ? null : header;
  }

  // ── fields ────────────────────────────────────────────────────────────────

  void _onField(FoundMarker m, FormLine line) {
    if (_mode == _Mode.label) {
      _unpaired(
        'missing-answer-marker',
        _cur!.markerLine,
        fieldId: _cur!.id,
        facts: {'at': line.number},
      );
      _cur = null;
    } else if (_mode == _Mode.notice) {
      _unpaired('notice-not-closed', _noticeOpen!.line);
      _noticeOpen = null;
    }
    _mode = _Mode.label;
    _cur = _readField(m, line);
  }

  _FieldBuilder _readField(FoundMarker m, FormLine line) {
    final at = line.number;
    final id = m.attr('id');
    final typeWord = m.attr('type');
    final field = _FieldBuilder(_ref(line), id, typeWord, at);

    void fail(FormProblem p) {
      field.valid = false;
      _add(p);
    }

    FormProblem missing(String attribute, String reason, [Object? value]) =>
        FormProblem(
          FormIssueCode.markerMalformed,
          line: at,
          fieldId: id,
          facts: {
            'marker': 'field',
            'attribute': attribute,
            'reason': reason,
            'value': ?value,
          },
        );

    if (id == null) {
      fail(missing('id', 'missing-attribute'));
    } else if (!_slug.hasMatch(id)) {
      fail(missing('id', 'bad-id', id));
    } else if (_idLines.containsKey(id)) {
      fail(
        FormProblem(
          FormIssueCode.duplicateFieldId,
          line: at,
          fieldId: id,
          facts: {'first': _idLines[id]},
        ),
      );
    } else {
      _idLines[id] = at;
    }

    final descriptor = typeWord == null ? null : kFormFieldTypes[typeWord];
    if (typeWord == null) {
      fail(missing('type', 'missing-attribute'));
    } else if (descriptor == null) {
      fail(
        FormProblem(
          FormIssueCode.unknownType,
          line: at,
          fieldId: id,
          facts: {'type': typeWord},
        ),
      );
    }
    if (descriptor != null) _readRules(m, field, descriptor, at);
    return field;
  }

  void _readRules(
    FoundMarker m,
    _FieldBuilder field,
    FormFieldTypeDescriptor descriptor,
    int at,
  ) {
    void malformed(String rule, String reason) {
      field.valid = false;
      _add(
        FormProblem(
          FormIssueCode.ruleMalformed,
          line: at,
          fieldId: field.id,
          facts: {'rule': rule, 'reason': reason},
        ),
      );
    }

    for (final attr in m.attrs) {
      final key = attr.key;
      if (key == 'id' || key == 'type') continue;
      if (key == 'required') {
        if (attr.isFlag) {
          field.required = true;
        } else {
          malformed(key, 'flag-takes-no-value');
        }
        continue;
      }
      final spec = descriptor.rule(key);
      if (spec == null) {
        field.extra[key] = attr.value;
        _add(
          FormProblem(
            FormIssueCode.unknownRule,
            line: at,
            fieldId: field.id,
            facts: {'rule': key},
          ),
        );
        continue;
      }
      final read = interpretRule(spec, attr);
      if (read.value != null) {
        field.rules[key] = read.value!;
      } else {
        malformed(key, read.reason!);
      }
    }
    for (final spec in descriptor.rules) {
      if (spec.required && !m.has(spec.key)) malformed(spec.key, 'missing');
    }
    if (field.valid) {
      for (final (rule, reason) in descriptor.crossChecks(field.rules)) {
        malformed(rule, reason);
      }
    }
  }

  void _onAnswer(FormLine line) {
    if (_mode != _Mode.label) {
      _unpaired('answer-outside-field', line.number);
      return;
    }
    _cur!.answer = _ref(line);
    _mode = _Mode.zone;
  }

  void _onFieldEnd(FormLine line) {
    if (_mode == _Mode.label) {
      _unpaired(
        'missing-answer-marker',
        _cur!.markerLine,
        fieldId: _cur!.id,
        facts: {'at': line.number},
      );
      _cur = null;
      _mode = _Mode.outside;
      return;
    }
    _unpaired('close-without-open', line.number);
  }

  // ── the notice ────────────────────────────────────────────────────────────

  void _onNotice(FormLine line) {
    switch (_mode) {
      case _Mode.label:
        _unpaired('notice-inside-field', line.number, fieldId: _cur!.id);
      case _Mode.notice:
        _unpaired('notice-not-closed', _noticeOpen!.line);
        _noticeOpen = _ref(line);
      case _Mode.outside:
        if (_noticeSeen) {
          _add(
            FormProblem(
              FormIssueCode.markerMisplaced,
              line: line.number,
              facts: {'reason': 'second-notice'},
            ),
          );
        }
        _noticeSeen = true;
        _noticeOpen = _ref(line);
        _mode = _Mode.notice;
      case _Mode.zone:
        break; // unreachable: zones are handled before markers are read
    }
  }

  void _onNoticeEnd(FormLine line) {
    if (_mode != _Mode.notice) {
      _unpaired('close-without-open', line.number);
      return;
    }
    _notice = FormNotice(_noticeOpen!, _ref(line));
    _noticeOpen = null;
    _mode = _Mode.outside;
  }

  // ── the end ───────────────────────────────────────────────────────────────

  void _unpaired(
    String reason,
    int line, {
    String? fieldId,
    Map<String, Object?> facts = const {},
  }) {
    _add(
      FormProblem(
        FormIssueCode.unpairedMarker,
        line: line,
        fieldId: fieldId,
        facts: {'reason': reason, ...facts},
      ),
    );
  }

  void _atEnd() {
    final cur = _cur;
    switch (_mode) {
      case _Mode.label:
        _unpaired(
          'missing-answer-marker',
          cur!.markerLine,
          fieldId: cur.id,
          facts: const {'at': 'end-of-file'},
        );
      case _Mode.zone:
        _unpaired(
          'unclosed-field',
          cur!.markerLine,
          fieldId: cur.id,
          facts: {
            if (cur.markersInZone > 0) 'markersInZone': cur.markersInZone,
            if (cur.foundClosers.isNotEmpty)
              'foundClosers': cur.foundClosers.join(', '),
          },
        );
      case _Mode.notice:
        _unpaired('notice-not-closed', _noticeOpen!.line);
      case _Mode.outside:
        break;
    }
    _checkReferences();
  }

  /// `overview=` and `keep-record=` may only name fields that exist.
  void _checkReferences() {
    final header = _header;
    if (header == null) return;
    void check(String rule, List<String> ids) {
      for (final id in ids) {
        if (!_idLines.containsKey(id)) {
          _add(
            FormProblem(
              FormIssueCode.ruleMalformed,
              line: header.marker.line,
              facts: {'rule': rule, 'reason': 'unknown-field', 'field': id},
            ),
          );
        }
      }
    }

    check('overview', header.overview);
    check('keep-record', header.keepRecord);
  }

  // ── the answer ────────────────────────────────────────────────────────────

  FormParseResult _result() {
    if (!_formSeen) {
      final miscased = _miscasedForm;
      if (miscased != null) {
        return BrokenForm(
          _problems
              .where((p) => p.code == FormIssueCode.unknownMarker)
              .toList(),
        );
      }
      if (!_intent) return const NotAForm();
      return BrokenForm(_problems.where((p) => p.isError).toList());
    }

    final errors = _problems.any((p) => p.isError);
    if (errors || _header == null) {
      return BrokenForm([
        for (final p in _problems)
          if (p.isError || p.code == FormIssueCode.unknownMarker) p,
      ]);
    }

    final header = _header!;
    final fields = [
      for (final f in _fields)
        if (f.valid && f.answer != null && f.close != null)
          FormFieldSpec(
            id: f.id!,
            type: f.type!,
            required: f.required,
            rules: f.rules,
            extraAttributes: f.extra,
            open: f.open,
            answer: f.answer!,
            close: f.close!,
          ),
    ];
    final introEnd = _tooNew || fields.isEmpty
        ? _text.length
        : fields.first.open.start;
    final spec = FormSpec(
      id: header.id,
      version: header.version,
      rules: header.rules,
      formMarker: header.marker,
      intro: FormRegion(header.marker.nextStart, introEnd),
      lang: header.lang,
      controller: header.controller,
      contact: header.contact,
      retainUnused: header.retainUnused,
      closes: header.closes,
      overview: header.overview,
      states: header.states,
      keepRecord: header.keepRecord,
      extraAttributes: header.extra,
      fields: _tooNew ? const [] : fields,
      notice: _tooNew ? null : _notice,
    );

    if (_tooNew) {
      return ParsedForm(spec, [
        FormProblem(
          FormIssueCode.rulesTooNew,
          line: header.marker.line,
          facts: {'declared': header.rules, 'supported': kFormRulesVersion},
        ),
      ]);
    }
    return ParsedForm(spec, [..._problems, ..._completeness(spec)]);
  }

  /// Warnings for an author about what a publishable form should say: the
  /// notice, the controller, a contact, how long data is kept (§7.7).
  List<FormProblem> _completeness(FormSpec spec) => [
    if (spec.notice == null) FormProblem(FormIssueCode.noticeMissing),
    for (final entry in {
      'controller': spec.controller,
      'contact': spec.contact,
      'retain-unused': spec.retainUnused,
    }.entries)
      if (entry.value == null)
        FormProblem(
          FormIssueCode.formAttributeMissing,
          line: spec.formMarker.line,
          facts: {'attribute': entry.key},
        ),
  ];
}
