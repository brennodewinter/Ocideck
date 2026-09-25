import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:markdown_quill/markdown_quill.dart';

import '../../models/settings.dart' show ThemeProfile;
import '../../services/markdown_table_codec.dart';
import '../../services/document_timeline.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/timeline_table_embed_syntax.dart';
import '../reader/document_markdown_view.dart';
import '../reader/table_edit_controller.dart';
import 'markdown_editor_theme.dart';
import 'table_embed_binding.dart';
import 'table_sort_actions.dart';

/// Tekent een `x-embed-table`-blok in de visuele (Quill) editor als een échte,
/// gerenderde tabel — dezelfde weergave als de documentlezer — en laat je er
/// rechtstreeks in typen: klik in een cel en vul hem in, zoals in een rekenblad.
///
/// Dat verving een dialoog met losse velden van gelijke breedte. Daar zag je
/// niet wat je kreeg, terwijl juist bij een tabel de vorm de helft van de
/// leesbaarheid is. Nu herschikt de tabel terwijl je typt — de kolombreedtes
/// worden per toetsaanslag opnieuw gekozen, precies zoals ze in het document
/// komen te staan. Dat is het voordeel van Markdown als drager: de tabel heeft
/// geen vaste kolommaten die je met de hand goed moet zetten.
///
/// Elke wijziging schrijft de tabel byte-getrouw terug in de embed; de
/// markdown-round-trip (`MarkdownQuillCodec`) serialiseert hem weer als
/// GFM-tabel. Dit is ook de reden dat een tabel geen visuele-modus-beperking
/// meer is (`markdownVisualLimitations`): waar de heen-en-terugweg door de
/// platte rijke-tekstlaag een tabel tot losse woorden maalde, blijft hij nu één
/// blok.
class TableEmbedBuilder extends EmbedBuilder {
  const TableEmbedBuilder({required this.controllerStore, this.onDiscreteEdit});

  final VoidCallback? onDiscreteEdit;
  final TableEmbedControllerStore controllerStore;

  @override
  String get key => EmbeddableTable.tableType;

  /// Een tabel is een blok, geen inline-teken: hij vult de breedte.
  @override
  bool get expanded => true;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final gfm = (embedContext.node.value.data ?? '').toString().trimRight();
    final profile = DocumentStyleScope.maybeOf(context);
    // Alleen-lezen (bijv. een niet-bewerkbare weergave): render de tabel zonder
    // invulbare cellen.
    if (embedContext.readOnly) {
      return DocumentMarkdownView(
        gfm,
        maxTextWidth: null,
        themeProfile: profile,
        chartTheme: profile,
      );
    }
    return _EditableTableEmbed(
      key: ValueKey('document-table-${embedContext.node.documentOffset}'),
      gfm: gfm,
      profile: profile,
      embedContext: embedContext,
      onDiscreteEdit: onDiscreteEdit,
      controllerStore: controllerStore,
    );
  }
}

/// Houdt de [TableEditController] van één embed vast — die leeft zolang de
/// tabel in beeld is, niet per opbouw, anders zou elke toetsaanslag de cursor
/// en de focus kwijtraken.
class _EditableTableEmbed extends StatefulWidget {
  const _EditableTableEmbed({
    super.key,
    required this.gfm,
    required this.profile,
    required this.embedContext,
    required this.onDiscreteEdit,
    required this.controllerStore,
  });

  final String gfm;
  final ThemeProfile? profile;
  final EmbedContext embedContext;
  final VoidCallback? onDiscreteEdit;
  final TableEmbedControllerStore controllerStore;

  @override
  State<_EditableTableEmbed> createState() => _EditableTableEmbedState();
}

class _EditableTableEmbedState extends State<_EditableTableEmbed> {
  late TableEmbedBinding _binding;

  TableEditController get _editor => _binding.editor;

  bool get _canBecomeTimeline =>
      _editor.rows.isNotEmpty && _editor.rows.first.length >= 2;

  @override
  void initState() {
    super.initState();
    _binding = TableEmbedBinding(
      controllerStore: widget.controllerStore,
      embedContext: widget.embedContext,
      source: widget.gfm,
      unwrapSource: _identity,
      wrapTable: _identity,
      makeEmbed: EmbeddableTable.new,
      isMounted: () => mounted,
    );
  }

  @override
  void didUpdateWidget(_EditableTableEmbed old) {
    super.didUpdateWidget(old);
    _binding.reconnect(widget.embedContext, widget.gfm);
  }

