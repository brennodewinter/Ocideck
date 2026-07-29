// De uitkomst van een OpenKAT-import en de zin die erbij hoort. Hier en niet
// in `openkat_import_action_io.dart`, omdat dit geen dart:io raakt: de
// webhelft moet dezelfde vorm kunnen benoemen, en een tweede exemplaar van
// deze tekst in die romp zou meteen uit de pas gaan lopen.
//
// Eén zin voor twee plekken (de melding onderin en het instellingenpaneel) is
// hier geen zuinigheid maar de bedoeling: wie de import vanuit Integraties
// start, hoort hetzelfde te lezen als wie hem uit het menu start.
import '../../l10n/app_localizations.dart';

/// Wat een import opleverde.
///
/// [loaded] en [skipped] komen uit het manifest — geladen rapportages en wat
/// er overgeslagen is (dubbel, onherkend, kapot of te groot). [updatedDeck] is
/// waar wanneer een bestaand OpenKAT-deck is bijgewerkt in plaats van een
/// nieuw tabblad geopend. [failed] is waar wanneer de import zelf misging; dan
/// zeggen de tellingen niets.
typedef OpenKatImportOutcome = ({
  int loaded,
  int skipped,
  bool updatedDeck,
  bool failed,
});

/// De melding bij [outcome], in de taal van de gebruiker.
///
/// Ook een geslaagde import noemt het aantal overgeslagen bestanden: een
/// import die stil half slaagt is erger dan een die faalt.
String openKatImportSummary(
  AppLocalizations l10n,
  OpenKatImportOutcome outcome,
) {
  if (outcome.failed) return l10n.d('OpenKAT-rapport kon niet worden gemaakt.');
  final counts =
      '(${outcome.loaded} ${l10n.d('rapportages')}, '
      '${outcome.skipped} ${l10n.d('overgeslagen')})';
  if (outcome.loaded == 0) {
    return '${l10n.d('Geen OpenKAT-rapportages gevonden in deze map.')} '
        '(${outcome.skipped} ${l10n.d('overgeslagen')})';
  }
  return outcome.updatedDeck
      ? '${l10n.d('Rapport bijgewerkt. Uw eigen dia’s zijn behouden.')} '
            '$counts'
      : '${l10n.d('Rapport gemaakt.')} $counts';
}
