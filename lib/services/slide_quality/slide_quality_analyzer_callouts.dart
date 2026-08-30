// Part of the slide_quality_analyzer library — see
// ../slide_quality_analyzer.dart. Split out for navigability (de callout-
// checker: §2.6 binding, geometrie, wezen, dubbele refs, anker, en de
// clip-check van #1853); alle imports staan in het hoofdbestand.
part of '../slide_quality_analyzer.dart';

/// De callout-checker (IMAGE_CALLOUTS.md §2.6). Vijf regels, alle per-slide:
///
/// 1. **Invalid geometry** — een target met coördinaten buiten [0,1] of een
///    verkeerd aantal componenten. De codec weigert het te tekenen; de checker
///    meldt het zodat de auteur weet waarom de pijl ontbreekt.
/// 2. **Orphan reference** — een callout-entry in de front matter zonder
///    bijbehorende `(A)`-markering in de tekst, of omgekeerd.
/// 3. **Duplicate reference** — dezelfde letter twee keer op één dia.
/// 4. **Missing anchor** — de dia heeft callouts maar geen anker, dus de front
///    matter kan ze niet aan de dia koppelen.
/// 5. **Target out of view** (#1853) — een doel valt buiten de zichtbare band
///    die cover/zoom/focal laat zien. De overlay tekent niets; de checker
///    meldt het zodat de auteur weet waarom de markering ontbreekt.
///
/// De checker rapporteert alleen — hij clamp niet, verwijdert niet, en herschikt
/// niet. De codec behoudt alles byte-voor-byte (§2.5).
void _checkCallouts(Slide slide, int index, List<SlideQualityIssue> issues) {
  if (slide.callouts.isEmpty) return;

  // §2.6 binding regel 4: een dia met callouts moet een anker hebben.
  if (slide.anchor.isEmpty) {
    issues.add(
      SlideQualityIssue(
        slideIndex: index,
        kind: SlideQualityIssueKind.calloutMissingAnchor,
        category: SlideQualityCategory.callout,
        severity: MarkdownValidationSeverity.error,
      ),
    );
  }

  // Verzamel alle (A)-markeringen in de tekst van deze dia, met telling: een
  // letter die twee keer voorkomt (geplakte bullet) is een duplicate finding
  // (§2.6), geen geldige referentie.
  final textRefCount = <String, int>{};
  for (final bullet in [...slide.bullets, ...slide.bullets2]) {
    for (final m in _reCalloutReference.allMatches(bullet)) {
      final ref = m.group(1)!;
      textRefCount[ref] = (textRefCount[ref] ?? 0) + 1;
    }
  }
  final textRefs = textRefCount.keys.toSet();

  // §2.6: twee of meer bullets eindigen op (X) → duplicate finding.
  for (final entry in textRefCount.entries) {
    if (entry.value > 1) {
      issues.add(
        SlideQualityIssue(
          slideIndex: index,
          kind: SlideQualityIssueKind.calloutDuplicateReference,
          category: SlideQualityCategory.callout,
          severity: MarkdownValidationSeverity.error,
          args: {'ref': '(${entry.key})'},
        ),
      );
    }
  }

  // Track welke refs we al gezien hebben voor duplicate detection.
  final seen = <String>{};
  for (final callout in slide.callouts) {
    final ref = callout.reference;

    // Duplicate: dezelfde letter twee keer.
    if (!seen.add(ref)) {
      issues.add(
        SlideQualityIssue(
          slideIndex: index,
          kind: SlideQualityIssueKind.calloutDuplicateReference,
          category: SlideQualityCategory.callout,
          severity: MarkdownValidationSeverity.error,
          args: {'ref': '($ref)'},
        ),
      );
    }

    // Invalid geometry: een target buiten [0,1] of met verkeerde componenten.
    // §8: een region heeft minimaal 0.02 op beide assen.
    for (final target in callout.targets) {
      final tooSmall =
          target is CalloutRegion && (target.w < 0.02 || target.h < 0.02);
      if (!target.isValid || tooSmall) {
        issues.add(
          SlideQualityIssue(
            slideIndex: index,
            kind: SlideQualityIssueKind.calloutInvalidGeometry,
            category: SlideQualityCategory.callout,
            severity: MarkdownValidationSeverity.error,
            args: {'ref': '($ref)'},
          ),
        );
        break;
      }
    }

    // Orphan: entry in front matter zonder (A) in de tekst.
    if (!textRefs.contains(ref)) {
      issues.add(
        SlideQualityIssue(
          slideIndex: index,
          kind: SlideQualityIssueKind.calloutOrphanReference,
          category: SlideQualityCategory.callout,
          severity: MarkdownValidationSeverity.warning,
          args: {'ref': '($ref)'},
        ),
      );
    }
  }

  // Orphan: (A) in de tekst zonder entry in de front matter.
  final entryRefs = slide.callouts.map((c) => c.reference).toSet();
  for (final ref in textRefs) {
    if (!entryRefs.contains(ref)) {
      issues.add(
        SlideQualityIssue(
          slideIndex: index,
          kind: SlideQualityIssueKind.calloutOrphanReference,
          category: SlideQualityCategory.callout,
          severity: MarkdownValidationSeverity.warning,
          args: {'ref': '($ref)'},
        ),
      );
    }
  }

  // #1853: doel valt buiten de zichtbare band. Alleen te bepalen met de
  // intrinsieke beeldmaat — zonder die kan de checker niet weten of cover
  // het doel afsnijdt. Geen beeld of niet op schijf → stil (geen valse
  // positief, en de editor-visie dekt dat geval visueel).
  _checkCalloutClip(slide, index, issues);

  // §5: kruisende pijlen in arrow-modus. Met de fixed-rail-ontwerp (alle
  // pijlen horizontaal van x=0 naar het target) is kruising geometrisch
  // onmogelijk — twee horizontale lijnen op verschillende y kruisen nooit.
  // De check is hier als ankerpunt voor het geval een toekomstige variant
  // niet-horizontale pijlen toestaat.
  // ponytail: als pijlen ooit niet-horizontaal worden, is dit de plek om
  // echte lijn-kruising te detecteren en calloutCrossingArrows te melden.
}

