import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:markdown_quill/markdown_quill.dart';

import '../../models/settings.dart' show ThemeProfile;
import '../../models/slide.dart';
import '../../services/markdown_table_codec.dart';
import '../../services/table_sort.dart';
import '../../services/document_timeline.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/timeline_table_embed_syntax.dart';
import '../reader/document_markdown_view.dart';
import '../reader/table_edit_controller.dart';
import 'markdown_editor_theme.dart';

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
    final analysis = analyzeTimelineTable(current);
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
    var table = current;
    if (choice == _TimelineActivationChoice.sort) {
      final sorted = await smartSortTable(
        context,
        current,
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
        onSortTableColumn: (column, ascending) =>
            ascending == null ? _sortAs(column) : _sort(column, ascending),
      ),
    ],
  );
}

/// Vraagt alleen om hulp wanneer lokale analyse geen eenduidige of volledig
/// leesbare kolom vindt. Zo blijft de standaardhandeling snel, maar worden
/// onbekende waarden nooit stilzwijgend anders geïnterpreteerd.
Future<String?> smartSortTable(
  BuildContext context,
  String gfm, {
  required int column,
  required bool ascending,
  TableSortKind kind = TableSortKind.automatic,
}) async {
  const sorter = TableSortService();
  final lines = gfm.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  var analysis = sorter.analyze(lines, columnIndex: column);
  if (kind != TableSortKind.automatic) {
    analysis = sorter.analyze(lines, columnIndex: column, kind: kind);
  } else if (!analysis.canSort) {
    final chosen = await showDialog<TableSortKind>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.d('Hoe wil je deze kolom sorteren?')),
        content: Text(
          context.l10n.d(
            'De waarden lijken niet allemaal van hetzelfde type. Kies hoe OciDeck ze moet lezen; niet-herkende waarden blijven onderaan in hun oorspronkelijke volgorde staan.',
          ),
        ),
        actions: [
          for (final option in const [
            (TableSortKind.text, 'Tekst'),
            (TableSortKind.number, 'Getal'),
            (TableSortKind.date, 'Datum'),
            (TableSortKind.time, 'Tijd'),
          ])
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, option.$1),
              child: Text(context.l10n.d(option.$2)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.d('Annuleren')),
          ),
        ],
      ),
    );
    if (!context.mounted || chosen == null) return null;
    kind = chosen;
    analysis = sorter.analyze(lines, columnIndex: column, kind: kind);
  }
  if (!analysis.canSort) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.d(
            'Deze kolom bevat nog geen waarden die op deze manier gesorteerd kunnen worden.',
          ),
        ),
      ),
    );
    return null;
  }
  if (analysis.suitability ==
      TableAnalysisSuitability.suitableWithAttentionPoints) {
    final choice = await _reviewSortAttention(context, lines, analysis, column);
    if (!context.mounted || choice != _SortAttentionChoice.apply) return null;
  }
  final result = sorter.sortSource(
    gfm,
    columnIndex: column,
    kind: kind,
    direction: ascending
        ? TableSortDirection.ascending
        : TableSortDirection.descending,
  );
  return result.changed ? result.source : null;
}

typedef ExplicitSortChoice = ({TableSortKind kind, bool ascending});

Future<ExplicitSortChoice?> chooseExplicitSort(BuildContext context) {
  var selected = TableSortKind.automatic;
  return showDialog<ExplicitSortChoice>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(context.l10n.d('Sorteren als…')),
        content: RadioGroup<TableSortKind>(
          groupValue: selected,
          onChanged: (value) => setDialogState(() => selected = value!),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in const [
                (TableSortKind.automatic, 'Automatisch'),
                (TableSortKind.text, 'Tekst'),
                (TableSortKind.number, 'Getal'),
                (TableSortKind.date, 'Datum'),
                (TableSortKind.time, 'Tijd'),
              ])
                RadioListTile<TableSortKind>(
                  value: option.$1,
                  title: Text(context.l10n.d(option.$2)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.d('Annuleren')),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, (kind: selected, ascending: true)),
            child: Text(context.l10n.d('Oplopend')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, (
              kind: selected,
              ascending: false,
            )),
            child: Text(context.l10n.d('Aflopend')),
          ),
        ],
      ),
    ),
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
    if (timeline.headers.length == 3) '3: ${timeline.headers[2]}',
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

enum _SortAttentionChoice { review, apply }

Future<_SortAttentionChoice?> _reviewSortAttention(
  BuildContext context,
  List<String> lines,
  TableSortAnalysis analysis,
  int column,
) async {
  while (true) {
    if (!context.mounted) return null;
    final l10n = context.l10n;
    final profile = analysis.profile;
    final choice = await showDialog<_SortAttentionChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.d('Sorteren met aandachtspunten?')),
        content: Text(
          '${profile.parsedRowIndices.length} ${l10n.d('waarden herkend.')}\n'
          '${profile.unparsedRowIndices.length} ${l10n.d('waarden niet herkend. Die rijen blijven onderaan in hun huidige volgorde.')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.d('Annuleren')),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _SortAttentionChoice.review),
            child: Text(l10n.d('Waarden bekijken')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _SortAttentionChoice.apply),
            child: Text(l10n.d('Sorteren toepassen')),
          ),
        ],
      ),
    );
    if (!context.mounted || choice != _SortAttentionChoice.review) {
      return choice;
    }
    final rows = decodeMarkdownTableRows(lines).skip(1).toList();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.d('Niet-herkende waarden')),
        content: SingleChildScrollView(
          child: SelectableText(
            profile.unparsedRowIndices
                .map(
                  (index) =>
                      '${l10n.d('Rij')} ${index + 1}: ${index < rows.length && column < rows[index].length ? rows[index][column] : ''}',
                )
                .join('\n'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.d('Sluiten')),
          ),
        ],
      ),
    );
  }
}
