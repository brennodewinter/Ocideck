import 'dart:math' as math;

import '../models/body_block.dart';
import '../models/conversion_issue.dart';
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

  // Images drive the image-based layouts.
  if (s.images.length == 2 && _bullets(s).isEmpty) {
    return ClassifiedSlide(
      source: s,
      type: SlideType.twoImages,
      issues: issues,
    );
  }
  if (s.images.length == 1) {
    if (_bullets(s).isNotEmpty) {
      return ClassifiedSlide(
        source: s,
        type: SlideType.bulletsImage,
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

  // Title slide: the first slide with only a title (+ subtitle) and no body.
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
