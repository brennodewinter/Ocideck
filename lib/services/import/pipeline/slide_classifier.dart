import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/body_block.dart';
import '../models/conversion_issue.dart';
import '../models/source_image.dart';
import '../models/source_slide.dart';
import '../../../models/slide.dart';

/// A source slide paired with the OciDeck [SlideType] the classifier chose
/// for it, plus the issues the classifier recorded (features that could not
/// be mapped and will become a "not converted" note slide).
class ClassifiedSlide {
  const ClassifiedSlide({
    required this.source,
    required this.type,
    this.issues = const [],
  });

  final SourceSlide source;
  final SlideType type;

  /// Issues raised while classifying this slide (e.g. merged cells, free
  /// positioning, decorative shapes). The pipeline collects these and emits a
  /// note slide after this one.
  ///
  /// [ConversionIssue] en niet een kale string: de tekst hierin belandt
  /// vertaald in het document van de gebruiker (#806), en een aantal dat in de
  /// zin gebakken zit vindt geen vertaling. Wat variabel is gaat door
  /// [ConversionIssue.args].
  final List<ConversionIssue> issues;
}

/// Decide which OciDeck [SlideType] best fits a [SourceSlide].
///
/// The order matters: more specific types win over the generic bullets/free
/// fallback. The classifier is deterministic and has no external side effects,
/// so it is
/// unit-testable in isolation.
ClassifiedSlide classifySlide(SourceSlide s) {
  final issues = <ConversionIssue>[];

  // Free-form positioning is always partially lost in OciDeck's fixed
  // layouts; record it once when present.
  if (s.positionedTexts.length > 1) {
    issues.add(
      ConversionIssue(
        slideIndex: s.index,
        feature: '{n} vrij geplaatste tekstvakken',
        description: 'samengevoegd in leesvolgorde',
        args: {'n': '${s.positionedTexts.length}'},
      ),
    );
  }

  if (s.isSection) {
    return ClassifiedSlide(source: s, type: SlideType.section, issues: issues);
  }

  if (s.chart != null) {
    return ClassifiedSlide(source: s, type: SlideType.chart, issues: issues);
  }

  if (s.video != null) {
    return ClassifiedSlide(source: s, type: SlideType.video, issues: issues);
  }

  // Table: whenever a table is present, because Markdown can still emit the
  // bullet list after the GFM table.
  if (s.table != null) {
    return ClassifiedSlide(source: s, type: SlideType.table, issues: issues);
  }

  // Quote: a single quote body block signals a quote slide.
  if (s.bodyBlocks.any((b) => b.kind == BodyBlockKind.quote)) {
    return ClassifiedSlide(source: s, type: SlideType.quote, issues: issues);
  }

  // Images drive the image-based layouts. Een bron-dia kan 3+ afbeeldingen
  // dragen (Keynote-decks hebben er vaak 6+ door master-slide-logo's); de
  // vaste layouts tonen er maximaal twee, dus de rest valt weg — maar de dia
  // krijgt wél een image-type, in plaats van te degenereren naar `bullets`
  // dat alle afbeeldingen stil wegdropt.
  final hasBullets = _bullets(s).isNotEmpty;
  final backgroundImage = s.images.any(
    (image) => image.role == SourceImageRole.background,
  );
  final substantiveImages = s.images.where(
    (image) => image.role != SourceImageRole.decoration,
  );
  final titleSupportingText =
      s.bodyBlocks.isNotEmpty &&
      s.bodyBlocks.length <= 3 &&
      s.bodyBlocks.every((block) => block.kind == BodyBlockKind.paragraph) &&
      s.bodyBlocks.fold<int>(0, (sum, block) => sum + block.text.length) <= 240;
  // De titellayout kan zelf een beeld dragen. Dit moet vóór de generieke
  // beeldclassificatie gebeuren, anders wordt een omslag een afbeeldingsdia en
  // verdwijnt zijn ondertitel. Een full-bleed indelingsbeeld maakt dezelfde
  // keuze ook voor een slotdia midden of achter in het deck.
  if (s.title.isNotEmpty &&
      (s.bodyBlocks.isEmpty || titleSupportingText) &&
      !hasBullets &&
      substantiveImages.isNotEmpty &&
      substantiveImages.length <= 1 &&
      (s.index == 0 || backgroundImage)) {
    return ClassifiedSlide(source: s, type: SlideType.title, issues: issues);
  }
  if (s.images.isNotEmpty) {
    if (hasBullets) {
      return ClassifiedSlide(
        source: s,
        type: SlideType.bulletsImage,
        issues: issues,
      );
    }
    if (s.images.length >= 2) {
      return ClassifiedSlide(
        source: s,
        type: SlideType.twoImages,
        issues: issues,
      );
    }
    return ClassifiedSlide(source: s, type: SlideType.image, issues: issues);
  }

  // Timeline: a bullet list whose items look like `marker :: title` events.
  if (_looksLikeTimeline(s)) {
    return ClassifiedSlide(source: s, type: SlideType.timeline, issues: issues);
  }

  // Two text columns: positioned texts that split into a left and a right
  // cluster with no image.
  if (s.images.isEmpty && _isTwoColumn(s)) {
    return ClassifiedSlide(
      source: s,
      type: SlideType.twoBullets,
      issues: issues,
    );
  }

  // Een beeldloze eerste dia blijft pas ná de vrij-geplaatste kolommen een
  // titelvoorstel. Anders kan aanwezige kolominhoud verdwijnen in een titel.
  if (s.index == 0 &&
      s.bodyBlocks.isEmpty &&
      s.images.isEmpty &&
      s.title.isNotEmpty) {
    return ClassifiedSlide(source: s, type: SlideType.title, issues: issues);
  }

  if (_bullets(s).isNotEmpty) {
    return ClassifiedSlide(source: s, type: SlideType.bullets, issues: issues);
  }

  return ClassifiedSlide(
    source: s,
    type: SlideType.freeMarkdown,
    issues: issues,
  );
}

