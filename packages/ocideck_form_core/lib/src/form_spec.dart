/// What the parser returns (FORM_INTAKE.md §4.4): a typed description of a form
/// template, with the **position** of every part of it in the source.
///
/// Positions matter because the fill view later changes *only* the bytes inside
/// an answer zone and leaves every other byte of the file alone (§4.1). So the
/// spec never copies text out of the source; it says where text is, as offsets
/// into the string that was parsed.
library;

import 'form_field_types.dart';
import 'form_issue.dart';
import 'form_rule_values.dart';

/// Where a marker line sits: [start] is its first character (leading blanks
/// included), [end] just past its last character before the line ending, and
/// [nextStart] where the following line begins. `text.substring(start, end)` is
/// the marker itself; `[nextStart]` is where the text after it begins.
class FormMarkerRef {
  const FormMarkerRef(this.line, this.start, this.end, this.nextStart);

  /// 1-based.
  final int line;
  final int start;
  final int end;
  final int nextStart;
}

/// A half-open span `[start, end)` of the source.
class FormRegion {
  const FormRegion(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start;
  bool get isEmpty => end == start;
}

/// One field: its rules, and where its three parts are.
class FormFieldSpec {
  const FormFieldSpec({
    required this.id,
    required this.type,
    required this.required,
    required this.rules,
    required this.extraAttributes,
    required this.open,
    required this.answer,
    required this.close,
  });

  final String id;

  /// The `type=` word; always a key of [kFormFieldTypes].
  final String type;
  final bool required;

  /// The rules this type understands, typed. Does not include `required`.
  final Map<String, FormRuleValue> rules;

  /// Attributes the field's type does not know, as written (a flag has a null
  /// value). Kept so a form saved by this engine does not lose what a newer one
  /// wrote; reported to the author as `unknown-rule`.
  final Map<String, String?> extraAttributes;

  final FormMarkerRef open;
  final FormMarkerRef answer;
  final FormMarkerRef close;

  /// The template-owned text between the opening marker and the answer marker:
  /// the label, the guidance, and for a consent field the consent text itself.
  FormRegion get label => FormRegion(open.nextStart, answer.start);

  /// The only text a respondent edits.
  FormRegion get zone => FormRegion(answer.nextStart, close.start);

  FormRange? range(String key) {
    final v = rules[key];
    return v is RangeRule ? v.value : null;
  }

  int? intRule(String key) {
    final v = rules[key];
    return v is IntRule ? v.value : null;
  }

  List<String>? list(String key) {
    final v = rules[key];
    return v is ListRule ? v.items : null;
  }

  String? text(String key) {
    final v = rules[key];
    return v is TextRule ? v.value : null;
  }

  bool flag(String key) => rules[key] is FlagRule;
}

/// The `notice` region: text the respondent is shown before the first field.
class FormNotice {
  const FormNotice(this.open, this.close);

  final FormMarkerRef open;
  final FormMarkerRef close;

  /// The text between the two markers.
  FormRegion get content => FormRegion(open.nextStart, close.start);
}

/// A parsed form template.
class FormSpec {
  const FormSpec({
    required this.id,
    required this.version,
    required this.rules,
    required this.formMarker,
    required this.intro,
    this.lang,
    this.controller,
    this.contact,
    this.retainUnused,
    this.closes,
    this.overview = const [],
    this.states = const [],
    this.keepRecord = const [],
    this.extraAttributes = const {},
    this.fields = const [],
    this.notice,
  });

  final String id;

  /// The form's own version, set by its author.
  final int version;

  /// The rule-semantics version this form needs (§4.7, §4.8). Defaults to 1.
  final int rules;

  final String? lang;
  final String? controller;
  final String? contact;
  final String? retainUnused;

  /// ISO date, informational.
  final String? closes;

  /// Field ids shown as columns in the organiser's register.
  final List<String> overview;

  /// The closed list of workflow states; empty means the default list.
  final List<String> states;

  /// Field ids whose values stay in the minimal record after deletion.
  final List<String> keepRecord;

  /// Attributes of the `form` marker this engine does not know, as written.
  final Map<String, String?> extraAttributes;

  final FormMarkerRef formMarker;

  /// The text between the `form` marker and the first field (or the end of the
  /// file): the introduction the landing page shows. It includes the `notice`
  /// region, which a caller subtracts if it wants them apart.
  final FormRegion intro;

  final List<FormFieldSpec> fields;
  final FormNotice? notice;

  FormFieldSpec? fieldById(String id) {
    for (final f in fields) {
      if (f.id == id) return f;
    }
    return null;
  }
}

/// The three things [parseForm] can say about a text.
sealed class FormParseResult {
  const FormParseResult();
}

/// There is no form marker: an ordinary document. Not an error.
class NotAForm extends FormParseResult {
  const NotAForm();
}

/// A usable form. [notes] are warnings and information for the author (a
/// missing notice, an unknown rule) — nothing in them blocks filling it, except
/// an error-severity `rules-too-new`, which means this engine must not judge the
/// form at all.
class ParsedForm extends FormParseResult {
  const ParsedForm(this.spec, this.notes);

  final FormSpec spec;
  final List<FormProblem> notes;

  /// Whether this engine may fill and validate the form: false when it needs
  /// newer rule semantics than this package implements.
  bool get canFill => !notes.any((n) => n.code == FormIssueCode.rulesTooNew);
}

/// A text that has a `form` marker (or is plainly meant to be a form) but is
/// not valid: a duplicate id, an unpaired marker, `words=300..150`. These are
/// author errors and **block publishing**; [problems] lists every one found, in
/// the order they appear, capped at 100.
class BrokenForm extends FormParseResult {
  const BrokenForm(this.problems);

  final List<FormProblem> problems;
}
