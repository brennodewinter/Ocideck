// Wat het exportvenster toont terwijl een export lóópt.
//
// Los van het venster om dezelfde reden als `export_failure_text.dart`: het is
// pure tekstkeuze — geen toestand, geen widgets — en zo te toetsen zonder een
// dialoog te openen. Dat is hier geen smaakkwestie. Deze functie was een
// private methode op de dialoogstate, en juist daardoor kon #714 er ongezien in
// zitten: geen enkele toets kwam erlangs, want alle exporttoetsen roepen de
// rasteraar aan zónder voortgangs-callback.
import '../../l10n/app_localizations.dart';

/// De voortgangsregel voor [phase], zoals de rasteraar hem meldt.
///
/// [done] en [total] betekenen per fase iets anders: bij `precache` is [total]
/// het aantal te laden **afbeeldingen**, bij de rest het aantal **dia's**.
///
/// **[total] mag nul zijn, en dat was #714.** Hier stond
/// `(done + 1).clamp(1, total)`, en Dart's `clamp` gooit
/// `ArgumentError(lowerLimit)` zodra de bovengrens onder de ondergrens zakt —
/// bij `total == 0` dus letterlijk `ArgumentError(1)`, wat de gebruiker zag als
/// "Invalid argument(s): 1". Een deck zonder ook maar één afbeelding meldt
/// `precache` met nul, en een pentestrapport is daar het schoolvoorbeeld van:
/// bevindingen, checklists en tabellen, geen enkele foto. De HTML-export van
/// hetzelfde deck lukte wél, want die rastert niet en komt hier nooit langs.
String exportProgressText(
  AppLocalizations l10n,
  String phase,
  int done,
  int total,
) {
  // De ondergrens 1 blijft: een dia heet "1" en niet "0". Bij `total < 1` is er
  // geen zinnige bovengrens om tegen te knippen, dus die vervalt.
  final number = total < 1 ? done + 1 : (done + 1).clamp(1, total);
  switch (phase) {
    case 'precache':
      return total == 0
          ? l10n.d('Afbeeldingen laden…')
          : '${l10n.d('Afbeeldingen laden…')} $done ${l10n.t('of')} $total';
    case 'prepare':
      return '${l10n.d('Slide')} $number ${l10n.d('voorbereiden…')}';
    case 'render':
      return '${l10n.d('Slide')} $number ${l10n.d('renderen…')}';
    case 'done':
      return done >= total
          ? l10n.d('Slides gerenderd.')
          : '${l10n.d('Slide')} $done ${l10n.d('gerenderd.')}';
    default:
      return l10n.t('renderingSlides');
  }
}
