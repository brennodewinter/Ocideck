/// A form being filled in (FORM_INTAKE.md §4.10, §8): the document, the form it
/// is, the answer to every field and what is wrong with each — everything the fill
/// view shows, as plain data with no widget in it.
///
/// A [FormFill] is **immutable**. [FormFill.setAnswer] returns the next one, built
/// by [applyAnswer], so the only text it ever produces is the old document with one
/// answer zone replaced; and every [FormFill] has been parsed from the text it
/// carries, so what it says about the document is never stale.
///
/// What a fill view needs beyond that — the title, the introduction, the notice,
/// the sections with their state — is read from the template-owned text here, once,
/// so the widget does not have to know what a heading in a form means.
library;

import 'form_answer_writer.dart';
import 'form_answers.dart';
import 'form_counts.dart';
import 'form_issue.dart';
import 'form_parser.dart';
import 'form_source.dart';
import 'form_spec.dart';
import 'form_template_text.dart';
import 'form_validator.dart';

/// One piece of the form page, in document order (FORM_INTAKE.md §8). A fill view
/// is a list of these: the template-owned text, the headings with the state of
/// their section, the notice, and each field.
sealed class FormItem {
  const FormItem();
}

/// A heading of the form and the fields under it, up to the next heading.
class FormHeadingItem extends FormItem {
  const FormHeadingItem(this.level, this.title, this.fieldIds);

  /// 1–6, the number of `#`.
  final int level;
  final String title;
  final List<String> fieldIds;
}

/// Template-owned Markdown between the fields: the introduction, guidance, a
/// closing remark. Never empty, never a heading.
class FormTextItem extends FormItem {
  const FormTextItem(this.markdown);

  final String markdown;
}

/// The notice (§9.3): who collects what, and for how long.
class FormNoticeItem extends FormItem {
  const FormNoticeItem(this.markdown);

  final String markdown;
}

/// A field; its label, rules and answer are on the [FormFill] under [fieldId].
class FormFieldItem extends FormItem {
  const FormFieldItem(this.fieldId);

  final String fieldId;
}

/// The outcome of [FormFill.open].
sealed class FormFillOpen {
  const FormFillOpen();
}

/// The document is a form this engine can fill.
class FormFillReady extends FormFillOpen {
  const FormFillReady(this.fill);

  final FormFill fill;
}

/// It is not: [problem] is `structure-damaged` with the `reason` — `not-a-form`,
/// `broken` (an author error) or `rules-too-new`.
class FormFillUnavailable extends FormFillOpen {
  const FormFillUnavailable(this.problem);

  final FormProblem problem;
}

/// The outcome of [FormFill.setAnswer].
sealed class FormFillStep {
  const FormFillStep();
}

/// The answer is in; [fill] is the document after it.
class FormFillChanged extends FormFillStep {
  const FormFillChanged(this.fill);

  final FormFill fill;
}

/// Nothing was written, because the answer would have changed the form itself.
class FormFillRefused extends FormFillStep {
  const FormFillRefused(this.problem);

  final FormProblem problem;
}

final RegExp _heading = RegExp(r'^[ \t]{0,3}(#{1,6})[ \t]+(.*?)[ \t#]*$');

class FormFill {
  FormFill._(
    this.text,
    this.spec,
    this.imageFacts,
    this._answers,
    this._problems,
    this._layout,
  );

  /// Opens [text] for filling. [imageFacts] is what is known about the image
  /// files so far; without it an image is `image-unchecked`.
  static FormFillOpen open(
    String text, {
    FormImageFacts imageFacts = const {},
  }) {
    final parsed = parseForm(text);
    switch (parsed) {
      case NotAForm():
        return FormFillUnavailable(_damaged('not-a-form'));
      case BrokenForm(:final problems):
        return FormFillUnavailable(
          _damaged('broken', {
            'problems': problems.take(5).map((p) => p.code.wireName).join(','),
            'line': problems.first.line,
          }),
        );
      case ParsedForm(canFill: false):
        return FormFillUnavailable(_damaged('rules-too-new'));
      case ParsedForm(:final spec):
        return FormFillReady(_build(text, spec, imageFacts));
    }
  }

  static FormProblem _damaged(
    String reason, [
    Map<String, Object?> more = const {},
  ]) => FormProblem(
    FormIssueCode.structureDamaged,
    facts: {'reason': reason, ...more},
  );

  static FormFill _build(String text, FormSpec spec, FormImageFacts facts) {
    final answers = <String, FormAnswer>{};
    final problems = <String, List<FormProblem>>{};
    for (final field in spec.fields) {
      final answer = parseAnswer(
        field,
        text.substring(field.zone.start, field.zone.end),
        firstLine: field.answer.line + 1,
      );
      answers[field.id] = answer;
      problems[field.id] = validateAnswer(field, answer, imageFacts: facts);
    }
    return FormFill._(
      text,
      spec,
      facts,
      answers,
      problems,
      _layoutOf(text, spec),
    );
  }

  /// The document, byte for byte — what is saved, and what a package carries.
  final String text;

  /// The form, parsed from [text].
  final FormSpec spec;

  /// What is known about the image files, by path.
  final FormImageFacts imageFacts;

  final Map<String, FormAnswer> _answers;
  final Map<String, List<FormProblem>> _problems;
  final _Layout _layout;

  // ── what the page shows ───────────────────────────────────────────────────

  /// The first level-1 heading before the first field, or the form's id.
  String get title => _layout.title ?? spec.id;

  /// The page, top to bottom: template text, headings, the notice and the fields,
  /// in the order of the document. The title heading and the `form` marker are not
  /// items — [title] has the first.
  List<FormItem> get items => _layout.items;

