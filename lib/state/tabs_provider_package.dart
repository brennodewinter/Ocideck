part of 'tabs_provider.dart';

/// Het uitpak-pad van een `.ocideck`-pakket dat in het geheugen is geopend
/// (web, of een import zonder projectmap): de leden naast de hoofd-markdown
/// worden teruggezet in het deck. Apart bestand omdat `tabs_provider` tegen de
/// regelratchet aan zit; de extensie zit in dezelfde library, dus de private
/// helpers blijven bereikbaar.
///
/// Elk type lid heeft zijn eigen route: afbeeldingen gaan naar de
/// [WebAssetStore] en de slidepaden worden naar `mem:` herschreven,
/// grafiekdata wordt inline in de spec gezet, en de sidecars worden als losse
/// lagen op het deck teruggelegd. Wat ze delen is de insluiting: een
/// verwijzing die met `../` buiten de pakketwortel wijst wordt niet gevolgd.
extension _TabsPackageAssets on TabsNotifier {
  /// Zet de afbeeldings-leden van een pakket in de [WebAssetStore] en
  /// herschrijf de slidepaden die ernaar verwijzen naar hun mem:-pad.
  /// Verwijzingen zijn relatief aan de hoofd-markdown ([mdName]). Alleen
  /// leden die de afbeeldingsvalidatie (magic bytes + cap) doorstaan doen mee.
  Deck _attachPackageAssets(
    Deck deck,
    List<PackageEntry> entries,
    String mdName,
  ) {
    final mdDir = p.posix.dirname(mdName);
    final byName = {
      for (final e in entries) p.posix.normalize(e.name): e.bytes,
    };
    final memFor = <String, String>{};
    String? memPath(String ref) {
      if (ref.trim().isEmpty || WebAssetStore.isMemPath(ref)) return null;
      final resolved = p.posix.normalize(
        mdDir == '.' ? ref : p.posix.join(mdDir, ref),
      );
      if (resolved.startsWith('..')) return null; // buiten het pakket
      final cached = memFor[resolved];
      if (cached != null) return cached;
      final bytes = byName[resolved];
      if (bytes == null ||
          bytes.isEmpty ||
          bytes.length > ImageService.maxImageBytes ||
          !ImageService.looksLikeImage(bytes)) {
        return null;
      }
      final mem = WebAssetStore.put(bytes, name: p.posix.basename(resolved));
      memFor[resolved] = mem;
      return mem;
    }

    final slides = [
      for (final s in deck.slides)
        s.copyWith(
          imagePath: memPath(s.imagePath) ?? s.imagePath,
          imagePath2: memPath(s.imagePath2) ?? s.imagePath2,
        ),
    ];
    return deck.copyWith(slides: slides);
  }

  /// Vul chart-slides die hun data via `source` koppelen aan uit de `data/`-
  /// leden van het pakket — het tegenhangertje van `_hydrateCharts` op schijf.
  ///
  /// Anders dan afbeeldingen gaat dit *niet* via de [WebAssetStore]: de data is
  /// tekst die in de spec zelf hoort, en er is op web geen projectmap waar een
  /// los databestand naast kan blijven liggen. Zonder deze stap komt een deck
  /// met gekoppelde grafieken binnen met lege plots.
  Deck _attachPackageChartData(
    Deck deck,
    List<PackageEntry> entries,
    String mdName,
  ) {
    final mdDir = p.posix.dirname(mdName);
    final byName = {
      for (final e in entries) p.posix.normalize(e.name): e.bytes,
    };
    var changed = false;
    final slides = <Slide>[];
    for (final s in deck.slides) {
      final spec = s.type == SlideType.chart
          ? ChartSpec.parse(s.customMarkdown)
          : null;
      final source = spec?.source;
      if (spec == null || source == null || spec.hasInlineData) {
        slides.add(s);
        continue;
      }
      // Zelfde insluiting als resolveProjectRelative op schijf: een `source`
      // als ../../geheim.csv mag niet buiten het pakket wijzen.
      final resolved = p.posix.normalize(
        mdDir == '.' ? source : p.posix.join(mdDir, source),
      );
      final bytes = resolved.startsWith('..') ? null : byName[resolved];
      if (bytes == null ||
          bytes.isEmpty ||
          bytes.length > FileService.maxDeckMarkdownBytes) {
        slides.add(s);
        continue;
      }
      try {
        slides.add(
          s.copyWith(
            customMarkdown: spec.withCsv(utf8.decode(bytes)).toBlock(),
          ),
        );
        changed = true;
      } on FormatException catch (e) {
        logWarning('TabsNotifier._attachPackageChartData: data not UTF-8', e);
        slides.add(s);
      }
    }
    return changed ? deck.copyWith(slides: slides) : deck;
  }

  /// Herstel de sidecar-lagen (ink-annotaties en sprekersnotities) uit de
  /// pakket-leden naast de hoofd-markdown — dezelfde bestandsnamen als de
  /// schijfvariant in [FileService.openDeckDetailed].
  Deck _attachPackageSidecars(
    Deck deck,
    List<PackageEntry> entries,
    String mdName,
  ) {
    final base = mdName.replaceAll(RegExp(r'\.md$', caseSensitive: false), '');
    String? textFor(String memberName) {
      for (final e in entries) {
        if (p.posix.normalize(e.name) == p.posix.normalize(memberName)) {
          try {
            return utf8.decode(e.bytes);
          } on FormatException catch (err) {
            logWarning(
              'TabsNotifier._attachPackageSidecars: sidecar not UTF-8',
              err,
            );
            return null;
          }
        }
      }
      return null;
    }

    var result = deck;
    final ink = textFor('$base.ink.json');
    if (ink != null) {
      try {
        final map = AnnotationCodec.decode(ink, result.slides);
        if (map.isNotEmpty) result = result.copyWith(annotations: map);
      } catch (e) {
        // Een kapotte sidecar mag het openen nooit blokkeren.
        logWarning('TabsNotifier._attachPackageSidecars: ink unreadable', e);
      }
    }
    final notes = textFor('$base.user-notes.json');
    if (notes != null) {
      try {
        final map = UserNotesCodec.decode(notes, result.slides);
        if (map.isNotEmpty) result = result.copyWith(userNotes: map);
      } catch (e) {
        logWarning('TabsNotifier._attachPackageSidecars: notes unreadable', e);
      }
    }
    return result;
  }
}
