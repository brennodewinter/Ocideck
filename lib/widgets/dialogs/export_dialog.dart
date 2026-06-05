import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../models/deck.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../services/export_service.dart';
import '../../services/slide_rasterizer.dart';
import '../../l10n/app_localizations.dart';

/// Exports the deck by rendering the on-screen slide previews to images and
/// packing them into a PDF or PPTX (WYSIWYG — the export matches the preview).
class ExportDialog extends StatefulWidget {
  final String deckPath;
  final List<Slide> slides;
  final ThemeProfile themeProfile;
  final String? projectPath;
  final ExportService exportService;
  final TlpLevel tlp;

  /// Folder all exports are written to. Null = next to the source deck.
  final String? exportDirectory;

  /// The deck's Marp Markdown, used for the self-contained HTML export.
  final String markdown;

  const ExportDialog({
    super.key,
    required this.deckPath,
    required this.slides,
    required this.themeProfile,
    required this.projectPath,
    required this.exportService,
    this.tlp = TlpLevel.none,
    this.exportDirectory,
    this.markdown = '',
  });

  static Future<void> show(
    BuildContext context, {
    required String deckPath,
    required List<Slide> slides,
    required ThemeProfile themeProfile,
    required String? projectPath,
    required ExportService exportService,
    TlpLevel tlp = TlpLevel.none,
    String? exportDirectory,
    String markdown = '',
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExportDialog(
        deckPath: deckPath,
        slides: slides,
        themeProfile: themeProfile,
        projectPath: projectPath,
        exportService: exportService,
        tlp: tlp,
        exportDirectory: exportDirectory,
        markdown: markdown,
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

  Future<void> _export(ExportFormat format, {bool compress = false}) async {
    final l10n = context.l10n;
    // HTML renders from Markdown in the browser, so it needs no slide raster.
    final needsRaster = format != ExportFormat.html;
    setState(() {
      _loading = true;
      _result = null;
      _phase = needsRaster ? l10n.t('renderingSlides') : l10n.t('buildingHtml');
      _done = 0;
      _total = needsRaster ? widget.slides.length : 0;
    });

    // Give the dialog a frame to paint before the potentially expensive first
    // image decode/raster pass starts.
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    final images = needsRaster
        ? await SlideRasterizer.rasterize(
            context: context,
            slides: widget.slides,
            themeProfile: widget.themeProfile,
            projectPath: widget.projectPath,
            tlp: widget.tlp,
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
    setState(() => _phase = '${format.label} ${l10n.t('buildingExport')}');

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
    );

    if (!mounted) return;
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
      final fraction = _total == 0 ? null : _done / _total;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _phase,
            style: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: fraction, minHeight: 6),
          ),
          const SizedBox(height: 8),
          Text(
            _total == 0
                ? ''
                : '${l10n.t('slideOf')} $_done ${l10n.t('of')} $_total',
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l10n.t('exportIntro'),
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            l10n.t('imageQualityPdf'),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF475569),
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
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
        ),
        _exportButton(
          icon: _formatIcon(ExportFormat.pdf),
          label: l10n.t('exportAsPdf'),
          onPressed: () => _export(ExportFormat.pdf, compress: _compress),
        ),
        _exportButton(
          icon: _formatIcon(ExportFormat.pptx),
          label: l10n.t('exportAsPptx'),
          onPressed: () => _export(ExportFormat.pptx),
        ),
        _exportButton(
          icon: _formatIcon(ExportFormat.html),
          label: l10n.t('exportAsHtml'),
          onPressed: () => _export(ExportFormat.html),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            l10n.d(
              'HTML opent in elke browser zonder internet en rendert codeblokken, wiskunde en mermaid-diagrammen.',
            ),
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
        ),
      ],
    );
  }

  Widget _exportButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
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
