// Part of the document_editor_screen library — see ../document_editor_screen.dart.
// De werkbalk is een op zichzelf staande, privé widget; hier apart zodat het
// bewerkscherm zelf onder zijn regelplafond blijft. Alle imports leven in het
// hoofdbestand.
part of '../document_editor_screen.dart';

/// De werkbalk bovenaan de documenteditor: links de segmentkeuze Visueel | Bron,
/// rechts het invoeg-palet. Top-level widget zodat het bewerkscherm zelf slank
/// blijft; de labels lopen via [l10n] mee met de langste taal (geen vaste
/// breedte, DOCUMENT_MODE.md §8).
class _DocEditorToolbar extends StatelessWidget {
  final _DocViewMode mode;
  final ValueChanged<_DocViewMode> onModeChanged;

  /// Staan de pagina-einden in de schrijfstand aan, en de schakelaar ervoor.
  /// Alleen zichtbaar in de visuele stand: in de bron zijn er geen blokken om
  /// aan te meten, en de Pagina's-stand ís al pagina's.
  final bool showPageBreaks;
  final ValueChanged<bool> onShowPageBreaksChanged;

  /// Op welke breedte je schrijft, en de keuze ervoor. Alleen in de visuele
  /// stand: de bron heeft geen schrijfvlak met een maat, en een vel heeft er
  /// zelf al een.
  final DocumentEditorWidth width;
  final ValueChanged<DocumentEditorWidth> onWidthChanged;

  /// De zoomfactor van het schrijfvlak (visueel) of het vel (Pagina's), en de
  /// knoppen ervoor. 1,0 is ware grootte.
  final double zoom;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onInsertChart;
  final VoidCallback onInsertTable;
  final VoidCallback onInsertMermaid;
  final VoidCallback onInsertImage;
  final VoidCallback onInsertPageBreak;
  final VoidCallback onInsertToc;
  final VoidCallback onInsertFootnote;

  /// Staan de voetnoten van dít document achterin in plaats van onderaan de
  /// bladzijde, en de omschakeling ervoor. De keuze landt in de front matter
  /// van het document zelf.
  final bool footnotesAtEnd;
  final ValueChanged<bool> onFootnotesAtEndChanged;

  /// Zet in één keer een `---` vóór elk hoofdstuk (`H1`) behalve het eerste.
  /// Geen invoeging op de cursor maar een bewerking van het hele document —
  /// daarom onder een eigen scheiding in het palet.
  final VoidCallback onApplyChapterBreaks;
  final VoidCallback onPaste;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback onExport;
  final VoidCallback onOpenSettings;
  final VoidCallback onConvertToPresentation;
  final TextEditingController controller;
  final FocusNode editorFocus;

  /// Het schrijfoppervlak-thema (met het stijl-lettertype), voor de opmaakbalk
  /// in Bron zodat die met het gekozen lettertype meeloopt.
  final MarkdownEditorTheme docTheme;

  /// De namen van de beschikbare stijlprofielen, voor de Stijl-kiezer.
  final List<String> styleNames;

  /// De per-document gekozen stijl (of `null` = Geen/platte tekst).
  final String? currentStyleName;

  /// Of een huisstijl via de instellingen wordt afgedwongen; dan is de kiezer
  /// vergrendeld en toont hij [enforcedStyleName].
  final bool styleEnforced;
  final String? enforcedStyleName;

  /// Zet (of wist met `null`) de documentstijl.
  final ValueChanged<String?> onStyleChanged;

