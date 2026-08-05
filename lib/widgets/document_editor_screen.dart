import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/document_provider.dart';
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
    return Scaffold(
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
          return Row(
            children: [
              Expanded(child: editor),
              VerticalDivider(width: 1, thickness: 1, color: divider),
              Expanded(child: preview),
            ],
          );
        },
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
      child: DocumentMarkdownView(source, maxTextWidth: 720),
    ),
  );
}
