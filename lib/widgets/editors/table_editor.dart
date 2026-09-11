import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../models/slide.dart';
import '../../services/markdown_table_codec.dart';
import '../../state/collab_session_provider.dart';
import '../../theme/app_theme.dart';
import '../reader/document_markdown_view.dart';
import '../reader/table_edit_controller.dart';
import '_editor_field.dart';
import 'editor_text_controller.dart';

/// Editor for a table slide (and Gantt, which stores the same grid).
///
/// Het raster is het document-rekenblad: [TableEditController] plus dezelfde
/// tekening als [DocumentMarkdownView], zodat bouwen en een document dezelfde
/// look-and-feel hebben. Dia-specifiek (titel, getalnotatie, collaboratie)
/// blijft erboven; het raster zelf is geen rij Material-velden meer.
class TableEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final bool nestedInScrollView;

  /// In een plat document bestaat er geen dia: dan verbergt de editor de
  /// dia-specifieke onderdelen (het 'Slide titel'-veld), zodat er geen
  /// presentatie-woordenschat in een documentcontext lekt.
  final bool documentContext;

  const TableEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.nestedInScrollView = false,
    this.documentContext = false,
  });

  @override
  State<TableEditor> createState() => _TableEditorState();
}

class _TableEditorState extends State<TableEditor> {
  late final EditorTextController _title;
  late TableEditController _grid;

  @override
  void initState() {
    super.initState();
    _title = EditorTextController(text: widget.slide.title);
    _title.addTextListener(_emitTitle);
    _grid = _makeGrid(widget.slide);
  }

  TableEditController _makeGrid(Slide slide) => TableEditController(
    rows: slide.tableRows,
    alignments: slide.tableColumnAlignments,
    onChanged: _onGrid,
  );

  @override
  void didUpdateWidget(covariant TableEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slide.id == widget.slide.id) return;
    _title.text = widget.slide.title;
    _grid.dispose();
    _grid = _makeGrid(widget.slide);
  }

  @override
  void dispose() {
    _title.dispose();
    _grid.dispose();
    super.dispose();
  }

  void _onGrid(List<List<String>> rows, List<TableAlign> alignments) {
    widget.onUpdate(
      widget.slide.copyWith(
        title: _title.text,
        tableRows: rows,
        tableColumnAlignments: alignments,
      ),
    );
  }

  void _emitTitle() {
    widget.onUpdate(
      widget.slide.copyWith(
        title: _title.text,
        tableRows: _grid.rows,
        tableColumnAlignments: _grid.alignments,
      ),
    );
  }

  void _toggleNumberColumn(int c) {
    final cols = List<bool>.from(widget.slide.tableNumberColumns);
    while (cols.length <= c) {
      cols.add(false);
    }
    cols[c] = !cols[c];
    widget.onUpdate(widget.slide.copyWith(tableNumberColumns: cols));
  }

  List<Widget> _numberToolbar(BuildContext context, ({int row, int col}) at) {
    if (widget.documentContext) return const [];
    final l10n = context.l10n;
    final selected =
        at.col < widget.slide.tableNumberColumns.length &&
        widget.slide.tableNumberColumns[at.col];
    return [
      IconButton(
        onPressed: () => _toggleNumberColumn(at.col),
        icon: const Icon(Icons.numbers, size: 16),
        tooltip: l10n.d('Getalnotatie'),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        color: selected ? Theme.of(context).colorScheme.primary : null,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final gfm = encodeMarkdownTable(_grid.rows, alignments: _grid.alignments);
    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        Consumer(
          builder: (context, ref, _) {
            final collab = ref.watch(collabSessionProvider);
            if (!collab.isActive) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: AppTheme.amber600.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 15,
                        color: AppTheme.amber600,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          l10n.d(
                            'Tabelcel-bewerkingen worden niet gesynchroniseerd naar medebewerkers. De titel en andere velden wel.',
                          ),
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        if (!widget.documentContext) ...[
          EditorField(label: 'Titel', controller: _title, hint: 'Slide titel'),
          const SizedBox(height: 16),
        ],
        const SectionLabel('Tabel'),
        DocumentMarkdownView(
          gfm,
          maxTextWidth: null,
          tableEditController: _grid,
          tableToolbarExtras: widget.documentContext ? null : _numberToolbar,
        ),
      ],
    );
  }
}
