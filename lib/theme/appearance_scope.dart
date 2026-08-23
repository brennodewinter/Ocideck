import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';

import '../models/settings.dart';
import 'app_theme.dart';

/// Zet [AppTheme.isDark] gelijk aan het gekozen profiel, en zorgt dat de hele
/// interface daar ook werkelijk op herbouwt.
///
/// Dat tweede is de reden dat dit bestaat. [AppTheme.isDark] is een *statische*
/// vlag: de mode-afhankelijke tokens (`slate600`, `successBg`, `paper`, …) zijn
/// getters die hem uitlezen. Dat is een bewuste keuze — een dia moet in een
/// headless export-isolate identiek renderen aan de preview, en daar bestaat
/// geen `BuildContext` (PENTEST_MIAUW §11). Maar een statische vlag is geen
/// `InheritedWidget`: wie hem uitleest, krijgt geen melding als hij verandert.
///
/// ## Waarom er dan tóch niets herbouwde
///
/// De scope zelf herbouwt wel — zijn profiel verandert. Maar zijn kind is een
/// `const` widget, en `Element.updateChild` slaat een herbouw over zodra het
/// nieuwe widget identiek is aan het oude. Twee `const`-instanties van hetzelfde
/// zíjn identiek. Daarmee stopt de herbouw bij de scope, en alles eronder blijft
/// staan met de kleuren die het toen las: het slidekwaliteitspaneel bleef
/// donkergroen op een lichte interface tot een herstart (#780). Dat gold voor
/// élke widget die zich uit [AppTheme] kleurt en niet toevallig van
/// `Theme.of(context)` afhangt — 776 gebruiksplekken in 139 bestanden (#814).
///
/// ## Waarom de boom márkeren en niet weggooien
///
/// De voor de hand liggende reparatie is een sleutel op de modus, zodat Flutter
/// de element-boom weggooit en opnieuw opbouwt. Dat is geprobeerd in #780 en
/// teruggedraaid: de deck-providers hangen aan het tabblad, dus dat afbreken
/// disposet `DeckNotifier` terwijl er nog naar geluisterd wordt — en erger dan
/// de crash is wat eraan voorafgaat, namelijk het niet-opgeslagen deck van de
/// gebruiker.
///
/// Wat hier gebeurt houdt de elementen juist vást. Élk element onder deze scope
/// wordt vuil gemarkeerd; Flutter draait dan hun `build` opnieuw, waarna elke
/// [AppTheme]-getter de nieuwe kant leest. Geen enkele `State` wordt weggegooid,
/// dus schuifposities, uitgeklapte panelen, tekstcursors én de deckstaat blijven
/// staan.
///
/// De prijs is één volledige herbouw van de boom per moduswissel. Dat is een
/// bewuste, zeldzame handeling, en de markering hangt dan ook aan de *modus* en
/// niet aan het profiel: één kleur bijstellen in een eigen profiel loopt via
/// `ThemeData` en propageert vanzelf.
class AppearanceScope extends StatefulWidget {
  final AppAppearanceProfile appearance;
  final Widget child;

  const AppearanceScope({
    super.key,
    required this.appearance,
    required this.child,
  });

  @override
  State<AppearanceScope> createState() => _AppearanceScopeState();
}

class _AppearanceScopeState extends State<AppearanceScope> {
  @override
  void initState() {
    super.initState();
    // Vóór de eerste descendant bouwt, niet in `build`: die loopt ná de
    // constructor maar de vlag moet er al staan als het eerste blad hem leest.
    AppTheme.isDark = widget.appearance.isDark;
  }

  @override
  void didUpdateWidget(covariant AppearanceScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasDark = oldWidget.appearance.isDark;
    final isDark = widget.appearance.isDark;
    AppTheme.isDark = isDark;
    if (wasDark == isDark) return;
    // Ná dit frame, niet erin: `markNeedsBuild` op een element dat in dit frame
    // al gebouwd is, is een fout. Eén frame in de oude kleuren ziet niemand;
    // een assertie-crash bij elke themawissel wel.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) markAppearanceSubtreeDirty(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Markeert élk element onder [context] als "moet opnieuw bouwen", zonder er een
/// weg te gooien.
///
/// Losse functie omdat hij van buiten te toetsen moet zijn. Dat hij niets
/// selecteert is geen luiheid: welke widget zich uit [AppTheme] kleurt valt van
/// buitenaf niet te zien — dat is nu juist wat een statische vlag onzichtbaar
/// maakt. Dus allemaal.
@visibleForTesting
void markAppearanceSubtreeDirty(BuildContext context) {
  void mark(Element element) {
    element.markNeedsBuild();
    element.visitChildren(mark);
  }

  context.visitChildElements(mark);
}
