import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../l10n/app_localizations.dart';
import '../l10n/slide_quality_localization.dart';
import '../utils/log.dart';
import '../utils/user_facing_error.dart';
import '../utils/atomic_file.dart';
import '../models/deck.dart';
import '../models/privacy_disposition.dart';
import '../models/redaction_manifest.dart';
import 'privacy/privacy_export_policy.dart';
import '../models/settings.dart';
import 'classification_enforcement_policy.dart';
import '../models/slide_quality.dart';
import 'export_metadata.dart';
import 'quality_export_policy.dart';
import 'marp_html_service.dart';

enum ExportFormat { pdf, pptx, html }

extension ExportFormatExtension on ExportFormat {
  String get label {
    switch (this) {
      case ExportFormat.pdf:
        return 'PDF';
      case ExportFormat.pptx:
        return 'PowerPoint (PPTX)';
      case ExportFormat.html:
        return 'HTML (Marp, self-contained)';
    }
  }

  String get extension {
    switch (this) {
      case ExportFormat.pdf:
        return '.pdf';
      case ExportFormat.pptx:
        return '.pptx';
      case ExportFormat.html:
        return '.html';
    }
  }
}

class ExportResult {
  final bool success;
  final String? outputPath;
  final String? error;

  const ExportResult._({required this.success, this.outputPath, this.error});

  factory ExportResult.ok(String path) =>
      ExportResult._(success: true, outputPath: path);
  factory ExportResult.fail(String error) =>
      ExportResult._(success: false, error: error);
}

/// Builds PDF and PPTX files from pre-rendered slide images (WYSIWYG export).
/// Slides are expected to be 16:9 PNG bytes (see [SlideRasterizer]).
class ExportService {
  /// Renders the self-contained Marp HTML export. Injectable for testing.
  final MarpHtmlService _html;

  ExportService({MarpHtmlService? htmlService})
    : _html = htmlService ?? MarpHtmlService();

  // 16:9 widescreen slide size in EMU (English Metric Units): 13.333" x 7.5".
  static const int _slideWidthEmu = 12192000;
  static const int _slideHeightEmu = 6858000;

  /// JPEG quality (0–100) used when a PDF is exported in compressed mode.
  /// Low enough to shrink photo-heavy decks dramatically while keeping slides
  /// legible.
  static const int _compressedJpegQuality = 60;

  /// Slides are downscaled to this width (px) in compressed mode. The compressed
  /// PDF is meant as a screen handout, so 720p is plenty and shrinks the file
  /// further on top of JPEG encoding. Wider slides are never upscaled.
  static const int _compressedMaxWidth = 1280;