  Future<void> _sort(int column, TableSortIntent intent) async {
    final sorted = await sortTableForIntent(
      context,
      _binding.tableSource,
      column: column,
      intent: intent,
    );
    if (mounted && sorted != null) {
      _binding.clearPending();
      _binding.replaceTable(
        sorted,
        discrete: true,
        onDiscreteEdit: widget.onDiscreteEdit,
      );
    }
  }

  Future<void> _asTimeline() async {
    final current = _binding.tableSource;
    final lines = current.trimRight().split('\n');
    final decoded = decodeMarkdownTableRows(lines);
    if (decoded.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.d(
              'Deze tabel kan nog niet als tijdlijn worden weergegeven en blijft ongewijzigd.',
            ),
          ),
        ),
      );
      return;
    }
    final colCount = decoded.first.length;
    // Bij 4+ kolommen kiest de gebruiker welke 2-3 kolommen de tijdlijn worden.
    // De overige kolommen verdwijnen uit de tabel — de tijdlijn is een projectie,
    // geen extra weergave, en de marker draagt geen kolommetadata.
    String table = current;
    if (colCount > 3) {
      final selection = await _pickTimelineColumns(context, decoded);
      if (!mounted || selection == null) return;
      final subRows = [
        [
          decoded.first[selection.marker],
          decoded.first[selection.event],
          if (selection.metadata != null) decoded.first[selection.metadata!],
        ],
        for (final row in decoded.skip(1))
          [
            row.length > selection.marker ? row[selection.marker] : '',
            row.length > selection.event ? row[selection.event] : '',
            if (selection.metadata != null)
              row.length > selection.metadata! ? row[selection.metadata!] : '',
          ],
      ];
      table = encodeMarkdownTable(subRows);
    }
    final analysis = analyzeTimelineTable(table);
    if (!analysis.isUsable) {
      final message = switch (analysis.issue) {
        TimelineTableIssue.wrongColumnCount => context.l10n.d(
          'Een tijdlijn werkt met twee of drie kolommen. Deze tabel blijft ongewijzigd.',
        ),
        TimelineTableIssue.noEvents => context.l10n.d(
          'Voeg eerst minstens één gebeurtenis toe. Deze tabel blijft ongewijzigd.',
        ),
        _ => context.l10n.d(
          'Deze tabel kan nog niet als tijdlijn worden weergegeven en blijft ongewijzigd.',
        ),
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    final timeline = analysis.timeline!;
    final choice = await _confirmTimelineActivation(context, timeline);
    if (!mounted || choice == null) return;
    if (choice == _TimelineActivationChoice.sort) {
      final sorted = await smartSortTable(
        context,
        table,
        column: 0,
        ascending: true,
      );
      if (!mounted || sorted == null) return;
      table = sorted;
    }
    _binding.clearPending();
    final source = markTableAsTimeline(table);
    _binding.replaceSource(
      source,
      discrete: true,
      onDiscreteEdit: widget.onDiscreteEdit,
      embed: EmbeddableTimelineTable(source),
    );
  }

  @override
  void dispose() {
    _binding.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_canBecomeTimeline)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _asTimeline(),
            icon: const Icon(Icons.timeline_outlined),
            label: Text(context.l10n.d('Als tijdlijn weergeven')),
          ),
        ),
      DocumentMarkdownView(
        widget.gfm,
        maxTextWidth: null,
        themeProfile: widget.profile,
        chartTheme: widget.profile,
        tableEditController: _editor,
        onSortTableColumn: _sort,
      ),
    ],
  );
}

String _identity(String source) => source;

enum _TimelineActivationChoice { keepOrder, sort }

