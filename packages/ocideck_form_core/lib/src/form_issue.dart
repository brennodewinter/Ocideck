/// How serious a [FormProblem] is (FORM_INTAKE.md §4.11): an *error* blocks, a
/// *warning* asks for confirmation, *info* only informs.
enum FormSeverity { error, warning, info }

/// Every issue code the form engine can report, with its stable wire name.
///
/// The wire name is what the interface, the organiser's register and the tests
/// key on, so it never changes; the list is pinned to FORM_INTAKE.md §4.11 by a
/// test in the app (a code added here without a line in the document fails it).
/// A bare code is never shown to a person: each has a message-catalogue entry in
/// the app (§8) that says what is wrong and what to do.
enum FormIssueCode {
  // ── Answers (reported by validation, FORM_INTAKE.md §4.7 and §4.11) ──
  requiredEmpty('required-empty', FormSeverity.error),
  tooFewWords('too-few-words', FormSeverity.error),
  tooManyWords('too-many-words', FormSeverity.error),
  tooShort('too-short', FormSeverity.error),
  tooLong('too-long', FormSeverity.error),
  notAnOption('not-an-option', FormSeverity.error),
  countOutOfRange('count-out-of-range', FormSeverity.error),
  badNumber('bad-number', FormSeverity.error),
  numberOutOfRange('number-out-of-range', FormSeverity.error),
  badDate('bad-date', FormSeverity.error),
  badPattern('bad-pattern', FormSeverity.error),
  imageTooSmall('image-too-small', FormSeverity.warning),
  imageTooLarge('image-too-large', FormSeverity.error),
  imageFormat('image-format', FormSeverity.error),
  imageMissingFile('image-missing-file', FormSeverity.error),
  imageMissingAlt('image-missing-alt', FormSeverity.error),
  imageMissingCredit('image-missing-credit', FormSeverity.error),
  imageUnchecked('image-unchecked', FormSeverity.error),
  imageHeicUnverified('image-heic-unverified', FormSeverity.warning),
  imageUnexpectedFaces('image-unexpected-faces', FormSeverity.info),
  consentNotGiven('consent-not-given', FormSeverity.error),
  structureDamaged('structure-damaged', FormSeverity.error),
  answerMalformed('answer-malformed', FormSeverity.error),
  answerContainsMarker('answer-contains-marker', FormSeverity.error),
  answerContainsHtml('answer-contains-html', FormSeverity.error),
  answerUnclosedFence('answer-unclosed-fence', FormSeverity.error),
  answerBadImage('answer-bad-image', FormSeverity.error),
  answerBadLink('answer-bad-link', FormSeverity.error),

  // ── Submission against the published form ──
  templateTextAltered('template-text-altered', FormSeverity.error),
  templateUnknown('template-unknown', FormSeverity.error),
  fieldNotInForm('field-not-in-form', FormSeverity.error),
  fieldMissing('field-missing', FormSeverity.error),
  formVersionMismatch('form-version-mismatch', FormSeverity.warning),
  rulesTooNew('rules-too-new', FormSeverity.error),

  // ── Author level: found while parsing a template; they block publishing ──
  ruleMalformed('rule-malformed', FormSeverity.error),
  duplicateFieldId('duplicate-field-id', FormSeverity.error),
  unpairedMarker('unpaired-marker', FormSeverity.error),
  unknownType('unknown-type', FormSeverity.error),
  markerMalformed('marker-malformed', FormSeverity.error),
  markerMisplaced('marker-misplaced', FormSeverity.error),
  noticeMissing('notice-missing', FormSeverity.warning),
  formAttributeMissing('form-attribute-missing', FormSeverity.warning),
  unknownMarker('unknown-marker', FormSeverity.warning),
  unknownRule('unknown-rule', FormSeverity.info);

  const FormIssueCode(this.wireName, this.severity);

  /// The stable, kebab-case name used everywhere outside this enum.
  final String wireName;

  /// The severity this code normally has. A caller may report it lower (never
  /// higher) where the rules say so, e.g. `min-width` is a warning by default.
  final FormSeverity severity;

  /// The code named [wire], or null for a name this engine does not know.
  static FormIssueCode? fromWire(String wire) {
    for (final code in values) {
      if (code.wireName == wire) return code;
    }
    return null;
  }
}

/// One thing the parser found wrong (or worth noting) in a template.
///
/// [line] is 1-based and points at the marker the problem belongs to when there
/// is one, so an editor can jump there. [facts] carries the machine-readable
/// detail the message catalogue turns into a sentence (`{'rule': 'words',
/// 'reason': 'range-reversed'}`); keys and values are plain strings, ints and
/// bools so a problem can travel across an isolate or into a test as data.
class FormProblem {
  FormProblem(
    this.code, {
    this.line,
    this.fieldId,
    this.facts = const {},
    FormSeverity? severity,
  }) : severity = severity ?? code.severity;

  final FormIssueCode code;
  final FormSeverity severity;
  final int? line;
  final String? fieldId;
  final Map<String, Object?> facts;

  bool get isError => severity == FormSeverity.error;

  @override
  String toString() {
    final where = line == null ? '' : ' (line $line)';
    final field = fieldId == null ? '' : ' [$fieldId]';
    final detail = facts.isEmpty ? '' : ' $facts';
    return '${code.wireName}$where$field$detail';
  }
}
