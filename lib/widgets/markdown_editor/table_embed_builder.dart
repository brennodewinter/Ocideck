import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:markdown_quill/markdown_quill.dart';

import '../../models/settings.dart' show ThemeProfile;
import '../../models/slide.dart';
import '../../services/markdown_table_codec.dart';
import '../../services/document_timeline.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/timeline_table_embed_syntax.dart';
import '../reader/document_markdown_view.dart';
import '../reader/table_edit_controller.dart';
import '../reader/table_edit_scaffold.dart' show TableSortIntent;
import 'markdown_editor_theme.dart';
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
  const TableEmbedBuilder({this.onDiscreteEdit});

  final VoidCallback? onDiscreteEdit;

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
      gfm: gfm,
      profile: profile,
      embedContext: embedContext,
      onDiscreteEdit: onDiscreteEdit,
    );
  }
}

/// Houdt de [TableEditController] van één embed vast — die leeft zolang de
/// tabel in beeld is, niet per opbouw, anders zou elke toetsaanslag de cursor
/// en de focus kwijtraken.
class _EditableTableEmbed extends StatefulWidget {
  const _EditableTableEmbed({
    required this.gfm,
    required this.profile,
    required this.embedContext,
    required this.onDiscreteEdit,
  });

  final String gfm;
  final ThemeProfile? profile;
  final EmbedContext embedContext;
  final VoidCallback? onDiscreteEdit;

  @override
  State<_EditableTableEmbed> createState() => _EditableTableEmbedState();
}

class _EditableTableEmbedState extends State<_EditableTableEmbed> {
  late TableEditController _editor;

  bool get _canBecomeTimeline =>
      _editor.rows.isNotEmpty && _editor.rows.first.length >= 2;

  @override
  void initState() {
    super.initState();
    _editor = _makeController(widget.gfm);
  }

  @override
  void didUpdateWidget(_EditableTableEmbed old) {
    super.didUpdateWidget(old);
    // De bron verandert normaal alleen dóór ons eigen terugschrijven; komt er
    // van buiten een andere tabel binnen (ongedaan maken, samenwerking), dan
    // begint de bewerkstaat opnieuw.
    if (widget.gfm !=
        encodeMarkdownTable(_editor.rows, alignments: _editor.alignments)) {
      _editor.dispose();
      _editor = _makeController(widget.gfm);
    }
  }

  TableEditController _makeController(String gfm) {
    final decoded = decodeMarkdownTableWithAlignment(gfm.split('\n'));
    return TableEditController(
      rows: decoded.rows,
      alignments: decoded.alignments,
      onChanged: _writeBack,
    );
  }

  /// De tabel die nog naar het document moet; `null` als er niets wacht.
  String? _pending;
  bool _flushScheduled = false;

  /// Plant het terugschrijven ná deze frame in plaats van er middenin.
  ///
  /// Terugschrijven vervángt de embed-knoop, en koppelt daarmee de knoop los
  /// waar dit blok aan hangt. Twee schrijfacties in dezelfde frame zouden de
  /// tweede dus op een losgekoppelde knoop laten landen: die heeft
  /// `documentOffset` 0, en de tabel werd bovenaan het document geplakt, dwars
  /// door de tekst heen. Eén schrijfactie per frame, met de laatste stand,
  /// houdt de knoop heel — en scheelt bovendien een ongedaan-stap per aanslag.
  void _writeBack(List<List<String>> rows, List<TableAlign> alignments) {
    _pending = encodeMarkdownTable(rows, alignments: alignments);
    if (_flushScheduled) return;
    _flushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushScheduled = false;
      if (mounted) _flush();
    });
  }

  void _flush() {
    final gfm = _pending;
    _pending = null;
    if (gfm == null || gfm == widget.gfm) return;
    final node = widget.embedContext.node;
    if (node.parent == null) return;
    // De embed heeft lengte 1 in het Quill-document: dit vervangt exact dit
    // blok en laat de rest van de tekst — en de cursor daarbuiten — met rust.
    widget.embedContext.controller.replaceText(
      node.documentOffset,
      1,
      EmbeddableTable(gfm),
      null,
    );
  }

  Future<void> _sort(int column, bool ascending) async {
    final current = _pending ?? widget.gfm;
    final sorted = await smartSortTable(
      context,
      current,
      column: column,
      ascending: ascending,
    );
    if (mounted && sorted != null) {
      _pending = null;
      _replaceRaw(sorted);
    }
  }

  Future<void> _sortAs(int column) async {
    final choice = await chooseExplicitSort(context);
    if (!mounted || choice == null) return;
    final sorted = await smartSortTable(
      context,
      _pending ?? widget.gfm,
      column: column,
      ascending: choice.ascending,
      kind: choice.kind,
    );
    if (mounted && sorted != null) {
      _pending = null;
      _replaceRaw(sorted);
    }
  }

  void _replaceRaw(String gfm) {
    final node = widget.embedContext.node;
    if (node.parent == null || gfm == widget.gfm) return;
    widget.onDiscreteEdit?.call();
    widget.embedContext.controller.replaceText(
      node.documentOffset,
      1,
      EmbeddableTable(gfm),
      null,
    );
  }

  Future<void> _asTimeline() async {
    final current = _pending ?? widget.gfm;
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
    final node = widget.embedContext.node;
    if (node.parent == null) return;
    widget.onDiscreteEdit?.call();
    widget.embedContext.controller.replaceText(
      node.documentOffset,
      1,
      EmbeddableTimelineTable(markTableAsTimeline(table)),
      null,
    );
  }

  @override
  void dispose() {
    _editor.dispose();
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
        onSortTableColumn: (column, intent) => switch (intent) {
          TableSortIntent.ascending => _sort(column, true),
          TableSortIntent.descending => _sort(column, false),
          TableSortIntent.choose => _sortAs(column),
        },
      ),
    ],
  );
}

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
class _TimelineColumnSelection {
  const _TimelineColumnSelection({
    required this.marker,
    required this.event,
    this.metadata,
  });

  final int marker;
  final int event;
  final int? metadata;
}

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
            onPressed: () => Navigator.pop(
              ctx,
              _TimelineColumnSelection(
                marker: marker,
                event: event,
                metadata: metadata,
              ),
            ),
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
