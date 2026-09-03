import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import '../../models/deck.dart';
import '../../models/settings.dart';
import '../../models/slide_quality.dart';
import '../../services/classification_enforcement_policy.dart';
import '../../services/export_metadata.dart';
import '../../services/export_service.dart';
import '../../models/privacy_disposition.dart';
import '../../models/redaction_manifest.dart';
import '../../services/export_bundle.dart';
import '../../services/privacy/privacy_export_policy.dart';
import '../../services/quality_export_policy.dart';
import '../../services/slide_rasterizer.dart';
import '../../l10n/app_localizations.dart';
import '../editors/advanced_section.dart';
import '../../l10n/slide_quality_localization.dart';
import '../../utils/log.dart';
import 'slide_quality_details_dialog.dart';
import '../../theme/app_theme.dart';
import '../../l10n/export_block_localization.dart';
import 'export_failure_text.dart';
import 'export_progress_text.dart';

part 'parts/export_dialog_notices.dart';
part 'parts/export_dialog_sections.dart';

/// Exports the deck by rendering the on-screen slide previews to images and
/// packing them into a PDF or PPTX (WYSIWYG — the export matches the preview).
class ExportDialog extends StatefulWidget {
  final String deckPath;

  /// Levert per doelgroepprofiel alles wat de export nodig heeft.
  ///
  /// Een fabriek en geen kant-en-klaar deck, omdat de gebruiker het profiel hier
  /// kiest — en het dialoog de bron níét mag hebben (dat is de projectiegrens).
  /// De functie sluit in de shell om de bron heen; het dialoog kan er alleen
  /// `AudienceDeck`s uit halen.
  final ExportBundle Function(PrivacyExportProfile, {bool includeDetail})
  bundleFor;

  /// Of dit deck überhaupt privacybevindingen heeft. Zo niet, dan heeft de keuze
  /// tussen "volledig" en "geredigeerd" geen betekenis en tonen we hem niet.
  final bool hasPrivacyFindings;

  /// Of er een diepgangkeuze te maken valt: het deck heeft zowel
  /// verdiepingsslides als gewone. Zo niet, dan levert "beknopt" hetzelfde
  /// bestand of een leeg deck, en tonen we de keuze niet.
  final bool hasDepthChoice;

  final CockpitColorScheme cockpitColorScheme;
  final ExportService exportService;

  /// Classificatie-handhaving (plafond, minimum, verplicht classificeren).
  final ClassificationEnforcementPolicy enforcementPolicy;

  /// Slide-kwaliteit van de te exporteren slides.
  final SlideQualityResult qualityResult;

  /// Soft gate — waarschuwing vóór export wanneer ingeschakeld.
  final QualityExportPolicy qualityPolicy;

  /// Folder all exports are written to. Null = next to the source deck.
  final String? exportDirectory;

  final bool showClassificationWatermark;

  /// Waarschuwen of blokkeren bij onafgehandelde bevindingen.
  final PrivacyExportPolicy privacyPolicy;

  /// Of de privacycontrole heeft gedraaid. Staat ze uit, dan is een leeg
  /// scanresultaat geen schone uitslag maar een niet-gestelde vraag, en mag de
  /// groene balk dat niet als geruststelling verkopen.
  final bool privacyChecksEnabled;

  /// Na een geslaagde export aangeroepen met het formaat-label ("PDF",
  /// "PPTX", "HTML") — bijv. om het bij de recente bestanden te noteren.
  final void Function(String formatLabel)? onExported;

  const ExportDialog({
    super.key,
    required this.deckPath,
    required this.bundleFor,
    this.hasPrivacyFindings = false,
    this.hasDepthChoice = false,
    this.cockpitColorScheme = CockpitColorScheme.standard,
    required this.exportService,
    this.enforcementPolicy = const ClassificationEnforcementPolicy(),
    this.qualityResult = const SlideQualityResult([]),
    this.qualityPolicy = const QualityExportPolicy(),
    this.exportDirectory,
    this.showClassificationWatermark = false,
    this.privacyPolicy = const PrivacyExportPolicy(),
    this.privacyChecksEnabled = true,
    this.onExported,
  });

