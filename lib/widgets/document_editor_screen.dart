import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../models/chart.dart';
import '../models/markdown_kind.dart';
import '../models/markdown_outline.dart';
import '../models/slide.dart';
import '../services/file_service.dart';
import '../state/deck_provider.dart'
    show fileServiceProvider, imageServiceProvider;
import '../state/document_provider.dart';
import '../state/settings_provider.dart' show settingsProvider, SettingsTraces;
import '../utils/doc_link.dart' show headingSlug;
import 'editors/_editor_field.dart' show pickImageWithFeedback;
import 'editors/chart_editor.dart';
import 'editors/table_editor.dart';
import 'markdown_editor/markdown_editor_theme.dart';
import 'markdown_editor/markdown_editor_toolbar.dart';
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

  /// De actieve weergavemodus. [_DocViewMode.source] toont de split (rauwe bron +
  /// live weergave) om tekst te bewerken; [_DocViewMode.visual] maakt de weergave
  /// het hoofdoppervlak, waar je de ingebedde blokken (grafiek/tabel) met een
  /// dubbelklik bewerkt. Standaard bron: dat is waar je tekst typt.
  _DocViewMode _viewMode = _DocViewMode.source;

  /// De focus van de rauwe editor. De opmaak-knoppenbalk geeft de focus hierheen
  /// terug na een klik, zodat je meteen verder typt.
  final FocusNode _editorFocus = FocusNode();

  /// Waar terwijl de controller van *buitenaf* wordt gelijkgetrokken aan de bron
  /// (ongedaan maken/opnieuw, of een invoeging): dan mag de controllerluisteraar
  /// niet terugstromen naar de notifier — dat zou een lus of dubbele bewerking
  /// geven.
  bool _applyingExternal = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(documentProvider).document?.source ?? '',
    );
    // Eén luisteraar vangt élke bronwijziging in de controller — typen én de
    // opmaak-knoppenbalk (die de controller rechtstreeks muteert en dus geen
    // onChanged afvuurt). Zo stroomt alles langs dezelfde weg naar de notifier.
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _editorFocus.dispose();
    _previewScroll.dispose();
    super.dispose();
  }

  /// Stroom een controllerwijziging naar de notifier. Slaat over wanneer de
  /// controller juist van búiten wordt bijgewerkt (`_applyingExternal`), en
  /// wanneer alleen de selectie/cursor verschoof (tekst gelijk) — anders zou een
  /// simpele cursorbeweging een lege bewerking worden.
  void _onControllerChanged() {
    if (_applyingExternal) return;
    final text = _controller.text;
    final current = ref.read(documentProvider).document?.source ?? '';
    if (text == current) return;
    ref.read(documentProvider.notifier).edit(text, coalesceKey: 'doc');
  }

  /// Sla het document op. Cmd/Ctrl+S, net als een deck. Feedback is de dirty-stip
  /// op het tabblad die verdwijnt — geen aparte melding nodig.
  ///
  /// Heeft het al een pad, dan byte-getrouw terug naar dat pad (alleen als er
  /// iets veranderde). Een nog niet opgeslagen document (nieuw, geen pad) valt
  /// terug op 'Opslaan als…': kies een pad, schrijf, en zet het in de recente
  /// lijst — net als een deck.
  Future<void> _save() async {
    final state = ref.read(documentProvider);
    final document = state.document;
    if (document == null) return;
    final path = state.filePath;
    if (path != null) {
      if (!state.isDirty) return;
      if (await saveDocument(document, path) && mounted) {
        ref.read(documentProvider.notifier).markSaved(filePath: path);
      }
      return;
    }
    final saved = await ref.read(fileServiceProvider).saveDocumentAs(document);
    if (saved == null || !mounted) return;
    ref.read(documentProvider.notifier).markSaved(filePath: saved);
    await ref
        .read(settingsProvider.notifier)
        .addRecentFile(saved, kind: MarkdownKind.document);
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
        _applyingExternal = true;
        _controller.value = TextEditingValue(
          text: source,
          selection: TextSelection.collapsed(offset: source.length),
        );
        _applyingExternal = false;
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
        body: Column(
          children: [
            _DocEditorToolbar(
              mode: _viewMode,
              onModeChanged: (m) => setState(() => _viewMode = m),
              onInsertChart: _insertChart,
              onInsertTable: _insertTable,
              onInsertMermaid: _insertMermaid,
              onInsertImage: _insertImage,
              controller: _controller,
              editorFocus: _editorFocus,
            ),
            Divider(height: 1, thickness: 1, color: theme.colorScheme.outlineVariant),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => _viewMode == _DocViewMode.visual
                    ? _visualLayout(theme, source, constraints)
                    : _sourceLayout(theme, source, constraints),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Bron-modus: de rauwe bron en de live weergave naast elkaar op een breed
  /// venster, onder elkaar wanneer het te smal wordt voor twee leesbare kolommen.
  /// De Overzicht-rail komt erbij zodra er breedte genoeg is.
  Widget _sourceLayout(ThemeData theme, String source, BoxConstraints c) {
    final divider = theme.colorScheme.outlineVariant;
    final editor = _editor(theme);
    final preview = _preview(theme, source);
    if (c.maxWidth < 760) {
      return Column(
        children: [
          Expanded(child: editor),
          Divider(height: 1, thickness: 1, color: divider),
          Expanded(child: preview),
        ],
      );
    }
    // Waar een presentatie de diastrook heeft, toont een document zijn koppen —
    // maar alleen als er breedte genoeg is voor rail + twee leesbare kolommen.
    final showRail = c.maxWidth >= 940;
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
  }

  /// Visuele modus: de weergave is het hoofdoppervlak (gecentreerd als een
  /// documentpagina), waar je de ingebedde blokken met een dubbelklik bewerkt.
  /// Geen rauwe editor; voor tekst wissel je terug naar de bron. De Overzicht-rail
  /// blijft naast de weergave zolang er breedte genoeg is.
  Widget _visualLayout(ThemeData theme, String source, BoxConstraints c) {
    final divider = theme.colorScheme.outlineVariant;
    final showRail = c.maxWidth >= 940;
    return Row(
      children: [
        if (showRail) ...[
          _outlineRail(theme, source),
          VerticalDivider(width: 1, thickness: 1, color: divider),
        ],
        Expanded(child: _preview(theme, source, centered: true)),
      ],
    );
  }

  Widget _editor(ThemeData theme) => TextField(
    controller: _controller,
    focusNode: _editorFocus,
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

  Widget _preview(ThemeData theme, String source, {bool centered = false}) => Container(
    color: theme.colorScheme.surface,
    alignment: centered ? Alignment.topCenter : Alignment.topLeft,
    child: SingleChildScrollView(
      controller: _previewScroll,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: DocumentMarkdownView(
        source,
        maxTextWidth: 720,
        anchorBlockIndex: _anchorBlockIndex,
        anchorKey: _anchorKey,
        onEditChart: _editChart,
        onEditTable: _editTable,
      ),
    ),
  );

  /// De gedeelde dialoogschil voor het bewerken van een ingebedde kaart (grafiek
  /// of tabel): de volwaardige editor in een venster met Annuleren/Toepassen
  /// (bestaande l10n). Het venster mikt op 760×560 maar klemt op de
  /// kijkvenstermaat, zodat het ook op een klein of laag scherm past in plaats
  /// van horizontaal over te lopen (de vaste maat kromp zelf niet mee). Geeft
  /// `true` terug bij Toepassen.
  Future<bool?> _embedEditorDialog(Widget editor) {
    final l10n = context.l10n;
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final media = MediaQuery.of(ctx).size;
        final width = math.max(280.0, math.min(760.0, media.width - 96));
        final height = math.max(320.0, math.min(560.0, media.height - 160));
        return AlertDialog(
          contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          content: SizedBox(
            width: width,
            height: height,
            child: SingleChildScrollView(child: editor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.d('Annuleren')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.d('Toepassen')),
            ),
          ],
        );
      },
    );
  }

  /// Dubbelklik op een gerenderde grafiek → de volwaardige [ChartEditor] in een
  /// dialoog (dezelfde editor als een dia, met een wegwerp-[Slide] om zijn bron
  /// vast te houden). 'Toepassen' schrijft het bewerkte ```chart-blok terug op
  /// zijn plek in de bron; de weergave hertekent mee. DOCUMENT_MODE.md §4.2.
  Future<void> _editChart(int chartOrdinal, String block) async {
    var edited = block;
    final slide = Slide.create(SlideType.chart).copyWith(customMarkdown: block);
    final apply = await _embedEditorDialog(
      ChartEditor(
        slide: slide,
        themeAnimationDurationMs: 0,
        nestedInScrollView: true,
        onUpdate: (s) => edited = s.customMarkdown,
      ),
    );
    if (apply != true || !mounted) return;
    final source = ref.read(documentProvider).document?.source ?? '';
    final next = replaceNthChartBlock(source, chartOrdinal, edited);
    if (next != source) {
      ref.read(documentProvider.notifier).edit(next, coalesceKey: null);
    }
  }

  /// Dubbelklik op een gerenderde tabel → de volwaardige [TableEditor] in een
  /// dialoog. De rauwe GFM-regels worden naar een celraster ontleed (via
  /// [DocumentMarkdownView.tableCells]) en in een wegwerp-[Slide] gezet;
  /// 'Toepassen' serialiseert het raster terug naar een GFM-tabel en vervangt
  /// precies dat tabelblok in de bron. DOCUMENT_MODE.md §4.2.
  Future<void> _editTable(int tableOrdinal, List<String> rawRows) async {
    final cells = DocumentMarkdownView.tableCells(rawRows);
    var edited = cells;
    final slide = Slide.create(SlideType.table).copyWith(tableRows: cells);
    final apply = await _embedEditorDialog(
      TableEditor(
        slide: slide,
        nestedInScrollView: true,
        onUpdate: (s) => edited = s.tableRows,
      ),
    );
    if (apply != true || !mounted) return;
    final source = ref.read(documentProvider).document?.source ?? '';
    final next = replaceNthTableBlock(
      source,
      tableOrdinal,
      rowsToGfmTable(edited),
    );
    if (next != source) {
      ref.read(documentProvider.notifier).edit(next, coalesceKey: null);
    }
  }

  /// Voeg [block] als een verse alinea in op de cursorpositie (of achteraan als
  /// er geen selectie is). De pure [insertBlockIntoSource] regelt de lege regels
  /// eromheen; hier zetten we de controller en de bron gelijk en plaatsen we de
  /// cursor ná het blok, zodat je meteen verder kunt typen. Een expliciete
  /// bewerking (`coalesceKey: null`) — geen samenvoeging met eerder typen.
  void _insertBlock(String block) {
    final sel = _controller.selection;
    final (next, cursor) = insertBlockIntoSource(
      _controller.text,
      sel.start,
      sel.end,
      block,
    );
    // Zet de controller (met cursor ná het blok) los van de luisteraar en dien de
    // bewerking als een eigen stap in (`coalesceKey: null`), zodat een invoeging
    // niet met eerder typen samenvloeit in de ongedaan-maken-geschiedenis.
    _applyingExternal = true;
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: cursor),
    );
    _applyingExternal = false;
    ref.read(documentProvider.notifier).edit(next, coalesceKey: null);
  }

  /// Voeg een verse grafiek in: dezelfde [ChartEditor] als een dia (met een
  /// wegwerp-[Slide]), en bij 'Toepassen' een ```chart-blok op de cursorpositie.
  /// Identiek aan het dia-mechanisme — geen tweede grafiekweg (DOCUMENT_MODE.md
  /// §4.2). Zonder ingevulde data blijft het een geldig, later invulbaar blok.
  Future<void> _insertChart() async {
    final slide = Slide.create(SlideType.chart);
    var spec = ChartSpec.parse(slide.customMarkdown).toBlock();
    final apply = await _embedEditorDialog(
      ChartEditor(
        slide: slide,
        themeAnimationDurationMs: 0,
        nestedInScrollView: true,
        onUpdate: (s) => spec = s.customMarkdown,
      ),
    );
    if (apply != true || !mounted) return;
    _insertBlock('```chart\n$spec\n```');
  }

  /// Voeg een verse tabel in: de [TableEditor] met een leeg 2×2-raster, en bij
  /// 'Toepassen' een GFM-pijptabel op de cursorpositie.
  Future<void> _insertTable() async {
    final slide = Slide.create(SlideType.table);
    var rows = slide.tableRows;
    final apply = await _embedEditorDialog(
      TableEditor(
        slide: slide,
        nestedInScrollView: true,
        onUpdate: (s) => rows = s.tableRows,
      ),
    );
    if (apply != true || !mounted) return;
    _insertBlock(rowsToGfmTable(rows));
  }

  /// Voeg een verse ```mermaid-fence in met een minimaal, taal-neutraal
  /// startdiagram (knoop-id's, geen tekst om te vertalen). Bewerken gaat via de
  /// bron — de dubbelklik is voor mermaid bewust overgeslagen (DOCUMENT_MODE.md).
  void _insertMermaid() =>
      _insertBlock('```mermaid\nflowchart TD\n  A --> B\n```');

  /// Voeg een afbeelding in: kies een bestand via de bestaande import-keten
  /// (grootte-cap, magic-bytes, kopie naar `images/` of `mem:` zolang het
  /// document nog niet is opgeslagen) en zet een `![](…)`-verwijzing op de
  /// cursorpositie. Hergebruikt exact de dia-import — geen tweede assetweg.
  Future<void> _insertImage() async {
    final state = ref.read(documentProvider);
    final projectPath = state.filePath == null
        ? null
        : p.dirname(state.filePath!);
    final reference = await pickImageWithFeedback(
      context,
      ref.read(imageServiceProvider),
      projectPath: projectPath,
    );
    if (reference == null || !mounted) return;
    _insertBlock('![]($reference)');
  }

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

