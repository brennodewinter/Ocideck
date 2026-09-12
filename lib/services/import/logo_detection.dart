import 'models/source_deck.dart';
import 'models/source_image.dart';
import 'models/source_slide.dart';
import '../../models/settings.dart';

enum ImportLogoEdge { top, bottom }

/// Eén inhoudelijk identieke randafbeelding die op minstens twee dia's staat.
class ImportLogoCandidate {
  const ImportLogoCandidate({
    required this.image,
    required this.slideIndexes,
    required this.edge,
  });

  final SourceImage image;
  final List<int> slideIndexes;
  final ImportLogoEdge edge;

  int get occurrenceCount => slideIndexes.length;

  bool matches(SourceImage other) {
    final placement = other.placement;
    if (other.sha256 != image.sha256 || placement == null) return false;
    return placement.isLogoLikeAtVerticalEdge &&
        (placement.isAtTop ? ImportLogoEdge.top : ImportLogoEdge.bottom) ==
            edge;
  }
}

class ImportLogoResolution {
  const ImportLogoResolution({required this.candidate, required this.profile});

  final ImportLogoCandidate candidate;
  final ThemeProfile profile;
}

/// Vind herhaalde, kleine afbeeldingen in de boven- of onderrand.
///
/// De inhoudshash is leidend, niet de archiefnaam: PowerPoint en Keynote mogen
/// hetzelfde beeld onder verschillende partnamen bewaren. Eén afbeelding die
/// tweemaal op dezelfde dia staat telt maar één keer; herhaling over dia's is
/// juist het bewijs dat dit deckbrede versiering kan zijn.
List<ImportLogoCandidate> detectImportLogoCandidates(SourceDeck deck) {
  final occurrences = <String, ({SourceImage image, Set<int> slides})>{};
  for (final slide in deck.slides) {
    final seenOnSlide = <String>{};
    for (final image in slide.images) {
      if (!(image.placement?.isLogoLikeAtVerticalEdge ?? false)) continue;
      final edge = image.placement!.isAtTop
          ? ImportLogoEdge.top
          : ImportLogoEdge.bottom;
      final key = '${image.sha256}:${edge.name}';
      if (!seenOnSlide.add(key)) continue;
      final current = occurrences[key];
      if (current == null) {
        occurrences[key] = (image: image, slides: {slide.index});
      } else {
        current.slides.add(slide.index);
      }
    }
  }

  final result = <ImportLogoCandidate>[];
  for (final occurrence in occurrences.values) {
    if (occurrence.slides.length < 2) continue;
    result.add(
      ImportLogoCandidate(
        image: occurrence.image,
        slideIndexes: occurrence.slides.toList()..sort(),
        edge: occurrence.image.placement!.isAtTop
            ? ImportLogoEdge.top
            : ImportLogoEdge.bottom,
      ),
    );
  }
  result.sort((a, b) => b.occurrenceCount.compareTo(a.occurrenceCount));
  return result;
}

/// Verwijder alleen de bevestigde logo-inhoud uit alle dia's.
SourceDeck sourceDeckWithoutLogo(
  SourceDeck deck,
  ImportLogoCandidate candidate,
) => SourceDeck(
  title: deck.title,
  author: deck.author,
  theme: deck.theme,
  issues: deck.issues,
  slides: [
    for (final slide in deck.slides)
      SourceSlide(
        index: slide.index,
        title: slide.title,
        subtitle: slide.subtitle,
        bodyBlocks: slide.bodyBlocks,
        images: [
          for (final image in slide.images)
            if (!candidate.matches(image)) image,
        ],
        chart: slide.chart,
        table: slide.table,
        video: slide.video,
        audioFileName: slide.audioFileName,
        hyperlinks: slide.hyperlinks,
        notes: slide.notes,
        comments: slide.comments,
        theme: slide.theme,
        isHidden: slide.isHidden,
        isSection: slide.isSection,
        positionedTexts: slide.positionedTexts,
        parseIssues: slide.parseIssues,
      ),
  ],
);

/// Bouw een veilig stijlprofiel uit de gevonden bronstijl en het bevestigde
/// logo. [ThemeProfile.fromJson] is hier de hardende poort: een brondocument
/// mag geen onbekend lettertype of ongeldige kleur in de renderer brengen.
ThemeProfile importedLogoProfile({
  required SourceDeck deck,
  required ImportLogoCandidate candidate,
  required String logoPath,
  required String name,
  ThemeProfile base = const ThemeProfile(),
}) {
  final source = deck.theme;
  final placement = candidate.image.placement!;
  final horizontal = placement.left + placement.width / 2 <= 0.5
      ? 'left'
      : 'right';
  final vertical = candidate.edge == ImportLogoEdge.top ? 'top' : 'bottom';
  final json = <String, Object?>{
    ...base.toJson(),
    'name': name,
    'logoPath': logoPath,
    'logoPosition': '$vertical-$horizontal',
    'logoSize': (placement.width * 960).round().clamp(32, 480),
    if (source?.slideBackgroundColor != null)
      'slideBackgroundColor': source!.slideBackgroundColor,
    if (source?.textColor != null) 'textColor': source!.textColor,
    if (source?.accentColor != null) 'accentColor': source!.accentColor,
    if (source?.titleBackgroundColor != null)
      'titleBackgroundColor': source!.titleBackgroundColor,
    if (source?.sectionBackgroundColor != null)
      'sectionBackgroundColor': source!.sectionBackgroundColor,
    if (source?.fontFamily != null) 'fontFamily': source!.fontFamily,
    if (source?.footerText != null) 'footerText': source!.footerText,
    if (source?.showPageNumbers != null)
      'footerShowPageNumbers': source!.showPageNumbers,
  };
  return ThemeProfile.fromJson(json);
}
