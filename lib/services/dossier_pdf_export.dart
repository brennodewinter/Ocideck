import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/document_dossier.dart';
import '../models/markdown_document.dart';
import '../models/privacy_disposition.dart';
import '../models/settings.dart' show AppSettings, ThemeProfile;
import 'classification_enforcement_policy.dart';
import 'classification_policy.dart';
import 'document_dossier_store.dart';
import 'document_export_service.dart';
import 'markdown_service.dart';
import 'pdf/document_pdf_blocks.dart';
import 'pdf/document_pdf_fonts.dart';
import 'pdf/document_pdf_renderer.dart';
import 'pdf/document_pdf_style.dart';
import 'pdf/markdown_to_pdf_blocks.dart';
import 'privacy/privacy_own_identity.dart';
import 'privacy/privacy_export_policy.dart';
import 'privacy/privacy_projection.dart';

class DossierPdfClassificationException implements Exception {
  const DossierPdfClassificationException(this.decision);
  final ExportDecision decision;
}

class DossierPdfPrivacyException implements Exception {
  const DossierPdfPrivacyException(this.decision);
  final PrivacyExportDecision decision;
}

/// Builds one document PDF from the dossier's verified, projected sources.
///
/// The caller writes the returned bytes only after this completes. A changed,
/// missing or unsafe source therefore never produces a partial export. The
/// redacted profile is the safe default; a full export requires an explicit
/// profile choice in the calling UI.
Future<Uint8List> buildDossierPdf(
  DocumentDossier dossier,
  DocumentDossierStore store, {
  required AppSettings settings,
  bool includeInterleaves = true,
  PrivacyExportProfile profile = PrivacyExportProfile.redacted,
  bool privacyAcknowledged = false,
  List<ByteData> fallbackFonts = const [],
}) async {
  final verified = await _verifiedSources(dossier, store);
  final projection = _DossierPdfProjection(settings, profile);

  final dossierTitle = await projection.display(dossier.title);
  final dossierDescription = await projection.display(dossier.description);
  final entryTitles = <String>[
    for (final (entry, _) in verified) await projection.display(entry.title),
  ];

  final blocks = <PdfBlock>[
    PdfHeadingBlock(1, [PdfSpan(dossierTitle)], dossierTitle),
    if (dossierDescription.isNotEmpty)
      PdfParagraphBlock([PdfSpan(dossierDescription)]),
    PdfParagraphBlock([
      PdfSpan('${dossier.entries.length} documenten', bold: true),
    ]),
    const PdfPageBreakBlock(),
    const PdfHeadingBlock(1, [PdfSpan('Inhoud')], 'Inhoud'),
    for (var i = 0; i < verified.length; i++)
      PdfParagraphBlock([
        PdfSpan(
          '${dossier.numberFor(i).toString().padLeft(2, '0')}   ',
          bold: true,
        ),
        PdfSpan(entryTitles[i]),
      ]),
  ];
  final images = <String, Uint8List>{};
  for (var i = 0; i < verified.length; i++) {
    await _appendEntry(
      blocks,
      dossier,
      verified[i].$1,
      verified[i].$2,
      i,
      entryTitles[i],
      projection,
      images,
      includeInterleaves: includeInterleaves,
    );
  }
  projection.checkPrivacy(privacyAcknowledged);
  return buildDocumentPdf(
    blocks,
    style: DocumentPdfStyle.fromTheme(const ThemeProfile()),
    fonts: DocumentPdfFonts.forFamily(
      'Helvetica',
      fallbackFonts: fallbackFonts,
    ),
    verbatimLabel: (kind) => switch (kind) {
      PdfVerbatimKind.math => 'Formule',
      PdfVerbatimKind.mermaid => 'Diagram',
      PdfVerbatimKind.chart => 'Grafiek',
    },
    images: images,
    chrome: const DocumentPdfChrome(showPageNumbers: true),
  );
}