Future<_TimelineActivationChoice?> _confirmTimelineActivation(
  BuildContext context,
  DocumentTimeline timeline,
) {
  final l10n = context.l10n;
  final outOfOrder =
      timeline.markerAnalysis.canSort &&
      !timeline.markerAnalysis.profile.alreadyMonotonic;
  final emptyEvents = <int>[
    for (var i = 0; i < timeline.events.length; i++)
      if (timeline.events[i].event.trim().isEmpty) i + 1,
  ];
  final roles = <String>[
    '${l10n.d('Volgorde')}: ${timeline.headers[0]}',
    '${l10n.d('Gebeurtenis')}: ${timeline.headers[1]}',
    if (timeline.headers.length == 3)
      '${l10n.d('Toelichting')}: ${timeline.headers[2]}',
  ];
  final notes = <String>[
    '${timeline.events.length} ${l10n.d('gebeurtenissen gevonden.')}',
    if (timeline.markerAnalysis.profile.unparsedRowIndices.isNotEmpty)
      '${timeline.markerAnalysis.profile.unparsedRowIndices.length} ${l10n.d('markeringen hebben geen herkenbare volgordewaarde. Ze blijven zichtbaar.')}',
    if (outOfOrder)
      l10n.d('De waarden in de volgordekolom staan niet oplopend.'),
    if (emptyEvents.isNotEmpty)
      '${l10n.d('Lege gebeurtenissen blijven zichtbaar. Controleer rij:')} ${emptyEvents.join(', ')}',
  ];
  return showDialog<_TimelineActivationChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.d('Tijdlijn maken?')),
      content: SingleChildScrollView(
        child: SelectableText('${roles.join('\n')}\n\n${notes.join('\n')}'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(l10n.d('Annuleren')),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(dialogContext, _TimelineActivationChoice.keepOrder),
          child: Text(
            outOfOrder
                ? l10n.d('Huidige volgorde behouden')
                : l10n.d('Tijdlijn maken'),
          ),
        ),
        if (outOfOrder)
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _TimelineActivationChoice.sort),
            child: Text(l10n.d('Sorteren en tijdlijn maken')),
          ),
      ],
    ),
  );
}

/// De kolommen die de gebruiker voor de tijdlijn heeft gekozen.
typedef _TimelineColumnSelection = ({int marker, int event, int? metadata});

/// Toont een dialoog waarin de gebruiker kiest welke 2-3 kolommen van een brede
/// tabel de tijdlijn worden (volgorde, gebeurtenis, optioneel toelichting).
/// De overige kolommen verdwijnen uit de tabel.
Future<_TimelineColumnSelection?> _pickTimelineColumns(
  BuildContext context,
  List<List<String>> rows,
) {
  final l10n = context.l10n;
  final headers = rows.first;
  final colCount = headers.length;
  int marker = 0;
  int event = 1;
  int? metadata = colCount > 2 ? 2 : null;
  final bodyCount = rows.length - 1;
  final state = showDialog<_TimelineColumnSelection>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(l10n.d('Kies kolommen voor de tijdlijn')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.d(
                  'Een tijdlijn gebruikt twee of drie kolommen. Kies welke kolommen uit deze tabel de tijdlijn worden. De overige kolommen verdwijnen uit de tabel.',
                ),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              _ColumnDropdown(
                label: l10n.d('Volgorde (marker)'),
                headers: headers,
                value: marker,
                exclude: {event, metadata},
                onChanged: (v) => setState(() => marker = v ?? 0),
              ),
              const SizedBox(height: 12),
              _ColumnDropdown(
                label: l10n.d('Gebeurtenis'),
                headers: headers,
                value: event,
                exclude: {marker, metadata},
                onChanged: (v) => setState(() => event = v ?? 1),
              ),
              const SizedBox(height: 12),
              _ColumnDropdown(
                label: l10n.d('Toelichting (optioneel)'),
                headers: headers,
                value: metadata,
                exclude: {marker, event},
                allowNone: true,
                onChanged: (v) => setState(() => metadata = v),
              ),
              const SizedBox(height: 16),
              Text(
                '${l10n.d('Gebeurtenissen')}: $bodyCount',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.d('Annuleren')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, (
              marker: marker,
              event: event,
              metadata: metadata,
            )),
            child: Text(l10n.d('Tijdlijn maken')),
          ),
        ],
      ),
    ),
  );
  return state;
}

class _ColumnDropdown extends StatelessWidget {
  const _ColumnDropdown({
    required this.label,
    required this.headers,
    required this.value,
    required this.exclude,
    required this.onChanged,
    this.allowNone = false,
  });

  final String label;
  final List<String> headers;
  final int? value;
  final Set<int?> exclude;
  final ValueChanged<int?> onChanged;
  final bool allowNone;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(flex: 2, child: Text(label)),
      Expanded(
        flex: 3,
        child: DropdownButton<int?>(
          isExpanded: true,
          value: value,
          items: [
            if (allowNone)
              DropdownMenuItem<int?>(
                value: null,
                child: Text(context.l10n.d('Geen')),
              ),
            for (var i = 0; i < headers.length; i++)
              if (!exclude.contains(i))
                DropdownMenuItem<int?>(
                  value: i,
                  child: Text(
                    headers[i].isEmpty
                        ? '${context.l10n.d('Kolom')} ${i + 1}'
                        : headers[i],
                  ),
                ),
          ],
          onChanged: onChanged,
        ),
      ),
    ],
  );
}
