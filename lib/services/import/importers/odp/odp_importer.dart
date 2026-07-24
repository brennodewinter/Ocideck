import 'package:xml/xml.dart';

import '../../core/result.dart';
import '../../models/source_format.dart';
import '../../models/source_deck.dart';
import '../../models/source_slide.dart';
import '../../utils/archive_utils.dart';
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
  }) async {
    try {
      final archive = safeDecodeZip(bytes);
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

      final slides = <SourceSlide>[];
      for (var i = 0; i < pages.length; i++) {
        final page = pages[i];
        slides.add(parsePage(ctx, i, page, isHidden: _isHidden(page)));
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
