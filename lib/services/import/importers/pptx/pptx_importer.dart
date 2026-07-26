import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../core/result.dart';
import '../../models/source_format.dart';
import '../../models/source_deck.dart';
import '../../models/source_slide.dart';
import '../../models/source_theme.dart';
import '../../utils/archive_utils.dart';
import '../../utils/import_budget.dart';
import '../../../../utils/log.dart';
import '../import_failure.dart';
import '../importer.dart';
import 'pptx_context.dart';
import 'pptx_slide.dart';
import 'pptx_theme.dart';

/// Imports a PowerPoint `.pptx` (Open XML) presentation.
///
/// The package is unzipped once; `presentation.xml`'s `sldIdLst` gives the
/// slide order, each `sldId`'s `r:id` is resolved through
/// `presentation.xml.rels` to `ppt/slides/slideN.xml`, and [parseSlide] turns
/// each into a [SourceSlide]. Hidden slides (`show="0"`) are kept and marked
/// `isHidden` so the writer can emit `<!-- skip -->`. The deck-level theme is
/// salvaged from `ppt/theme/theme1.xml` and the title/author from
/// `docProps/core.xml`.
class PptxImporter extends Importer {
  @override
  SourceFormat get format => SourceFormat.pptx;

  @override
  String get displayName => 'PowerPoint (.pptx)';

  @override
  Future<Result<ImportFailure, SourceDeck>> importBytes(
    List<int> bytes, {
    String? path,
    void Function(double progress, String message)? onProgress,
    ImportBudget budget = ImportBudget.standard,
    Archive? preDecoded,
  }) async {
    try {
      final archive = preDecoded ?? safeDecodeZip(bytes, budget: budget);
      final ctx = PptxContext(archive);

      final slideRefs = _orderedSlidePaths(ctx);
      if (slideRefs.isEmpty) {
        return const Err(
          ImportFailure(
            'Geen slides gevonden — is dit een geldig .pptx?',
            reason: ImportFailureReason.noSlides,
            args: {'formaat': 'pptx'},
          ),
        );
      }
      // Begrens vóór de dure per-dia parseerlus: het aantal `sldId`-knopen komt
      // rechtstreeks uit de bron en mag de allocatie niet sturen.
      if (slideRefs.length > budget.maxSlides) {
        throw ImportBudgetException('${budget.maxSlides} dia\'s');
      }

      final sectionStarts = _sectionStartSlideIds(ctx);
      final slides = <SourceSlide>[];
      for (var i = 0; i < slideRefs.length; i++) {
        final entry = slideRefs[i];
        slides.add(
          parseSlide(
            ctx,
            i,
            entry.path,
            isHidden: entry.isHidden,
            isSection: sectionStarts.contains(entry.slideId),
          ),
        );
        onProgress?.call(
          (i + 1) / slideRefs.length,
          'Slide ${i + 1}/${slideRefs.length}',
        );
      }

      return Ok(
        SourceDeck(
          slides: slides,
          title: _coreProperty(ctx, 'title'),
          author: _coreProperty(ctx, 'creator'),
          theme: _deckTheme(ctx),
        ),
      );
    } on ImportBudgetException catch (e) {
      logError(
        'PptxImporter: ${path ?? 'bestand'} overschrijdt het importbudget '
        '(${e.limitLabel})',
        e,
      );
      return Err(
        ImportFailure(
          'De presentatie overschrijdt de importlimiet (${e.limitLabel}).',
          cause: e,
          reason: ImportFailureReason.tooLarge,
          args: {'formaat': 'pptx', 'limiet': e.limitLabel},
        ),
      );
    } on FormatException catch (e) {
      logError(
        'PptxImporter: ${path ?? 'bestand'} is geen geldig zip-archief',
        e,
      );
      return Err(
        ImportFailure(
          'Dit bestand is geen geldig .pptx (beschadigd zip-archief).',
          cause: e,
          reason: ImportFailureReason.corrupt,
          args: const {'formaat': 'pptx'},
        ),
      );
    } on Exception catch (e) {
      logError('PptxImporter failed for ${path ?? 'bestand'}', e);
      return Err(
        ImportFailure(
          'Kon het .pptx niet lezen.',
          cause: e,
          reason: ImportFailureReason.unreadable,
          args: const {'formaat': 'pptx'},
        ),
      );
    }
  }

  List<_SlideRef> _orderedSlidePaths(PptxContext ctx) {
    final pres = ctx.readXml('ppt/presentation.xml');
    if (pres == null) return const [];
    final presRels = ctx.relsFor('ppt/presentation.xml');

    final sldIds = descendantsLocal(pres, 'sldId');
    final refs = <_SlideRef>[];
    for (final sldId in sldIds) {
      final rId = sldId.getAttribute('id', namespaceUri: relsNs);
      if (rId == null) continue;
      final target = ctx.resolveRel(presRels, rId, 'ppt/presentation.xml');
      if (target == null) continue;
      final isHidden = sldId.getAttribute('show') == '0';
      final slideId = int.tryParse(sldId.getAttribute('id') ?? '') ?? -1;
      refs.add(_SlideRef(target, isHidden, slideId));
    }
    return refs;
  }

  /// Slide ids that start a section (PowerPoint `p:sections` ext). These
  /// slides are marked `isSection` so the classifier maps them to an OciDeck
  /// `section` divider.
  Set<int> _sectionStartSlideIds(PptxContext ctx) {
    final pres = ctx.readXml('ppt/presentation.xml');
    if (pres == null) return const {};
    final ids = <int>{};
    for (final section in descendantsLocal(pres, 'section')) {
      final idAttr = section.getAttribute('spid') ?? section.getAttribute('id');
      final id = int.tryParse(idAttr ?? '');
      if (id != null) ids.add(id);
    }
    return ids;
  }

  String _coreProperty(PptxContext ctx, String localName) {
    final doc = ctx.readXml('docProps/core.xml');
    if (doc == null) return '';
    // Core props use the dc: namespace; match by local name.
    for (final el in doc.descendants.whereType<XmlElement>()) {
      if (el.name.local == localName) return el.innerText.trim();
    }
    return '';
  }

  SourceTheme? _deckTheme(PptxContext ctx) {
    // The first theme part referenced by presentation.xml is the deck theme.
    final themeXml = ctx.readPart('ppt/theme/theme1.xml');
    if (themeXml == null) return null;
    return parseTheme(themeXml);
  }
}

class _SlideRef {
  const _SlideRef(this.path, this.isHidden, this.slideId);
  final String path;
  final bool isHidden;
  final int slideId;
}
