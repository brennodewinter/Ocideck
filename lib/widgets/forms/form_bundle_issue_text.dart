// De zin bij een bundel die niet werd geloofd (FORM_INTAKE.md §5.1). Eén plek voor de weg
// via een bundelbestand en de weg via een uitnodiging: dezelfde reden moet in beide dezelfde
// zin geven, in elke taal.

import 'package:ocideck_form_core/ocideck_form_core.dart' show FormBundleIssue;

import '../../l10n/app_localizations.dart';

/// Wat de invuller te lezen krijgt omdat een bundel om [issue] niet werd geloofd.
String formBundleIssueText(
  AppLocalizations l10n,
  FormBundleIssue issue,
) => switch (issue) {
  FormBundleIssue.notABundle => l10n.d(
    'Dit bestand is geen bundel die OciDeck kan lezen.',
  ),
  FormBundleIssue.unsupportedVersion || FormBundleIssue.rulesTooNew => l10n.d(
    'Dit formulier of deze bundel is van een nieuwere versie van OciDeck. Werk OciDeck bij.',
  ),
  FormBundleIssue.fingerprintMismatch => l10n.d(
    'De vingerafdruk past niet bij deze bundel: het formulier komt niet van wie de uitnodiging zegt. Controleer de vingerafdruk en het bundelbestand.',
  ),
  FormBundleIssue.badSignature => l10n.d(
    'De handtekening van de bundel klopt niet: hij is veranderd of niet van wie de vingerafdruk zegt. Vraag de organisator om een nieuwe bundel.',
  ),
  FormBundleIssue.templateMismatch => l10n.d(
    'Deze bundel hoort niet bij dit formulier. Gebruik het bundelbestand dat bij precies dit formulier hoort.',
  ),
  FormBundleIssue.expired => l10n.d(
    'Deze bundel is verlopen. Vraag de organisator om een nieuwe.',
  ),
  FormBundleIssue.rollback => l10n.d(
    'Deze bundel is ouder dan een bundel die je eerder van deze organisator kreeg. Vraag de organisator om de nieuwste.',
  ),
  FormBundleIssue.hostMismatch => l10n.d(
    'Het formulier hoort niet bij de server uit de uitnodiging. Vraag de organisator om een nieuwe uitnodiging.',
  ),
  FormBundleIssue.badStructure ||
  FormBundleIssue.noFingerprint ||
  FormBundleIssue.badFingerprint => l10n.d(
    'De bundel bevat iets wat niet kan. Vraag de organisator om een nieuwe bundel.',
  ),
};
