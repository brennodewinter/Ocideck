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
  final VoidCallback onInsertChart;
  final VoidCallback onInsertTable;
  final VoidCallback onInsertMermaid;
  final VoidCallback onInsertImage;
  final VoidCallback onInsertPageBreak;
  final VoidCallback onInsertToc;
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
    required this.onInsertChart,
    required this.onInsertTable,
    required this.onInsertMermaid,
    required this.onInsertImage,
    required this.onInsertPageBreak,
    required this.onInsertToc,
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
                      _moreMenu(l10n),
                    ],
                  ),
                ),
              ),
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
        }
      },
      itemBuilder: (context) => [
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
          Text(label),
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
/// Staat buiten de schermklasse omdat hij niets van het scherm nodig heeft
/// behalve de maat en de marges, net als [_documentOutlineRail] hieronder.
Widget _documentPageIndicator(
  BuildContext context,
  ThemeData theme, {
  required PageSize pageSize,
  required PageMargins margins,
}) => Positioned(
  right: 8,
  bottom: 8,
  child: IgnorePointer(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        // Zelf samengesteld, niet door l10n.d(): de indicator draagt alleen
        // data — de maatnaam en vier getallen in mm. Door d() halen zou een
        // onvertaalbare sleutel per papiermaat-en-margecombinatie opleveren.
        // Het enige wóórd zit in pageSizeLabel (de oriëntatie), en dat is wél
        // vertaald.
        '${pageSizeLabel(context.l10n, pageSize)} · '
        '${margins.topMm.toStringAsFixed(0)}/'
        '${margins.bottomMm.toStringAsFixed(0)}/'
        '${margins.leftMm.toStringAsFixed(0)}/'
        '${margins.rightMm.toStringAsFixed(0)}mm'
        // De afloop geldt app-breed en werkt door op het volgende document;
        // hem hier tonen houdt dat zichtbaar in plaats van stil.
        '${margins.hasBleed ? ' · +${margins.bleedMm.toStringAsFixed(0)}mm' : ''}',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 10,
        ),
      ),
    ),
  ),
);

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
