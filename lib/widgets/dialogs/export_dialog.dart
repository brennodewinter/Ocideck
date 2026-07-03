import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../models/deck.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../models/slide_quality.dart';
import '../../services/classification_enforcement_policy.dart';
import '../../services/export_metadata.dart';
import '../../services/export_service.dart';
import '../../services/quality_export_policy.dart';
import '../../services/slide_rasterizer.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/slide_quality_localization.dart';
import 'slide_quality_details_dialog.dart';
import '../../theme/app_theme.dart';

/// Exports the deck by rendering the on-screen slide previews to images and
/// packing them into a PDF or PPTX (WYSIWYG — the export matches the preview).
class ExportDialog extends StatefulWidget {
  final String deckPath;
  final List<Slide> slides;
  final ThemeProfile themeProfile;
  final CockpitColorScheme cockpitColorScheme;
  final String? projectPath;
  final ExportService exportService;
  final TlpLevel tlp;

  /// Classificatie-handhaving (plafond, minimum, verplicht classificeren).
  final ClassificationEnforcementPolicy enforcementPolicy;

  /// Slide-kwaliteit van de te exporteren slides.
  final SlideQualityResult qualityResult;

  /// Soft gate — waarschuwing vóór export wanneer ingeschakeld.
  final QualityExportPolicy qualityPolicy;

  /// Folder all exports are written to. Null = next to the source deck.
  final String? exportDirectory;

  /// The deck's Marp Markdown, used for the self-contained HTML export.
  final String markdown;

  final String organization;
  final bool showClassificationWatermark;
  final ExportDocumentMetadata documentMetadata;

  /// Na een geslaagde export aangeroepen met het formaat-label ("PDF",
  /// "PPTX", "HTML") — bijv. om het bij de recente bestanden te noteren.
  final void Function(String formatLabel)? onExported;

  const ExportDialog({
    super.key,
    required this.deckPath,
    required this.slides,
    required this.themeProfile,
    this.cockpitColorScheme = CockpitColorScheme.standard,
    required this.projectPath,
    required this.exportService,
    this.tlp = TlpLevel.none,
    this.enforcementPolicy = const ClassificationEnforcementPolicy(),
    this.qualityResult = const SlideQualityResult([]),
    this.qualityPolicy = const QualityExportPolicy(),
    this.exportDirectory,
    this.markdown = '',
    this.organization = '',
    this.showClassificationWatermark = false,
    this.documentMetadata = const ExportDocumentMetadata(),
    this.onExported,
  });