  const _DocEditorToolbar({
    required this.mode,
    required this.onModeChanged,
    required this.showPageBreaks,
    required this.onShowPageBreaksChanged,
    required this.width,
    required this.onWidthChanged,
    required this.zoom,
    required this.onZoomChanged,
    required this.onInsertChart,
    required this.onInsertTable,
    required this.onInsertMermaid,
    required this.onInsertImage,
    required this.onInsertPageBreak,
    required this.onInsertToc,
    required this.onInsertFootnote,
    required this.footnotesAtEnd,
    required this.onFootnotesAtEndChanged,
    required this.onApplyChapterBreaks,
    required this.onPaste,
    required this.onUndo,
    required this.onRedo,
    required this.onExport,
    required this.onOpenSettings,
    required this.onConvertToPresentation,
    required this.controller,
    required this.editorFocus,
    required this.docTheme,
    required this.styleNames,
    required this.currentStyleName,
    required this.styleEnforced,
    required this.enforcedStyleName,
    required this.onStyleChanged,
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
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      SegmentedButton<_DocViewMode>(
                        segments: [
                          ButtonSegment(
                            value: _DocViewMode.visual,
                            label: Text(l10n.d('Visueel')),
                            icon: const Icon(
                              Icons.visibility_outlined,
                              size: 15,
                            ),
                          ),
                          ButtonSegment(
                            value: _DocViewMode.source,
                            label: Text(l10n.d('Bron')),
                            icon: const Icon(Icons.code, size: 15),
                          ),
                          ButtonSegment(
                            value: _DocViewMode.pages,
                            label: Text(l10n.d("Pagina's")),
                            icon: const Icon(
                              Icons.menu_book_outlined,
                              size: 15,
                            ),
                          ),
                        ],
                        selected: {mode},
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                        ),
                        onSelectionChanged: (s) => onModeChanged(s.first),
                      ),
                      if (mode == _DocViewMode.visual) ...[
                        const SizedBox(width: 8),
                        _widthMenu(l10n),
                        IconButton(
                          tooltip: width == DocumentEditorWidth.page
                              ? (showPageBreaks
                                    ? l10n.d('Pagina-einden verbergen')
                                    : l10n.d('Pagina-einden tonen'))
                              // Op een andere breedte breekt het vel ergens
                              // anders dan de lijn zou aanwijzen; hem dan tonen
                              // zou een onwaarheid tekenen.
                              : l10n.d(
                                  'Pagina-einden gelden alleen op paginabreedte.',
                                ),
                          onPressed: width == DocumentEditorWidth.page
                              ? () => onShowPageBreaksChanged(!showPageBreaks)
                              : null,
                          icon: Icon(
                            showPageBreaks && width == DocumentEditorWidth.page
                                ? Icons.horizontal_split
                                : Icons.horizontal_split_outlined,
                            size: 18,
                          ),
                          isSelected:
                              showPageBreaks &&
                              width == DocumentEditorWidth.page,
                        ),
                      ],
                      if (mode != _DocViewMode.source) ...[
                        const SizedBox(width: 8),
                        ..._zoomControls(l10n),
                      ],
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: l10n.d('Ongedaan maken'),
                        onPressed: onUndo,
                        icon: const Icon(Icons.undo, size: 18),
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        tooltip: l10n.d('Opnieuw'),
                        onPressed: onRedo,
                        icon: const Icon(Icons.redo, size: 18),
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 8),
                      _insertMenu(l10n),
                      const SizedBox(width: 4),
                      _styleMenu(l10n),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        onPressed: onExport,
                        icon: const Icon(Icons.ios_share, size: 16),
                        label: Text(l10n.d('Exporteren…')),
                      ),
                    ],
                  ),
                ),
              ),
              // Het overloopmenu staat buiten de schuivende rij: het is de
              // enige route naar Instellingen in documentmodus, en meeschuiven
              // maakte hem onbereikbaar zodra er een knop bij kwam en de rij
              // breder werd dan het venster.
              _moreMenu(l10n),
            ],
          ),
          // Opmaak-knoppenbalk alleen in bron-modus: in Visueel heeft
          // MarkdownNotesEditor zijn eigen balk (Quill of markdown). Twee
          // balkjes op één controller zouden uit de pas lopen.
          if (mode == _DocViewMode.source)
            MarkdownEditorToolbar(
              controller: controller,
              focusNode: editorFocus,
              theme: docTheme,
              bordered: false,
              onInsertImage: onInsertImage,
            ),
        ],
      ),
    );
  }

  /// De breedtekiezer: op de breedte van het vel, op een rustige leeskolom, of
  /// het hele venster.
  ///
  /// Hoort in de werkbalk en niet (alleen) in de instellingen, omdat het een
  /// keuze is die je tijdens het schrijven maakt: even het hele scherm voor een
  /// brede tabel, en daarna terug naar het vel. In de instellingen stond hij
  /// bovendien stil te wezen — de pagina-einden overschreven hem.
  Widget _widthMenu(AppLocalizations l10n) {
    String label(DocumentEditorWidth value) => switch (value) {
      DocumentEditorWidth.page => l10n.d('Paginabreedte'),
      DocumentEditorWidth.column => l10n.d('Leeskolom'),
      DocumentEditorWidth.full => l10n.d('Volledige breedte'),
    };
    IconData icon(DocumentEditorWidth value) => switch (value) {
      DocumentEditorWidth.page => Icons.description_outlined,
      DocumentEditorWidth.column => Icons.view_agenda_outlined,
      DocumentEditorWidth.full => Icons.width_normal,
    };
    return PopupMenuButton<DocumentEditorWidth>(
      tooltip: l10n.d('Schrijfbreedte'),
      position: PopupMenuPosition.under,
      onSelected: onWidthChanged,
      itemBuilder: (context) => [
        for (final value in DocumentEditorWidth.values)
          PopupMenuItem<DocumentEditorWidth>(
            value: value,
            child: Row(
              children: [
                Icon(value == width ? Icons.check : icon(value), size: 17),
                const SizedBox(width: 10),
                Expanded(child: Text(label(value))),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Icon(icon(width), size: 18),
      ),
    );
  }

  /// Kleiner, groter, en — alleen wanneer je niet op ware grootte staat — het
  /// huidige percentage als knop terug naar 100%.
  ///
  /// Het percentage is zelf die knop: een aparte terugzetknop ernaast zou drie
  /// knoppen maken van iets wat er twee waardevol heeft, en het getal is de
  /// plek waar je kijkt als je je afvraagt hoe ver je bent afgedwaald. Op 100%
  /// staat er niets: er valt dan niets terug te zetten, en de werkbalk heeft
  /// die breedte hard nodig — hij schuift al op een smal venster.
  List<Widget> _zoomControls(AppLocalizations l10n) {
    const step = kDocumentEditorZoomStep;
    return [
      IconButton(
        tooltip: l10n.d('Uitzoomen'),
        onPressed: zoom > kDocumentEditorZoomMin + 1e-6
            ? () => onZoomChanged(zoom - step)
            : null,
        icon: const Icon(Icons.zoom_out, size: 18),
        visualDensity: VisualDensity.compact,
      ),
      if (zoom != 1)
        Tooltip(
          message: l10n.d('Ware grootte'),
          child: TextButton(
            onPressed: () => onZoomChanged(1),
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 32),
              padding: EdgeInsets.zero,
            ),
            child: Text(
              '${(zoom * 100).round()}%',
              style: const TextStyle(
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      IconButton(
        tooltip: l10n.d('Inzoomen'),
        onPressed: zoom < kDocumentEditorZoomMax - 1e-6
            ? () => onZoomChanged(zoom + step)
            : null,
        icon: const Icon(Icons.zoom_in, size: 18),
        visualDensity: VisualDensity.compact,
      ),
    ];
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
        3 => onInsertImage(),
        5 => onInsertPageBreak(),
        6 => onInsertToc(),
        7 => onApplyChapterBreaks(),
        8 => onInsertFootnote(),
        _ => onPaste(),
      },
      itemBuilder: (context) => [
        _insertItem(0, Icons.bar_chart, l10n.d('Grafiek')),
        _insertItem(1, Icons.table_chart_outlined, l10n.d('Tabel')),
        _insertItem(2, Icons.account_tree_outlined, l10n.d('Mermaid')),
        _insertItem(3, Icons.image_outlined, l10n.d('Afbeelding')),
        _insertItem(
          5,
          Icons.insert_page_break_outlined,
          l10n.d('Pagina-einde'),
        ),
        _insertItem(6, Icons.list_outlined, l10n.d('Inhoudsopgave')),
        _insertItem(8, Icons.superscript, l10n.d('Voetnoot')),
        const PopupMenuDivider(),
        _insertItem(
          7,
          Icons.auto_stories_outlined,
          l10n.d('Hoofdstukken op nieuwe pagina'),
        ),
        const PopupMenuDivider(),
        _insertItem(4, Icons.content_paste, l10n.d('Plakken')),
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

  /// De Stijl-kiezer: kies één documentbreed stijlprofiel (lettertype + opmaak),
  /// of 'Geen' voor platte tekst. De keuze landt byte-chirurgisch als `theme:` in
  /// de frontmatter en stuurt de weergave én de export (DOCUMENT_MODE.md). Onder
  /// een via de instellingen afgedwongen huisstijl is de kiezer vergrendeld en
  /// toont hij de afgedwongen stijl.
  Widget _styleMenu(AppLocalizations l10n) {
    final geen = l10n.d('Geen');
    if (styleEnforced) {
      return Tooltip(
        message: l10n.d(
          'De documentstijl wordt afgedwongen via de instellingen.',
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 15),
              const SizedBox(width: 4),
              Text(
                '${l10n.d('Stijl')}: ${enforcedStyleName ?? geen}',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    return PopupMenuButton<String>(
      tooltip: l10n.d('Documentstijl'),
      position: PopupMenuPosition.under,
      onSelected: (value) => onStyleChanged(value.isEmpty ? null : value),
      itemBuilder: (context) => [
        _styleItem('', l10n.d('Geen (platte tekst)'), currentStyleName == null),
        const PopupMenuDivider(),
        for (final name in styleNames)
          _styleItem(name, name, currentStyleName == name),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.font_download_outlined, size: 16),
            const SizedBox(width: 4),
            Text(
              '${l10n.d('Stijl')}: ${currentStyleName ?? geen}',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _styleItem(String value, String label, bool selected) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(selected ? Icons.check : Icons.style_outlined, size: 17),
          const SizedBox(width: 10),
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  /// Het overloopmenu rechts: Instellingen (anders alleen via macOS-menubalk
  /// bereikbaar in documentmodus) en conversie naar presentatie.
  Widget _moreMenu(AppLocalizations l10n) {
    return PopupMenuButton<int>(
      tooltip: l10n.t('more'),
      position: PopupMenuPosition.under,
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (value) {
        switch (value) {
          case 0:
            onOpenSettings();
          case 1:
            onConvertToPresentation();
          case 2:
            onFootnotesAtEndChanged(!footnotesAtEnd);
        }
      },
      itemBuilder: (context) => [
        // De plaatsing van de voetnoten is een eigenschap van dít document en
        // landt in zijn front matter; daarom hier en niet bij de instellingen.
        PopupMenuItem<int>(
          value: 2,
          child: Row(
            children: [
              Icon(
                footnotesAtEnd
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
                size: 17,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.d('Voetnoten achterin het document'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<int>(
          value: 0,
          child: Row(
            children: [
              const Icon(Icons.settings_outlined, size: 17),
              const SizedBox(width: 10),
              Expanded(child: Text(l10n.t('settings'))),
            ],
          ),
        ),
        PopupMenuItem<int>(
          value: 1,
          child: Row(
            children: [
              const Icon(Icons.slideshow_outlined, size: 17),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.d('Converteer naar presentatie…'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  PopupMenuItem<int> _insertItem(int value, IconData icon, String label) {
    return PopupMenuItem<int>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 10),
          // Buigzaam, niet vast: een popupmenu is op ~256px afgekapt en een
          // langer label (een andere taal, of 200% tekstgrootte) liet de rij
          // overlopen in plaats van netjes af te breken.
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

/// Eén kop in de Overzicht-rail: inspringing per niveau, de actieve kop in
/// EU-blauw. Buiten de schermklasse omdat hij niets van het scherm nodig heeft
/// behalve wat er bij een tik moet gebeuren.
Widget _outlineItem(
  ThemeData theme,
  MarkdownOutlineEntry entry, {
  required bool active,
  required VoidCallback onTap,
}) => InkWell(
  onTap: onTap,
  child: Container(
    color: active
        ? AppTheme.blueVivid.withValues(alpha: 0.08)
        : Colors.transparent,
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
        fontWeight: active || entry.level <= 1
            ? FontWeight.w600
            : FontWeight.w400,
        color: active
            ? AppTheme.blueVivid
            : entry.level <= 1
            ? theme.colorScheme.onSurface
            : theme.colorScheme.onSurfaceVariant,
      ),
    ),
  ),
);

/// De paginamaat-indicator rechtsonder in de Visuele modus: op welk formaat,
/// met welke marges en — als hij aanstaat — met hoeveel afloop je schrijft.
///
/// Klikbaar sinds de paginaopmaak per document kan gelden: hij toont niet
/// alleen op welk formaat je schrijft, maar ook *waar die keuze vandaan komt* —
/// uit dit document of uit je instellingen. Dat onderscheid moet zichtbaar zijn
/// op de plek waar je de maat toch al ziet staan, anders schrijft een knop
/// ergens anders ongemerkt sleutels in je bestand.
///
/// Staat buiten de schermklasse omdat hij niets van het scherm nodig heeft
/// behalve de maat en de marges, net als [_documentOutlineRail] hieronder.
///
/// Een echte [TextButton] en geen kale [InkWell]: hij gedraagt zich als een
/// knop, dus hoort hij er ook een te zijn — met knop-semantiek, toetsenbordfocus
/// en een focusring. Een kale InkWell op deze plek liet bovendien de
/// semantiek-opbouw van Flutter vastlopen op
/// `identical(childRenderObject, parentRenderObject)`, wat met een screenreader
/// aan een crash zou zijn geweest.
Widget _documentPageIndicator(
  BuildContext context,
  ThemeData theme, {
  required PageSizeSpec pageSize,
  required PageMargins margins,
  required bool fromDocument,
  required VoidCallback onTap,
}) {
  final l10n = context.l10n;
  // De speld en zijn rand volgen de modus: `primary` is in een donker profiel
  // de donkere merkkleur en zou daar wegvallen — zie [AppPalette.accentInk].
  final accent = AppPalette.of(theme).accentInk;
  return Positioned(
    right: 8,
    bottom: 8,
    child: Tooltip(
      message: fromDocument
          ? l10n.d('Deze paginaopmaak staat in dit document')
          : l10n.d('Deze paginaopmaak komt uit je instellingen'),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.85),
          foregroundColor: theme.colorScheme.onSurfaceVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(
              color: fromDocument ? accent : theme.colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (fromDocument) ...[
              Icon(Icons.push_pin_outlined, size: 11, color: accent),
              const SizedBox(width: 4),
            ],
            Text(
              // Zelf samengesteld, niet door l10n.d(): de indicator draagt
              // alleen data — de maatnaam en vier getallen in mm. Door d()
              // halen zou een onvertaalbare sleutel per papiermaat-en-
              // margecombinatie opleveren. Het enige wóórd zit in
              // pageSizeLabel (de oriëntatie), en dat is wél vertaald.
              '${pageSizeLabel(l10n, pageSize)} · '
              '${margins.topMm.toStringAsFixed(0)}/'
              '${margins.bottomMm.toStringAsFixed(0)}/'
              '${margins.leftMm.toStringAsFixed(0)}/'
              '${margins.rightMm.toStringAsFixed(0)}mm'
              // De afloop werkt door op élke export; hem hier tonen houdt dat
              // zichtbaar in plaats van stil.
              '${margins.hasBleed ? ' · +${margins.bleedMm.toStringAsFixed(0)}mm' : ''}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// De Overzicht-rail: de koppen van het document, live afgeleid, klikbaar om
/// naar die kop te springen. Europa-header (EU-blauw + geel). Inklapbaar tot
/// een smalle strook. Leeg document → lege rail.
///
/// Staat buiten de schermklasse omdat hij niets van het scherm nodig heeft
/// behalve de stand ([collapsed], [activeIndex]) en wat er bij een tik moet
/// gebeuren — net als [_outlineItem] hierboven.
Widget _documentOutlineRail(
  BuildContext context,
  ThemeData theme,
  String source, {
  required bool collapsed,
  required int activeIndex,
  required ValueChanged<bool> onCollapsedChanged,
  required void Function(MarkdownOutlineEntry entry) onSelect,
}) {
  final outline = buildMarkdownOutline(source);
  final l10n = context.l10n;
  if (collapsed) {
    return SizedBox(
      width: 40,
      child: Material(
        color: AppTheme.blueVivid,
        child: InkWell(
          onTap: () => onCollapsedChanged(false),
          child: Tooltip(
            message: l10n.d('Overzicht uitklappen'),
            child: Center(
              child: Icon(
                Icons.chevron_right,
                color: AppTheme.amberVivid,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
  return SizedBox(
    key: const Key('document-outline-rail'),
    width: 216,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: AppTheme.blueVivid,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.d('Overzicht').toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.amberVivid,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.d('Overzicht inklappen'),
                  onPressed: () => onCollapsedChanged(true),
                  icon: const Icon(Icons.chevron_left, size: 18),
                  color: AppTheme.amberVivid,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Container(
            color: theme.colorScheme.surface,
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 6, bottom: 12),
              itemCount: outline.length,
              itemBuilder: (context, i) => _outlineItem(
                theme,
                outline[i],
                active: i == activeIndex,
                onTap: () => onSelect(outline[i]),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