/// #1853: controleer of callout-doelen buiten de zichtbare band vallen die
/// cover/zoom/focal laat zien. De overlay tekent niets voor zo'n doel; deze
/// check meldt het zodat de auteur weet waarom de markering ontbreekt.
void _checkCalloutClip(Slide slide, int index, List<SlideQualityIssue> issues) {
  if (kIsWeb) return;
  if (slide.imagePath.trim().isEmpty) return;
  if (isBundledAssetPath(slide.imagePath)) return; // asset: — niet op schijf
  if (WebAssetStore.isMemPath(slide.imagePath)) return; // mem: — in-memory

  final resolved = resolveSlideAssetPath(slide.imagePath, null);
  if (resolved == null) return;
  final dims = readImageDimensions(resolved);
  if (dims == null) {
    return; // niet-leesbaar of onbekend formaat → geen valse positief
  }

  // De slot-aspectratio voor een bulletsImage-dia: imageFraction * 16/9.
  // De absolute waarden tellen niet, alleen de verhouding.
  final imgFraction = (slide.imageSize > 0 ? slide.imageSize / 100.0 : 0.40)
      .clamp(0.1, 0.70);
  final slotW = imgFraction * 16;
  final slotH = 9.0;

  final painted = ImageViewportGeometry.paintedRect(
    imageW: dims.width.toDouble(),
    imageH: dims.height.toDouble(),
    slotW: slotW,
    slotH: slotH,
    focalX: slide.imageFocalX,
    focalY: slide.imageFocalY,
    zoom: slide.imageZoom,
  );

  final reported = <String>{};
  for (final callout in slide.callouts) {
    if (reported.contains(callout.reference)) continue;
    for (final target in callout.targets) {
      if (!target.isValid) continue; // invalid geometry is al gemeld
      final mapped = ImageViewportGeometry.mapTarget(
        target,
        painted: painted,
        slotW: slotW,
        slotH: slotH,
      );
      if (mapped.clipped) {
        issues.add(
          SlideQualityIssue(
            slideIndex: index,
            kind: SlideQualityIssueKind.calloutTargetOutOfView,
            category: SlideQualityCategory.callout,
            severity: MarkdownValidationSeverity.warning,
            args: {'ref': '(${callout.reference})'},
          ),
        );
        reported.add(callout.reference);
        break;
      }
    }
  }
}

/// Herkent een `(A)`-calloutmarkering in slidetekst. Eén hoofdletter tussen
/// haakjes, optioneel gevolgd door een puntkomma of spatie — niet `(AB)` of
/// `(a)`, en niet een haakje dat toevallig in een afkorting staat.
final _reCalloutReference = RegExp(r'\(([A-Z])\)(?:[;,\s]|$)');