Future<List<(DossierEntry, String)>> _verifiedSources(
  DocumentDossier dossier,
  DocumentDossierStore store,
) async {
  final verified = <(DossierEntry, String)>[];
  for (final entry in dossier.entries) {
    final result = await store.verify(entry);
    final path = await store.resolvedPath(entry);
    if (result.status != DossierIntegrityStatus.matches || path == null) {
      throw FileSystemException(
        'Dossierbron is gewijzigd of niet veilig leesbaar: ${result.status.name}',
        entry.relativePath,
      );
    }
    if (p.extension(path).toLowerCase() != '.md') {
      throw FileSystemException(
        'Alleen Markdown-bronnen zijn ondersteund',
        path,
      );
    }
    verified.add((entry, path));
  }
  return verified;
}

class _DossierPdfProjection {
  _DossierPdfProjection(this.settings, this.profile);

  final AppSettings settings;
  final PrivacyExportProfile profile;
  final summaries = <PrivacyExportSummary>[];
  final projectedMetadata = <String, String>{};

  Future<String> display(String raw) async {
    if (raw.trim().isEmpty) return '';
    if (projectedMetadata[raw] case final String cached) return cached;
    final bundle = await buildDocumentExportBundle(
      raw,
      projectPath: null,
      profile: profile,
      ownIdentity: OwnIdentity.fromLines(settings.privacyOwnIdentity),
      regions: settings.privacyRegions,
      disabledRules: settings.privacyDisabledRules,
      markdownService: MarkdownService(),
    );
    summaries.add(bundle.privacySummary);
    final projected = projectedDocumentBodyForRendering(bundle).trim();
    if (projected.isEmpty) {
      throw const FormatException(
        'Dossiermetadata kon niet veilig worden geprojecteerd',
      );
    }
    return projectedMetadata[raw] = _safe(projected);
  }

  void checkPrivacy(bool acknowledged) {
    final summary = PrivacyExportSummary(
      unresolved: summaries.fold(0, (sum, item) => sum + item.unresolved),
      accepted: summaries.fold(0, (sum, item) => sum + item.accepted),
      shielded: summaries.fold(0, (sum, item) => sum + item.shielded),
      redacted: summaries.fold(0, (sum, item) => sum + item.redacted),
      setAside: summaries.fold(0, (sum, item) => sum + item.setAside),
    );
    final decision = PrivacyExportPolicy(
      gate: settings.privacyExportGate,
    ).evaluate(summary);
    if (!decision.allowed && (decision.hardBlocked || !acknowledged)) {
      throw DossierPdfPrivacyException(decision);
    }
  }
}

Future<void> _appendEntry(
  List<PdfBlock> blocks,
  DocumentDossier dossier,
  DossierEntry entry,
  String path,
  int index,
  String title,
  _DossierPdfProjection projection,
  Map<String, Uint8List> images, {
  required bool includeInterleaves,
}) async {
  final sourceBytes = await File(path).readAsBytes();
  if (sha256.convert(sourceBytes).toString() != entry.sha256) {
    throw FileSystemException('Dossierbron is tijdens export gewijzigd', path);
  }
  final source = MarkdownDocument.parse(utf8.decode(sourceBytes));
  final body = source.body;
  final settings = projection.settings;
  final bundle = await buildDocumentExportBundle(
    body,
    projectPath: p.dirname(path),
    profile: projection.profile,
    ownIdentity: OwnIdentity.fromLines(settings.privacyOwnIdentity),
    regions: settings.privacyRegions,
    disabledRules: settings.privacyDisabledRules,
    markdownService: MarkdownService(),
    tlp: source.tlp,
    fields: source.fields,
  );
  final classificationDecision =
      ClassificationEnforcementPolicy.fromAppSettings(
        settings,
      ).evaluate(bundle.audience.deck.tlp);
  if (!classificationDecision.allowed) {
    throw DossierPdfClassificationException(classificationDecision);
  }
  projection.summaries.add(bundle.privacySummary);
  final sourceBlocks = markdownToPdfBlocks(
    projectedDocumentBodyForRendering(bundle),
  );
  // Projection can remove image paths while preserving projected alt text.
  // Raw paths are used only for locating safe image bytes.
  final imageRefs = _imageSources(markdownToPdfBlocks(body));
  final rebased = await _embedLocalImages(
    sourceBlocks,
    path,
    entry.id,
    imageRefs,
    images,
  );
  blocks.add(const PdfPageBreakBlock());
  if (includeInterleaves) {
    blocks.addAll(await _interleaf(dossier, entry, index, title, projection));
  }
  // A presentation source is deliberately laid out as document text.
  blocks.add(PdfHeadingBlock(1, [PdfSpan(title)], title));
  blocks.addAll(rebased);
}