  /// The headings with the fields under them (the sections of the page).
  List<FormHeadingItem> get sections => [
    for (final item in _layout.items)
      if (item is FormHeadingItem) item,
  ];

  /// The notice, or null when the form has none.
  String? get notice => _layout.notice;

  // ── the answers ───────────────────────────────────────────────────────────

  FormFieldSpec fieldOf(String id) => spec.fieldById(id)!;

  /// The current answer to [fieldId].
  FormAnswer answerOf(String fieldId) => _answers[fieldId]!;

  /// What is wrong with the answer to [fieldId]: errors, warnings and notes.
  List<FormProblem> problemsOf(String fieldId) => _problems[fieldId]!;

  /// The counters to show beside [fieldId].
  List<FormCount> countsOf(String fieldId) =>
      formCounts(fieldOf(fieldId), answerOf(fieldId).value);

  /// The ids of the fields with an error, in the order of the form.
  List<String> get openFieldIds => [
    for (final field in spec.fields)
      if (formIssuesBlock(problemsOf(field.id))) field.id,
  ];

  /// How many fields still have an error.
  int get openCount => openFieldIds.length;

  /// The open fields of one section.
  int openIn(FormHeadingItem section) =>
      section.fieldIds.where((id) => formIssuesBlock(problemsOf(id))).length;

  /// Every problem of every field, in the order of the form.
  List<FormProblem> get allProblems => [
    for (final field in spec.fields) ...problemsOf(field.id),
  ];

  /// Whether the form may be sent: no field has an error. A warning only asks
  /// for confirmation.
  bool get canSend => openCount == 0;

  /// What the gate before sending checks (FORM_INTAKE.md §4.11, run 2): every
  /// problem of every field, and — when the form it came from is known — that the
  /// text outside the answers is still that form's.
  List<FormProblem> gateIssues({String? published}) => [
    ...allProblems,
    if (published != null) ...templateTextIssues(published, text),
  ];

  // ── changing it ───────────────────────────────────────────────────────────

  /// The document with [fieldId]'s answer set to [value]; or a refusal when
  /// writing it would change the form.
  FormFillStep setAnswer(String fieldId, FormAnswerValue value) {
    return switch (applyAnswer(text, spec, fieldId, value)) {
      FormEdited(:final text, :final spec) => FormFillChanged(
        _build(text, spec, imageFacts),
      ),
      FormEditRefused(:final problem) => FormFillRefused(problem),
    };
  }

  /// The same document with new knowledge about the image files; only the image
  /// fields are judged again.
  FormFill withImageFacts(FormImageFacts facts) {
    final problems = {
      for (final field in spec.fields)
        field.id: field.type == 'image'
            ? validateAnswer(field, _answers[field.id]!, imageFacts: facts)
            : _problems[field.id]!,
    };
    return FormFill._(text, spec, facts, _answers, problems, _layout);
  }
}

// ── the layout of the template-owned text ───────────────────────────────────

class _Layout {
  const _Layout(this.title, this.items, this.notice);

  final String? title;
  final List<FormItem> items;
  final String? notice;
}

/// Walks the document once and cuts it into [FormItem]s. A line belongs to the
/// template when it is outside every field and the notice; a heading there starts
/// a section, a heading inside a field's label is part of that label.
_Layout _layoutOf(String text, FormSpec spec) {
  final firstField = spec.fields.isEmpty ? null : spec.fields.first.open.line;
  final notice = spec.notice;
  final fieldAt = {for (final f in spec.fields) f.open.line: f};
  final fence = FormFenceTracker();

  String? title;
  final items = <FormItem>[];
  final buffer = <String>[];

  void flush() {
    final markdown = buffer.join('\n').trim();
    buffer.clear();
    if (markdown.isNotEmpty) items.add(FormTextItem(markdown));
  }

  final lines = FormSource(text).lines;
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    i++;
    if (line.number <= spec.formMarker.line) continue;

    final field = fieldAt[line.number];
    if (field != null) {
      flush();
      items.add(FormFieldItem(field.id));
      i = field.close.line; // 1-based close line is the index of the next line
      continue;
    }
    if (notice != null && line.number == notice.open.line) {
      flush();
      items.add(
        FormNoticeItem(
          text.substring(notice.content.start, notice.content.end).trim(),
        ),
      );
      i = notice.close.line;
      continue;
    }

    if (fence.isCode(line.text)) {
      buffer.add(line.text);
      continue;
    }
    final match = _heading.firstMatch(line.text);
    if (match == null) {
      buffer.add(line.text);
      continue;
    }
    final level = match.group(1)!.length;
    final heading = match.group(2)!;
    if (title == null &&
        level == 1 &&
        (firstField == null || line.number < firstField)) {
      flush();
      title = heading;
      continue;
    }
    flush();
    items.add(FormHeadingItem(level, heading, const []));
  }
  flush();

  // Give each heading the fields up to the next heading.
  final grouped = <FormItem>[];
  for (var n = 0; n < items.length; n++) {
    final item = items[n];
    if (item is! FormHeadingItem) {
      grouped.add(item);
      continue;
    }
    final ids = <String>[];
    for (var m = n + 1; m < items.length && items[m] is! FormHeadingItem; m++) {
      final next = items[m];
      if (next is FormFieldItem) ids.add(next.fieldId);
    }
    grouped.add(FormHeadingItem(item.level, item.title, ids));
  }

  return _Layout(
    title,
    grouped,
    notice == null
        ? null
        : text.substring(notice.content.start, notice.content.end).trim(),
  );
}