  /// Timestamp for [time] in UTC, formatted `YYYYMMDDHHMMSS` —
  /// e.g. `20260603124547`. Used as a filename prefix so exports sort
  /// chronologically and never overwrite each other.
  static String natoDtg(DateTime time) {
    final t = time.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year.toString().padLeft(4, '0')}${two(t.month)}${two(t.day)}'
        '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  /// Write [images] to a file named after [deckPath] in the requested [format].
  ///
  /// The file name is prefixed with a UTC timestamp (see [natoDtg]),
  /// e.g. `20260603124547 deck.pdf`.
  ///
  /// The file is written to [outputDirectory] when given (created if missing);
  /// otherwise it lands next to the source deck (legacy behaviour).
  ///
  /// When [compress] is set (PDF only), each slide is re-encoded as JPEG instead
  /// of being embedded as lossless PNG, and `-compact` is appended to the file
  /// name so it never overwrites a full-quality export.
  Future<ExportResult> export(
    String deckPath,
    ExportFormat format,
    List<Uint8List> images, {
    bool compress = false,
    String? outputDirectory,
    List<String>? notes,
    String? markdown,
    ThemeProfile? themeProfile,
    CockpitColorScheme cockpitColorScheme = CockpitColorScheme.standard,
    TlpLevel tlp = TlpLevel.none,
    ClassificationEnforcementPolicy enforcementPolicy =
        const ClassificationEnforcementPolicy(),
    SlideQualityResult? qualityResult,
    QualityExportPolicy qualityPolicy = const QualityExportPolicy(),
    bool qualityAcknowledged = false,
    ExportDocumentMetadata? metadata,
    RedactionManifest redactionManifest = RedactionManifest.empty,
    PrivacyExportSummary privacySummary = PrivacyExportSummary.empty,
    PrivacyExportPolicy privacyPolicy = const PrivacyExportPolicy(),
    bool privacyAcknowledged = false,
    PrivacyExportProfile privacyProfile = PrivacyExportProfile.full,

    /// Of de verdiepingsslides in deze uitvoer zitten. Alleen de beknopte
    /// versie krijgt een achtervoegsel: de volledige uitvoer heet zoals hij
    /// altijd al heette.
    bool includeDetail = true,
  }) async {
    // Classificatie-gate. Dit is het enige chokepoint waar elk formaat
    // (PDF/PPTX/HTML) doorheen moet, dus de handhaving zit hier en niet in de
    // UI-laag: zo kan geen exportpad de gate omzeilen. Fail-closed — bij een
    // weigering wordt er niets gebouwd of weggeschreven.
    final decision = enforcementPolicy.evaluate(tlp);
    if (!decision.allowed) {
      return ExportResult.fail(decision.reason!);
    }
    // Privacy-gate. Op hetzelfde chokepoint als de classificatie-gate, en om
    // dezelfde reden: geen exportpad mag eromheen. De harde blokkade telt hier
    // ook zonder de UI — een gate die alleen in een dialoog leeft, is er geen.
    final privacyDecision = privacyPolicy.evaluate(privacySummary);
    if (!privacyDecision.allowed &&
        (privacyDecision.hardBlocked || !privacyAcknowledged)) {
      const l10n = AppLocalizations(Locale('nl'));
      return ExportResult.fail(
        privacyDecision.hardBlocked
            ? l10n.d(
                'Export geblokkeerd: er staan persoonsgegevens in dit deck waarvoor nog geen keuze is gemaakt.',
              )
            : l10n.d('Export afgebroken vanwege privacybevindingen.'),
      );
    }

    final quality = qualityResult ?? const SlideQualityResult([]);
    final qualityDecision = qualityPolicy.evaluate(
      quality,
      acknowledged: qualityAcknowledged,
    );
    if (!qualityDecision.allowed) {
      final l10n = AppLocalizations(const Locale('nl'));
      return ExportResult.fail(formatQualityExportReason(l10n, quality));
    }
    if (format == ExportFormat.html) {
      if (markdown == null || markdown.trim().isEmpty) {
        return ExportResult.fail('Geen inhoud om te exporteren.');
      }
    } else if (images.isEmpty) {
      return ExportResult.fail('Geen slides om te exporteren.');
    }
    final fallbackTitle = p.basenameWithoutExtension(deckPath);
    final docMeta =
        metadata ?? ExportDocumentMetadata(title: fallbackTitle, tlp: tlp);
    final compactSuffix = compress && format == ExportFormat.pdf
        ? '-compact'
        : '';
    final dir = (outputDirectory != null && outputDirectory.isNotEmpty)
        ? outputDirectory
        : p.dirname(deckPath);
    final prefix = '${natoDtg(DateTime.now())} ';
    final fileName =
        '$prefix${p.basenameWithoutExtension(deckPath)}'
        '${privacyProfile.fileSuffix}${includeDetail ? '' : '-beknopt'}'
        '$compactSuffix${format.extension}';
    final outputPath = p.join(dir, fileName);
    try {
      final Uint8List bytes;
      switch (format) {
        case ExportFormat.pdf:
          bytes = await _buildPdf(
            images,
            metadata: docMeta,
            fallbackTitle: fallbackTitle,
            compress: compress,
          );
        case ExportFormat.pptx:
          bytes = await _offload(
            () => _buildPptx(
              images,
              metadata: docMeta,
              fallbackTitle: fallbackTitle,
              notes: notes,
            ),
          );
        case ExportFormat.html:
          bytes = Uint8List.fromList(
            utf8.encode(
              await _html.build(
                markdown!,
                theme: themeProfile,
                cockpitColorScheme: cockpitColorScheme,
                metadata: docMeta,
                fallbackTitle: fallbackTitle,
              ),
            ),
          );
      }
      if (kIsWeb) {
        // Web: geen bestandssysteem — file_picker maakt van de bytes een
        // browser-download (Blob + anker). De bestandsnaam is het resultaat.
        await FilePicker.saveFile(fileName: fileName, bytes: bytes);
        return ExportResult.ok(fileName);
      }
      await Directory(dir).create(recursive: true);
      // Atomair: exporteren over een bestaand bestand mag dat bij een crash
      // niet half-geschreven achterlaten.
      await writeBytesAtomic(File(outputPath), bytes);
      await _writeRedactionManifest(outputPath, redactionManifest);
      return ExportResult.ok(outputPath);
    } catch (e) {
      // Technische details naar het log; de gebruiker krijgt een korte,
      // vertaalde melding met handelingsperspectief i.p.v. een rauwe exception.
      logError('ExportService.export: export failed', e);
      const l10n = AppLocalizations(Locale('nl'));
      return ExportResult.fail(userFacingError(l10n, e));
    }
  }