/// De weergavemodus van de documenteditor. Twee manieren om naar hetzelfde
/// document te kijken, nooit een derde renderpad (DOCUMENT_MODE.md §2.1): de bron
/// als tekst, of de weergave als hoofdoppervlak.
enum _DocViewMode { visual, source }

/// De werkbalk bovenaan de documenteditor: links de segmentkeuze Visueel | Bron,
/// rechts het invoeg-palet. Top-level widget zodat het bewerkscherm zelf slank
/// blijft; de labels lopen via [l10n] mee met de langste taal (geen vaste
/// breedte, DOCUMENT_MODE.md §8).
class _DocEditorToolbar extends StatelessWidget {
  final _DocViewMode mode;
  final ValueChanged<_DocViewMode> onModeChanged;
  final VoidCallback onInsertChart;
  final VoidCallback onInsertTable;
  final VoidCallback onInsertMermaid;
  final VoidCallback onInsertImage;
  final TextEditingController controller;
  final FocusNode editorFocus;

  const _DocEditorToolbar({
    required this.mode,
    required this.onModeChanged,
    required this.onInsertChart,
    required this.onInsertTable,
    required this.onInsertMermaid,
    required this.onInsertImage,
    required this.controller,
    required this.editorFocus,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SegmentedButton<_DocViewMode>(
                segments: [
                  ButtonSegment(
                    value: _DocViewMode.visual,
                    label: Text(l10n.d('Visueel')),
                    icon: const Icon(Icons.visibility_outlined, size: 15),
                  ),
                  ButtonSegment(
                    value: _DocViewMode.source,
                    label: Text(l10n.d('Bron')),
                    icon: const Icon(Icons.code, size: 15),
                  ),
                ],
                selected: {mode},
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                onSelectionChanged: (s) => onModeChanged(s.first),
              ),
              const Spacer(),
              _insertMenu(l10n),
            ],
          ),
          // De gedeelde opmaak-knoppenbalk (vet/cursief/kop/lijst/…), dezelfde als
          // de deck-markdown-editor. Zit hier in de gedeelde kop zonder eigen
          // kader (`bordered: false`, zoals de knoppenbalk zelf documenteert), en
          // muteert de bron via de controller — de controllerluisteraar stroomt
          // dat door naar de weergave en de opslag.
          MarkdownEditorToolbar(
            controller: controller,
            focusNode: editorFocus,
            theme: MarkdownEditorTheme.documentSurface(scheme: scheme),
            bordered: false,
          ),
        ],
      ),
    );
  }

  /// Het invoeg-palet: één menu dat een rijk blok op de cursorpositie invoegt.
  /// Hergebruikt de bestaande labels (Grafiek/Tabel/Afbeelding); Mermaid is de
  /// productnaam van de fence. Elke keuze schrijft een verse, draagbare
  /// Markdown-constructie in de bron (DOCUMENT_MODE.md §4).
  Widget _insertMenu(AppLocalizations l10n) {
    return PopupMenuButton<int>(
      tooltip: l10n.d('Invoegen'),
      position: PopupMenuPosition.under,
      onSelected: (value) => switch (value) {
        0 => onInsertChart(),
        1 => onInsertTable(),
        2 => onInsertMermaid(),
        _ => onInsertImage(),
      },
      itemBuilder: (context) => [
        _insertItem(0, Icons.bar_chart, l10n.d('Grafiek')),
        _insertItem(1, Icons.table_chart_outlined, l10n.d('Tabel')),
        _insertItem(2, Icons.account_tree_outlined, l10n.d('Mermaid')),
        _insertItem(3, Icons.image_outlined, l10n.d('Afbeelding')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 16),
            const SizedBox(width: 4),
            Text(l10n.d('Invoegen'), style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<int> _insertItem(int value, IconData icon, String label) {
    return PopupMenuItem<int>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 10),
          Text(label),
        ],
      ),
    );
  }
}