Future<List<PdfBlock>> _interleaf(
  DocumentDossier dossier,
  DossierEntry entry,
  int index,
  String title,
  _DossierPdfProjection projection,
) async => [
  PdfHeadingBlock(1, [PdfSpan(title)], title),
  PdfParagraphBlock([
    PdfSpan('DOCUMENT ${dossier.numberFor(index)}', bold: true),
  ]),
  if (entry.description.trim().isNotEmpty)
    PdfParagraphBlock([PdfSpan(await projection.display(entry.description))]),
  if (entry.documentDate case final String date when date.trim().isNotEmpty)
    PdfParagraphBlock([
      const PdfSpan('Datum  ', bold: true),
      PdfSpan(await projection.display(date)),
    ]),
  if (entry.author.trim().isNotEmpty)
    PdfParagraphBlock([
      const PdfSpan('Opsteller  ', bold: true),
      PdfSpan(await projection.display(entry.author)),
    ]),
  PdfParagraphBlock([
    const PdfSpan('SHA-256  ', bold: true),
    PdfSpan(entry.sha256, code: true),
  ]),
  const PdfPageBreakBlock(),
];

String _safe(String value) => PrivacyProjection.redactText(value).text;

/// Give each image a dossier-unique key and read only files beside its source.
/// Symlinks and escapes are rejected before their bytes can enter the PDF.
Future<List<PdfBlock>> _embedLocalImages(
  List<PdfBlock> blocks,
  String sourcePath,
  String entryId,
  List<String> imageRefs,
  Map<String, Uint8List> images,
) async {
  final root = p.dirname(sourcePath);
  var next = 0;
  Future<List<PdfBlock>> visit(List<PdfBlock> source) async {
    final output = <PdfBlock>[];
    for (final block in source) {
      switch (block) {
        case PdfImageBlock(:final alt):
          if (next >= imageRefs.length) {
            throw const FormatException(
              'Afbeeldingsverwijzing wijkt af na projectie',
            );
          }
          final source = imageRefs[next];
          final target = Uri.tryParse(source);
          if (source.isEmpty ||
              target == null ||
              target.hasScheme ||
              target.hasQuery ||
              target.hasFragment ||
              p.isAbsolute(source)) {
            throw FileSystemException(
              'Onveilige afbeeldingsverwijzing',
              source,
            );
          }
          final path = p.normalize(p.join(root, Uri.decodeComponent(source)));
          if (!p.isWithin(root, path) ||
              await FileSystemEntity.type(path, followLinks: false) !=
                  FileSystemEntityType.file) {
            throw FileSystemException(
              'Onveilige afbeeldingsverwijzing',
              source,
            );
          }
          if (await File(path).resolveSymbolicLinks() != path) {
            throw FileSystemException(
              'Onveilige afbeeldingsverwijzing',
              source,
            );
          }
          final key = 'dossier-image:$entryId:${next++}';
          images[key] = await File(path).readAsBytes();
          output.add(PdfImageBlock(key, alt: alt));
        case PdfQuoteBlock(:final blocks):
          output.add(PdfQuoteBlock(await visit(blocks)));
        case PdfListBlock(:final items, :final ordered, :final startNumber):
          output.add(
            PdfListBlock(
              [
                for (final item in items)
                  PdfListItem(await visit(item.blocks), checked: item.checked),
              ],
              ordered: ordered,
              startNumber: startNumber,
            ),
          );
        default:
          output.add(block);
      }
    }
    return output;
  }

  final result = await visit(blocks);
  if (next != imageRefs.length) {
    throw const FormatException('Afbeeldingsverwijzing wijkt af na projectie');
  }
  return result;
}

List<String> _imageSources(List<PdfBlock> blocks) {
  final result = <String>[];
  void visit(List<PdfBlock> source) {
    for (final block in source) {
      switch (block) {
        case PdfImageBlock(:final source):
          result.add(source);
        case PdfQuoteBlock(:final blocks):
          visit(blocks);
        case PdfListBlock(:final items):
          for (final item in items) {
            visit(item.blocks);
          }
        default:
          break;
      }
    }
  }

  visit(blocks);
  return result;
}
