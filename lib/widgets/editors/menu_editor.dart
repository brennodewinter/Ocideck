import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/menu.dart';
import '../../models/slide.dart';
import '../../services/image_service.dart';
import '../../services/menu_blocks.dart';
import '../../state/deck_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/inline_markdown.dart';
import '_editor_field.dart';

part 'menu_editor_block.dart';

/// Editor voor een keuze-menudia (#1162): de indeling van de dia, en per blok een
/// label, een uitleg, een doeldia en een optionele afbeelding. De gebruiker kiest
/// een doeldia op kop uit een lijst — het stabiele anker eronder wordt door de
/// app beheerd, nooit getypt.
///
/// De blokken zijn gewone bullets (`[label](#anker) — uitleg` + optioneel
/// `![](mem:…)`), categorieën zijn tussenkop-bullets; deze editor leest en
/// schrijft ze via [menu_blocks]. Label, uitleg, afbeelding en indeling
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

/// Hoe ver de blokken onder een categoriekop inspringen: de breedte van het
/// mappictogram in die kop plus de ruimte erachter, zodat een blokkaart precies
/// onder het naamveld begint.
const double _menuCategoryInset = 22;

class _MenuEditorState extends ConsumerState<MenuEditor> {
  /// Tekstvelden per blok, in dezelfde volgorde als [_blocks] — dus dwars door
  /// de categorieën heen doorgeteld. Bij invoegen, verwijderen en verplaatsen
  /// schuiven ze met de blokken mee, zodat de cursor nooit in een ander veld
  /// belandt.
  final _labels = <TextEditingController>[];
  final _descriptions = <TextEditingController>[];

  /// Tekstveld per categorienaam.
  final _categoryNames = <TextEditingController>[];

  @override
  void initState() {
    super.initState();
    for (final b in _blocks) {
      _labels.add(TextEditingController(text: b.label));
      _descriptions.add(TextEditingController(text: b.description));
    }
    for (final c in _categories) {
      _categoryNames.add(TextEditingController(text: c.label));
    }
  }

  @override
  void dispose() {
    for (final c in [..._labels, ..._descriptions, ..._categoryNames]) {
      c.dispose();
    }
    super.dispose();
  }

  List<MenuBlock> get _blocks => menuBlocksFor(widget.slide.bullets);
  List<MenuCategory> get _categories => menuCategoriesFor(widget.slide.bullets);

  /// De doorlopende blokindex van blok [i] in categorie [cat] — de index waarop
  /// [_labels], [_descriptions] en de deck-notifier rekenen.
  int _flatIndex(List<MenuCategory> categories, int cat, int i) {
    var flat = 0;
    for (var c = 0; c < cat; c++) {
      flat += categories[c].blocks.length;
    }
    return flat + i;
  }

  void _writeCategories(List<MenuCategory> categories) => widget.onUpdate(
    widget.slide.copyWith(bullets: menuBulletsFrom(categories)),
  );

  /// Vervang blok [flat] door [make] van het huidige blok.
  void _updateBlock(int flat, MenuBlock Function(MenuBlock) make) {
    final categories = _categories;
    var seen = 0;
    for (var c = 0; c < categories.length; c++) {
      final blocks = categories[c].blocks;
      if (flat < seen + blocks.length) {
        final updated = List<MenuBlock>.from(blocks);
        updated[flat - seen] = make(updated[flat - seen]);
        categories[c] = MenuCategory(
          label: categories[c].label,
          blocks: updated,
        );
        _writeCategories(categories);
        return;
      }
      seen += blocks.length;
    }
  }

  void _addBlock(int cat) {
    final categories = _categories;
    final flat = _flatIndex(categories, cat, categories[cat].blocks.length);
    categories[cat] = MenuCategory(
      label: categories[cat].label,
      blocks: [...categories[cat].blocks, const MenuBlock()],
    );
    _labels.insert(flat, TextEditingController());
    _descriptions.insert(flat, TextEditingController());
    _writeCategories(categories);
    setState(() {});
  }

  void _removeBlock(int cat, int i) {
    final categories = _categories;
    final flat = _flatIndex(categories, cat, i);
    categories[cat] = MenuCategory(
      label: categories[cat].label,
      blocks: [...categories[cat].blocks]..removeAt(i),
    );
    _labels.removeAt(flat).dispose();
    _descriptions.removeAt(flat).dispose();
    _writeCategories(categories);
    setState(() {});
  }

