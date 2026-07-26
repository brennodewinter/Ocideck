import 'package:archive/archive.dart';

import '../core/result.dart';
import '../models/source_format.dart';
import '../models/source_deck.dart';
import '../utils/import_budget.dart';
import 'import_failure.dart';

/// Parses one source presentation file into a [SourceDeck].
///
/// Implementations are expected to be robust: a malformed part should produce
/// a [ConversionIssue] on the affected slide (and continue) rather than abort
/// the whole import. A failure that prevents any slide from being read is
/// reported as an [Err] with an [ImportFailure].
abstract class Importer {
  /// The source format this importer handles.
  SourceFormat get format;

  /// Human-readable name of the source format, e.g. "PowerPoint (.pptx)".
  String get displayName;

  /// Parse [bytes] into a source deck. [path] is used for logging and error
  /// messages only. [onProgress] receives a 0..1 fraction and a short status
  /// message as the import advances.
  ///
  /// [budget] caps every resource the source file may drive (bytes, entries,
  /// uncompressed size, slides, IWA objects); an overrun ends the import with
  /// [ImportFailureReason.tooLarge] rather than exhausting memory (#874).
  ///
  /// [preDecoded] lets the caller hand in an already-decoded archive so the
  /// same file is not unzipped twice. The import service decodes once (to
  /// validate the format) and passes the archive on; a direct caller that only
  /// has bytes leaves it null and the importer decodes within the [budget].
  Future<Result<ImportFailure, SourceDeck>> importBytes(
    List<int> bytes, {
    String? path,
    void Function(double progress, String message)? onProgress,
    ImportBudget budget = ImportBudget.standard,
    Archive? preDecoded,
  });
}