  /// Zware bouwstappen draaien op desktop in een eigen isolate zodat de UI
  /// responsief blijft; op web bestaan isolates niet en draait dezelfde stap
  /// op de main thread — de export duurt daar merkbaar, maar werkt.
  static Future<R> _offload<R>(FutureOr<R> Function() body) {
    if (kIsWeb) return Future.sync(body);
    return Isolate.run(body);
  }

  // ── PDF ───────────────────────────────────────────────────────────────────

  // JPEG-hercompressie en PDF-assemblage zijn CPU-zwaar (honderden ms per
  // slide); in een eigen isolate blijft de UI responsief tijdens export.
  /// Schrijft het redactiemanifest naast een geredigeerde export.
  ///
  /// TWEE bestanden, met opzet, en met namen die het verschil onmiskenbaar maken:
  ///
  ///   * `<naam>-redacties.json` — commitments zonder salts. Dit reist mee met
  ///     het geredigeerde rapport. Een ontvanger ziet hoeveel er is weggehaald,
  ///     welke regel het vond en op welke slide, en kan een specifieke redactie
  ///     bij naam betwisten ("ik betwist a3f1"). Terugrekenen kan hij niet.
  ///
  ///   * `<naam>-redacties-verificatiesleutels.json` — mét salts. Dit levert je
  ///     NIET mee. Hiermee kan de houder van de bron elke redactie natrekken, of
  ///     er één selectief openen zonder de rest prijs te geven.
  ///
  /// Zonder salt is een SHA-256 van een geredigeerd BSN in seconden terug te
  /// rekenen — 10⁹ kandidaten. De scheiding tussen deze twee bestanden ís de
  /// beveiliging; daarom staat het verschil in de bestandsnaam en niet in een
  /// veldje binnenin.
  static Future<void> _writeRedactionManifest(
    String outputPath,
    RedactionManifest manifest,
  ) async {
    if (manifest.isEmpty) return;
    final base = p.withoutExtension(outputPath);
    await writeStringAtomic(
      File('$base-redacties.json'),
      manifest.withoutSalts.toPrettyJson(),
    );
    if (manifest.carriesSalts) {
      await writeStringAtomic(
        File('$base-redacties-verificatiesleutels.json'),
        manifest.toPrettyJson(),
      );
    }
  }

  static Future<Uint8List> _buildPdf(
    List<Uint8List> images, {
    required ExportDocumentMetadata metadata,
    required String fallbackTitle,
    bool compress = false,
  }) {
    return _offload(() async {
      final doc = pw.Document(
        title: metadata.displayTitle(fallbackTitle),
        author: metadata.documentAuthor,
        subject: metadata.subject(fallbackTitle),
        keywords: metadata.exportKeywords(),
        creator: metadata.creator,
        producer: metadata.producer,
      );
      // Page size in points; only the ratio matters for a full-bleed image.
      const format = PdfPageFormat(1280, 720, marginAll: 0);
      for (final png in images) {
        // MemoryImage auto-detects PNG vs JPEG from the byte header, so a
        // compressed (JPEG) slide embeds just like the lossless one.
        final image = pw.MemoryImage(compress ? _toJpeg(png) : png);
        doc.addPage(
          pw.Page(
            pageFormat: format,
            build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
          ),
        );
      }
      return doc.save();
    });
  }

  /// Downscale a rendered slide PNG to [_compressedMaxWidth] and re-encode it as
  /// JPEG at [_compressedJpegQuality]. Slides are full-bleed (no transparency),
  /// so dropping the alpha channel is safe.
  static Uint8List _toJpeg(Uint8List png) {
    final decoded = img.decodePng(png);
    if (decoded == null) return png; // Unexpected; keep the original bytes.
    final resized = decoded.width > _compressedMaxWidth
        ? img.copyResize(
            decoded,
            width: _compressedMaxWidth,
            interpolation: img.Interpolation.average,
          )
        : decoded;
    return img.encodeJpg(resized, quality: _compressedJpegQuality);
  }

