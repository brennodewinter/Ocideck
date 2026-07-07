import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/documentation_service.dart';
import '../../state/settings_provider.dart';
import '../../utils/url_launcher_util.dart';
import 'document_markdown_view.dart';

/// A full-screen, accessible reader for a bundled Markdown document.
///
/// The content fills the height and uses most of the window width: tables and
/// code blocks span the full measure (so wide tables are no longer squeezed),
/// while prose is kept to a readable line length. A subtle text-size control in
/// the app bar enlarges or shrinks the document text; the choice is remembered
/// (see [SettingsNotifier.setDocReaderTextScale]) independently of the app-wide
/// interface scale. Text is selectable and links open externally. It sits above
/// dialogs (pushed on the root navigator), so it can be opened from the consent
/// gate and the settings screen alike.
class DocumentReaderScreen extends ConsumerStatefulWidget {
  const DocumentReaderScreen({
    super.key,
    required this.title,
    required this.assetBase,
    this.onlineUrl,
    this.service = const DocumentationService(),
  });

  /// Localised screen title (e.g. the document name).
  final String title;

  /// Base asset key, e.g. `docs/USER_GUIDE.md` or `LICENSE.md`.
  final String assetBase;

  /// Optional canonical online version, offered as an "open online" action.
  final String? onlineUrl;

  final DocumentationService service;

  /// Prose is bounded to this measure; tables and code use the full width.
  static const double _proseMaxWidth = 860;

  /// Cap the content column so ultra-wide windows don't stretch edge-to-edge,
  /// yet far more of the width is used than the old fixed narrow column.
  static const double _contentMaxWidth = 1200;

  @override
  ConsumerState<DocumentReaderScreen> createState() =>
      _DocumentReaderScreenState();

  /// Pushes the reader over everything (including any open dialog).
  static Future<void> open(
    BuildContext context, {
    required String title,
    required String assetBase,
    String? onlineUrl,
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => DocumentReaderScreen(
          title: title,
          assetBase: assetBase,
          onlineUrl: onlineUrl,
        ),
      ),
    );
  }
}

class _DocumentReaderScreenState extends ConsumerState<DocumentReaderScreen> {
  // Shared by the Scrollbar and the SingleChildScrollView so the thumb is
  // bound to a real ScrollPosition. Without this, on desktop the Scrollbar
  // falls back to the PrimaryScrollController (which the scroll view does not
  // attach to there), and dragging throws "no ScrollPosition attached".
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final languageCode = Localizations.localeOf(context).languageCode;
    final scale = ref.watch(
      settingsProvider.select((s) => s.docReaderTextScale),
    );

    return Scaffold(
      appBar: AppBar(
        title: Semantics(header: true, child: Text(widget.title)),
        actions: [
          ..._textSizeActions(context, ref, l10n, scale),
          if (widget.onlineUrl != null)
            IconButton(
              icon: const Icon(Icons.open_in_new),
              tooltip: l10n.d('Online openen'),
              onPressed: () => openExternalUrl(widget.onlineUrl!),
            ),
        ],
      ),
      body: FutureBuilder<String>(
        future: widget.service.load(widget.assetBase, languageCode),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || !snap.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.d('Dit document kon niet worden geladen.')),
              ),
            );
          }
          return _body(context, snap.data!, scale);
        },
      ),
    );
  }

  /// The subtle "smaller / larger" pair, each disabled at its bound.
  List<Widget> _textSizeActions(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    double scale,
  ) {
    void nudge(double delta) => ref
        .read(settingsProvider.notifier)
        .setDocReaderTextScale(scale + delta);

    const step = SettingsNotifier.docReaderTextScaleStep;
    final canShrink = scale > SettingsNotifier.docReaderTextScaleMin + 1e-6;
    final canGrow = scale < SettingsNotifier.docReaderTextScaleMax - 1e-6;
    return [
      IconButton(
        icon: const Icon(Icons.text_decrease),
        iconSize: 20,
        tooltip: l10n.d('Tekst kleiner'),
        onPressed: canShrink ? () => nudge(-step) : null,
      ),
      IconButton(
        icon: const Icon(Icons.text_increase),
        iconSize: 20,
        tooltip: l10n.d('Tekst groter'),
        onPressed: canGrow ? () => nudge(step) : null,
      ),
    ];
  }

  Widget _body(BuildContext context, String markdown, double scale) {
    final media = MediaQuery.of(context);
    // The reader's own scale multiplies whatever the OS and the app-wide
    // interface scale already ask for, so all document text (tables included)
    // grows and shrinks together.
    final scaled = media.copyWith(
      textScaler: TextScaler.linear(media.textScaler.scale(1.0) * scale),
    );

    return MediaQuery(
      data: scaled,
      child: Scrollbar(
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: DocumentReaderScreen._contentMaxWidth,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 28,
                ),
                // SelectionArea makes the whole document selectable/copyable
                // while keeping links tappable.
                child: SelectionArea(
                  child: DocumentMarkdownView(
                    markdown,
                    onTapLink: openExternalUrl,
                    maxTextWidth: DocumentReaderScreen._proseMaxWidth,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