/// Voeg [block] in [source] in op het bereik [selStart]–[selEnd] (een negatieve
/// start betekent 'geen cursor' → achteraan), omgeven door precies genoeg lege
/// regels om een eigen alinea te vormen zonder er ooit meer dan één dubbele
/// witregel van te maken. Geeft de nieuwe bron én de cursorpositie ná het
/// ingevoegde blok terug. Top-level en puur, zodat de invoeglogica los toetsbaar
/// is van het editor-scherm — net als de terugschrijf-helpers hierboven.
(String, int) insertBlockIntoSource(
  String source,
  int selStart,
  int selEnd,
  String block,
) {
  final start = selStart < 0 ? source.length : math.min(selStart, selEnd);
  final end = selEnd < 0 ? source.length : math.max(selStart, selEnd);
  final before = source.substring(0, start);
  final after = source.substring(end);
  final lead = before.isEmpty
      ? ''
      : before.endsWith('\n\n')
      ? ''
      : before.endsWith('\n')
      ? '\n'
      : '\n\n';
  final trail = after.isEmpty
      ? '\n'
      : after.startsWith('\n')
      ? ''
      : '\n\n';
  final insertion = '$lead$block$trail';
  return ('$before$insertion$after', before.length + insertion.length);
}

/// De fence van één ```chart-blok, om de `chartOrdinal`-de (vanaf 0) in de bron
/// te vinden en te vervangen. Dezelfde vorm als [MarpHtmlService], zodat wat de
/// weergave telt en wat de editor terugschrijft naar dezelfde blokken wijzen.
final RegExp _documentChartFence = RegExp(
  r'```chart[ \t]*\n([\s\S]*?)\n```',
  multiLine: true,
);