/// Classificeer alle dia's, inclusief aparte dia's voor afbeeldingen die niet
/// in het gekozen vaste beeldraster passen.
///
/// Dit staat publiek naast [classifySlide], omdat een herhaalde randafbeelding
/// pas na de eerste parse als logo kan worden bevestigd. Na het verwijderen van
/// zo'n logo moet exact dezelfde classificatie opnieuw lopen; anders blijft een
/// tekst-dia ten onrechte een afbeeldingsdia door een beeld dat er niet meer is.
List<ClassifiedSlide> classifySourceSlides(List<SourceSlide> slides) => [
  for (final slide in slides) ..._classifyWithImageOverflow(slide),
];

int _imagesShownByType(SlideType type) => switch (type) {
  SlideType.twoImages => 2,
  SlideType.image || SlideType.bulletsImage || SlideType.title => 1,
  _ => 0,
};

List<ClassifiedSlide> _classifyWithImageOverflow(SourceSlide slide) {
  final composite = _composePositionedImageGrid(slide);
  if (composite != null) {
    return [
      classifySlide(_withImages(slide, [composite])),
    ];
  }
  final main = classifySlide(slide);
  final shown = _imagesShownByType(main.type);
  if (shown == 0 || slide.images.length <= shown) return [main];

  return [
    main,
    for (var i = shown; i < slide.images.length; i++)
      ClassifiedSlide(
        source: SourceSlide(
          index: slide.index,
          title: '',
          images: [slide.images[i]],
        ),
        type: SlideType.image,
      ),
  ];
}