  /// Verplaats blok [i] uit categorie [cat] naar het eind van categorie [to].
  void _moveBlock(int cat, int i, int to) {
    if (to == cat) return;
    final categories = _categories;
    final from = _flatIndex(categories, cat, i);
    final block = categories[cat].blocks[i];
    categories[cat] = MenuCategory(
      label: categories[cat].label,
      blocks: [...categories[cat].blocks]..removeAt(i),
    );
    categories[to] = MenuCategory(
      label: categories[to].label,
      blocks: [...categories[to].blocks, block],
    );
    final target = _flatIndex(categories, to, categories[to].blocks.length - 1);
    _labels.insert(target, _labels.removeAt(from));
    _descriptions.insert(target, _descriptions.removeAt(from));
    _writeCategories(categories);
    setState(() {});
  }

  void _addCategory(String name) {
    final categories = _categories;
    // De eerste keer krijgt de bestaande, naamloze groep ook een naam — anders
    // zou de balk beginnen met een categorie die niemand benoemd heeft.
    if (categories.length == 1 && !categories.first.isNamed) {
      categories[0] = MenuCategory(
        label: context.l10n.d('Algemeen'),
        blocks: categories.first.blocks,
      );
      _categoryNames[0].text = categories[0].label;
    }
    categories.add(MenuCategory(label: name));
    _categoryNames.add(TextEditingController(text: name));
    _writeCategories(categories);
    setState(() {});
  }

  void _renameCategory(int cat, String name) {
    final categories = _categories;
    categories[cat] = MenuCategory(label: name, blocks: categories[cat].blocks);
    _writeCategories(categories);
  }

  /// Een categorie opheffen. De blokken erin gaan naar de vorige categorie —
  /// werk weggooien omdat iemand een kopje weghaalt, is nooit wat hij bedoelde.
  void _removeCategory(int cat) {
    final categories = _categories;
    if (categories.length < 2) return;
    final into = cat == 0 ? 1 : cat - 1;
    categories[into] = MenuCategory(
      label: categories[into].label,
      blocks: cat == 0
          ? [...categories[cat].blocks, ...categories[into].blocks]
          : [...categories[into].blocks, ...categories[cat].blocks],
    );
    categories.removeAt(cat);
    _categoryNames.removeAt(cat).dispose();
    // De blokken zelf blijven bestaan en houden hun onderlinge volgorde alleen
    // dan niet als de eerste categorie verdwijnt; hun tekstvelden volgen die
    // volgorde, dus die bouwen we opnieuw op uit wat er nu staat.
    if (cat == 0) _rebuildControllersFrom(categories);
    _writeCategories(categories);
    setState(() {});
  }

  void _rebuildControllersFrom(List<MenuCategory> categories) {
    final blocks = [for (final c in categories) ...c.blocks];
    for (final c in [..._labels, ..._descriptions]) {
      c.dispose();
    }
    _labels
      ..clear()
      ..addAll(blocks.map((b) => TextEditingController(text: b.label)));
    _descriptions
      ..clear()
      ..addAll(blocks.map((b) => TextEditingController(text: b.description)));
  }

  Future<void> _pickImage(int flat) async {
    final path = await widget.imageService.pickImage(
      projectPath: widget.searchPaths.isNotEmpty
          ? widget.searchPaths.first
          : null,
    );
    if (path == null) return;
    _updateBlock(flat, (b) => b.copyWith(imagePath: path));
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
    final categories = _categories;
    final slides = deck?.slides ?? const <Slide>[];
    // De tekstvelden overleven een herbouw van buitenaf (bijvoorbeeld ongedaan
    // maken); loopt hun aantal uit de pas met de dia, dan winnen de bullets.
    if (_categoryNames.length != categories.length ||
        _labels.length != [for (final c in categories) ...c.blocks].length) {
      _resyncControllers(categories);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _layoutPicker(l10n),
        const SizedBox(height: 16),
        for (var c = 0; c < categories.length; c++)
          _categorySection(context, l10n, c, categories, slides),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () =>
                _addCategory('${l10n.d('Categorie')} ${categories.length + 1}'),
            icon: const Icon(Icons.folder_outlined, size: 16),
            label: Text(l10n.d('Categorie toevoegen')),
          ),
        ),
        if (_blocks.isEmpty)
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

