import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/documentation_service.dart';
import '../../utils/url_launcher_util.dart';
import 'document_markdown_view.dart';

/// A full-screen, accessible reader for a bundled Markdown document.
///
/// Unlike the cramped in-dialog viewers, this route uses the whole window: the
/// content fills the height and is centred in a readable-width column (long
/// measure hurts readability, so the width is bounded rather than edge-to-edge).
/// Text follows the OS text-size setting, is selectable, and links open
/// externally. It sits above dialogs (pushed on the root navigator), so it can
/// be opened from the consent gate and the settings screen alike.
class DocumentReaderScreen extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final languageCode = Localizations.localeOf(context).languageCode;

    return Scaffold(
      appBar: AppBar(
        title: Semantics(header: true, child: Text(title)),
        actions: [
          if (onlineUrl != null)
            IconButton(
              icon: const Icon(Icons.open_in_new),
              tooltip: l10n.d('Online openen'),
              onPressed: () => openExternalUrl(onlineUrl!),
            ),
        ],
      ),
      body: FutureBuilder<String>(
        future: service.load(assetBase, languageCode),
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
          return _body(snap.data!);
        },
      ),
    );
  }

  Widget _body(String markdown) {
    return Scrollbar(
      child: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              // SelectionArea makes the whole document selectable/copyable while
              // keeping links tappable.
              child: SelectionArea(
                child: DocumentMarkdownView(
                  markdown,
                  onTapLink: openExternalUrl,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
