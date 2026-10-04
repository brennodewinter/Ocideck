// De zinnen bij een uitnodiging die niet openging (FORM_INTAKE.md §6.4, §6.6): wat er mis is met
// de link, en wat er mis ging onderweg. Elke zin zegt wat de invuller kan doen; een technische
// reden hoort in het log, niet op het scherm.

import 'package:ocideck_form_core/ocideck_form_core.dart'
    show InviteLinkIssue, IntakeErrorCode;

import '../../l10n/app_localizations.dart';
import '../../services/form/intake/intake_client.dart';
import '../../services/form/intake/intake_http.dart';
import 'form_bundle_issue_text.dart';

/// Wat er aan een link ontbreekt of mankeert.
String inviteLinkIssueText(
  AppLocalizations l10n,
  InviteLinkIssue issue,
) => switch (issue) {
  // De vingerafdruk is het enige wat de invuller heeft dat de server niet in de hand heeft:
  // een link zonder gaat niet verder, en dat is geen "doorgaan" waard.
  InviteLinkIssue.noApi ||
  InviteLinkIssue.noFingerprint ||
  InviteLinkIssue.noToken => l10n.d(
    'Deze link is niet compleet. Vraag de organisator om de volledige uitnodigingslink.',
  ),
  InviteLinkIssue.notHttps => l10n.d('De link moet met https beginnen.'),
  _ => l10n.d(
    'Dit is geen uitnodigingslink die OciDeck kent. Vraag de organisator om de volledige link.',
  ),
};

/// Wat de invuller te lezen krijgt omdat [failed] mislukte; [host] is de server uit de link.
String intakeFailureText(
  AppLocalizations l10n,
  IntakeFailed failed, {
  required String host,
}) => switch (failed.problem) {
  IntakeProblem.unreachable => switch (failed.http) {
    IntakeHttpFailure.hostRefused || IntakeHttpFailure.requestRefused => l10n.d(
      'OciDeck maakt geen verbinding met dit adres.',
    ),
    IntakeHttpFailure.responseTooLarge => l10n.d(
      'De server stuurde meer dan OciDeck accepteert.',
    ),
    _ =>
      l10n
          .d(
            'Geen verbinding met {host}. Controleer je internetverbinding en probeer het later opnieuw.',
          )
          .replaceAll('{host}', host),
  },
  IntakeProblem.notIntakeServer =>
    l10n
        .d('{host} is geen inzendserver die OciDeck begrijpt.')
        .replaceAll('{host}', host),
  IntakeProblem.serverTooOld => l10n.d(
    'Deze server is te oud voor deze versie van OciDeck.',
  ),
  IntakeProblem.serverTooNew => l10n.d(
    'Deze server is van een nieuwere versie. Werk OciDeck bij.',
  ),
  IntakeProblem.serverRefused => switch (failed.error?.code) {
    IntakeErrorCode.formUnknown => l10n.d(
      'Dit formulier bestaat niet (meer) op de server. Vraag de organisator om een nieuwe uitnodiging.',
    ),
    IntakeErrorCode.rateLimited => l10n.d(
      'De server is druk. Probeer het later opnieuw.',
    ),
    _ => l10n.d('De server weigerde het verzoek.'),
  },
  IntakeProblem.formMalformed => l10n.d(
    'De server stuurde een formulier dat OciDeck niet kan lezen.',
  ),
  IntakeProblem.bundleRefused => formBundleIssueText(l10n, failed.bundleIssue!),
};
