import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'models/source_deck.dart';
import 'models/source_image.dart';
import 'models/source_slide.dart';
import '../../models/settings.dart';

enum ImportLogoEdge { top, bottom }

/// Eén inhoudelijk identieke randafbeelding die op minstens twee dia's staat.
class ImportLogoCandidate {
  const ImportLogoCandidate({
    required this.image,
    required this.sourceSha256,
    required this.slideIndexes,
    required this.edge,
  });

  final SourceImage image;

  /// De identiteit van het bronbeeld. [image] kan een veilig uitgesneden
  /// beeldmerk zijn uit een brede merkstrook, maar bij verwijderen moeten alle
  /// oorspronkelijke stroken uit de dia's verdwijnen.
  final String sourceSha256;
  final List<int> slideIndexes;
  final ImportLogoEdge edge;

  int get occurrenceCount => slideIndexes.length;

  bool matches(SourceImage other) {
    final placement = other.placement;
    if (other.sha256 != sourceSha256 || placement == null) return false;
    return (placement.isLogoLikeAtVerticalEdge ||
            placement.isWideBrandStripAtVerticalEdge) &&
        (placement.isAtTop ? ImportLogoEdge.top : ImportLogoEdge.bottom) ==
            edge;
  }
}

class ImportLogoResolution {
  const ImportLogoResolution({required this.candidate, required this.profile});

  const ImportLogoResolution.ignored(this.candidate) : profile = null;

  final ImportLogoCandidate candidate;

  /// Het toe te passen logoprofiel, of `null` wanneer de kandidaat bewust uit
  /// de import wordt weggelaten.
  final ThemeProfile? profile;
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
      final placement = image.placement;
      if (placement == null ||
          (!placement.isLogoLikeAtVerticalEdge &&
              !(image.role == SourceImageRole.decoration &&
                  placement.isWideBrandStripAtVerticalEdge))) {
        continue;
      }
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
    final candidateImage = _candidateImage(occurrence.image);
    if (candidateImage == null) continue;
    result.add(
      ImportLogoCandidate(
        image: candidateImage,
        sourceSha256: occurrence.image.sha256,
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

/// Een gewone kleine hoekafbeelding is al een bruikbaar logo. Een brede
/// modelstrook is dat niet: sla je die rechtstreeks op, dan blijft het echte
/// beeldmerk piepklein in een wit lint. Alleen wanneer een compact, gekleurd
/// hoekbeeld veilig van de dominante achtergrond is te scheiden, bieden we de
/// uitgesneden regio als logo aan.
SourceImage? _candidateImage(SourceImage source) {
  final placement = source.placement;
  if (placement == null || !placement.isWideBrandStripAtVerticalEdge) {
    return source;
  }
  return _extractBrandMark(source);
}

SourceImage? _extractBrandMark(SourceImage source) {
  final decoded = _decodeBounded(source.bytes);
  if (decoded == null) return null;
  final background = _dominantOpaqueColor(decoded);
  if (background == null) return null;

  var minX = decoded.width;
  var minY = decoded.height;
  var maxX = -1;
  var maxY = -1;
  for (final pixel in decoded) {
    if (pixel.a < 64 || !_differsFrom(pixel, background)) continue;
    minX = pixel.x < minX ? pixel.x : minX;
    minY = pixel.y < minY ? pixel.y : minY;
    maxX = pixel.x > maxX ? pixel.x : maxX;
    maxY = pixel.y > maxY ? pixel.y : maxY;
  }
  if (maxX < minX || maxY < minY) return null;
  final width = maxX - minX + 1;
  final height = maxY - minY + 1;
  final centre = (minX + maxX + 1) / (2 * decoded.width);
  // Een middenornament of een gekleurde balk over bijna de volle breedte is
  // decoratie, geen hoeklogo. Bij twijfel blijft de strook gewone inhoud.
  if (width > decoded.width * 0.40 ||
      height > decoded.height * 0.95 ||
      (centre > 0.35 && centre < 0.65)) {
    return null;
  }

  final crop = img.copyCrop(
    decoded,
    x: minX,
    y: minY,
    width: width,
    height: height,
  );
  final placement = source.placement!;
  return SourceImage(
    bytes: Uint8List.fromList(img.encodePng(crop)),
    ext: 'png',
    name: '${source.name ?? 'merkstrook'}-logo.png',
    placement: SourceImagePlacement(
      left: placement.left + placement.width * minX / decoded.width,
      top: placement.top + placement.height * minY / decoded.height,
      width: placement.width * width / decoded.width,
      height: placement.height * height / decoded.height,
    ),
    role: SourceImageRole.decoration,
  );
}

img.Image? _decodeBounded(Uint8List bytes) {
  try {
    final info = img.findDecoderForData(bytes)?.startDecode(bytes);
    // Dezelfde 4096-grens als de renderlaag: een klein gecomprimeerd bestand
    // mag de logoanalyse niet alsnog tot een onbeheersbare pixelallocatie
    // dwingen. Onbekende of grotere beelden worden niet als logo voorgesteld.
    if (info == null ||
        info.width <= 0 ||
        info.height <= 0 ||
        info.width > 4096 ||
        info.height > 4096) {
      return null;
    }
    return img.decodeImage(bytes);
  } on Object {
    return null;
  }
}

({int r, int g, int b})? _dominantOpaqueColor(img.Image image) {
  final buckets = <int, int>{};
  for (final pixel in image) {
    if (pixel.a < 192) continue;
    final key =
        (pixel.r.toInt() >> 4) << 8 |
        (pixel.g.toInt() >> 4) << 4 |
        (pixel.b.toInt() >> 4);
    buckets[key] = (buckets[key] ?? 0) + 1;
  }
  if (buckets.isEmpty) return null;
  final key = buckets.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  return (
    r: ((key >> 8) & 0xF) * 16 + 8,
    g: ((key >> 4) & 0xF) * 16 + 8,
    b: (key & 0xF) * 16 + 8,
  );
}

bool _differsFrom(img.Pixel pixel, ({int r, int g, int b}) background) {
  final red = (pixel.r.toInt() - background.r).abs();
  final green = (pixel.g.toInt() - background.g).abs();
  final blue = (pixel.b.toInt() - background.b).abs();
  return red > 40 || green > 40 || blue > 40;
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
    // De renderer ijkt `logoSize` op een dia van 1280 px breed. Met 960 werd
    // ieder geïmporteerd logo structureel een kwart te klein.
    'logoSize': (placement.width * 1280).round().clamp(32, 480),
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
