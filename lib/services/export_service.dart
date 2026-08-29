import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show Locale;

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
import '../models/image_callout.dart';
import '../models/privacy_disposition.dart';
import '../models/redaction_manifest.dart';
import 'privacy/privacy_export_policy.dart';
import '../models/settings.dart';
import 'classification_enforcement_policy.dart';
import '../models/slide_quality.dart';
import 'export_bundle.dart';
import 'export_metadata.dart';
import 'html_image_embedder.dart';
import 'image_service.dart';
import 'latex/beamer_slide_builder.dart';
import 'latex/latex_preamble.dart';
import 'quality_export_policy.dart';
import 'marp_html_service.dart';
import 'classification_policy.dart';
import 'odp/deck_odp_export.dart';
import 'pptx/deck_pptx_export.dart';

part 'export_service_raster.dart';

enum ExportFormat { pdf, pptx, odp, html, latex }

extension ExportFormatExtension on ExportFormat {
  String get label {
    switch (this) {
      case ExportFormat.pdf:
        return 'PDF';
      case ExportFormat.pptx:
        return 'PowerPoint (PPTX)';
      case ExportFormat.odp:
        return 'OpenDocument (ODP)';
      case ExportFormat.html:
        return 'HTML (Marp, self-contained)';
      case ExportFormat.latex:
        return 'LaTeX (Beamer)';
    }
  }

  String get extension {
    switch (this) {
      case ExportFormat.pdf:
        return '.pdf';
      case ExportFormat.pptx:
        return '.pptx';
      case ExportFormat.odp:
        return '.odp';
      case ExportFormat.html:
        return '.html';
      case ExportFormat.latex:
        return '.tex';
    }
  }
}

class ExportResult {
  final bool success;
  final String? outputPath;
  final String? error;

  /// Gezet wanneer het classificatiebeleid de export tegenhield.
  ///
  /// Een beslissing en geen zin: de dienst kent de taal van de gebruiker niet,
  /// en een weigering die het TLP-niveau in de zin noemt heeft geen letterlijke
  /// vorm om op te vertalen (#576). De schil maakt er een zin van met
  /// `exportBlockMessage`.
  final ExportDecision? classificationDecision;

  const ExportResult._({
    required this.success,
    this.outputPath,
    this.error,
    this.classificationDecision,
  });

  factory ExportResult.ok(String path) =>
      ExportResult._(success: true, outputPath: path);
  factory ExportResult.fail(String error) =>
      ExportResult._(success: false, error: error);
  factory ExportResult.blockedByClassification(ExportDecision decision) =>
      ExportResult._(success: false, classificationDecision: decision);
}

/// Builds PDF and PPTX files from pre-rendered slide images (WYSIWYG export).
/// Slides are expected to be 16:9 PNG bytes (see [SlideRasterizer]).
class ExportService {
  /// Renders the self-contained Marp HTML export. Injectable for testing.
  final MarpHtmlService _html;

