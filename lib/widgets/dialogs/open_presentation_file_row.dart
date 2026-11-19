part of 'open_presentation_dialog.dart';

String _fileDateLabel(ScannedMarkdown file, AppLocalizations l10n) {
  final date = file.deck?.date.trim() ?? '';
  final modified = file.modified;
  if (date.isEmpty && modified == null) return l10n.d('Geen datum bekend');
  return [
    if (date.isNotEmpty) '${l10n.d('Presentatiedatum')} · $date',
    if (modified != null && _presentationDate(file) == null)
      '${l10n.d('Laatst gewijzigd op')} ${formatModifiedDate(modified)}',
  ].join('  •  ');
}

class _FileRow extends StatelessWidget {
  final DuplicateInfo<ScannedMarkdown> info;

  /// De gescande map; de rij toont de vindplaats relatief hieraan zodat in
  /// een boom met submappen zichtbaar is wáár elk bestand staat.
  final String? scanRoot;

  /// Naam van de bibliotheek waaronder dit bestand valt; leeg wanneer er maar
  /// één wortel in beeld is (dan voegt de naam niets toe).
  final String rootName;
  final List<_Hit> hits;

  /// Of het soortlabel achter de titel staat; zie de aanroeper.
  final bool showKind;
  final bool showPreview;

  /// Of dit bestand is aangewezen om samen met andere geopend te worden.
  final bool selected;

  /// Of deze rij de toetsenbordfocus draagt — de zichtbare focusrand, los
  /// van de [selected]-achtergrond.
  final bool focused;

  /// Klik op de rij. De dialoog leest de modificatietoetsen: kaal openen,
  /// met Ctrl/Cmd of Shift de selectie veranderen.
  final VoidCallback onTap;
  final ValueChanged<String> onPreview;

  /// Open dit ene bestand meteen, buiten de selectie om — de identieke-kopie-
  /// chip en een trefferregel in een document wijzen elk één bestand aan.
  final ValueChanged<String> onOpen;
  final ValueChanged<int> onOpenAt;

  const _FileRow({
    required this.info,
    required this.scanRoot,
    required this.rootName,
    required this.hits,
    required this.showKind,
    required this.showPreview,
    required this.selected,
    required this.focused,
    required this.onTap,
    required this.onPreview,
    required this.onOpen,
    required this.onOpenAt,
  });

  ScannedMarkdown get file => info.primary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            selected: selected,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                decoration: BoxDecoration(
                  // Aangewezen rijen krijgen dezelfde blauwe tint die de app
                  // elders voor een info-vlak gebruikt; die schakelt mee met
                  // licht en donker.
                  color: selected ? AppTheme.infoBg : null,
                  borderRadius: BorderRadius.circular(6),
                  // Toetsenbordfocusrand: een blauwe contour los van de
                  // selectie-achtergrond, zodat beide tegelijk zichtbaar zijn.
                  border: focused
                      ? Border.all(color: AppTheme.accentFg, width: 1.6)
                      : null,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      markdownKindIcon(file.kind),
                      size: 18,
                      color: AppTheme.brandFg,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _titleAndPlace(l10n)),
                    if (showPreview) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.visibility_outlined, size: 16),
                        tooltip: l10n.d('Voorbeeld tonen'),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => onPreview(file.path),
                      ),
                    ],
                    const SizedBox(width: 8),
                    // Het pijltje belooft "dit opent"; bij een aangewezen rij
                    // is dat niet meer waar — die wacht op "Openen (n)".
                    selected
                        ? Icon(
                            Icons.check_circle,
                            size: 16,
                            color: AppTheme.accentFg,
                          )
                        : Icon(
                            Icons.north_east,
                            size: 16,
                            color: AppTheme.slate500,
                          ),
                  ],
                ),
              ),
            ),
          ),
          if (hits.isNotEmpty) _hitList(l10n),
        ],
      ),
    );
    if (!showPreview) return row;
    // Aanwijzen met de muis laat het voorbeeld meelopen; de knop hierboven doet
    // hetzelfde voor wie met het toetsenbord of op een aanraakscherm werkt.
    return MouseRegion(onEnter: (_) => onPreview(file.path), child: row);
  }

  Widget _titleAndPlace(AppLocalizations l10n) {
    final deck = file.deck;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                file.displayTitle,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slate800,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (showKind) ...[
              const SizedBox(width: 6),
              MarkdownKindBadge(kind: file.kind),
            ],
            if (info.hasIdenticalCopies) ...[
              const SizedBox(width: 6),
              IdenticalCopiesChip(
                otherPaths: [for (final copy in info.identical) copy.path],
                homeDir: scanRoot,
                onOpen: onOpen,
              ),
            ],
          ],
        ),
        // Vindplaats relatief aan de gescande map, zodat bij submappen
        // zichtbaar is wáár het bestand staat; het volledige pad zit in de
        // tooltip.
        Tooltip(
          message: file.path,
          waitDuration: const Duration(milliseconds: 400),
          child: Text(
            '${rootName.isEmpty ? '' : '$rootName  ·  '}'
            '${displayFolder(file.path, homeDir: scanRoot, osHome: osHomeDirectory)}'
            '  ·  ${file.fileName}'
            '${deck == null ? '' : '  ·  ${deck.slides.length} ${l10n.t('slides')}'}',
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          _fileDateLabel(file, l10n),
          style: TextStyle(fontSize: 11, color: AppTheme.slate500),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (info.hasTitleConflict) ...[
          const SizedBox(height: 2),
          TitleConflictMarker(modified: file.modified),
        ],
      ],
    );
  }

  Widget _hitList(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(left: 34, top: 2, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final hit in hits.take(4)) _hitRow(l10n, hit),
          if (hits.length > 4)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2),
              child: Text(
                '+ ${hits.length - 4} ${l10n.d('meer treffer(s)')}',
                style: TextStyle(fontSize: 11, color: AppTheme.slate400),
              ),
            ),
        ],
      ),
    );
  }

  /// Eén trefferregel. Bij een presentatie springt hij naar de dia; bij een
  /// document opent hij het bestand — daar is geen dia om naartoe te gaan, en
  /// een label dat een sprong belooft die niet bestaat, is erger dan geen label.
  Widget _hitRow(AppLocalizations l10n, _Hit hit) {
    final index = hit.slideIndex;
    return InkWell(
      onTap: () => index == null ? onOpen(file.path) : onOpenAt(index),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (index != null) ...[
              Text(
                '${l10n.d('Slide')} ${index + 1}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accentFg,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                hit.snippet,
                style: TextStyle(fontSize: 12, color: AppTheme.slate600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