  void _resyncControllers(List<MenuCategory> categories) {
    for (final c in _categoryNames) {
      c.dispose();
    }
    _categoryNames
      ..clear()
      ..addAll(categories.map((c) => TextEditingController(text: c.label)));
    _rebuildControllersFrom(categories);
  }

  /// De indelingskeuze: raster, onder elkaar of in een cirkel. Bovenaan, want
  /// het is de vorm waarin alles eronder verschijnt.
  Widget _layoutPicker(AppLocalizations l10n) {
    final options = <(MenuLayout, String, IconData)>[
      (MenuLayout.grid, l10n.d('Raster'), Icons.grid_view_outlined),
      (MenuLayout.list, l10n.d('Onder elkaar'), Icons.view_list_outlined),
      // Bewust niet `Cirkel`: die bronstring is elders het cirkel*diagram*, en
      // vertaalt in het Engels naar "Pie" — een menu-indeling heet geen taart.
      (MenuLayout.circle, l10n.d('In een cirkel'), Icons.donut_large_outlined),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(l10n.d('Indeling')),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (layout, label, icon) in options)
              ChoiceChip(
                avatar: Icon(icon, size: 16),
                label: Text(label),
                selected: widget.slide.menuLayout == layout,
                onSelected: (_) =>
                    widget.onUpdate(widget.slide.copyWith(menuLayout: layout)),
              ),
          ],
        ),
      ],
    );
  }

  /// Eén categorie: de naam (alleen als er meer dan één is), de blokken erin en
  /// de knop om er een blok bij te zetten.
  Widget _categorySection(
    BuildContext context,
    AppLocalizations l10n,
    int cat,
    List<MenuCategory> categories,
    List<Slide> slides,
  ) {
    final blocks = categories[cat].blocks;
    final named = categories.length > 1 || categories[cat].isNamed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (named) _categoryHeader(l10n, cat, categories),
        for (var i = 0; i < blocks.length; i++)
          Padding(
            // Inspringen onder een categoriekop: zonder dat staan de kop en de
            // blokken eronder even ver naar links en is de indeling visueel plat
            // (#1162, beeldkeuring). De maat is niet vrij gekozen — de kop begint
            // met een pictogram van 16 met 6 ernaast, dus op [_menuCategoryInset]
            // staat de blokkaart precies onder het naamveld in plaats van er
            // links van uit te steken.
            padding: EdgeInsets.only(
              bottom: 8,
              left: named ? _menuCategoryInset : 0,
            ),
            child: _MenuBlockRow(
              block: blocks[i],
              label: _labels[_flatIndex(categories, cat, i)],
              description: _descriptions[_flatIndex(categories, cat, i)],
              categories: categories,
              categoryIndex: cat,
              slides: slides,
              menuIndex: _menuIndex,
              onLabel: (v) => _updateBlock(
                _flatIndex(categories, cat, i),
                (b) => b.copyWith(label: v),
              ),
              onDescription: (v) => _updateBlock(
                _flatIndex(categories, cat, i),
                (b) => b.copyWith(description: v),
              ),
              onTarget: (target) => ref
                  .read(deckProvider.notifier)
                  .setMenuBlockTarget(
                    _menuIndex,
                    _flatIndex(categories, cat, i),
                    target,
                  ),
              onCategory: (to) => _moveBlock(cat, i, to),
              onPickImage: () => _pickImage(_flatIndex(categories, cat, i)),
              onClearImage: () => _updateBlock(
                _flatIndex(categories, cat, i),
                (b) => b.copyWith(imagePath: ''),
              ),
              onRemove: () => _removeBlock(cat, i),
            ),
          ),
        Padding(
          padding: EdgeInsets.only(left: named ? _menuCategoryInset : 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _addBlock(cat),
              icon: const Icon(Icons.add, size: 16),
              label: Text(l10n.d('Blok toevoegen')),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _categoryHeader(
    AppLocalizations l10n,
    int cat,
    List<MenuCategory> categories,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Icon(Icons.folder_outlined, size: 16, color: AppTheme.slate500),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: _categoryNames[cat],
            onChanged: (v) => _renameCategory(cat, v),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              isDense: true,
              labelText: l10n.d('Categorie'),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        if (categories.length > 1)
          IconButton(
            tooltip: l10n.d('Categorie opheffen (blokken blijven behouden)'),
            icon: const Icon(Icons.folder_off_outlined, size: 18),
            onPressed: () => _removeCategory(cat),
          ),
      ],
    ),
  );
}
