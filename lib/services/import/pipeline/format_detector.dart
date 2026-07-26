import 'package:archive/archive.dart';

import '../importers/import_failure.dart';
import '../models/source_format.dart';
import '../utils/archive_utils.dart';
import '../utils/import_budget.dart';

/// Detect a presentation's format from its file: first by extension, then by
/// the ZIP local-file-header magic (`PK\x03\x04`), and finally by peeking
/// inside the archive for a format-specific marker entry.
///
/// The marker entries are stable across versions:
/// - **PPTX** always contains `ppt/presentation.xml`.
/// - **ODP** carries its media type in the uncompressed `mimetype` entry
///   (`application/vnd.oasis.opendocument.presentation`).
/// - **KEY** stores Snappy-protobuf in `Index/*.iwa` (older IWA packages) or
///   an iWork `META-INF/manifest.json`; either marker identifies it.
SourceFormat detectFormatFromBytes(List<int> bytes, {String basename = ''}) {
  return validateFormatFromBytes(bytes, basename: basename).format;
}

/// Result of an integrity-aware format check.
///
/// [error] is a Dutch technical string for the log; [reason] is the stable
/// code the UI turns into a localised message. The two travel together so the
/// service can hand the reason on in the [ImportFailure] it builds (#806).
class FormatValidation {
  const FormatValidation(
    this.format, {
    this.isValid = true,
    this.error,
    this.reason,
  });

  final SourceFormat format;
  final bool isValid;
  final String? error;
  final ImportFailureReason? reason;
}

/// Validates already-read [bytes]: they must form a readable ZIP archive within
/// the [budget] and contain the marker entries for one of the supported
/// formats.
///
/// Decodes the archive to check it, then delegates the marker detection to
/// [validateFormatFromArchive]. The import service does not use this path: it
/// decodes the archive once itself and calls [validateFormatFromArchive]
/// directly, so a real import never decodes the same file twice (#874). This
/// bytes-in entry point stays for callers that only have the raw bytes and only
/// want the format ([detectFormatFromBytes], the format tests).
FormatValidation validateFormatFromBytes(
  List<int> bytes, {
  String basename = '',
  ImportBudget budget = ImportBudget.standard,
}) {
  if (bytes.length < 4) {
    return const FormatValidation(
      SourceFormat.unknown,
      isValid: false,
      error: 'Bestand is te klein om een presentatie te zijn.',
      reason: ImportFailureReason.notAPresentation,
    );
  }
  // ZIP local file header magic.
  if (bytes[0] != 0x50 ||
      bytes[1] != 0x4B ||
      bytes[2] != 0x03 ||
      bytes[3] != 0x04) {
    return FormatValidation(
      _byExtension(basename),
      isValid: false,
      error: 'Dit bestand is geen geldig zip-archief (pptx/odp/key).',
      reason: ImportFailureReason.notAPresentation,
    );
  }

  final Archive archive;
  try {
    archive = safeDecodeZip(bytes, budget: budget);
  } on ImportBudgetException {
    // Te groot voor het budget: voor de kale formaatdetectie telt alleen dát
    // het geen bruikbaar archief oplevert. De service handelt de echte
    // tooLarge-melding af op zijn eigen decodeerpad.
    return FormatValidation(
      _byExtension(basename),
      isValid: false,
      error: 'Bestand overschrijdt het importbudget.',
      reason: ImportFailureReason.tooLarge,
    );
  } on Exception {
    return FormatValidation(
      _byExtension(basename),
      isValid: false,
      error: 'Beschadigd zip-archief: het bestand kan niet worden uitgepakt.',
      reason: ImportFailureReason.corrupt,
    );
  }
  return validateFormatFromArchive(archive, basename: basename);
}

/// Detect the format from an already-decoded [archive] by its marker entries.
///
/// Split from [validateFormatFromBytes] so the import service can decode the
/// archive once and share it between validation and the importer (#874).
FormatValidation validateFormatFromArchive(
  Archive archive, {
  String basename = '',
}) {
  final names = archive.map((f) => f.name).toSet();

  if (names.contains('ppt/presentation.xml')) {
    return const FormatValidation(SourceFormat.pptx);
  }

  final mimetype = _archiveFile(archive, 'mimetype');
  if (mimetype != null &&
      String.fromCharCodes(
        mimetype.content as List<int>,
      ).contains('application/vnd.oasis.opendocument.presentation')) {
    return const FormatValidation(SourceFormat.odp);
  }
  if (names.any((n) => n.startsWith('Index/') && n.endsWith('.iwa')) ||
      names.contains('META-INF/manifest.json')) {
    return const FormatValidation(SourceFormat.key);
  }

  final fallback = _byExtension(basename);
  if (fallback != SourceFormat.unknown) {
    return FormatValidation(
      fallback,
      isValid: false,
      error: 'Beschadigd of ongeldig ${fallback.name}-bestand.',
      reason: ImportFailureReason.corrupt,
    );
  }

  return const FormatValidation(
    SourceFormat.unknown,
    isValid: false,
    error: 'Onbekend of ongeldig zip-archief.',
    reason: ImportFailureReason.notAPresentation,
  );
}

SourceFormat _byExtension(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.pptx')) return SourceFormat.pptx;
  if (lower.endsWith('.odp')) return SourceFormat.odp;
  if (lower.endsWith('.key')) return SourceFormat.key;
  return SourceFormat.unknown;
}

ArchiveFile? _archiveFile(Archive archive, String name) {
  for (final f in archive) {
    if (f.name == name) return f;
  }
  return null;
}
