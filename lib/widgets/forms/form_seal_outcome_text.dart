// De zin bij een verzegeling die niet doorging (FORM_INTAKE.md §5.1, §5.6). Eén plek voor het
// opslaan van een verzegeld bestand en voor het versturen naar een server: dezelfde reden geeft in
// beide dezelfde zin, in elke taal.

import '../../l10n/app_localizations.dart';
import '../../services/form/form_submission_seal.dart';
import 'form_bundle_issue_text.dart';

/// Wat de invuller te lezen krijgt omdat [outcome] geen verzegeld pakket is.
String formSealOutcomeText(
  AppLocalizations l10n,
  FormSealOutcome outcome,
) => switch (outcome) {
  FormSealBadFingerprint() => l10n.d(
    'Dat is geen vingerafdruk. Hij bestaat uit 52 tekens, meestal in groepjes van vier.',
  ),
  FormSealBundleRefused(:final issue) => formBundleIssueText(l10n, issue),
  FormSealClosed(:final closes) =>
    l10n
        .d(
          'Dit formulier is gesloten: de laatste dag was {datum}. Neem contact op met de organisator.',
        )
        .replaceAll('{datum}', closes),
  FormSealTooLarge(:final cap) =>
    l10n
        .d(
          'De inzending is groter dan de organisator toestaat ({mb} MB). Haal een foto weg of maak er een kleiner.',
        )
        .replaceAll('{mb}', (cap / (1024 * 1024)).toStringAsFixed(1)),
  FormSealFailed() => l10n.d('De inzending kon niet worden verzegeld.'),
  FormSubmissionSealed() => '',
};
