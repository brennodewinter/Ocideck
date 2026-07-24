import 'package:flutter/material.dart';

import '../models/settings.dart';
import 'app_theme.dart';

/// Zet [AppTheme.isDark] gelijk aan het gekozen profiel en zorgt dat de
/// interface daar ook werkelijk op herbouwt.
///
/// Dat tweede is de reden dat dit een widget is en geen regel in `build`.
/// [AppTheme.isDark] is een *statische* vlag: de mode-afhankelijke tokens
/// (`slate600`, `successBg`, `paper`, …) zijn getters die hem uitlezen. Dat is
/// een bewuste keuze — een dia moet in een headless export-isolate identiek
/// renderen aan de preview, en daar bestaat geen `BuildContext`
/// (PENTEST_MIAUW §11). Maar een statische vlag is geen `InheritedWidget`: wie
/// hem uitleest, krijgt geen melding als hij verandert.
///
/// Het gevolg stond tot #780 in de app. Bij het omzetten van *Donker* naar
/// *Europa* wisselde alles wat via `ThemeData` gaat netjes mee, maar het
/// slidekwaliteitspaneel bleef donkergroen op een lichte interface staan —
/// het herbouwt alleen als zijn eigen invoer verandert, en het thema is zijn
/// invoer niet. Een dia kiezen hielp niet, in- en uitklappen hielp niet;
/// alleen een herstart. Dat is de hele klasse: élke widget die zich uit
/// [AppTheme] kleurt en niet van `Theme.of(context)` afhangt, houdt de kleuren
/// van het vorige thema vast.
///
/// De sleutel op de modus lost dat op: wisselt de modus, dan gooit Flutter de
/// element-boom eronder weg en bouwt hem opnieuw op, waarna elke getter de
/// nieuwe kant leest. De prijs is dat vluchtige interface-staat (schuifpositie,
/// een uitgeklapt paneel) bij die wisseling terugvalt naar de beginstand. Dat
/// is aanvaardbaar en niet toevallig: de inhoud zit in Riverpod en overleeft,
/// en van modus wisselen is een bewuste, zeldzame handeling — de sleutel staat
/// dan ook op de modus en niet op het profiel, zodat het bijstellen van één
/// kleur in een eigen profiel géén boom weggooit.
class AppearanceScope extends StatelessWidget {
  final AppAppearanceProfile appearance;
  final Widget child;

  const AppearanceScope({
    super.key,
    required this.appearance,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    AppTheme.isDark = appearance.isDark;
    return KeyedSubtree(key: ValueKey<bool>(appearance.isDark), child: child);
  }
}