/// Vervang de inhoud van het `chartOrdinal`-de ```chart-blok (vanaf 0) in
/// [source] door [newContent] (de kale spec-tekst, zonder fence). Andere blokken
/// — en alle tekst eromheen — blijven byte-getrouw staan; een `chartOrdinal`
/// buiten bereik laat de bron ongemoeid. Top-level en puur, zodat de
/// terugschrijf-logica los toetsbaar is van het editor-scherm.
String replaceNthChartBlock(
  String source,
  int chartOrdinal,
  String newContent,
) {
  var seen = 0;
  return source.replaceAllMapped(_documentChartFence, (m) {
    if (seen++ != chartOrdinal) return m.group(0)!;
    return '```chart\n$newContent\n```';
  });
}

/// Serialiseer een celraster (eerste rij = koppen) naar een GFM-pijptabel: een
/// koprij, een scheidingsrij en de body. Cellen met een `|` worden ontsnapt naar
/// `\|` zodat ze de kolomgrens niet breken. Ragged rijen worden met lege cellen
/// aangevuld tot de breedste. Uitlijning wordt niet bewaard (de editor kent geen
/// uitlijning); een bewuste vereenvoudiging bij het bewerken van een tabel.
String rowsToGfmTable(List<List<String>> rows) {
  if (rows.isEmpty) return '';
  final cols = rows.fold<int>(1, (m, r) => r.length > m ? r.length : m);
  String cell(List<String> r, int c) =>
      (c < r.length ? r[c] : '').replaceAll('|', r'\|');
  String line(List<String> r) =>
      '| ${List.generate(cols, (c) => cell(r, c)).join(' | ')} |';
  return [
    line(rows.first),
    '| ${List.filled(cols, '---').join(' | ')} |',
    for (final r in rows.skip(1)) line(r),
  ].join('\n');
}

/// Vervang het `tableOrdinal`-de GFM-tabelblok (vanaf 0) in [source] door
/// [newGfm], en laat elke andere byte staan. De regel-reikwijdte komt van
/// [DocumentMarkdownView.nthTableBlockRange], zodat de telling exact die van de
/// weergave volgt; een ordinaal buiten bereik laat de bron ongemoeid. Top-level
/// en puur, zodat de terugschrijf-logica los toetsbaar is.
String replaceNthTableBlock(String source, int tableOrdinal, String newGfm) {
  final range = DocumentMarkdownView.nthTableBlockRange(source, tableOrdinal);
  if (range == null) return source;
  final lines = source.split('\n');
  lines.replaceRange(range[0], range[1], newGfm.split('\n'));
  return lines.join('\n');
}
