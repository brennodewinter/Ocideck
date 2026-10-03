// De zinnen bij het versturen van een inzending naar een server (FORM_INTAKE.md §6.6, §5.8): wat
// er mis ging, in woorden die zeggen wat de invuller kan doen. Een technische reden hoort in het
// log, niet op het scherm.

import 'package:ocideck_form_core/ocideck_form_core.dart' show IntakeErrorCode;

import '../../l10n/app_localizations.dart';
import '../../services/form/intake/intake_client.dart';
import '../../services/form/intake/intake_http.dart';

/// Wat de invuller te lezen krijgt omdat het versturen mislukte met [failed]; [host] is de server.
String intakeSendFailureText(
  AppLocalizations l10n,
  IntakeFailed failed, {
  required String host,
}) => switch (failed.problem) {
  IntakeProblem.unreachable => switch (failed.http) {
    IntakeHttpFailure.hostRefused || IntakeHttpFailure.requestRefused => l10n.d(
      'OciDeck maakt geen verbinding met dit adres.',
    ),
    _ =>
      l10n
          .d(
            'Geen verbinding met {host}. Controleer je internetverbinding en probeer het later opnieuw.',
          )
          .replaceAll('{host}', host),
  },
  IntakeProblem.serverRefused => switch (failed.error?.code) {
    IntakeErrorCode.inviteInvalid => l10n.d(
      'De uitnodiging is niet meer geldig: de organisator heeft hem ingetrokken of vervangen. Vraag om een nieuwe uitnodiging.',
    ),
    IntakeErrorCode.formClosed => l10n.d(
      'Dit formulier is gesloten voor nieuwe inzendingen. Neem contact op met de organisator.',
    ),
    IntakeErrorCode.tooLarge => l10n.d(
      'De server neemt deze inzending niet aan omdat ze te groot is. Haal een foto weg of maak er een kleiner.',
    ),
    IntakeErrorCode.rateLimited => l10n.d(
      'De server is druk. Probeer het later opnieuw.',
    ),
    _ => l10n.d(
      'De server weigerde de inzending. Probeer het later opnieuw, of sla de verzegelde inzending op en mail die.',
    ),
  },
  IntakeProblem.noteMismatch => l10n.d(
    'De server bevestigde iets anders dan wat je verstuurde. Probeer het opnieuw, of sla de verzegelde inzending op en mail die.',
  ),
  // Deze horen bij het openen van een uitnodiging; bij het versturen komen ze niet voor.
  IntakeProblem.notIntakeServer ||
  IntakeProblem.serverTooOld ||
  IntakeProblem.serverTooNew ||
  IntakeProblem.formMalformed ||
  IntakeProblem.bundleRefused => l10n.d(
    'De server weigerde de inzending. Probeer het later opnieuw, of sla de verzegelde inzending op en mail die.',
  ),
};
