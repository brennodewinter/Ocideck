import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../l10n/app_localizations.dart';

/// Read-only PDF viewer shared by local files and clean OciServe evidence.
///
/// The original bytes remain untouched. PDFium renders PDF, PDF/A and visible
/// signature appearances, but this screen deliberately does not claim to
/// validate an embedded certificate or its trust chain.
class PdfEvidenceViewer extends StatefulWidget {
  const PdfEvidenceViewer({
    super.key,
    required this.bytes,
    required this.fileName,
  });

  final Uint8List bytes;
  final String fileName;

  static Future<void> open(
    BuildContext context, {
    required Uint8List bytes,
    required String fileName,
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfEvidenceViewer(bytes: bytes, fileName: fileName),
      ),
    );
  }

  @override
  State<PdfEvidenceViewer> createState() => _PdfEvidenceViewerState();
}

class _PdfEvidenceViewerState extends State<PdfEvidenceViewer> {
  final PdfViewerController _controller = PdfViewerController();
  int _pageNumber = 1;
  int? _pageCount;

  Future<String?> _requestPassword() async {
    final field = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.l10n.d('Wachtwoord')),
          content: TextField(
            controller: field,
            autofocus: true,
            obscureText: true,
            decoration: InputDecoration(
              labelText: context.l10n.d('Wachtwoord'),
            ),
            onSubmitted: (value) => Navigator.pop(dialogContext, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.l10n.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, field.text),
              child: Text(context.l10n.d('Openen')),
            ),
          ],
        ),
      );
    } finally {
      field.dispose();
    }
  }

  void _loaded(bool succeeded) {
    if (!mounted || !succeeded || !_controller.isReady) return;
    setState(() {
      _pageCount = _controller.pageCount;
      _pageNumber = _controller.pageNumber ?? 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final pageLabel = _pageCount == null
        ? null
        : l10n
              .d('Pagina {n} van {m}')
              .replaceAll('{n}', '$_pageNumber')
              .replaceAll('{m}', '$_pageCount');

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n.d('Sluiten'),
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
        ),
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (pageLabel != null)
              Text(
                pageLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l10n.d('Uitzoomen'),
            onPressed: _controller.isReady ? _controller.zoomDown : null,
            icon: const Icon(Icons.zoom_out),
          ),
          IconButton(
            tooltip: l10n.d('Inzoomen'),
            onPressed: _controller.isReady ? _controller.zoomUp : null,
            icon: const Icon(Icons.zoom_in),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _SignatureNotice(
            theme: theme,
            text: l10n.d(
              'PDF/A en digitale handtekeningen blijven zichtbaar. OciDeck controleert de handtekening niet.',
            ),
          ),
          Expanded(
            child: PdfViewer.data(
              widget.bytes,
              sourceName:
                  '${widget.fileName}-${widget.bytes.length}-${identityHashCode(widget.bytes)}',
              controller: _controller,
              passwordProvider: _requestPassword,
              params: PdfViewerParams(
                margin: 24,
                backgroundColor: theme.colorScheme.surfaceContainerLow,
                pageDropShadow: BoxShadow(
                  color: theme.colorScheme.shadow.withValues(alpha: 0.18),
                  blurRadius: 18,
                  spreadRadius: 1,
                  offset: const Offset(0, 6),
                ),
                limitRenderingCache: true,
                maxImageBytesCachedOnMemory: 64 * 1024 * 1024,
                interactionDelegateProvider:
                    const PdfViewerScrollInteractionDelegateProviderPhysics(),
                sizeDelegateProvider: const PdfViewerSizeDelegateProviderSmart(
                  maxScale: 6,
                ),
                onDocumentLoadFinished: (_, succeeded) => _loaded(succeeded),
                onPageChanged: (number) {
                  if (number != null && mounted) {
                    setState(() => _pageNumber = number);
                  }
                },
                loadingBannerBuilder: (_, _, _) =>
                    const Center(child: CircularProgressIndicator()),
                errorBannerBuilder: (_, _, _, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      l10n.d('Kon dit bestand niet openen.'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignatureNotice extends StatelessWidget {
  const _SignatureNotice({required this.theme, required this.text});

  final ThemeData theme;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
    decoration: BoxDecoration(
      color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.42),
      border: Border(
        bottom: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.info_outline,
          size: 17,
          color: theme.colorScheme.onTertiaryContainer,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onTertiaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
