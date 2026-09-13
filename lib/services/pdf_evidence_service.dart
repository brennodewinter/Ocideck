import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../utils/project_path.dart';
import '../utils/safe_filename.dart';
import 'image_service.dart';
import 'web_asset_store.dart';

const int maxPdfEvidenceBytes = 64 * 1024 * 1024;

bool isSupportedPdfEvidence(Uint8List bytes) =>
    bytes.length >= 5 &&
    bytes.length <= maxPdfEvidenceBytes &&
    bytes[0] == 0x25 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x44 &&
    bytes[3] == 0x46 &&
    bytes[4] == 0x2d;

enum PdfEvidenceImportFailure { cancelled, invalid, writeFailed }

typedef PdfEvidenceImportResult = ({
  String? path,
  PdfEvidenceImportFailure? failure,
});

typedef PdfEvidenceAttachment = ({String label, String path});

/// Imports and reads PDF evidence without teaching the slide model a PDF type.
///
/// The deck stores a standard Markdown link on a regular free-Markdown evidence
/// slide. That keeps the source useful in every Markdown/Marp tool while the
/// original PDF travels beside it under `evidence/`.
class PdfEvidenceService {
  const PdfEvidenceService();

  Future<PdfEvidenceImportResult> pickAndImport({
    required ImageService assetService,
    required String? projectPath,
  }) async {
    final picked = await FilePicker.pickFile(type: FileType.any);
    final sourcePath = picked?.path;
    if (sourcePath == null) {
      return (path: null, failure: PdfEvidenceImportFailure.cancelled);
    }
    final bytes = await _readBounded(File(sourcePath));
    if (bytes == null || !isSupportedPdfEvidence(bytes)) {
      return (path: null, failure: PdfEvidenceImportFailure.invalid);
    }
    try {
      final imported = await assetService.importIntoDeck(
        sourcePath,
        projectPath: projectPath,
        subdir: 'evidence',
      );
      // ImageService deliberately falls back to the original path when a copy
      // fails. That is useful for images with a visible warning, but a PDF
      // evidence link must never silently retain an absolute/outside path.
      if (projectPath != null &&
          (p.isAbsolute(imported) ||
              resolveContainedRealPath(imported, projectPath) == null)) {
        return (path: null, failure: PdfEvidenceImportFailure.writeFailed);
      }
      return (path: imported, failure: null);
    } on FileSystemException {
      return (path: null, failure: PdfEvidenceImportFailure.writeFailed);
    }
  }

  Future<Uint8List?> read(String path, {required String? projectPath}) async {
    if (WebAssetStore.isMemPath(path)) {
      final bytes = WebAssetStore.bytesFor(path);
      return bytes != null && isSupportedPdfEvidence(bytes) ? bytes : null;
    }
    final resolved = resolveContainedRealPath(path, projectPath);
    if (resolved == null) return null;
    final bytes = await _readBounded(File(resolved));
    return bytes != null && isSupportedPdfEvidence(bytes) ? bytes : null;
  }

  static String markdownFor(String path, {String? label}) {
    final safeLabel = sanitizeFilename(
      label ?? p.basenameWithoutExtension(path),
      fallback: 'PDF',
    );
    final target = path.split('/').map(Uri.encodeComponent).join('/');
    return '[$safeLabel](<$target>)';
  }

  static PdfEvidenceAttachment? attachmentFromMarkdown(String markdown) {
    final match = RegExp(
      r'^\s*\[([^\]]+)\]\((?:<([^>]+)>|([^\s)]+))\)\s*$',
      caseSensitive: false,
    ).firstMatch(markdown);
    if (match == null) return null;
    late final String target;
    try {
      // markdownFor encodes each path segment, so '/' remains structural while
      // reserved characters such as the ':' in an internal mem: path decode.
      target = Uri.decodeComponent(match.group(2) ?? match.group(3)!);
    } on Object {
      return null;
    }
    final uri = Uri.tryParse(target);
    if (uri != null && uri.hasScheme && uri.scheme != 'mem') return null;
    if (!(uri?.scheme == 'mem') &&
        p.extension(target).toLowerCase() != '.pdf') {
      return null;
    }
    return (label: match.group(1)!, path: target);
  }

  Future<Uint8List?> _readBounded(File file) async {
    try {
      final size = await file.length();
      if (size < 5 || size > maxPdfEvidenceBytes) return null;
      return Uint8List.fromList(await file.readAsBytes());
    } on FileSystemException {
      return null;
    }
  }
}
