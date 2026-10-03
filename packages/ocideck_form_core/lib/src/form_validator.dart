/// Judging answers against the rules of a form (FORM_INTAKE.md §4.5, §4.7, §4.11).
///
/// [validateAnswer] judges **one** field — the fill view calls it for the field
/// being edited, so a keystroke never re-validates a whole form — and
/// [validateForm] judges a whole submission. Both are **pure and synchronous**:
/// the one thing that needs I/O, looking at an image file, is an *input*
/// ([FormImageFact]) that a probe fills in elsewhere. Without it an image is
/// `image-unchecked`, never silently fine.
///
/// The order of the issues of one field is fixed: the problems with the answer's
/// shape, then the safety rules of §4.6, then the rules of the field. A malformed
/// answer gets no rule issues, because its value cannot be read.
library;

import 'form_answer_safety.dart';
import 'form_answers.dart';
import 'form_issue.dart';
import 'form_patterns.dart';
import 'form_rule_values.dart';
import 'form_spec.dart';
import 'form_words.dart';

/// What a probe learned about one image file. All of it is *input* to
/// validation: the engine itself never opens a file.
class FormImageFact {
  const FormImageFact({
    this.exists = true,
    this.displayedWidth,
    this.bytes,
    this.format,
    this.faces,
    this.unverified = false,
  });

  /// False when the file the answer names is not in the package or folder.
  final bool exists;

  /// The width as it is *shown*, after EXIF orientation (§5.5).
  final int? displayedWidth;
  final int? bytes;

  /// `jpg`, `png`, `webp` or `heic`, decided from the file's magic bytes.
  final String? format;

  /// The number of faces found, or null when no count is known.
  final int? faces;

  /// A HEIC kept as it is (§5.5): it could not be measured or decoded.
  final bool unverified;
}

/// The image facts by path (`images/portret-1.jpg`).
typedef FormImageFacts = Map<String, FormImageFact>;

/// Whether any of [issues] blocks sending: an *error*. A warning asks for
/// confirmation and information only informs (§4.11).
bool formIssuesBlock(Iterable<FormProblem> issues) =>
    issues.any((i) => i.severity == FormSeverity.error);

/// Every issue of a submission: its structure problems first, then each field of
/// the *published* [spec], in order. A field the submission lacks is reported once
/// (`field-missing`), not also as empty.
List<FormProblem> validateForm(
  FormSpec spec,
  FormAnswers answers, {
  FormImageFacts? imageFacts,
}) => [
  ...answers.structure,
  for (final field in spec.fields)
    if (answers.byId[field.id] case final answer?)
      ...validateAnswer(field, answer, imageFacts: imageFacts),
];

/// The issues of one [answer] to [field].
List<FormProblem> validateAnswer(
  FormFieldSpec field,
  FormAnswer answer, {
  FormImageFacts? imageFacts,
}) {
  final out = <FormProblem>[...answer.shape];
  out.addAll(
    answerSafetyIssues(
      answer.raw,
      firstLine: answer.firstLine,
      fieldId: field.id,
    ),
  );
  if (answer.shape.isNotEmpty) return out;

  void add(
    FormIssueCode code,
    Map<String, Object?> facts, {
    FormSeverity? severity,
  }) => out.add(
    FormProblem(
      code,
      line: answer.firstLine,
      fieldId: field.id,
      facts: facts,
      severity: severity,
    ),
  );

  if (answer.isEmpty) {
    // Nothing was answered: a required field says so, any other is fine and
    // none of its rules apply.
    if (field.required) add(FormIssueCode.requiredEmpty, const {});
    return out;
  }

  switch (field.type) {
    case 'text':
      _chars(field, answer.text!, add);
      _pattern(field, answer.text!, add);
    case 'prose':
      _words(field.range('words'), countFormWords(answer.text!), add);
      _chars(field, answer.text!, add);
    case 'number':
      _number(field, answer.text!, add);
    case 'date':
      _date(field, answer.text!, add);
    case 'choice':
      _choice(field, answer.text!, add);
    case 'multichoice':
      _multichoice(field, answer, add);
    case 'list':
      _list(field, answer, add);
    case 'table':
      _count(field.range('rows'), answer.rows.length, add, what: 'rows');
    case 'image':
      _images(field, answer, imageFacts, add);
    case 'consent':
      if (field.required && answer.consent == false) {
        add(FormIssueCode.consentNotGiven, const {});
      }
  }
  return out;
}

typedef _Add =
    void Function(
      FormIssueCode code,
      Map<String, Object?> facts, {
      FormSeverity? severity,
    });

/// `{min, max, actual}` with the open ends left out.
Map<String, Object?> _rangeFacts(FormRange r, int actual, [String? what]) => {
  'min': ?r.min,
  'max': ?r.max,
  'actual': actual,
  'what': ?what,
};

void _chars(FormFieldSpec field, String text, _Add add) {
  final min = field.intRule('min-chars');
  final max = field.intRule('max-chars');
  if (min == null && max == null) return;
  final n = countFormChars(text);
  final facts = {'min': ?min, 'max': ?max, 'actual': n};
  if (min != null && n < min) add(FormIssueCode.tooShort, facts);
  if (max != null && n > max) add(FormIssueCode.tooLong, facts);
}

void _words(FormRange? range, int n, _Add add, {Map<String, Object?>? extra}) {
  if (range == null) return;
  final facts = {..._rangeFacts(range, n), ...?extra};
  if (range.min != null && n < range.min!) {
    add(FormIssueCode.tooFewWords, facts);
  } else if (range.max != null && n > range.max!) {
    add(FormIssueCode.tooManyWords, facts);
  }
}

