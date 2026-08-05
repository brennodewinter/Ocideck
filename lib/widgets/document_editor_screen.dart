import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../models/markdown_outline.dart';
import '../services/file_service.dart';
import '../state/document_provider.dart';
import '../utils/doc_link.dart' show headingSlug;
import 'reader/document_markdown_view.dart';

/// De schermvullende editor voor een documenttabblad: links de platte
/// Markdown-bron, rechts een live weergave. De bron *ís* de waarheid — elke
/// toetsaanslag stroomt direct naar de [DocumentNotifier] (geen 'Toepassen'-muur,
/// DOCUMENT_MODE.md §1.1), en de weergave hertekent mee.
///
/// Bewust nog kaal: dit is de rauw+preview-basis. De visuele (WYSIWYG) modus met
/// ingebedde kaarten, het invoeg-palet en de Overzicht-rail komen er in latere
/// fasen omheen — dit oppervlak is de spil waar ze op landen.
class DocumentEditorScreen extends ConsumerStatefulWidget {
  const DocumentEditorScreen({super.key});

  @override
  ConsumerState<DocumentEditorScreen> createState() =>
      _DocumentEditorScreenState();
}

class _DocumentEditorScreenState extends ConsumerState<DocumentEditorScreen> {
  late final TextEditingController _controller;
  final ScrollController _previewScroll = ScrollController();

  /// De kop waar de Overzicht-rail naartoe scrollt: het blokindexnummer in de
  /// weergave dat [_anchorKey] draagt, of -1. Dezelfde één-verplaatsende-sleutel
  /// als de docs-lezer, zodat `ensureVisible` betrouwbaar landt.
  final GlobalKey _anchorKey = GlobalKey();
  int _anchorBlockIndex = -1;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(documentProvider).document?.source ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _previewScroll.dispose();
    super.dispose();
  }

  /// Sla het document byte-getrouw op naar zijn eigen pad. Cmd/Ctrl+S, net als
  /// een deck. Feedback is de dirty-stip op het tabblad die verdwijnt — geen
  /// aparte melding nodig. Een nog niet opgeslagen document (geen pad) kan pas
  /// worden bewaard zodra 'Opslaan als…' er is; tot dan is dit een no-op.
  Future<void> _save() async {
    final state = ref.read(documentProvider);
    final path = state.filePath;
    final document = state.document;
    if (path == null || document == null || !state.isDirty) return;
    if (await saveDocument(document, path) && mounted) {
      ref.read(documentProvider.notifier).markSaved(filePath: path);
    }
  }

  /// Scroll de weergave naar de aangeklikte kop uit de Overzicht-rail. Hergebruikt
  /// het anker-mechanisme van [DocumentMarkdownView]: markeer het blok via
  /// setState zodat [_anchorKey] deze frame aanhecht, en scroll het daarna in
  /// beeld — dezelfde route als de docs-lezer, die betrouwbaar landt.
  void _scrollToHeading(MarkdownOutlineEntry entry) {
    final source = ref.read(documentProvider).document?.source ?? '';
    final index = DocumentMarkdownView.headingBlockIndex(
      source,
      headingSlug(entry.title),
    );
    if (index < 0) return;
    setState(() => _anchorBlockIndex = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _anchorKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.08,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Wanneer de bron van búiten de editor verandert (ongedaan maken/opnieuw),
    // de controller bijwerken. Bij gewoon typen is de bron na de `edit` al gelijk
    // aan de controllertekst, dus dan doet dit niets — geen terugkoppellus.
    ref.listen(documentProvider.select((s) => s.document?.source ?? ''), (
      _,
      source,
    ) {
      if (source != _controller.text) {
        _controller.value = TextEditingValue(
          text: source,
          selection: TextSelection.collapsed(offset: source.length),
        );
      }
    });
    final source = ref.watch(
      documentProvider.select((s) => s.document?.source ?? ''),
    );
    final theme = Theme.of(context);
    return CallbackShortcuts(
      bindings: {
        // Cmd op macOS, Ctrl elders — net als het opslaan van een deck.
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            unawaited(_save()),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            unawaited(_save()),
      },
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final divider = theme.colorScheme.outlineVariant;
            final editor = _editor(theme);
            final preview = _preview(theme, source);
            // Naast elkaar op een breed venster; onder elkaar wanneer het te smal
            // wordt voor twee leesbare kolommen.
            if (constraints.maxWidth < 760) {
              return Column(
                children: [
                  Expanded(child: editor),
                  Divider(height: 1, thickness: 1, color: divider),
                  Expanded(child: preview),
                ],
              );
            }
            // Waar een presentatie de diastrook heeft, toont een document zijn
            // koppen — maar alleen als er breedte genoeg is voor rail + twee
            // leesbare kolommen ernaast.
            final showRail = constraints.maxWidth >= 940;
            return Row(
              children: [
                if (showRail) ...[
                  _outlineRail(theme, source),
                  VerticalDivider(width: 1, thickness: 1, color: divider),
                ],
                Expanded(child: editor),
                VerticalDivider(width: 1, thickness: 1, color: divider),
                Expanded(child: preview),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _editor(ThemeData theme) => TextField(
    controller: _controller,
    onChanged: (text) =>
        ref.read(documentProvider.notifier).edit(text, coalesceKey: 'doc'),
    maxLines: null,
    expands: true,
    textAlignVertical: TextAlignVertical.top,
    cursorColor: theme.colorScheme.primary,
    keyboardType: TextInputType.multiline,
    style: TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
      fontSize: 14,
      height: 1.5,
      color: theme.colorScheme.onSurface,
    ),
    decoration: const InputDecoration(
      border: InputBorder.none,
      contentPadding: EdgeInsets.all(16),
    ),
  );

  Widget _preview(ThemeData theme, String source) => Container(
    color: theme.colorScheme.surface,
    alignment: Alignment.topLeft,
    child: SingleChildScrollView(
      controller: _previewScroll,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: DocumentMarkdownView(
        source,
        maxTextWidth: 720,
        anchorBlockIndex: _anchorBlockIndex,
        anchorKey: _anchorKey,
      ),
    ),
  );

  /// De Overzicht-rail: de koppen van het document, live afgeleid, klikbaar om
  /// naar die kop in de weergave te scrollen. Leeg document → lege rail.
  Widget _outlineRail(ThemeData theme, String source) {
    final outline = buildMarkdownOutline(source);
    return SizedBox(
      width: 216,
      child: Container(
        color: theme.colorScheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
              child: Text(
                context.l10n.d('Overzicht').toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: outline.length,
                itemBuilder: (context, i) => _outlineItem(theme, outline[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _outlineItem(ThemeData theme, MarkdownOutlineEntry entry) => InkWell(
    onTap: () => _scrollToHeading(entry),
    child: Padding(
      padding: EdgeInsets.only(
        left: 16 + (entry.level - 1).clamp(0, 5) * 12.0,
        right: 10,
        top: 5,
        bottom: 5,
      ),
      child: Text(
        entry.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: entry.level <= 1 ? 13 : 12.5,
          fontWeight: entry.level <= 1 ? FontWeight.w600 : FontWeight.w400,
          color: entry.level <= 1
              ? theme.colorScheme.onSurface
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}