  static Future<void> show(
    BuildContext context, {
    required String deckPath,
    required ExportBundle Function(PrivacyExportProfile, {bool includeDetail})
    bundleFor,
    bool hasPrivacyFindings = false,
    bool hasDepthChoice = false,
    CockpitColorScheme cockpitColorScheme = CockpitColorScheme.standard,
    required ExportService exportService,
    ClassificationEnforcementPolicy enforcementPolicy =
        const ClassificationEnforcementPolicy(),
    SlideQualityResult qualityResult = const SlideQualityResult([]),
    QualityExportPolicy qualityPolicy = const QualityExportPolicy(),
    String? exportDirectory,
    bool showClassificationWatermark = false,
    PrivacyExportPolicy privacyPolicy = const PrivacyExportPolicy(),
    bool privacyChecksEnabled = true,
    void Function(String formatLabel)? onExported,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExportDialog(
        deckPath: deckPath,
        bundleFor: bundleFor,
        hasPrivacyFindings: hasPrivacyFindings,
        hasDepthChoice: hasDepthChoice,
        cockpitColorScheme: cockpitColorScheme,
        exportService: exportService,
        enforcementPolicy: enforcementPolicy,
        qualityResult: qualityResult,
        qualityPolicy: qualityPolicy,
        exportDirectory: exportDirectory,
        showClassificationWatermark: showClassificationWatermark,
        privacyPolicy: privacyPolicy,
        privacyChecksEnabled: privacyChecksEnabled,
        onExported: onExported,
      ),
    );
  }

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  bool _loading = false;
  String? _result;

  /// De stap waar de export nu is; leest de `catch` uit om te zeggen wát er
  /// misging in plaats van alleen dát er iets misging.
  ExportStage _stage = ExportStage.preparing;

  /// Alleen het pad, los van de melding eromheen — dat is wat je wilt plakken.
  String? _outputPath;
  bool _success = false;
  String _phase = '';
  int _done = 0;
  int _total = 0;

  /// Door de gebruiker gevraagd om de lopende export af te breken; het
  /// rasteren stopt dan tussen twee slides en er wordt niets weggeschreven.
  bool _cancelRequested = false;

  /// Image quality for PDF export: false = full-resolution PNG, true = a smaller
  /// downscaled JPEG handout.
  bool _compress = false;

  /// Voor wie deze export bedoeld is. Volledig is de standaard: dat is het
  /// exemplaar waarmee een derde partij de bevindingen kan natrekken.
  PrivacyExportProfile _profile = PrivacyExportProfile.full;

  /// De bundel van het gekozen profiel. Eén keer per keuze gebouwd — het manifest
  /// bevat willekeurige salts, dus hem elke build opnieuw maken zou andere
  /// commitments opleveren dan er straks worden weggeschreven.
  /// Of de verdiepingsslides meegaan. Standaard ja: dan is de uitvoer precies
  /// wat hij zonder deze keuze ook zou zijn geweest.
  bool _includeDetail = true;

  late ExportBundle _bundle = widget.bundleFor(
    _profile,
    includeDetail: _includeDetail,
  );

  void _rebuild() =>
      _bundle = widget.bundleFor(_profile, includeDetail: _includeDetail);

  void _selectProfile(PrivacyExportProfile profile) {
    if (profile == _profile) return;
    setState(() {
      _profile = profile;
      _rebuild();
    });
  }

  void _selectDepth(bool includeDetail) {
    if (includeDetail == _includeDetail) return;
    setState(() {
      _includeDetail = includeDetail;
      _rebuild();
    });
  }

