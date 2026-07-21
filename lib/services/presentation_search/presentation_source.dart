import '../file_service.dart' show ScannedPresentation;

/// Eén doorzoekbare bron van presentaties voor 'Slide zoeken'.
///
/// Lokale bibliotheken scant de finder rechtstreeks van schijf; deze abstractie
/// dekt de bronnen die netwerk vergen — git, WebDAV en S3 — zodat de finder ze
/// uniform en gelijktijdig kan aftasten en de treffers naast de lokale kan
/// leggen. Elke bron levert dezelfde [ScannedPresentation]s op als een lokale
/// scan, met een deck waarvan de afbeeldingen al als in-geheugen `mem:`-paden
/// zijn opgelost, zodat previews en toevoegen zonder bestandssysteem werken.
abstract class PresentationSource {
  /// Korte naam voor de voortgangsregel en attributie, bijv. "Git: Werk".
  String get label;

  /// Haal alle presentaties uit deze bron op.
  ///
  /// Mag traag zijn (netwerk) en mag gooien: de finder vangt fouten per bron af
  /// en meldt ze, zodat één trage of onbereikbare verbinding de rest en het
  /// lokale zoeken niet blokkeert.
  Future<List<ScannedPresentation>> scan();
}