/// Houdt een bewust opgemaakte collage op één dia.
///
/// OciDeck kent maximaal twee losse beeldvakken. Een raster van drie of meer
/// beelden opsplitsen over vervolgdia's verandert zowel de betekenis als de
/// uitsnede. Als alle beelden een betrouwbare positie hebben, leggen we ze
/// daarom op één transparant canvas binnen hun gezamenlijke begrenzing. De
/// uitvoer blijft een gewone PNG en dus volledig backwards compatible.
SourceImage? _composePositionedImageGrid(SourceSlide slide) {
  final images = slide.images;
  if (images.length < 3 || images.length > 8 || _bullets(slide).isNotEmpty) {
    return null;
  }
  if (images.any(
    (image) => image.role != SourceImageRole.content || image.placement == null,
  )) {
    return null;
  }

  final placements = images.map((image) => image.placement!).toList();
  final left = placements.map((p) => p.left).reduce(math.min).clamp(0.0, 1.0);
  final top = placements.map((p) => p.top).reduce(math.min).clamp(0.0, 1.0);
  final right = placements
      .map((p) => p.left + p.width)
      .reduce(math.max)
      .clamp(0.0, 1.0);
  final bottom = placements
      .map((p) => p.top + p.height)
      .reduce(math.max)
      .clamp(0.0, 1.0);
  if (right <= left || bottom <= top) return null;

  const slideWidth = 1600;
  const slideHeight = 900;
  const maxDecodedPixels = 24000000;
  var decodedPixels = 0;
  final decoded = <img.Image>[];
  try {
    for (final image in images) {
      final info = img
          .findDecoderForData(image.bytes)
          ?.startDecode(image.bytes);
      if (info == null ||
          info.width <= 0 ||
          info.height <= 0 ||
          info.width > 4096 ||
          info.height > 4096) {
        return null;
      }
      decodedPixels += info.width * info.height;
      if (decodedPixels > maxDecodedPixels) return null;
      final value = img.decodeImage(image.bytes);
      if (value == null) return null;
      decoded.add(value);
    }

    final canvasWidth = math.max(1, ((right - left) * slideWidth).round());
    final canvasHeight = math.max(1, ((bottom - top) * slideHeight).round());
    final canvas = img.Image(
      width: canvasWidth,
      height: canvasHeight,
      numChannels: 4,
    );
    img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
    for (var i = 0; i < images.length; i++) {
      final placement = placements[i];
      img.compositeImage(
        canvas,
        decoded[i],
        dstX: ((placement.left - left) * slideWidth).round(),
        dstY: ((placement.top - top) * slideHeight).round(),
        dstW: math.max(1, (placement.width * slideWidth).round()),
        dstH: math.max(1, (placement.height * slideHeight).round()),
      );
    }
    return SourceImage(
      bytes: Uint8List.fromList(img.encodePng(canvas)),
      ext: 'png',
      name: 'samengestelde-afbeeldingen-dia-${slide.index + 1}.png',
      placement: SourceImagePlacement(
        left: left,
        top: top,
        width: right - left,
        height: bottom - top,
      ),
      isComposite: true,
    );
  } on Object {
    return null;
  }
}

SourceSlide _withImages(SourceSlide slide, List<SourceImage> images) =>
    SourceSlide(
      index: slide.index,
      title: slide.title,
      subtitle: slide.subtitle,
      bodyBlocks: slide.bodyBlocks,
      images: images,
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
    );

List<BodyBlock> _bullets(SourceSlide s) =>
    s.bodyBlocks.where((b) => b.kind == BodyBlockKind.bullet).toList();

bool _looksLikeTimeline(SourceSlide s) {
  final bullets = _bullets(s);
  if (bullets.length < 2) return false;
  final marker = RegExp(r'^[^:]+::');
  return bullets.every((b) => marker.hasMatch(b.text.trim()));
}

/// True when [SourceSlide.positionedTexts] form two horizontal clusters
/// (left/right) — a heuristic for the `two-bullets` layout.
bool _isTwoColumn(SourceSlide s) {
  final pts = s.positionedTexts;
  if (pts.length < 2) return false;
  final xs = pts.map((p) => p.left).toList()..sort();
  final median = xs[xs.length ~/ 2];
  final left = pts.where((p) => p.left < median).length;
  final right = pts.where((p) => p.left >= median).length;
  return left > 0 && right > 0 && math.min(left, right) >= 1;
}
