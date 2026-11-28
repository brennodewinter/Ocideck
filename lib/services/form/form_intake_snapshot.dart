// De immutable snapshot die een organisator publiceert (FORM_INTAKE.md §6.2):
// de envelop die OciServe toetst, met daarin als ondoorzichtige `definition`
// het formulier zoals OciDeck het kent — de hele template-markdown.
library;

import 'package:ocideck_form_core/ocideck_form_core.dart';

import '../../models/ociserve_intake.dart';

/// Het `format`-veld van de `definition`: OciDeck-formulierdefinitie v1,
/// voor de server ondoorzichtig (§6.2).
const String kIntakeDefinitionFormat = 'ocideck-form/1';

/// De contractgrenzen voor de retentievelden (gepinde spec).
const int intakeDraftDaysMax = 90;
const int intakeSubmittedDaysMax = 1825;

/// Bouwt de snapshot van [markdown] met de zichtbare beloftes — titel,
/// doelen, privacytekst, retentie en correctiebeleid. De geldigheid van de
/// waarden controleert de dialoog al; hier wordt alleen de vorm gelegd.
IntakeFormSnapshot buildIntakeSnapshot({
  required String markdown,
  required String title,
  required List<String> purposes,
  required String privacyText,
  required int retentionDraftDays,
  required int retentionSubmittedDays,
  required bool correctionAllowed,
  int? correctionDeadlineDays,
}) => IntakeFormSnapshot(
  title: title,
  purposes: List.unmodifiable(purposes),
  privacyText: privacyText,
  retentionDraftDays: retentionDraftDays,
  retentionSubmittedDays: retentionSubmittedDays,
  correctionAllowed: correctionAllowed,
  correctionDeadlineDays: correctionDeadlineDays,
  definition: {'format': kIntakeDefinitionFormat, 'markdown': markdown},
);

/// Het formulier uit een ontvangen snapshot — `null` als de `definition`
/// geen OciDeck-markdown draagt. Een snapshot zonder onze definitie is voor
/// de respondentweg waardeloos: er is niets om in te vullen.
String? intakeFormMarkdown(IntakeFormSnapshot snapshot) {
  final definition = snapshot.definition;
  if (definition['format'] != kIntakeDefinitionFormat) return null;
  final markdown = definition['markdown'];
  if (markdown is! String || markdown.trim().isEmpty) return null;
  return markdown;
}

/// Start an optional, empty consent answer unchecked in the respondent copy.
String intakeAnswerCopy(String markdown) {
  final opened = FormFill.open(markdown);
  if (opened is! FormFillReady) return markdown;
  var fill = opened.fill;
  for (final field in opened.fill.spec.fields) {
    if (field.type != 'consent' || field.required) continue;
    if (markdown
        .substring(field.zone.start, field.zone.end)
        .trim()
        .isNotEmpty) {
      continue;
    }
    if (fill.setAnswer(field.id, const FormAnswerValue(consent: false))
        case FormFillChanged(fill: final updated)) {
      fill = updated;
    }
  }
  return fill.text;
}