  // ── PPTX (Office Open XML) ─────────────────────────────────────────────────

  static Uint8List _buildPptx(
    List<Uint8List> images, {
    required ExportDocumentMetadata metadata,
    required String fallbackTitle,
    List<String>? notes,
  }) {
    final archive = Archive();
    void addText(String name, String content) {
      final data = utf8Bytes(content);
      archive.add(ArchiveFile(name, data.length, data));
    }

    final slideCount = images.length;
    // Which slides carry speaker notes. When none do, the whole notes machinery
    // (notesMaster + notesSlides) is omitted to keep the file minimal.
    final noteFor = <int, String>{
      for (var i = 0; i < slideCount; i++)
        if (notes != null && i < notes.length && notes[i].trim().isNotEmpty)
          i: notes[i].trim(),
    };
    final hasNotes = noteFor.isNotEmpty;

    addText('[Content_Types].xml', _contentTypes(slideCount, noteFor.keys));
    addText('_rels/.rels', _rootRels());
    addText(
      'docProps/core.xml',
      _coreProps(metadata, fallbackTitle: fallbackTitle),
    );
    addText('docProps/app.xml', _appProps(metadata));
    addText('ppt/presentation.xml', _presentationXml(slideCount, hasNotes));
    addText(
      'ppt/_rels/presentation.xml.rels',
      _presentationRels(slideCount, hasNotes),
    );
    addText('ppt/presProps.xml', _presProps());
    addText('ppt/theme/theme1.xml', _theme1());
    addText('ppt/slideMasters/slideMaster1.xml', _slideMaster());
    addText('ppt/slideMasters/_rels/slideMaster1.xml.rels', _slideMasterRels());
    addText('ppt/slideLayouts/slideLayout1.xml', _slideLayout());
    addText('ppt/slideLayouts/_rels/slideLayout1.xml.rels', _slideLayoutRels());

    if (hasNotes) {
      addText('ppt/notesMasters/notesMaster1.xml', _notesMaster());
      addText(
        'ppt/notesMasters/_rels/notesMaster1.xml.rels',
        _notesMasterRels(),
      );
    }

    for (var i = 0; i < slideCount; i++) {
      final n = i + 1;
      final hasNote = noteFor.containsKey(i);
      addText('ppt/slides/slide$n.xml', _slideXml());
      addText('ppt/slides/_rels/slide$n.xml.rels', _slideRels(n, hasNote));
      if (hasNote) {
        addText(
          'ppt/notesSlides/notesSlide$n.xml',
          _notesSlideXml(noteFor[i]!),
        );
        addText(
          'ppt/notesSlides/_rels/notesSlide$n.xml.rels',
          _notesSlideRels(n),
        );
      }
      final png = images[i];
      archive.add(ArchiveFile('ppt/media/image$n.png', png.length, png));
    }

    return ZipEncoder().encodeBytes(archive);
  }

  /// XML-escape free text destined for an `<a:t>` run.
  static String _xmlEscape(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  /// A notesSlide whose body placeholder carries the speaker notes. Newlines in
  /// [note] become separate paragraphs.
  static String _notesSlideXml(String note) {
    final paras = StringBuffer();
    for (final line in note.split('\n')) {
      paras.write('<a:p><a:r><a:t>${_xmlEscape(line)}</a:t></a:r></a:p>');
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:notes xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld><p:spTree>'
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
        '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
        '<p:sp>'
        '<p:nvSpPr><p:cNvPr id="2" name="Notes Placeholder"/>'
        '<p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>'
        '<p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>'
        '<p:spPr/>'
        '<p:txBody><a:bodyPr/><a:lstStyle/>$paras</p:txBody>'
        '</p:sp>'
        '</p:spTree></p:cSld>'
        '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
        '</p:notes>';
  }

  static String _notesSlideRels(int n) {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" '
        'Target="../slides/slide$n.xml"/>'
        '<Relationship Id="rId2" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster" '
        'Target="../notesMasters/notesMaster1.xml"/>'
        '</Relationships>';
  }

  static String _notesMaster() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:notesMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld><p:spTree>'
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
        '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
        '</p:spTree></p:cSld>'
        '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" '
        'accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" '
        'accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
        '</p:notesMaster>';
  }

  static String _notesMasterRels() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" '
        'Target="../theme/theme1.xml"/>'
        '</Relationships>';
  }

  static List<int> utf8Bytes(String s) => utf8.encode(s);

