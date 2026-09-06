import 'package:archive/archive.dart';

import '../importers/import_failure.dart';
import '../models/source_format.dart';
import '../utils/archive_utils.dart';
import '../utils/import_budget.dart';

/// Detect a presentation's format from its file. The **content decides**: the
/// bytes must be a ZIP archive (checked first by the `PK\x03\x04` local-file-
/// header magic), and a valid archive is then classified by a format-specific
/// marker entry inside it (see [validateFormatFromArchive]). The filename
/// extension is only a last-resort label — used to phrase a better error when
/// the content is unreadable (not a ZIP, over budget, corrupt, or a ZIP without
/// any known marker) — and never overrides a successful content match. So a file
/// whose extension lies (a `.pptx` that is really Impress, or the reverse) is
/// classified by what it actually is.
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
    // Geen ZIP — misschien een los eLearning-bestand (QTI XML, xAPI JSON,
    // AICC .crs). Probeer herkenning op bestandsnaam en content (#1992).
    final nonZip = _detectNonZipFormat(bytes, basename: basename);
    if (nonZip != null) return nonZip;
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

  // ── eLearning-formaten (#1992–#1997) ──
  // SCORM / IMS Content Packaging: imsmanifest.xml aan de root (#1993).
  if (names.contains('imsmanifest.xml')) {
    return const FormatValidation(SourceFormat.scorm);
  }
  // QTI: imsqti.xml of een XML met QTI-namespace (#1994).
  if (names.contains('imsqti.xml') ||
      names.any(
        (n) => n.endsWith('.xml') && _looksLikeQti(_archiveContent(archive, n)),
      )) {
    return const FormatValidation(SourceFormat.qti);
  }
  // cmi5: cmi5.xml (#1995).
  if (names.contains('cmi5.xml')) {
    return const FormatValidation(SourceFormat.xapiCmi5);
  }
  // OLX: course.xml met OLX-namespace (#1997).
  if (names.contains('course.xml') &&
      _looksLikeOlx(_archiveContent(archive, 'course.xml'))) {
    return const FormatValidation(SourceFormat.olx);
  }
  // AICC: .crs/.au/.cst/.des bestanden in de ZIP (#1996).
  if (names.any((n) {
    final l = n.toLowerCase();
    return l.endsWith('.crs') ||
        l.endsWith('.au') ||
        l.endsWith('.cst') ||
        l.endsWith('.des');
  })) {
    return const FormatValidation(SourceFormat.aicc);
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
  // eLearning-formaten op extensie (fallback binnen ZIP).
  if (lower.endsWith('.crs') ||
      lower.endsWith('.au') ||
      lower.endsWith('.cst') ||
      lower.endsWith('.des')) {
    return SourceFormat.aicc;
  }
  return SourceFormat.unknown;
}

ArchiveFile? _archiveFile(Archive archive, String name) {
  for (final f in archive) {
    if (f.name == name) return f;
  }
  return null;
}

/// Lees de eerste ~4 KB van een archiefbestand als string, voor namespace-
/// detectie. Houdt het klein: we zoeken alleen naar een marker in de header.
String _archiveContent(Archive archive, String name) {
  final file = _archiveFile(archive, name);
  if (file == null) return '';
  final content = file.content as List<int>;
  final slice = content.length > 4096 ? content.sublist(0, 4096) : content;
  return String.fromCharCodes(slice);
}

/// QTI-herkenning: een XML met een QTI-namespace (imsqti_v2 of imsqti_v3).
bool _looksLikeQti(String xml) {
  return xml.contains('imsqti_v2') ||
      xml.contains('imsqti_v3') ||
      xml.contains('http://www.imsglobal.org/xsd/imsqti');
}

/// OLX-herkenning: course.xml met de OLX-namespace.
bool _looksLikeOlx(String xml) {
  return xml.contains('olx') ||
      xml.contains('course.xml') ||
      xml.contains('xmlns="http://open.edx.org');
}

/// Herken losse (niet-ZIP) eLearning-bestanden op content en extensie.
FormatValidation? _detectNonZipFormat(List<int> bytes, {String basename = ''}) {
  final lower = basename.toLowerCase();
  // AICC: .crs, .au, .cst, .des (#1996).
  if (lower.endsWith('.crs') ||
      lower.endsWith('.au') ||
      lower.endsWith('.cst') ||
      lower.endsWith('.des')) {
    return const FormatValidation(SourceFormat.aicc);
  }
  // xAPI: .json met statement/activity/profile markers (#1995).
  if (lower.endsWith('.json')) {
    final head = String.fromCharCodes(
      bytes.length > 4096 ? bytes.sublist(0, 4096) : bytes,
    );
    if (head.contains('"verb"') &&
        (head.contains('"xapi"') || head.contains('"actor"'))) {
      return const FormatValidation(SourceFormat.xapiCmi5);
    }
  }
  // QTI: .xml met QTI-namespace (#1994).
  if (lower.endsWith('.xml')) {
    final head = String.fromCharCodes(
      bytes.length > 4096 ? bytes.sublist(0, 4096) : bytes,
    );
    if (_looksLikeQti(head)) return const FormatValidation(SourceFormat.qti);
    // cmi5: cmi5.xml (#1995).
    if (head.contains('cmi5') || lower.endsWith('cmi5.xml')) {
      return const FormatValidation(SourceFormat.xapiCmi5);
    }
  }
  return null;
}
