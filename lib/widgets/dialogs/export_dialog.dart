import 'package:flutter/material.dart';
import '../../models/deck.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../services/export_service.dart';
import '../../services/slide_rasterizer.dart';

/// Exports the deck by rendering the on-screen slide previews to images and
/// packing them into a PDF or PPTX (WYSIWYG — the export matches the preview).
class ExportDialog extends StatefulWidget {
  final String deckPath;
  final List<Slide> slides;
  final ThemeProfile themeProfile;
  final String? projectPath;
  final ExportService exportService;
  final TlpLevel tlp;

  const ExportDialog({
    super.key,
    required this.deckPath,
    required this.slides,
    required this.themeProfile,
    required this.projectPath,
    required this.exportService,
    this.tlp = TlpLevel.none,
  });

  static Future<void> show(
    BuildContext context, {
    required String deckPath,
    required List<Slide> slides,
    required ThemeProfile themeProfile,
    required String? projectPath,
    required ExportService exportService,
    TlpLevel tlp = TlpLevel.none,
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

  Future<void> _export(ExportFormat format) async {
    setState(() {
      _loading = true;
      _result = null;
      _phase = 'Slides renderen…';
      _done = 0;
      _total = widget.slides.length;
    });

    final images = await SlideRasterizer.rasterize(
      context: context,
      slides: widget.slides,
      themeProfile: widget.themeProfile,
      projectPath: widget.projectPath,
      tlp: widget.tlp,
      onProgress: (done, total) {
        if (mounted) setState(() => _done = done);
      },
    );

    if (!mounted) return;
    setState(() => _phase = '${format.label} samenstellen…');

    final r = await widget.exportService.export(
      widget.deckPath,
      format,
      images,
    );

    if (!mounted) return;
    setState(() {
      _loading = false;
      _success = r.success;
      _result = r.success ? 'Geëxporteerd naar:\n${r.outputPath}' : r.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Exporteren'),
      content: SizedBox(width: 380, child: _content()),
      actions: [
        if (_result != null && _success)
          TextButton(
            onPressed: () => setState(() => _result = null),
            child: const Text('Nogmaals exporteren'),
          ),
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Sluiten'),
        ),
      ],
    );
  }

  Widget _content() {
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
            _total == 0 ? '' : 'Slide $_done van $_total',
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
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'De export gebruikt exact de weergave uit de editor, inclusief je '
            'stijlprofiel.',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ),
        ...ExportFormat.values.map((f) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: OutlinedButton.icon(
              onPressed: () => _export(f),
              icon: Icon(_formatIcon(f)),
              label: Text('Exporteer als ${f.label}'),
            ),
          );
        }),
      ],
    );
  }

  IconData _formatIcon(ExportFormat f) {
    switch (f) {
      case ExportFormat.pdf:
        return Icons.picture_as_pdf_outlined;
      case ExportFormat.pptx:
        return Icons.slideshow_outlined;
    }
  }
}
