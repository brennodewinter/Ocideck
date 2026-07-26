import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../core/result.dart';
import '../../models/conversion_issue.dart';
import '../../models/source_format.dart';
import '../../models/source_deck.dart';
import '../../models/source_slide.dart';
import '../../pipeline/parse_guard.dart';
import '../../utils/archive_utils.dart';
import '../../utils/import_budget.dart';
import '../../../../utils/log.dart';
import '../import_failure.dart';
import '../importer.dart';
import 'odp_context.dart';
import 'odp_slide.dart';
import 'odp_theme.dart';

/// Imports a LibreOffice Impress `.odp` (OpenDocument Presentation).
///
/// `content.xml`'s `<office:body>` → `<office:presentation>` holds the
/// `<draw:page>` elements in order; each is parsed by [parsePage]. The deck
/// title/author come from `meta.xml` (`dc:title`/`dc:creator`).
class OdpImporter extends Importer {
  @override
  SourceFormat get format => SourceFormat.odp;

  @override
  String get displayName => 'LibreOffice Impress (.odp)';

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
      final ctx = OdpContext(archive);

      final pages = _pages(ctx);
      if (pages.isEmpty) {
        return const Err(
          ImportFailure(
            'Geen slides gevonden — is dit een geldig .odp?',
            reason: ImportFailureReason.noSlides,
            args: {'formaat': 'odp'},
          ),
        );
      }
      // Begrens vóór de per-dia parseerlus: het aantal `draw:page`-knopen komt
      // uit de bron en mag de allocatie niet sturen.
      if (pages.length > budget.maxSlides) {
        throw ImportBudgetException('${budget.maxSlides} dia\'s');
      }

      final slides = <SourceSlide>[];
      for (var i = 0; i < pages.length; i++) {
        final page = pages[i];
        // Isoleer een onverwachte fout tot déze pagina (#877): één beschadigde
        // dia mag de rest van het deck niet meesleuren. De fallback houdt de
        // volgorde intact en noteert het verlies.
        final parseIssues = <ConversionIssue>[];
        final slide =
            guardParse<SourceSlide>(
              sink: parseIssues,
              slideIndex: i,
              component: IssueComponent.slide,
              feature: 'Dia-inhoud',
              description: 'kon niet worden gelezen en is overgeslagen',
              logOp: 'OdpImporter: dia ${i + 1}',
              body: () => parsePage(ctx, i, page, isHidden: _isHidden(page)),
            ) ??
            SourceSlide(
              index: i,
              isHidden: _isHidden(page),
              parseIssues: parseIssues,
            );
        slides.add(slide);
        onProgress?.call(
          (i + 1) / pages.length,
          'Slide ${i + 1}/${pages.length}',
        );
      }

      return Ok(
        SourceDeck(
          slides: slides,
          title: _meta(ctx, 'title'),
          author: _meta(ctx, 'creator'),
          theme: parseOdpTheme(ctx),
        ),
      );
    } on ImportBudgetException catch (e) {
      logError(
        'OdpImporter: ${path ?? 'bestand'} overschrijdt het importbudget '
        '(${e.limitLabel})',
        e,
      );
      return Err(
        ImportFailure(
          'De presentatie overschrijdt de importlimiet (${e.limitLabel}).',
          cause: e,
          reason: ImportFailureReason.tooLarge,
          args: {'formaat': 'odp', 'limiet': e.limitLabel},
        ),
      );
    } on FormatException catch (e) {
      logError(
        'OdpImporter: ${path ?? 'bestand'} is geen geldig zip-archief',
        e,
      );
      return Err(
        ImportFailure(
          'Dit bestand is geen geldig .odp (beschadigd zip-archief).',
          cause: e,
          reason: ImportFailureReason.corrupt,
          args: const {'formaat': 'odp'},
        ),
      );
    } on Exception catch (e) {
      logError('OdpImporter failed for ${path ?? 'bestand'}', e);
      return Err(
        ImportFailure(
          'Kon het .odp niet lezen.',
          cause: e,
          reason: ImportFailureReason.unreadable,
          args: const {'formaat': 'odp'},
        ),
      );
    }
  }

  List<XmlElement> _pages(OdpContext ctx) {
    final doc = ctx.readXml('content.xml');
    if (doc == null) return const [];
    final presentation = descendantsLocal(doc, 'presentation').firstOrNull;
    if (presentation == null) return const [];
    return descendantsLocal(presentation, 'page').toList();
  }

  bool _isHidden(XmlElement page) {
    for (final a in page.attributes) {
      if (a.name.local == 'visibility' && a.value == 'hidden') return true;
    }
    return false;
  }

  String _meta(OdpContext ctx, String localName) {
    final doc = ctx.readXml('meta.xml');
    if (doc == null) return '';
    for (final el in doc.descendants.whereType<XmlElement>()) {
      if (el.name.local == localName) return el.innerText.trim();
    }
    return '';
  }
}
