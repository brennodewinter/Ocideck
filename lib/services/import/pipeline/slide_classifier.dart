import 'dart:math' as math;

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
/// fallback. The classifier is deterministic and side-effect-free so it is
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
  // De titellayout kan zelf een beeld dragen. Dit moet vóór de generieke
  // beeldclassificatie gebeuren, anders wordt een omslag een afbeeldingsdia en
  // verdwijnt zijn ondertitel. Een full-bleed indelingsbeeld maakt dezelfde
  // keuze ook voor een slotdia midden of achter in het deck.
  if (s.title.isNotEmpty &&
      s.bodyBlocks.isEmpty &&
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
