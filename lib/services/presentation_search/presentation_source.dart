// ── lib/services/presentation_search/ ────────────────────────────────────────
// De bronnen die 'Slide zoeken' aftast als ze niet op schijf staan. Eén
// contract ([PresentationSource]) met twee implementaties: git via de forge, en
// bestandsopslag (WebDAV of S3) via [RemoteFileClient] — een eigen, smalle
// listing zodat het loopwerk over een mappenboom maar één keer bestaat en niet
// per protocol wordt overgeschreven.
//
// Wat hier hoort is dus: een nieuwe soort bron, of het aftasten zelf. Wat hier
// níét hoort: het protocol (dat is ../s3/ en ../webdav_service.dart, die dit
// cluster alleen gebruikt), de lokale schijfscan (../file_service.dart), welke
// bronnen er aan staan (lib/state/presentation_sources.dart) en het venster dat
// de treffers toont (lib/widgets/dialogs/slide_finder_dialog.dart). Bestand
// voor bestand: docs/SOURCE_MAP.md.
// ─────────────────────────────────────────────────────────────────────────────

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
