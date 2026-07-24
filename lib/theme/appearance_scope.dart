import 'package:flutter/material.dart';

import '../models/settings.dart';
import 'app_theme.dart';

/// Zet [AppTheme.isDark] gelijk aan het gekozen profiel, en publiceert de modus
/// als iets waar een widget *op kan aansluiten*.
///
/// [AppTheme.isDark] is een statische vlag. Dat is een bewuste keuze — een dia
/// moet in een headless export-isolate identiek renderen aan de preview, en daar
/// bestaat geen `BuildContext` (PENTEST_MIAUW §11) — maar een statische vlag is
/// geen `InheritedWidget`: wie hem uitleest, krijgt geen melding als hij
/// verandert. Het slidekwaliteitspaneel bleef daardoor donkergroen op een lichte
/// interface staan tot een herstart (#780), en dat geldt voor élke widget die
/// zich uit [AppTheme] kleurt zonder van `Theme.of(context)` af te hangen.
///
/// **De boom weggooien is hier geen oplossing.** Een `KeyedSubtree` met een
/// sleutel op de modus doet precies wat je zou willen — alles bouwt opnieuw —
/// en laat de app omvallen: de deck-providers hangen aan het tabblad, dus het
/// afbreken van die boom disposet `DeckNotifier` terwijl er nog naar geluisterd
/// wordt (`ProviderException: Tried to use DeckNotifier after dispose`). Erger
/// dan de crash is wat eraan voorafgaat: dat is het niet-opgeslagen deck van de
/// gebruiker. Geprobeerd en teruggedraaid in #780; niet nog eens proberen zonder
/// de deckstaat éérst boven die grens te tillen.
///
/// Wat er nu staat is dus de bescheiden variant: de modus zit in een
/// `InheritedWidget`, en een widget die zich uit [AppTheme] kleurt sluit erop
/// aan met [AppearanceScope.modeOf]. Eén regel per oppervlak, en het is de enige
/// vorm die Flutter kent om wél een melding te krijgen. Zie #814 voor het
/// resterende deel: de oppervlakken die die regel nog niet hebben.
class AppearanceScope extends InheritedWidget {
  /// Of de app-chrome in donkere modus staat. Zelfde waarde als
  /// [AppTheme.isDark]; het verschil is dat hierop aangesloten kan worden.
  final bool isDark;

  AppearanceScope({
    super.key,
    required AppAppearanceProfile appearance,
    required super.child,
  }) : isDark = appearance.isDark {
    // In de constructor en niet in `build`: deze widget wordt aangemaakt in de
    // build van de app-root, dus de vlag staat goed vóór de eerste descendant
    // bouwt — ook bij de allereerste frame.
    AppTheme.isDark = isDark;
  }

  /// De huidige modus, mét een afhankelijkheid: de aanroeper herbouwt wanneer
  /// de gebruiker van profiel wisselt. Dat is het hele punt — de waarde zelf
  /// staat ook in [AppTheme.isDark].
  ///
  /// Buiten de app (een losse widget in een test, een export-isolate) is er geen
  /// scope; dan valt dit terug op de statische vlag in plaats van te werpen.
  static bool modeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppearanceScope>()?.isDark ??
      AppTheme.isDark;

  @override
  bool updateShouldNotify(AppearanceScope oldWidget) =>
      oldWidget.isDark != isDark;
}