  /// De privacy-gate in beeld.
  ///
  /// Toont wát er in het deck zit én wat de auteur ermee heeft gedaan. Dat laatste
  /// is de kern: de gate straft geen persoonsgegevens af, hij straft *onopgemerkte*
  /// persoonsgegevens af. Een briefing waarin alles bewust geaccepteerd is, gaat er
  /// zonder onderbreking doorheen.
  Future<bool> _confirmPrivacyExport() async {
    final decision = widget.privacyPolicy.evaluate(_bundle.privacySummary);
    if (decision.allowed) return true;

    final l10n = context.l10n;
    final s = decision.summary;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          decision.hardBlocked
              ? l10n.d('Export geblokkeerd')
              : l10n.d('Persoonsgegevens in dit deck'),
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${s.unresolved} ${l10n.d('bevinding(en) zonder keuze.')}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${l10n.d('Verder in dit deck:')} '
                '${s.accepted} ${l10n.d('geaccepteerd')}, '
                '${s.shielded} ${l10n.d('met waarschuwing')}, '
                '${s.redacted} ${l10n.d('geredigeerd')}.',
                style: TextStyle(fontSize: 12, color: AppTheme.slate600),
              ),
              const SizedBox(height: 10),
              Text(
                decision.hardBlocked
                    ? l10n.d(
                        'Maak per slide een keuze (accepteren, waarschuwen of weglaten) voordat je exporteert. Dit is zo ingesteld bij Beveiliging.',
                      )
                    : l10n.d(
                        'Kies per slide wat er moet gebeuren, of exporteer bewust zoals het is.',
                      ),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.t('cancel')),
          ),
          if (!decision.hardBlocked)
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.d('Toch exporteren')),
            ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<bool> _confirmQualityExport() async {
    final decision = widget.qualityPolicy.evaluate(widget.qualityResult);
    if (decision.allowed) return true;
    if (decision.hardBlocked) return false;

    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.d('Kwaliteitsproblemen gevonden')),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  formatSlideQualityCountSummary(l10n, widget.qualityResult),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => showSlideQualityDetailsDialog(
                    ctx,
                    result: widget.qualityResult,
                  ),
                  icon: const Icon(Icons.list_alt_outlined, size: 16),
                  label: Text(l10n.d('Bekijk alle meldingen…')),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.t('cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.d('Toch exporteren')),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  Future<void> _export(ExportFormat format, {bool compress = false}) async {
    final l10n = context.l10n;

    // Alles wat volgt kan gooien — een frame-timeout in de rasterizer, een
    // schrijffout, een fout in de PPTX/PDF-assemblage. Zonder deze omhulling
    // vloog zo'n uitzondering ongevangen naar buiten en werd de spinner nooit
    // uitgezet: het dialoog bleef eeuwig op "…samenstellen…" staan, zonder
    // melding, op 0% CPU. Dat is precies wat een gebruiker als "hij hangt"
    // ervaart. Een fout hoort een fout te tónen, niet te bevriezen.
    _stage = ExportStage.preparing;
    try {
      await _runExport(format, compress: compress, l10n: l10n);
    } catch (e, s) {
      logError(
        'ExportDialog._export: export mislukte met een uitzondering '
        '(stap: ${_stage.name})',
        e,
        s,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _success = false;
        _outputPath = null;
        _result = exportFailureText(l10n, _stage, e);
      });
    }
  }

  Future<void> _runExport(
    ExportFormat format, {
    required bool compress,
    required AppLocalizations l10n,
  }) async {
    final needsRaster =
        format != ExportFormat.html && format != ExportFormat.latex;

    // Show progress immediately so the dialog does not look idle while the
    // quality gate or the first heavy raster pass runs.
    setState(() {
      _loading = true;
      _cancelRequested = false;
      _result = null;
      _phase = l10n.d('Export wordt voorbereid…');
      _done = 0;
      _total = needsRaster ? _bundle.audience.slides.length : 0;
    });
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    if (!await _confirmPrivacyExport()) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!mounted) return;

    if (!await _confirmQualityExport()) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    if (!mounted) return;
    setState(() {
      _phase = needsRaster ? l10n.t('renderingSlides') : l10n.t('buildingHtml');
      _done = 0;
      _total = needsRaster ? _bundle.audience.slides.length : 0;
    });
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    _stage = needsRaster ? ExportStage.rendering : ExportStage.writing;
    final images = needsRaster
        ? await SlideRasterizer.rasterize(
            context: context,
            audience: _bundle.audience,
            cockpitColorScheme: widget.cockpitColorScheme,
            showClassificationWatermark: widget.showClassificationWatermark,
            targetWidth: compress ? 1280 : 1920,
            onProgress: (done, total) {
              if (mounted) setState(() => _done = done);
            },
            onStage: (phase, done, total) {
              if (!mounted) return;
              setState(() {
                _phase = exportProgressText(context.l10n, phase, done, total);
                _done = done;
                _total = total;
              });
            },
            isCancelled: () => _cancelRequested,
          )
        : const <Uint8List>[];

    if (!mounted) return;
    if (_cancelRequested) {
      // Geannuleerd: gooi het (onvolledige) rasterresultaat weg en toon de
      // exportopties opnieuw; er is niets weggeschreven.
      setState(() {
        _loading = false;
        _result = null;
      });
      return;
    }
    _stage = ExportStage.writing;
    setState(() {
      _phase = '${format.label} ${l10n.t('buildingExport')}';
      _done = needsRaster ? _bundle.audience.slides.length : 0;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final r = await widget.exportService.export(
      widget.deckPath,
      format,
      images,
      compress: compress,
      outputDirectory: widget.exportDirectory,
      // De bundel draagt de markdown voor de HTML en de sprekersnotities voor
      // het PPTX-notitiepaneel — beide uit hetzelfde geprojecteerde deck.
      audience: _bundle,
      themeProfile: _bundle.audience.deck.themeProfile,
      cockpitColorScheme: widget.cockpitColorScheme,
      tlp: _bundle.audience.deck.tlp,
      enforcementPolicy: widget.enforcementPolicy,
      qualityResult: widget.qualityResult,
      qualityPolicy: widget.qualityPolicy,
      qualityAcknowledged: true,
      metadata: ExportDocumentMetadata.fromDeck(_bundle.audience),
      redactionManifest: _bundle.manifest,
      privacyProfile: _profile,
      includeDetail: _includeDetail,
      privacySummary: _bundle.privacySummary,
      privacyPolicy: widget.privacyPolicy,
      privacyAcknowledged: true,
      // WCAG 2.1 SC 3.1.1: de HTML-export labelt de pagina met de
      // rapporttaal (metadata.language) en laat zijn chrome in die taal
      // renderen; bij afwezigheid valt hij terug op de interfacetaal. #1249
      interfaceLanguageCode: l10n.languageCode,
    );

    if (!mounted) return;
    if (r.success) widget.onExported?.call(format.label);
    setState(() {
      _loading = false;
      _success = r.success;
      _outputPath = r.success ? r.outputPath : null;
      _result = r.success
          ? '${exportDeliveryLabel(l10n)}\n${r.outputPath}'
          : (r.failure != null
                ? exportFailureReasonText(l10n, r.failure!)
                : r.error);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.t('exportDialogTitle')),
      content: SizedBox(width: 380, child: _content()),
      actions: [
        if (_loading)
          TextButton(
            onPressed: _cancelRequested
                ? null
                : () => setState(() {
                    _cancelRequested = true;
                    _phase = l10n.d('Annuleren…');
                  }),
            child: Text(l10n.t('cancel')),
          ),
        if (_result != null && _success)
          TextButton(
            onPressed: () => setState(() {
              _result = null;
              _outputPath = null;
            }),
            child: Text(l10n.t('exportAgain')),
          ),
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: Text(l10n.t('close')),
        ),
      ],
    );
  }

  Widget _content() {
    final l10n = context.l10n;
    if (_loading) {
      final showDeterminate = _total > 0 && _done > 0;
      final fraction = showDeterminate ? _done / _total : null;
      final counter = _total == 0
          ? ''
          : _done == 0
          ? '${l10n.d('Slide')} 1 ${l10n.t('of')} $_total…'
          : '${l10n.t('slideOf')} $_done ${l10n.t('of')} $_total';
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _phase,
            style: TextStyle(fontSize: 13, color: AppTheme.slate700),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: fraction, minHeight: 6),
          ),
          if (counter.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              counter,
              style: TextStyle(fontSize: 11, color: AppTheme.slate400),
            ),
          ],
        ],
      );
    }

    if (_result != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _success ? Icons.check_circle : Icons.error_outline,
            color: _success ? AppTheme.successFg : AppTheme.dangerFg,
            size: 36,
          ),
          const SizedBox(height: 12),
          // Selecteerbaar, want dit is meestal een pad. Het stond in een gewone
          // Text: je zag waar je bestand terechtkwam en kon er niets mee — niet
          // klikken, niet kopiëren, dus overtypen (#646). Een pad is precies het
          // soort tekst dat je ergens anders nodig hebt.
          SelectableText(
            _result!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: _success ? AppTheme.successFg : AppTheme.dangerFg,
            ),
          ),
          if (_success && _outputPath != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () async {
                // Messenger vóór de await vastpakken: erna is deze context
                // misschien weg, en dan is de melding een crash in plaats van
                // een bevestiging.
                final messenger = ScaffoldMessenger.of(context);
                final bevestiging = l10n.d('Gekopieerd');
                await Clipboard.setData(ClipboardData(text: _outputPath!));
                if (!mounted) return;
                messenger.showSnackBar(SnackBar(content: Text(bevestiging)));
              },
              icon: const Icon(Icons.copy, size: 16),
              // Het pad alleen, niet de hele melding eromheen: wie kopieert
              // wil het in een terminal of een bestandsvenster plakken.
              label: Text(l10n.d('Kopiëren')),
            ),
          ],
        ],
      );
    }

    // Pre-flight classificatie-gate: blokkeert de export al vóór een poging,
    // zodat de gebruiker meteen de reden ziet. De service handhaaft dezelfde
    // regel nog eens als backstop, dus dit is puur UX — niet de beveiliging.
    final decision = widget.enforcementPolicy.evaluate(
      _bundle.audience.deck.tlp,
    );
    if (!decision.allowed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block, color: AppTheme.dangerFg, size: 36),
          const SizedBox(height: 12),
          Text(
            exportBlockMessage(context.l10n, decision) ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.dangerFg),
          ),
          const SizedBox(height: 10),
          // Wijs de weg naar de oplossing: het TLP-niveau zit op de
          // TLP-knop in de werkbalk (die licht bij een blokkade ook op).
          Text(
            l10n.d(
              'Stel een TLP-niveau in — export is geblokkeerd door het classificatiebeleid.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppTheme.slate500),
          ),
        ],
      );
    }

    final qualityDecision = widget.qualityPolicy.evaluate(widget.qualityResult);
    if (qualityDecision.hardBlocked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block, color: AppTheme.dangerFg, size: 36),
          const SizedBox(height: 12),
          Text(
            l10n.d('Export geblokkeerd vanwege ernstige kwaliteitsproblemen.'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.dangerFg),
          ),
          const SizedBox(height: 8),
          Text(
            formatQualityExportReason(l10n, widget.qualityResult),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppTheme.slate500),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => showSlideQualityDetailsDialog(
              context,
              result: widget.qualityResult,
            ),
            icon: const Icon(Icons.list_alt_outlined, size: 16),
            label: Text(l10n.d('Bekijk alle meldingen…')),
          ),
        ],
      );
    }

    return _optionsContent(l10n);
  }

  /// De classificatie van dit deck, zolang die niet *geen* is — plus of er
  /// iets aan vastzit.
  ///
  /// Het dialoog zweeg erover en exporteerde naar PDF, PPTX en HTML zonder
  /// enige drempel. Wie TLP:RED had gekozen zag rode markeringen op elke dia en
  /// mocht daar iets van verwachten; als het alleen opmaak is, is dat erger dan
  /// geen classificatie (#627). Handhaving bestáát, maar alleen met het
  /// classificatiebeleid aan — en dat is nergens te zien vanaf hier.
  Widget _classificationBanner(AppLocalizations l10n) {
    final tlp = _bundle.audience.deck.tlp;
    if (tlp == TlpLevel.none) return const SizedBox.shrink();
    final enforced = widget.enforcementPolicy.isEnforcing;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.infoBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, size: 15, color: AppTheme.slate600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              enforced
                  ? '${tlp.label} — ${l10n.d('het classificatiebeleid bewaakt wat er uit mag.')}'
                  : '${tlp.label} — ${l10n.d('de markering reist mee, maar er is geen drempel: zet het classificatiebeleid aan onder Instellingen → Algemeen.')}',
              style: TextStyle(fontSize: 11.5, color: AppTheme.slate700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionsContent(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Alle gates staan open en er is niets te melden: zeg dat dan ook,
        // zodat de laatste stap met vertrouwen begint in plaats van stilte.
        if (widget.qualityResult.hasIssues)
          _qualityBanner(l10n)
        else
          _readyBanner(l10n),
        _classificationBanner(l10n),
        _privacyCaveat(l10n),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l10n.t('exportIntro'),
            style: TextStyle(fontSize: 12, color: AppTheme.slate500),
          ),
        ),
        _exportButton(
          icon: _formatIcon(ExportFormat.pdf),
          label: l10n.t('exportAsPdf'),
          onPressed: _loading
              ? null
              : () => _export(ExportFormat.pdf, compress: _compress),
        ),
        _exportButton(
          icon: _formatIcon(ExportFormat.pptx),
          label: l10n.t('exportAsPptx'),
          onPressed: _loading ? null : () => _export(ExportFormat.pptx),
        ),
        _exportButton(
          icon: _formatIcon(ExportFormat.odp),
          label: l10n.t('exportAsOdp'),
          onPressed: _loading ? null : () => _export(ExportFormat.odp),
        ),
        _exportButton(
          icon: _formatIcon(ExportFormat.html),
          label: l10n.t('exportAsHtml'),
          onPressed: _loading ? null : () => _export(ExportFormat.html),
        ),
        _exportButton(
          icon: _formatIcon(ExportFormat.latex),
          label: l10n.t('exportAsLatex'),
          onPressed: _loading ? null : () => _export(ExportFormat.latex),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            l10n.d(
              'HTML-bestand opent in elke browser zonder internet en rendert codeblokken, wiskunde en mermaid-diagrammen. LaTeX-bron compileer je met pdflatex of xelatex.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ),
        const SizedBox(height: 8),
        if (widget.hasPrivacyFindings) _profileSelector(l10n),
        _aiDraftNotice(l10n),
        _manifestNotice(l10n),
        if (widget.hasDepthChoice) _depthSelector(l10n),
        // De formaatknoppen zijn de hoofdactie; de beeldkwaliteit is een
        // verfijning en staat daarom achter een inklapbare kop (open zodra
        // er gecomprimeerd wordt, zodat de keuze zichtbaar blijft).
        AdvancedSection(
          title: l10n.t('imageQualityPdf'),
          initiallyExpanded: _compress,
          children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.image_outlined),
                  label: Text(l10n.t('normal')),
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.compress),
                  label: Text(l10n.t('compressed')),
                ),
              ],
              selected: {_compress},
              onSelectionChanged: (s) => setState(() => _compress = s.first),
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _compress ? l10n.t('compressedHelp') : l10n.t('losslessHelp'),
                style: TextStyle(fontSize: 11, color: AppTheme.slate400),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _exportButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }

  IconData _formatIcon(ExportFormat f) {
    switch (f) {
      case ExportFormat.pdf:
        return Icons.picture_as_pdf_outlined;
      case ExportFormat.pptx:
        return Icons.slideshow_outlined;
      case ExportFormat.odp:
        return Icons.slideshow_outlined;
      case ExportFormat.html:
        return Icons.public_outlined;
      case ExportFormat.latex:
        return Icons.science_outlined;
    }
  }
}
