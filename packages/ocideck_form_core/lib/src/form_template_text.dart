/// Is the template-owned text of a submission still the published one?
/// (FORM_INTAKE.md §4.6, "Template-owned text is immutable, and the organiser
/// enforces it".)
///
/// Everything outside the answer zones — the introduction, the notice, every
/// label and guidance text, **the consent text**, and the markers with their
/// rules — belongs to the template. Re-validation blanks every answer zone in the
/// submission and in the *published* template and requires the two to be equal
/// (line endings normalised, a BOM ignored). That is what stops a respondent, or
/// a modified client, from rewording "Ik ga akkoord met publicatie" to something
/// the organiser never offered, and from weakening a rule by editing its marker.
library;

import 'form_answers.dart';
import 'form_issue.dart';
import 'form_source.dart';
import 'form_spec.dart';

/// The `template-text-altered` problem if [submission] differs from [published]
/// outside its answer zones, or a `structure-damaged` one when either cannot be
/// read as a form. Empty means the template text is intact.
///
/// Only the **first** difference is reported (with how many lines differ), as
/// the line to look at: after one inserted or removed line everything below it
/// is misaligned, and a list of those would only be noise.
List<FormProblem> templateTextIssues(String published, String submission) {
  final theirs = readSubmissionStructure(submission);
  if (theirs.spec == null) return [theirs.damaged!];
  final ours = readSubmissionStructure(published);
  if (ours.spec == null) {
    return [
      FormProblem(
        FormIssueCode.structureDamaged,
        facts: {
          'reason': 'published-form',
          'because': ours.damaged!.facts['reason'],
        },
      ),
    ];
  }

  final a = _templateLines(published, ours.spec!);
  final b = _templateLines(submission, theirs.spec!);
  final longest = a.length > b.length ? a.length : b.length;
  var first = -1;
  var differing = 0;
  for (var i = 0; i < longest; i++) {
    final x = i < a.length ? a[i].text : null;
    final y = i < b.length ? b[i].text : null;
    if (x != y) {
      differing++;
      if (first < 0) first = i;
    }
  }
  if (first < 0) return const [];

  final line = first < b.length
      ? b[first].number
      : (b.isEmpty ? 1 : b.last.number + 1);
  final region = _regionOf(line, theirs.spec!);
  return [
    FormProblem(
      FormIssueCode.templateTextAltered,
      line: line,
      fieldId: region.field,
      facts: {'region': region.name, 'differing': differing},
    ),
  ];
}

/// The lines of [text] that are not inside an answer zone, with their numbers.
List<FormLine> _templateLines(String text, FormSpec spec) {
  final inZone = <int>{};
  for (final field in spec.fields) {
    for (var n = field.answer.line + 1; n < field.close.line; n++) {
      inZone.add(n);
    }
  }
  return [
    for (final line in FormSource(text).lines)
      if (!inZone.contains(line.number)) line,
  ];
}

({String name, String? field}) _regionOf(int line, FormSpec spec) {
  for (final field in spec.fields) {
    if (line >= field.open.line && line <= field.answer.line) {
      return (name: field.id, field: field.id);
    }
    if (line == field.close.line) return (name: field.id, field: field.id);
  }
  final notice = spec.notice;
  if (notice != null && line >= notice.open.line && line <= notice.close.line) {
    return (name: 'notice', field: null);
  }
  return (name: 'outside-fields', field: null);
}