  static String _contentTypes(int count, Iterable<int> noteIndices) {
    final overrides = StringBuffer();
    for (var i = 1; i <= count; i++) {
      overrides.write(
        '<Override PartName="/ppt/slides/slide$i.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>',
      );
    }
    final notes = noteIndices.toList();
    if (notes.isNotEmpty) {
      overrides.write(
        '<Override PartName="/ppt/notesMasters/notesMaster1.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.presentationml.notesMaster+xml"/>',
      );
      for (final i in notes) {
        overrides.write(
          '<Override PartName="/ppt/notesSlides/notesSlide${i + 1}.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml"/>',
        );
      }
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Default Extension="png" ContentType="image/png"/>'
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
        '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
        '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
        '<Override PartName="/ppt/presProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presProps+xml"/>'
        '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>'
        '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>'
        '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>'
        '$overrides'
        '</Types>';
  }

  static String _rootRels() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
        '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
        '</Relationships>';
  }

  static String _coreProps(
    ExportDocumentMetadata metadata, {
    required String fallbackTitle,
  }) {
    final now = DateTime.now().toUtc();
    String iso(DateTime t) => t.toIso8601String();
    final title = _xmlEscape(metadata.displayTitle(fallbackTitle));
    final subject = _xmlEscape(metadata.subject(fallbackTitle));
    final creator = _xmlEscape(metadata.documentAuthor);
    final keywords = _xmlEscape(metadata.exportKeywords());
    final description = metadata.htmlDescription;
    final descXml = description == null
        ? ''
        : '<dc:description>${_xmlEscape(description)}</dc:description>';
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties '
        'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:dcterms="http://purl.org/dc/terms/" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        '<dc:title>$title</dc:title>'
        '<dc:subject>$subject</dc:subject>'
        '<dc:creator>$creator</dc:creator>'
        '$descXml'
        '<cp:keywords>$keywords</cp:keywords>'
        '<cp:lastModifiedBy>${_xmlEscape(metadata.producer)}</cp:lastModifiedBy>'
        '<dcterms:created xsi:type="dcterms:W3CDTF">${iso(now)}</dcterms:created>'
        '<dcterms:modified xsi:type="dcterms:W3CDTF">${iso(now)}</dcterms:modified>'
        '</cp:coreProperties>';
  }

  static String _appProps(ExportDocumentMetadata metadata) {
    final company = metadata.organization.trim();
    final companyXml = company.isEmpty
        ? ''
        : '<Company>${_xmlEscape(company)}</Company>';
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
        'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
        '<Application>${_xmlEscape(metadata.producer)}</Application>'
        '$companyXml'
        '</Properties>';
  }

  static String _presentationXml(int count, bool hasNotes) {
    final sldIds = StringBuffer();
    for (var i = 0; i < count; i++) {
      // Slide relationship ids start at rId2 (rId1 = master).
      sldIds.write('<p:sldId id="${256 + i}" r:id="rId${i + 2}"/>');
    }
    // The notesMaster relationship is appended after the slides/presProps/theme
    // rels (see _presentationRels): rId(count+4).
    final notesMasterIdLst = hasNotes
        ? '<p:notesMasterIdLst><p:notesMasterId r:id="rId${count + 4}"/></p:notesMasterIdLst>'
        : '';
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>'
        // Schema order: notesMasterIdLst must precede sldIdLst.
        '$notesMasterIdLst'
        '<p:sldIdLst>$sldIds</p:sldIdLst>'
        '<p:sldSz cx="$_slideWidthEmu" cy="$_slideHeightEmu" type="screen16x9"/>'
        '<p:notesSz cx="6858000" cy="9144000"/>'
        '</p:presentation>';
  }

  static String _presentationRels(int count, bool hasNotes) {
    final rels = StringBuffer();
    rels.write(
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" '
      'Target="slideMasters/slideMaster1.xml"/>',
    );
    for (var i = 0; i < count; i++) {
      final n = i + 1;
      rels.write(
        '<Relationship Id="rId${i + 2}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" '
        'Target="slides/slide$n.xml"/>',
      );
    }
    final presPropsId = 'rId${count + 2}';
    final themeId = 'rId${count + 3}';
    rels.write(
      '<Relationship Id="$presPropsId" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/presProps" '
      'Target="presProps.xml"/>',
    );
    rels.write(
      '<Relationship Id="$themeId" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" '
      'Target="theme/theme1.xml"/>',
    );
    if (hasNotes) {
      // Must match the r:id used by notesMasterIdLst in _presentationXml.
      rels.write(
        '<Relationship Id="rId${count + 4}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesMaster" '
        'Target="notesMasters/notesMaster1.xml"/>',
      );
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '$rels'
        '</Relationships>';
  }

  static String _presProps() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:presentationPr xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"/>';
  }

