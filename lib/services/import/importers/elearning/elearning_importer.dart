import 'package:archive/archive.dart';

import '../../core/result.dart';
import '../../models/body_block.dart';
import '../../models/source_deck.dart';
import '../../models/source_format.dart';
import '../../models/source_slide.dart';
import '../../utils/archive_utils.dart';
import '../../utils/import_budget.dart';
import '../import_failure.dart';
import '../importer.dart';
import 'ims_manifest_reader.dart';
import 'qti_reader.dart';
import 'aicc_reader.dart';
import 'olx_reader.dart';
import 'cmi5_reader.dart';

/// Importer voor eLearning-pakketten (#1992–#1997).
///
/// Herkent SCORM/IMS, QTI, cmi5, AICC en OLX, en mapt ze naar OciDeck-slides.
/// De mapping is bewust beperkt: titels, beschrijvingen en structuur komen over;
/// niet-ondersteunde content (scripts, scoring formulas, LMS-runtime) wordt als
/// placeholder + waarschuwing bewaard, nooit stilzwijgend weggegooid.
///
/// Bronmetadata (source-id's, mapping report, warnings) hoort in de sidecar
/// `<name>.elearning.json` — dit is de import die het deck bouwt.
class ElearningImporter extends Importer {
  ElearningImporter(this._elearningFormat);

  final SourceFormat _elearningFormat;

  @override
  SourceFormat get format => _elearningFormat;

  @override
  String get displayName => switch (_elearningFormat) {
    SourceFormat.scorm => 'SCORM / IMS Manifest',
    SourceFormat.qti => 'QTI 2.x/3.x',
    SourceFormat.xapiCmi5 => 'xAPI / cmi5',
    SourceFormat.aicc => 'AICC',
    SourceFormat.olx => 'OLX (Open edX)',
    _ => 'eLearning',
  };

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
      final reader = _readerFor(_elearningFormat);
      final deck = reader.read(archive, basename: path ?? '');
      onProgress?.call(1.0, 'eLearning: ${archive.length} entries');
      return Ok(deck);
    } on ImportBudgetException {
      return Err(
        ImportFailure(
          'Het eLearning-pakket overschrijdt het importbudget.',
          reason: ImportFailureReason.tooLarge,
        ),
      );
    } catch (e) {
      return Err(
        ImportFailure(
          'Kan het eLearning-pakket niet lezen: $e',
          reason: ImportFailureReason.corrupt,
        ),
      );
    }
  }

  ElearningFormatReader _readerFor(SourceFormat format) => switch (format) {
    SourceFormat.scorm => ImsManifestReader(),
    SourceFormat.qti => QtiReader(),
    SourceFormat.xapiCmi5 => Cmi5Reader(),
    SourceFormat.aicc => AiccReader(),
    SourceFormat.olx => OlxReader(),
    _ => ImsManifestReader(),
  };
}

/// De gemeenschappelijke interface voor formaat-specifieke lezers.
abstract class ElearningFormatReader {
  /// Lees het archief en bouw een [SourceDeck].
  SourceDeck read(Archive archive, {required String basename});
}

/// Een eenvoudige bron-slide voor eLearning-import. Hergebruikt het bestaande
/// [SourceSlide] met een titel en bodyBlocks.
SourceSlide makeElearningSlide(int index, String title, String body) {
  return SourceSlide(
    index: index,
    title: title,
    bodyBlocks: [
      BodyBlock(kind: BodyBlockKind.paragraph, text: body, order: 0),
    ],
  );
}
