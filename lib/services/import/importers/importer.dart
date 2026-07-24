import '../core/result.dart';
import '../models/source_format.dart';
import '../models/source_deck.dart';
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
  Future<Result<ImportFailure, SourceDeck>> importBytes(
    List<int> bytes, {
    String? path,
    void Function(double progress, String message)? onProgress,
  });
}
