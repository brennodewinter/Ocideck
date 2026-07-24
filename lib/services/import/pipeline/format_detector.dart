import 'package:archive/archive.dart';

import '../models/source_format.dart';
import '../utils/archive_utils.dart';

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
class FormatValidation {
  const FormatValidation(this.format, {this.isValid = true, this.error});

  final SourceFormat format;
  final bool isValid;
  final String? error;
}

/// Validates already-read [bytes]: they must form a readable ZIP archive and
/// contain the marker entries for one of the supported formats.
FormatValidation validateFormatFromBytes(
  List<int> bytes, {
  String basename = '',
}) {
  if (bytes.length < 4) {
    return const FormatValidation(
      SourceFormat.unknown,
      isValid: false,
      error: 'Bestand is te klein om een presentatie te zijn.',
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
    );
  }

  try {
    final archive = safeDecodeZip(bytes);
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
  } on Exception {
    return FormatValidation(
      _byExtension(basename),
      isValid: false,
      error: 'Beschadigd zip-archief: het bestand kan niet worden uitgepakt.',
    );
  }

  final fallback = _byExtension(basename);
  if (fallback != SourceFormat.unknown) {
    return FormatValidation(
      fallback,
      isValid: false,
      error: 'Beschadigd of ongeldig ${fallback.name}-bestand.',
    );
  }

  return const FormatValidation(
    SourceFormat.unknown,
    isValid: false,
    error: 'Onbekend of ongeldig zip-archief.',
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
