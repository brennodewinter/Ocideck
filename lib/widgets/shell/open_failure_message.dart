import '../../l10n/app_localizations.dart';
import '../../services/file_service.dart' show OpenFailure;
import '../../utils/user_facing_error.dart';

/// Wat er misging, zo precies als het openpad het wist.
///
/// "Kon dit bestand niet openen." stond hier voor vier verschillende dingen,
/// terwijl `FileService.openDeckDetailed` het antwoord al had. Voor een product
/// dat om Markdown draait is dat te mager: de gebruiker weet dan niet of hij het
/// verkeerde bestand koos, of dat er iets stuk is, of dat hij iets kán doen.
///
/// Eigen bestand, en niet meer een privé-functie van de app-schil, omdat ook
/// "Herladen" na een bestandsconflict een open is die kan mislukken
/// (`saveDocumentWithDestination`) — en die moest dezelfde woorden gebruiken.
String openFailureMessage(
  AppLocalizations l10n,
  OpenFailure? reason,
) => switch (reason) {
  OpenFailure.notFound => l10n.d('Dit bestand bestaat niet meer op deze plek.'),
  OpenFailure.tooLarge => l10n.d('Dit bestand is te groot om te openen.'),
  OpenFailure.memoryBudgetExceeded => webAssetBudgetMessage(l10n),
  OpenFailure.corrupt => l10n.d(
    'Deze presentatie is beschadigd of half opgeslagen.',
  ),
  OpenFailure.unreadable => l10n.d(
    'Dit bestand is geen leesbare tekst. OciDeck opent Markdown.',
  ),
  // `unsafe` en `notPresentation` komen hier niet langs: die hebben hun
  // eigen afhandeling (het veiligheidsalarm en OpenResult.notAPresentation).
  // Null is het eerlijke geval — een afgebroken open, een tabblad dat
  // verdween — en houdt de algemene zin.
  OpenFailure.unsafe ||
  OpenFailure.notPresentation ||
  null => l10n.d('Kon dit bestand niet openen.'),
};