  static String _slideMaster() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld>'
        '<p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg>'
        '${_emptySpTree()}'
        '</p:cSld>'
        '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" '
        'accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" '
        'accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
        '<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>'
        '<p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles>'
        '</p:sldMaster>';
  }

  static String _slideMasterRels() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" '
        'Target="../slideLayouts/slideLayout1.xml"/>'
        '<Relationship Id="rId2" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" '
        'Target="../theme/theme1.xml"/>'
        '</Relationships>';
  }

  static String _slideLayout() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
        'type="blank" preserve="1">'
        '<p:cSld name="Leeg">${_emptySpTree()}</p:cSld>'
        '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
        '</p:sldLayout>';
  }

  static String _slideLayoutRels() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" '
        'Target="../slideMasters/slideMaster1.xml"/>'
        '</Relationships>';
  }

  static String _slideXml() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld><p:spTree>'
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
        '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
        '<p:pic>'
        '<p:nvPicPr><p:cNvPr id="2" name="Slide"/>'
        '<p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>'
        '<p:blipFill><a:blip r:embed="rId2"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>'
        '<p:spPr><a:xfrm><a:off x="0" y="0"/>'
        '<a:ext cx="$_slideWidthEmu" cy="$_slideHeightEmu"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>'
        '</p:pic>'
        '</p:spTree></p:cSld>'
        '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
        '</p:sld>';
  }

  static String _slideRels(int n, bool hasNote) {
    final notesRel = hasNote
        ? '<Relationship Id="rId3" '
              'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide" '
              'Target="../notesSlides/notesSlide$n.xml"/>'
        : '';
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" '
        'Target="../slideLayouts/slideLayout1.xml"/>'
        '<Relationship Id="rId2" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
        'Target="../media/image$n.png"/>'
        '$notesRel'
        '</Relationships>';
  }

  static String _emptySpTree() {
    return '<p:spTree>'
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
        '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/>'
        '<a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
        '</p:spTree>';
  }

  static String _theme1() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Office">'
        '<a:themeElements>'
        '<a:clrScheme name="Office">'
        '<a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>'
        '<a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>'
        '<a:dk2><a:srgbClr val="44546A"/></a:dk2>'
        '<a:lt2><a:srgbClr val="E7E6E6"/></a:lt2>'
        '<a:accent1><a:srgbClr val="4472C4"/></a:accent1>'
        '<a:accent2><a:srgbClr val="ED7D31"/></a:accent2>'
        '<a:accent3><a:srgbClr val="A5A5A5"/></a:accent3>'
        '<a:accent4><a:srgbClr val="FFC000"/></a:accent4>'
        '<a:accent5><a:srgbClr val="5B9BD5"/></a:accent5>'
        '<a:accent6><a:srgbClr val="70AD47"/></a:accent6>'
        '<a:hlink><a:srgbClr val="0563C1"/></a:hlink>'
        '<a:folHlink><a:srgbClr val="954F72"/></a:folHlink>'
        '</a:clrScheme>'
        '<a:fontScheme name="Office">'
        '<a:majorFont><a:latin typeface="Calibri Light"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>'
        '<a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont>'
        '</a:fontScheme>'
        '<a:fmtScheme name="Office">'
        '<a:fillStyleLst>'
        '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
        '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
        '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
        '</a:fillStyleLst>'
        '<a:lnStyleLst>'
        '<a:ln w="6350" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln>'
        '<a:ln w="12700" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln>'
        '<a:ln w="19050" cap="flat" cmpd="sng" algn="ctr"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln>'
        '</a:lnStyleLst>'
        '<a:effectStyleLst>'
        '<a:effectStyle><a:effectLst/></a:effectStyle>'
        '<a:effectStyle><a:effectLst/></a:effectStyle>'
        '<a:effectStyle><a:effectLst/></a:effectStyle>'
        '</a:effectStyleLst>'
        '<a:bgFillStyleLst>'
        '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
        '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
        '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
        '</a:bgFillStyleLst>'
        '</a:fmtScheme>'
        '</a:themeElements>'
        '</a:theme>';
  }
}
