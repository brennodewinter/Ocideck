import 'dart:typed_data';

import 'package:flutter/material.dart';
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
import 'slide_quality_details_dialog.dart';
import '../../theme/app_theme.dart';

part 'parts/export_dialog_notices.dart';

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
    final needsRaster = format != ExportFormat.html;

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
                _phase = _stageText(phase, done, total);
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
    );

    if (!mounted) return;
    if (r.success) widget.onExported?.call(format.label);
    setState(() {
      _loading = false;
      _success = r.success;
      _result = r.success
          ? '${l10n.t('exportedTo')}\n${r.outputPath}'
          : r.error;
    });
  }

  String _stageText(String phase, int done, int total) {
    final l10n = context.l10n;
    final number = (done + 1).clamp(1, total);
    switch (phase) {
      case 'precache':
        return total == 0
            ? l10n.d('Afbeeldingen laden…')
            : '${l10n.d('Afbeeldingen laden…')} $done ${l10n.t('of')} $total';
      case 'prepare':
        return '${l10n.d('Slide')} $number ${l10n.d('voorbereiden…')}';
      case 'render':
        return '${l10n.d('Slide')} $number ${l10n.d('renderen…')}';
      case 'done':
        return done >= total
            ? l10n.d('Slides gerenderd.')
            : '${l10n.d('Slide')} $done ${l10n.d('gerenderd.')}';
      default:
        return l10n.t('renderingSlides');
    }
  }

  /// Hoeveel detail wil deze lezer?
  ///
  /// De derde as naast classificatie en redactie, en bewust een eigen keuze:
  /// TLP zegt wíé het mag zien, redactie wélke gegevens eruit mogen, en dit
  /// hoevéél detail erbij hoort. Een slide kan prima openbaar zijn en tóch meer
  /// zijn dan waarvoor een managementpubliek kwam.
  ///
  /// Net als het profiel landt de keuze in de bestandsnaam (`…-beknopt.pdf`),
  /// om dezelfde reden: een verwisseling moet je kunnen zien.
  Widget _depthSelector(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d('Hoeveel detail?'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: true,
                label: Text(l10n.d('Met verdieping')),
                icon: const Icon(Icons.unfold_more, size: 15),
              ),
              ButtonSegment(
                value: false,
                label: Text(l10n.d('Beknopt')),
                icon: const Icon(Icons.unfold_less, size: 15),
              ),
            ],
            selected: {_includeDetail},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) => _selectDepth(s.first),
          ),
        ],
      ),
    );
  }

  /// Voor wie is deze export?
  ///
  /// Eén bron, twee versies. Dat is de kern van het pentestrapport-scenario: de
  /// opdrachtgever moet de bevinding kúnnen natrekken, dus die krijgt alles; de
  /// bredere kring krijgt hetzelfde rapport met de persoonsgegevens eruit.
  ///
  /// Het profiel staat in de bestandsnaam (`…-geredigeerd.pdf`). Dat is niet
  /// cosmetisch: de duurste fout die je met deze feature kunt maken, is het
  /// volledige exemplaar naar de brede kring sturen. Een verwisseling moet je
  /// kunnen *zien*, niet hoeven onthouden.
  Widget _profileSelector(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.d('Voor wie is deze export?'),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          SegmentedButton<PrivacyExportProfile>(
            segments: [
              ButtonSegment(
                value: PrivacyExportProfile.full,
                label: Text(l10n.d('Volledig')),
                icon: const Icon(Icons.lock_open_outlined, size: 15),
              ),
              ButtonSegment(
                value: PrivacyExportProfile.redacted,
                label: Text(l10n.d('Geredigeerd')),
                icon: const Icon(Icons.visibility_off_outlined, size: 15),
              ),
            ],
            selected: {_profile},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) => _selectProfile(s.first),
          ),
          const SizedBox(height: 4),
          Text(
            _profile == PrivacyExportProfile.full
                ? l10n.d(
                    'Voor de opdrachtgever of auditor: alleen wat je zelf op "weglaten" hebt gezet, gaat eruit. De rest blijft leesbaar, zodat een derde partij de bevindingen kan controleren.',
                  )
                : l10n.d(
                    'Voor de bredere kring: alles wat de controle vindt gaat eruit, ook op slides die je hebt geaccepteerd. Het bestand krijgt "-geredigeerd" in de naam.',
                  ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ],
      ),
    );
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
            onPressed: () => setState(() => _result = null),
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
            color: _success ? Colors.green : Colors.red,
            size: 36,
          ),
          const SizedBox(height: 12),
          Text(
            _result!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: _success ? AppTheme.success800 : Colors.red[800],
            ),
          ),
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
          const Icon(Icons.block, color: Colors.red, size: 36),
          const SizedBox(height: 12),
          Text(
            decision.reason!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.red[800]),
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
          const Icon(Icons.block, color: Colors.red, size: 36),
          const SizedBox(height: 12),
          Text(
            l10n.d('Export geblokkeerd vanwege ernstige kwaliteitsproblemen.'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.red[800]),
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
          icon: _formatIcon(ExportFormat.html),
          label: l10n.t('exportAsHtml'),
          onPressed: _loading ? null : () => _export(ExportFormat.html),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            l10n.d(
              'HTML opent in elke browser zonder internet en rendert codeblokken, wiskunde en mermaid-diagrammen.',
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

  /// De balk boven de exportknoppen als er niets te melden valt.
  ///
  /// Groen zegt "wij hebben gekeken en niets gevonden". Staat de privacycontrole
  /// uit, dan is de tweede helft van die zin niet waar, en juist die helft leest
  /// de gebruiker als toestemming om te delen. Dan wordt de balk neutraal en
  /// zegt hij wát er niet is nagekeken — plus waar hij dat aanzet, want een
  /// melding zonder uitweg is een doodlopende straat met tekst.
  Widget _readyBanner(AppLocalizations l10n) {
    final checked = widget.privacyChecksEnabled;
    final foreground = checked ? AppTheme.successFg : AppTheme.slate600;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: checked ? AppTheme.successBg : AppTheme.slate100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: checked ? AppTheme.successBgSoft : AppTheme.slate300,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.task_alt, size: 16, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              checked
                  ? '${l10n.d('Klaar voor export')} — '
                        '${l10n.d('Geen kwaliteitsproblemen gevonden')}'
                  : '${l10n.d('Klaar voor export')} — '
                        '${l10n.d('Er is niet gekeken naar persoonsgegevens, bijzondere gegevens en geheimen: de privacycontrole staat uit bij Beveiliging.')}',
              style: TextStyle(fontSize: 11, color: foreground),
            ),
          ),
        ],
      ),
    );
  }

  Widget _qualityBanner(AppLocalizations l10n) {
    final result = widget.qualityResult;
    final hasErrors = result.errorCount > 0;
    final hasWarnings = result.warningCount > 0;
    final color = hasErrors
        ? AppTheme.dangerBg
        : hasWarnings
        ? AppTheme.warningBg
        : AppTheme.infoBg;
    final borderColor = hasErrors
        ? AppTheme.dangerBgSoft
        : hasWarnings
        ? AppTheme.warningBgSoft
        : AppTheme.userNotesBorder;
    final iconColor = hasErrors
        ? Colors.red.shade700
        : hasWarnings
        ? AppTheme.warningFg
        : AppTheme.slate600;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.accessibility_new_outlined,
                size: 16,
                color: iconColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${l10n.d('Slidekwaliteit')}: '
                  '${formatSlideQualityCountSummary(l10n, result)}',
                  style: TextStyle(fontSize: 11, color: iconColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  showSlideQualityDetailsDialog(context, result: result),
              icon: const Icon(Icons.list_alt_outlined, size: 14),
              label: Text(l10n.d('Bekijk meldingen…')),
              style: TextButton.styleFrom(
                foregroundColor: iconColor,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
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
      case ExportFormat.html:
        return Icons.public_outlined;
    }
  }
}
