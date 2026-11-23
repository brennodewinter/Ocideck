import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/markdown_kind.dart';
import '../services/document_deck_bridge.dart';
import '../state/deck_provider.dart';
import '../state/document_provider.dart';
import '../state/tabs_provider.dart';
import '../theme/app_theme.dart';

/// Slanke balk boven een nog leeg bestand: het type kan nog gewisseld worden
/// (#3107). De widget watcht zelf de leegtoestand van de actieve editor en
/// rendert niets zodra er inhoud is — de aanroeper hoeft de balk alleen te
/// vermelden.
class EmptyFileSwitchBanner extends ConsumerWidget {
  const EmptyFileSwitchBanner({super.key, required this.toKind});

  /// Het soort waar de knop naartoe wisselt: vanuit een document is dat een
  /// presentatie, vanuit een presentatie een document.
  final MarkdownKind toKind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEmpty = switch (toKind) {
      MarkdownKind.presentation => ref.watch(
        documentProvider.select(
          (s) => s.document?.body.trim().isEmpty ?? false,
        ),
      ),
      MarkdownKind.document => ref.watch(
        deckProvider.select(
          (s) => s.deck != null && DocumentDeckBridge.deckIsEmpty(s.deck!),
        ),
      ),
    };
    if (!isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = context.l10n;
    // accentInk, niet colorScheme.primary: die is in een donker profiel de
    // donkere merkkleur en valt op de lichte balk weg.
    final accent = AppPalette.of(theme).accentInk;
    return Material(
      color: accent.withValues(alpha: 0.08),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.swap_horiz, size: 16, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.d('Leeg bestand'),
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
            TextButton(
              onPressed: () => switch (toKind) {
                MarkdownKind.presentation => swapEmptyDocumentForDeck(
                  ref.read(tabsProvider.notifier),
                ),
                MarkdownKind.document => swapEmptyDeckForDocument(
                  ref.read(tabsProvider.notifier),
                ),
              },
              child: Text(
                toKind == MarkdownKind.presentation
                    ? l10n.d('Wissel naar presentatie')
                    : l10n.d('Wissel naar document'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