void _count(FormRange? range, int n, _Add add, {String? what}) {
  if (range != null && !range.contains(n)) {
    add(FormIssueCode.countOutOfRange, _rangeFacts(range, n, what));
  }
}

void _pattern(FormFieldSpec field, String text, _Add add) {
  final pattern = field.text('pattern');
  if (pattern != null && !matchesFormPattern(pattern, text)) {
    add(FormIssueCode.badPattern, {'pattern': pattern});
  }
}

void _number(FormFieldSpec field, String text, _Add add) {
  if (!isValidNumberText(text)) {
    add(FormIssueCode.badNumber, {'value': text});
    return;
  }
  final min = field.text('min');
  final max = field.text('max');
  if ((min != null && compareNumberText(text, min) < 0) ||
      (max != null && compareNumberText(text, max) > 0)) {
    add(FormIssueCode.numberOutOfRange, {
      'min': ?min,
      'max': ?max,
      'value': text,
    });
    return;
  }
  final step = field.text('step');
  if (step != null && !isMultipleOfStep(text, min ?? '0', step)) {
    add(FormIssueCode.numberOutOfRange, {
      'reason': 'step',
      'step': step,
      'value': text,
    });
  }
}

void _date(FormFieldSpec field, String text, _Add add) {
  if (!isValidCalendarDate(text)) {
    add(FormIssueCode.badDate, {'value': text});
    return;
  }
  final min = field.text('min');
  final max = field.text('max');
  // Valid dates compare correctly as text: fixed width, most significant first.
  if (min != null && text.compareTo(min) < 0) {
    add(FormIssueCode.badDate, {
      'reason': 'before-min',
      'min': min,
      'value': text,
    });
  } else if (max != null && text.compareTo(max) > 0) {
    add(FormIssueCode.badDate, {
      'reason': 'after-max',
      'max': max,
      'value': text,
    });
  }
}

void _choice(FormFieldSpec field, String text, _Add add) {
  final options = field.list('options') ?? const [];
  if (!options.contains(text) && !field.flag('other')) {
    add(FormIssueCode.notAnOption, {'value': text});
  }
}

void _multichoice(FormFieldSpec field, FormAnswer answer, _Add add) {
  final options = field.list('options') ?? const [];
  if (!field.flag('other')) {
    for (final item in answer.items) {
      if (!options.contains(item)) {
        add(FormIssueCode.notAnOption, {'value': item});
      }
    }
  }
  _count(field.range('count'), answer.items.length, add);
}

void _list(FormFieldSpec field, FormAnswer answer, _Add add) {
  _count(field.range('items'), answer.items.length, add);
  final perItem = field.range('item-words');
  for (var i = 0; i < answer.items.length; i++) {
    _words(
      perItem,
      countFormWords(answer.items[i]),
      add,
      extra: {'item': i + 1},
    );
  }
}

const List<String> _allFormats = ['jpg', 'png', 'webp', 'heic'];

void _images(
  FormFieldSpec field,
  FormAnswer answer,
  FormImageFacts? facts,
  _Add add,
) {
  _count(field.range('count'), answer.images.length, add);
  final allowed = field.list('formats') ?? _allFormats;
  final minWidth = field.intRule('min-width');
  final maxBytes = field.intRule('max-bytes');
  final faces = field.range('faces');

  for (final image in answer.images) {
    final path = image.path;
    final ext = path.substring(path.lastIndexOf('.') + 1);
    if (!allowed.contains(ext)) {
      add(FormIssueCode.imageFormat, {'reason': 'not-allowed', 'path': path});
    }
    if (field.flag('alt') && image.alt.trim().isEmpty) {
      add(FormIssueCode.imageMissingAlt, {'path': path});
    }
    if (field.flag('credit') && (image.credit?.trim().isEmpty ?? true)) {
      add(FormIssueCode.imageMissingCredit, {'path': path});
    }

    final fact = facts?[path];
    if (fact == null || (fact.unverified && ext != 'heic')) {
      add(FormIssueCode.imageUnchecked, {'path': path});
      continue;
    }
    if (!fact.exists) {
      add(FormIssueCode.imageMissingFile, {'path': path});
      continue;
    }
    if (maxBytes != null && fact.bytes != null && fact.bytes! > maxBytes) {
      add(FormIssueCode.imageTooLarge, {
        'max': maxBytes,
        'actual': fact.bytes,
        'path': path,
      });
    }
    if (fact.unverified) {
      // A HEIC kept as it is: it was neither measured nor decoded, so there is
      // no width or face count to judge — only a warning to say so.
      add(FormIssueCode.imageHeicUnverified, {'path': path});
      continue;
    }
    if (fact.format != null && fact.format != ext) {
      add(FormIssueCode.imageFormat, {
        'reason': 'mismatch',
        'path': path,
        'content': fact.format,
      });
    }
    if (minWidth != null &&
        fact.displayedWidth != null &&
        fact.displayedWidth! < minWidth) {
      add(FormIssueCode.imageTooSmall, {
        'min': minWidth,
        'actual': fact.displayedWidth,
        'path': path,
      }, severity: field.flag('strict') ? FormSeverity.error : null);
    }
    if (faces != null && fact.faces != null && !faces.contains(fact.faces!)) {
      add(FormIssueCode.imageUnexpectedFaces, {
        'expected': faces.toString(),
        'actual': fact.faces,
        'path': path,
      });
    }
  }
}
