// Part of the settings_provider library — see ../settings_provider.dart.
// De kijkschalen: interfaceschaal en overzichtszoom. Allemaal pure
// kijkvoorkeuren — ze raken geen enkel bestand — maar wel bewaard, want wie
// grotere tekst of grotere miniaturen nodig heeft, stelt dat niet bij elk
// scherm opnieuw in.
part of '../settings_provider.dart';

/// Ondergrens, bovengrens en stapgrootte van de zoom in het slide-overzicht.
///
/// Top-level om dezelfde reden als de documentzoom-grenzen in
/// `settings_provider_document_style.dart`: de knoppen en de kolombrekening in
/// `preview_panel_overview.dart` lezen ze hier, zodat clampen en stappen aan
/// één kant vastliggen. 1,0 is de standaardtegel; 0,5 halveert hem en 3,0
/// verdrievoudigt hem.
const double kSlideOverviewZoomMin = 0.5;
const double kSlideOverviewZoomMax = 3.0;
const double kSlideOverviewZoomStep = 0.25;

/// De schaalfactor voor alle interfacetekst (1,0–2,0).
Future<void> _applyUiTextScale(SettingsNotifier notifier, double scale) async {
  final clamped = scale.clamp(1.0, 2.0).toDouble();
  notifier.currentState = notifier.currentState.copyWith(uiTextScale: clamped);
  await notifier._persist(
    'setUiTextScale',
    (prefs) => prefs.setDouble('uiTextScale', clamped),
  );
}

/// De zoomfactor van de tegels in het slide-overzicht, geklemd op zijn
/// grenzen.
Future<void> _applySlideOverviewZoom(SettingsNotifier notifier, double zoom) {
  final clamped = zoom
      .clamp(kSlideOverviewZoomMin, kSlideOverviewZoomMax)
      .toDouble();
  if (clamped == notifier.currentState.slideOverviewZoom) {
    return Future.value();
  }
  notifier.currentState = notifier.currentState.copyWith(
    slideOverviewZoom: clamped,
  );
  return notifier._persist(
    'setSlideOverviewZoom',
    (prefs) => prefs.setDouble('slideOverviewZoom', clamped),
  );
}

/// De opgeslagen overzichtszoom, geklemd — een corrupte of met de hand
/// aangepaste pref degradeert naar een geldige stand, niet naar een crash.
double _readSlideOverviewZoom(SharedPreferences prefs) =>
    (prefs.getDouble('slideOverviewZoom') ?? 1.0).clamp(
      kSlideOverviewZoomMin,
      kSlideOverviewZoomMax,
    );
