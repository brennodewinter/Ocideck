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
  const TableEmbedBuilder();

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
  });

  final String gfm;
  final ThemeProfile? profile;
  final EmbedContext embedContext;

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

  void _replaceRaw(String gfm) {
    final node = widget.embedContext.node;
    if (node.parent == null || gfm == widget.gfm) return;
    widget.embedContext.controller.replaceText(
      node.documentOffset,
      1,
      EmbeddableTable(gfm),
      null,
    );
  }

  void _asTimeline() {
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
    final node = widget.embedContext.node;
    if (node.parent == null) return;
    widget.embedContext.controller.replaceText(
      node.documentOffset,
      1,
      EmbeddableTimelineTable(markTableAsTimeline(current)),
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
          onPressed: _asTimeline,
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

/// Vraagt alleen om hulp wanneer lokale analyse geen eenduidige of volledig
/// leesbare kolom vindt. Zo blijft de standaardhandeling snel, maar worden
/// onbekende waarden nooit stilzwijgend anders geïnterpreteerd.
Future<String?> smartSortTable(
  BuildContext context,
  String gfm, {
  required int column,
  required bool ascending,
}) async {
  const sorter = TableSortService();
  final lines = gfm.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  var kind = TableSortKind.automatic;
  var analysis = sorter.analyze(lines, columnIndex: column);
  if (!analysis.canSort) {
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
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.d('Sorteren met aandachtspunten?')),
        content: Text(
          context.l10n.d(
            'Een deel van de waarden wordt niet herkend. Die rijen blijven bij elkaar onderaan staan; hun inhoud verandert niet.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.d('Annuleren')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.d('Toch sorteren')),
          ),
        ],
      ),
    );
    if (!context.mounted || proceed != true) return null;
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