  ExportService({MarpHtmlService? htmlService})
    : _html = htmlService ?? MarpHtmlService();

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
  ///
  /// ── Waarom [audience] één bundel is en geen losse strings ──
  ///
  /// De HTML-markdown en de PPTX-sprekersnotities komen allebei uit [audience].
  /// Dat waren eerder een `String? markdown` en een `List<String>? notes`, en
  /// dáár verdunde de projectiegrens: de rasterizer en het presentatievenster
  /// eisen al een `AudienceDeck`, maar hier kon een aanroeper ongeredigeerde
  /// tekst binnendragen zonder dat het typesysteem hem tegenhield. De huidige
  /// aanroepers deden het goed — het risico was menselijk en toekomstig, precies
  /// het faalpad dat deze codebase elders juist met een compileerfout afvangt.
  ///
  /// Een [ExportBundle] is niet te maken zonder een `AudienceDeck`, en die is
  /// alleen door `PrivacyProjection` te maken. Er reist dus geen bron meer langs
  /// deze poort, en `tool/check_conventions.dart` (`audienceBoundary`) houdt dat
  /// zo: de build faalt zodra hier weer een rauw `Deck` of `List<Slide>` in kan.
  Future<ExportResult> export(
    String deckPath,
    ExportFormat format,
    List<Uint8List> images, {
    bool compress = false,
    String? outputDirectory,

    ExportBundle? audience,
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
    String interfaceLanguageCode = 'nl', // WCAG 3.1.1 fallback (#1249)
    /// Of de verdiepingsslides in deze uitvoer zitten. Alleen de beknopte
    /// versie krijgt een achtervoegsel: de volledige uitvoer heet zoals hij
    /// altijd al heette.
    bool includeDetail = true,
  }) async {
    final refusal = _gateOrRefuse(
      tlp: tlp,
      enforcementPolicy: enforcementPolicy,
      privacyPolicy: privacyPolicy,
      privacySummary: privacySummary,
      privacyAcknowledged: privacyAcknowledged,
      qualityResult: qualityResult,
      qualityPolicy: qualityPolicy,
      qualityAcknowledged: qualityAcknowledged,
    );
    if (refusal != null) return refusal;
    final markdown = audience?.markdown;
    if (format == ExportFormat.html) {
      if (markdown == null || markdown.trim().isEmpty) {
        return ExportResult.fail('Geen inhoud om te exporteren.');
      }
    } else if (format == ExportFormat.latex) {
      if (audience == null || audience.audience.slides.isEmpty) {
        return ExportResult.fail('Geen inhoud om te exporteren.');
      }
    } else if (images.isEmpty) {
      return ExportResult.fail('Geen slides om te exporteren.');
    }
    final fallbackTitle = p.basenameWithoutExtension(deckPath);
    final given =
        metadata ?? ExportDocumentMetadata(title: fallbackTitle, tlp: tlp);
    // De AI-markering wordt hier gételd, niet aangenomen. `metadata` is
    // optioneel en door de aanroeper samen te stellen; zou de melding daaruit
    // moeten komen, dan is "vergeten door te geven" genoeg om ongecontroleerde
    // AI-tekst zwijgend de deur uit te laten gaan. Het geprojecteerde deck
    // weet het zelf, en dit is de ene poort waar elk formaat langskomt.
    final docMeta = audience == null
        ? given
        : given.withAiMarkingFrom(audience.audience);
    final compactSuffix = compress && format == ExportFormat.pdf
        ? '-compact'
        : '';
    final dir = (outputDirectory != null && outputDirectory.isNotEmpty)
        ? outputDirectory
        : p.dirname(deckPath);
    final prefix = '${natoDtg(DateTime.now())} ';
    // `docMeta.fileSuffix` is leeg zodra de AI-tekst is nagekeken, dus een
    // afgerond rapport heet zoals het altijd heette. Alleen een export mét
    // ongecontroleerde AI-tekst draagt het concept-achtervoegsel — daar is de
    // naam de enige plek die de ontvanger ziet zónder het bestand te openen.
    final fileName =
        '$prefix${p.basenameWithoutExtension(deckPath)}'
        '${privacyProfile.fileSuffix}${includeDetail ? '' : '-beknopt'}'
        '${docMeta.fileSuffix}$compactSuffix${format.extension}';
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
          bytes = await _buildPptx(
            images,
            metadata: docMeta,
            fallbackTitle: fallbackTitle,
            audience: audience,
          );
        case ExportFormat.odp:
          bytes = await _buildOdp(
            images,
            metadata: docMeta,
            fallbackTitle: fallbackTitle,
            audience: audience,
          );
        case ExportFormat.html:
          bytes = await _buildHtml(
            markdown!,
            deckPath: deckPath,
            themeProfile: themeProfile,
            cockpitColorScheme: cockpitColorScheme,
            metadata: docMeta,
            fallbackTitle: fallbackTitle,
            interfaceLanguageCode: interfaceLanguageCode,
          );
        case ExportFormat.latex:
          bytes = utf8.encode(_buildLatex(audience!, metadata: docMeta));
      }
      if (kIsWeb) {
        // Web: geen bestandssysteem — file_picker maakt van de bytes een
        // browser-download (Blob + anker). De bestandsnaam is het resultaat.
        await FilePicker.saveFile(fileName: fileName, bytes: bytes);
        // Het redactiemanifest hoort ook op web mee. Zonder dit kreeg de auteur
        // wél het geredigeerde rapport gedownload maar niet de commitments (die
        // met het rapport meereizen) of de verificatiesleutels (die de auteur
        // houdt) — dan is geen enkele redactie meer na te trekken.
        for (final f in _redactionManifestFiles(fileName, redactionManifest)) {
          await FilePicker.saveFile(fileName: f.name, bytes: f.bytes);
        }
        return ExportResult.ok(fileName);
      }
      await Directory(dir).create(recursive: true);
      // Atomair: exporteren over een bestaand bestand mag dat bij een crash
      // niet half-geschreven achterlaten.
      // Het manifest eerst. Het is klein en het exportbestand is de grote
      // schrijfbeurt, dus loopt de schijf vol, dan gebeurt dat op de tweede —
      // en dan is er geen export om een manifest bij te missen. Andersom bleef
      // er een compleet geredigeerd rapport liggen zónder manifest, terwijl de
      // gebruiker las dat de export was mislukt: hij weet dan niet dat het
      // bestand er staat, en de ontvanger kan geen enkele redactie natrekken.
      await _writeRedactionManifest(outputPath, redactionManifest);
      await writeBytesAtomic(File(outputPath), bytes);
      return ExportResult.ok(outputPath);
    } catch (e) {
      // Technische details naar het log; de gebruiker krijgt een korte,
      // vertaalde melding met handelingsperspectief i.p.v. een rauwe exception.
      logError('ExportService.export: export failed', e);
      const l10n = AppLocalizations(Locale('nl'));
      return ExportResult.fail(userFacingError(l10n, e));
    }
  }

  /// Bouwt het HTML-document en levert het als bytes.
  ///
  /// Bouwt een LaTeX Beamer-document uit het geprojecteerde deck. De body
  /// komt uit [buildBeamerBody], de preamble uit [beamerPreamble]. Afbeeldingen
  /// worden op relatief pad gereferentieerd — LaTeX kent geen data-URI-
  /// inlining (ponytail: ceiling is single-file; upgrade path is een zip-bundel
  /// met .tex + images).
  String _buildLatex(
    ExportBundle audience, {
    required ExportDocumentMetadata metadata,
  }) {
    final body = buildBeamerBody(audience.audience.deck);
    return '${beamerPreamble(metadata)}\n$body\n$beamerPostamble\n';
  }

  /// De insluitfunctie voor afbeeldingen wordt hier gemaakt en niet in de
  /// bouwer: de projectmap is de map van het deck, en die begrenzing hoort bij
  /// de laag die het bestandssysteem kent — zodat een deck van een derde geen
  /// bestanden buiten zijn eigen map de export in kan trekken.
  Future<Uint8List> _buildHtml(
    String markdown, {
    required String deckPath,
    required ThemeProfile? themeProfile,
    required CockpitColorScheme cockpitColorScheme,
    required ExportDocumentMetadata metadata,
    required String fallbackTitle,
    required String interfaceLanguageCode,
  }) async {
    // Een bewaard deck heeft een projectmap: de map van het `.md`, en daar
    // blijft het lezen binnen. Een deck dat nog nooit is opgeslagen heeft er
    // geen — dan is [deckPath] alleen een voorgestelde bestandsnaam, en zou
    // `dirname` de werkmap van het proces opleveren. `null` betekent hier
    // precies wat de resolver ervan maakt: absolute paden uit de lopende
    // bewerksessie mogen (dat zijn de wachtruimte-kopieën van net ingevoegd
    // beeld), relatieve niet. Zelfde regel als de preview.
    final projectPath = p.isAbsolute(deckPath) ? p.dirname(deckPath) : null;
    // WCAG 2.1 SC 3.1.1 (#1249): lang = de inhoudstaal (metadata.language),
    // interfacetaal als fallback. Chrome valt op de interfacetaal voor een
    // onbekende taal (lang blijft juist).
    final dl = metadata.language.trim();
    final htmlLang = dl.isNotEmpty ? dl : interfaceLanguageCode;
    final chromeLanguageCode = AppLocalizations.languageNames.containsKey(dl)
        ? dl
        : interfaceLanguageCode;
    // ponytail: chrome leest AppLocalizations.languageCode (bibliotheek-brede
    // static). Tijdelijk op de exporttaal, in finally terug. Plafond: globaal
    // muteerbare status; modale export zonder voortgangscallbacks, dus veilig.
    final previousLanguageCode = AppLocalizations.activeLanguageCode;
    AppLocalizations.setActiveLanguageCode(chromeLanguageCode);
    try {
      final html = await _html.build(
        markdown,
        theme: themeProfile,
        cockpitColorScheme: cockpitColorScheme,
        metadata: metadata,
        fallbackTitle: fallbackTitle,
        htmlLang: htmlLang,
        embedImage: (source) => _embedImage(source, projectPath),
      );
      return Uint8List.fromList(utf8.encode(html));
    } finally {
      AppLocalizations.setActiveLanguageCode(previousLanguageCode);
    }
  }

  /// Leest de afbeelding op [source] en maakt er een `data:`-URI van, zodat de
  /// HTML-export werkelijk één bestand is.
  ///
  /// De begrenzing zit hier, niet in de HTML-bouwer: [ImageService] lost het pad
  /// op binnen [projectPath] en weigert alles daarbuiten, precies zoals de
  /// preview, de presenter en de andere exports dat doen. Zonder die grens zou
  /// een deck van een derde met `![](/etc/passwd)` een willekeurig bestand de
  /// export in trekken — en die export gaat naar buiten.
  ///
  /// Het hercoderen kost honderden milliseconden per afbeelding en draait
  /// daarom in een isolate; een export van een deck met twintig foto's zou de
  /// interface anders seconden laten staan.
  Future<String?> _embedImage(String source, String? projectPath) async {
    final bytes = await ImageService().readSlideImageBytes(
      source,
      projectPath: projectPath,
    );
    if (bytes == null) return null;
    final encoded = await _offload(() => encodeForHtmlEmbed(bytes, source));
    return encoded == null ? null : htmlImageDataUri(encoded);
  }

  /// Zware bouwstappen draaien op desktop in een eigen isolate zodat de UI
  /// responsief blijft; op web bestaan isolates niet en draait dezelfde stap
  /// op de main thread — de export duurt daar merkbaar, maar werkt.
  /// De drie fail-closed poorten waar élke export doorheen moet: classificatie,
  /// privacy en kwaliteit. Geeft de weigering terug, of `null` als er niets in
  /// de weg staat.
  ///
  /// Ze staan hier bij elkaar en niet in de UI-laag, want dit is het enige
  /// chokepoint waar alle formaten (PDF/PPTX/HTML) langskomen — een poort die
  /// alleen in een dialoog leeft, is er geen. Bij een weigering wordt er niets
  /// gebouwd en niets weggeschreven.
  ExportResult? _gateOrRefuse({
    required TlpLevel tlp,
    required ClassificationEnforcementPolicy enforcementPolicy,
    required PrivacyExportPolicy privacyPolicy,
    required PrivacyExportSummary privacySummary,
    required bool privacyAcknowledged,
    required SlideQualityResult? qualityResult,
    required QualityExportPolicy qualityPolicy,
    required bool qualityAcknowledged,
  }) {
    final decision = enforcementPolicy.evaluate(tlp);
    if (!decision.allowed) {
      // Vastleggen dát de poort dichtging. Dit is de enige plek waar te zien is
      // dat een uitgave op de classificatie is tegengehouden. Alleen het
      // niveau — de reden is een gebruikersmelding en de deckinhoud hoort niet
      // in een log.
      logWarning(
        'ExportService: export geweigerd op classificatie (TLP: ${tlp.name})',
      );
      // De dienst kent de taal van de gebruiker niet; de schil vertaalt
      // deze beslissing (zie l10n/export_block_localization.dart, #576).
      return ExportResult.blockedByClassification(decision);
    }

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
    return null;
  }

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
  ///   * `<naam>-redactions.json` — commitments zonder salts. Dit reist mee met
  ///     het geredigeerde rapport. Een ontvanger ziet hoeveel er is weggehaald,
  ///     welke regel het vond en op welke slide, en kan een specifieke redactie
  ///     bij naam betwisten ("ik betwist a3f1"). Terugrekenen kan hij niet.
  ///
  ///   * `<naam>-redaction-keys.json` — mét salts. Dit levert je NIET mee.
  ///     Hiermee kan de houder van de bron elke redactie natrekken, of er één
  ///     selectief openen zonder de rest prijs te geven.
  ///
  /// Zonder salt is een SHA-256 van een geredigeerd BSN in seconden terug te
  /// rekenen — 10⁹ kandidaten. De scheiding tussen deze twee bestanden ís de
  /// beveiliging; daarom staat het verschil in de bestandsnaam.
  ///
  /// En sinds kort óók binnenin, in het `notice`-veld. Dat is geen dubbelop: de
  /// naam verdwijnt zodra iemand het bestand hernoemt of in een zip stopt, en
  /// dan is het enige wat de houder nog kan lezen de inhoud. De namen zijn
  /// daarnaast Engels geworden — ze heetten `-redacties.json` en
  /// `-redacties-verificatiesleutels.json`, twee Nederlandse namen die op
  /// elkaar lijken, in een app met 32 talen en ontvangers in evenzovele.
  /// [ExportDialog] noemt beide bestanden nu ook bij naam vóór de export, want
  /// tot dan schreef OciDeck de sleutel naast de deur zonder het te zeggen.
  static Future<void> _writeRedactionManifest(
    String outputPath,
    RedactionManifest manifest,
  ) async {
    for (final f in _redactionManifestFiles(outputPath, manifest)) {
      await writeBytesAtomic(
        File(p.join(p.dirname(outputPath), f.name)),
        f.bytes,
      );
    }
  }

  /// De manifestbestanden voor een geredigeerde export, als (naam, bytes). Eén
  /// bron voor beide uitgangen: het schijfpad ([_writeRedactionManifest]) en de
  /// browser-download op web. [reference] is het exportpad of de bestandsnaam;
  /// alleen de basisnaam (zonder extensie) wordt gebruikt.
  static List<({String name, Uint8List bytes})> _redactionManifestFiles(
    String reference,
    RedactionManifest manifest,
  ) {
    if (manifest.isEmpty) return const [];
    final base = p.basenameWithoutExtension(reference);
    Uint8List enc(String s) => Uint8List.fromList(utf8.encode(s));
    return [
      (
        name: '$base$kRedactionManifestSuffix',
        bytes: enc(manifest.withoutSalts.toPrettyJson()),
      ),
      if (manifest.carriesSalts)
        (
          name: '$base$kRedactionKeysSuffix',
          bytes: enc(manifest.toPrettyJson()),
        ),
    ];
  }
}
