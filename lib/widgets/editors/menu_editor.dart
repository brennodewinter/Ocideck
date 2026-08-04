import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/slide.dart';
import '../../services/image_service.dart';
import '../../services/menu_blocks.dart';
import '../../state/deck_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/inline_markdown.dart';

/// Editor voor een keuze-menudia (#1162): per blok een label, een doeldia en een
/// optionele afbeelding. De gebruiker kiest een doeldia op kop uit een lijst —
/// het stabiele anker eronder wordt door de app beheerd, nooit getypt.
///
/// De blokken zijn gewone bullets (`[label](#anker)` + optioneel `![](mem:…)`);
/// deze editor leest en schrijft ze via [menu_blocks]. Label en afbeelding
/// veranderen alleen deze dia (via [onUpdate]); een doeldia kiezen raakt óók de
/// doeldia (het anker) en loopt daarom via de deck-notifier.
class MenuEditor extends ConsumerStatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final ImageService imageService;
  final List<String> searchPaths;

  const MenuEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    required this.imageService,
    this.searchPaths = const [],
  });

  @override
  ConsumerState<MenuEditor> createState() => _MenuEditorState();
}

class _MenuEditorState extends ConsumerState<MenuEditor> {
  final _labels = <TextEditingController>[];

  @override
  void initState() {
    super.initState();
    for (final b in menuBlocksFor(widget.slide.bullets)) {
      _labels.add(TextEditingController(text: b.label));
    }
  }

  @override
  void dispose() {
    for (final c in _labels) {
      c.dispose();
    }
    super.dispose();
  }

  List<MenuBlock> get _blocks => menuBlocksFor(widget.slide.bullets);

  void _writeBlocks(List<MenuBlock> blocks) => widget.onUpdate(
    widget.slide.copyWith(
      bullets: [for (final b in blocks) menuBlockToBullet(b)],
    ),
  );

  void _setLabel(int i, String label) {
    final blocks = _blocks;
    if (i >= blocks.length) return;
    blocks[i] = blocks[i].copyWith(label: label);
    _writeBlocks(blocks);
  }

  void _addBlock() {
    final blocks = _blocks..add(const MenuBlock());
    _labels.add(TextEditingController());
    _writeBlocks(blocks);
    setState(() {});
  }

  void _removeBlock(int i) {
    final blocks = _blocks;
    if (i >= blocks.length) return;
    blocks.removeAt(i);
    _labels.removeAt(i).dispose();
    _writeBlocks(blocks);
    setState(() {});
  }

  Future<void> _pickImage(int i) async {
    final path = await widget.imageService.pickImage(
      projectPath: widget.searchPaths.isNotEmpty
          ? widget.searchPaths.first
          : null,
    );
    if (path == null) return;
    final blocks = _blocks;
    if (i >= blocks.length) return;
    blocks[i] = blocks[i].copyWith(imagePath: path);
    _writeBlocks(blocks);
    setState(() {});
  }

  void _clearImage(int i) {
    final blocks = _blocks;
    if (i >= blocks.length) return;
    blocks[i] = blocks[i].copyWith(imagePath: '');
    _writeBlocks(blocks);
    setState(() {});
  }

  int get _menuIndex {
    final deck = ref.read(deckProvider).deck;
    if (deck == null) return -1;
    return deck.slides.indexWhere((s) => s.id == widget.slide.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final deck = ref.watch(deckProvider.select((s) => s.deck));
    final blocks = _blocks;
    final menuIndex = _menuIndex;
    final slides = deck?.slides ?? const <Slide>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _blockRow(context, l10n, i, blocks[i], menuIndex, slides),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addBlock,
            icon: const Icon(Icons.add, size: 16),
            label: Text(l10n.d('Blok toevoegen')),
          ),
        ),
        if (blocks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l10n.d('Nog geen blokken. Voeg een keuzeblok toe.'),
              style: TextStyle(fontSize: 12, color: AppTheme.slate500),
            ),
          ),
      ],
    );
  }

  Widget _blockRow(
    BuildContext context,
    AppLocalizations l10n,
    int i,
    MenuBlock block,
    int menuIndex,
    List<Slide> slides,
  ) {
    // Welke dia is nu het doel (de index in het deck), of null bij geen sprong.
    final targetIndex = block.hasTarget
        ? slides.indexWhere((s) => s.anchor == block.targetAnchor)
        : -1;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.paper,
        border: Border.all(color: AppTheme.slate200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _labels[i],
                  onChanged: (v) => _setLabel(i, v),
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: l10n.d('Label'),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.d('Blok verwijderen'),
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => _removeBlock(i),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.alt_route, size: 15, color: AppTheme.slate500),
              const SizedBox(width: 6),
              Text(
                l10n.d('Springt naar'),
                style: TextStyle(fontSize: 12, color: AppTheme.slate600),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    isDense: true,
                    isExpanded: true,
                    value: targetIndex < 0 ? null : targetIndex,
                    style: TextStyle(fontSize: 12, color: AppTheme.ink),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(l10n.d('Geen sprong')),
                      ),
                      for (var s = 0; s < slides.length; s++)
                        if (s != menuIndex)
                          DropdownMenuItem(
                            value: s,
                            child: Text(
                              '${s + 1}. ${_slideLabel(l10n, slides[s], s)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                    ],
                    onChanged: (target) => ref
                        .read(deckProvider.notifier)
                        .setMenuBlockTarget(menuIndex, i, target),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.image_outlined, size: 15, color: AppTheme.slate500),
              const SizedBox(width: 6),
              if (block.hasImage)
                Expanded(
                  child: Text(
                    block.imagePath.split(RegExp(r'[\\/]')).last,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppTheme.slate600),
                  ),
                )
              else
                Expanded(
                  child: Text(
                    l10n.d('Geen afbeelding'),
                    style: TextStyle(fontSize: 12, color: AppTheme.slate400),
                  ),
                ),
              TextButton(
                onPressed: () => _pickImage(i),
                child: Text(
                  block.hasImage ? l10n.d('Wijzigen') : l10n.d('Kiezen'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (block.hasImage)
                IconButton(
                  tooltip: l10n.d('Afbeelding verwijderen'),
                  icon: const Icon(Icons.clear, size: 16),
                  onPressed: () => _clearImage(i),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _slideLabel(AppLocalizations l10n, Slide s, int i) {
    final title = stripInlineMarkdown(s.title).trim();
    return title.isEmpty ? l10n.d('Dia') : title;
  }
}