  static Future<void> show(
    BuildContext context, {
    required String deckPath,
    required List<Slide> slides,
    required ThemeProfile themeProfile,
    CockpitColorScheme cockpitColorScheme = CockpitColorScheme.standard,
    required String? projectPath,
    required ExportService exportService,
    TlpLevel tlp = TlpLevel.none,
    ClassificationEnforcementPolicy enforcementPolicy =
        const ClassificationEnforcementPolicy(),
    SlideQualityResult qualityResult = const SlideQualityResult([]),
    QualityExportPolicy qualityPolicy = const QualityExportPolicy(),
    String? exportDirectory,
    String markdown = '',
    String organization = '',
    bool showClassificationWatermark = false,
    ExportDocumentMetadata documentMetadata = const ExportDocumentMetadata(),
    void Function(String formatLabel)? onExported,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExportDialog(
        deckPath: deckPath,
        slides: slides,
        themeProfile: themeProfile,
        cockpitColorScheme: cockpitColorScheme,
        projectPath: projectPath,
        exportService: exportService,
        tlp: tlp,
        enforcementPolicy: enforcementPolicy,
        qualityResult: qualityResult,
        qualityPolicy: qualityPolicy,
        exportDirectory: exportDirectory,
        markdown: markdown,
        organization: organization,
        showClassificationWatermark: showClassificationWatermark,
        documentMetadata: documentMetadata,
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

  /// Image quality for PDF export: false = full-resolution PNG, true = a smaller
  /// downscaled JPEG handout.
  bool _compress = false;

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
      _result = null;
      _phase = l10n.d('Export wordt voorbereid…');
      _done = 0;
      _total = needsRaster ? widget.slides.length : 0;
    });
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    if (!await _confirmQualityExport()) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    if (!mounted) return;
    setState(() {
      _phase = needsRaster ? l10n.t('renderingSlides') : l10n.t('buildingHtml');
      _done = 0;
      _total = needsRaster ? widget.slides.length : 0;
    });
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    final images = needsRaster
        ? await SlideRasterizer.rasterize(
            context: context,
            slides: widget.slides,
            themeProfile: widget.themeProfile,
            cockpitColorScheme: widget.cockpitColorScheme,
            projectPath: widget.projectPath,
            tlp: widget.tlp,
            showClassificationWatermark: widget.showClassificationWatermark,
            organization: widget.organization,
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
          )
        : const <Uint8List>[];

    if (!mounted) return;
    setState(() {
      _phase = '${format.label} ${l10n.t('buildingExport')}';
      _done = needsRaster ? widget.slides.length : 0;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final r = await widget.exportService.export(
      widget.deckPath,
      format,
      images,
      compress: compress,
      outputDirectory: widget.exportDirectory,
      // Speaker notes travel 1:1 with the rendered slides (PPTX notes pane).
      notes: [for (final s in widget.slides) s.notes],
      markdown: widget.markdown,
      themeProfile: widget.themeProfile,
      cockpitColorScheme: widget.cockpitColorScheme,
      tlp: widget.tlp,
      enforcementPolicy: widget.enforcementPolicy,
      qualityResult: widget.qualityResult,
      qualityPolicy: widget.qualityPolicy,
      qualityAcknowledged: true,
      metadata: widget.documentMetadata,
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      scrollable: true,
      title: Text(l10n.t('exportDialogTitle')),
      content: SizedBox(width: 380, child: _content()),
      actions: [
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
            style: const TextStyle(fontSize: 13, color: AppTheme.slate700),
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
              style: const TextStyle(fontSize: 11, color: AppTheme.slate400),
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
              color: _success ? const Color(0xFF166534) : Colors.red[800],
            ),
          ),
        ],
      );
    }

    // Pre-flight classificatie-gate: blokkeert de export al vóór een poging,
    // zodat de gebruiker meteen de reden ziet. De service handhaaft dezelfde
    // regel nog eens als backstop, dus dit is puur UX — niet de beveiliging.
    final decision = widget.enforcementPolicy.evaluate(widget.tlp);
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
            style: const TextStyle(fontSize: 12, color: AppTheme.slate500),
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
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l10n.t('exportIntro'),
            style: const TextStyle(fontSize: 12, color: AppTheme.slate500),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            l10n.t('imageQualityPdf'),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.slate600,
            ),
          ),
        ),
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
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            _compress ? l10n.t('compressedHelp') : l10n.t('losslessHelp'),
            style: const TextStyle(fontSize: 11, color: AppTheme.slate400),
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
            style: const TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ),
      ],
    );
  }

  Widget _readyBanner(AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFA7F3D0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.task_alt, size: 16, color: Color(0xFF047857)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${l10n.d('Klaar voor export')} — '
              '${l10n.d('Geen kwaliteitsproblemen gevonden')}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF047857)),
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
        ? const Color(0xFFFEE2E2)
        : hasWarnings
        ? const Color(0xFFFEF3C7)
        : const Color(0xFFEFF6FF);
    final borderColor = hasErrors
        ? const Color(0xFFFECACA)
        : hasWarnings
        ? const Color(0xFFFDE68A)
        : const Color(0xFFBFDBFE);
    final iconColor = hasErrors
        ? Colors.red.shade700
        : hasWarnings
        ? const Color(0xFF92400E)
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
