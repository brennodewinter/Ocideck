import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:markdown_quill/markdown_quill.dart';

import '../../l10n/app_localizations.dart';
import '../../models/settings.dart' show ThemeProfile;
import '../../models/slide.dart' show TableAlign;
import '../../services/document_timeline.dart';
import '../../services/markdown_table_codec.dart';
import '../../utils/timeline_table_embed_syntax.dart';
import '../reader/document_markdown_view.dart';
import '../reader/table_edit_controller.dart';
import '../reader/table_edit_scaffold.dart' show TableSortIntent;
import 'markdown_editor_theme.dart';
import 'table_embed_builder.dart' show TableEmbedControllerStore;
import 'table_sort_actions.dart';

/// Tekent marker en tabel als één verliesvrij tijdlijnblok in de visuele editor.
class TimelineTableEmbedBuilder extends EmbedBuilder {
  const TimelineTableEmbedBuilder({
    required this.controllerStore,
    this.onDiscreteEdit,
  });

  final VoidCallback? onDiscreteEdit;
  final TableEmbedControllerStore controllerStore;

  @override
  String get key => EmbeddableTimelineTable.timelineType;

  @override
  bool get expanded => true;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final source = (embedContext.node.value.data ?? '').toString();
    final profile = DocumentStyleScope.maybeOf(context);
    if (embedContext.readOnly) {
      return DocumentMarkdownView(
        source,
        maxTextWidth: null,
        themeProfile: profile,
        chartTheme: profile,
      );
    }
    return _EditableTimelineEmbed(
      key: ValueKey('document-timeline-${embedContext.node.documentOffset}'),
      source: source,
      profile: profile,
      embedContext: embedContext,
      onDiscreteEdit: onDiscreteEdit,
      controllerStore: controllerStore,
    );
  }
}

class _EditableTimelineEmbed extends StatefulWidget {
  const _EditableTimelineEmbed({
    super.key,
    required this.source,
    required this.profile,
    required this.embedContext,
    required this.onDiscreteEdit,
    required this.controllerStore,
  });

  final String source;
  final ThemeProfile? profile;
  final EmbedContext embedContext;
  final VoidCallback? onDiscreteEdit;
  final TableEmbedControllerStore controllerStore;

  @override
  State<_EditableTimelineEmbed> createState() => _EditableTimelineEmbedState();
}

class _EditableTimelineEmbedState extends State<_EditableTimelineEmbed> {
  late TableEditController _editor;
  late int _documentOffset;
  late String _source;
  bool _editing = false;
  String? _pending;
  bool _flushScheduled = false;

  String get _currentSource => _pending ?? _source;
  String get _tableSource => unmarkTimeline(_currentSource);

  @override
  void initState() {
    super.initState();
    _documentOffset = widget.embedContext.node.documentOffset;
    _source = widget.source;
    _editor = _obtainController();
    _editing = !analyzeMarkedTimeline(_source).isUsable;
  }

  @override
  void didUpdateWidget(_EditableTimelineEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    final node = widget.embedContext.node;
    if (node.parent != null) _documentOffset = node.documentOffset;
    _source = widget.source;
    _editor = _obtainController();
  }

  TableEditController _obtainController() => widget.controllerStore.obtain(
    _documentOffset,
    _tableSource,
    onChanged: _writeBack,
    // Zie table_embed_builder.dart: Quill's _TransparentTapGestureRecognizer
    // kaapt de TextInputConnection terug na een tap op de cel (#1718).
    onCellFocused: () =>
        widget.embedContext.controller.skipRequestKeyboard = true,
  );

  void _writeBack(List<List<String>> rows, List<TableAlign> alignments) {
    _pending = markTableAsTimeline(
      encodeMarkdownTable(rows, alignments: alignments),
    );
    if (_flushScheduled) return;
    _flushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushScheduled = false;
      if (mounted) _flush();
    });
  }

  void _flush() {
    final source = _pending;
    _pending = null;
    if (source == null) return;
    _replace(source, preserveEditor: true);
  }

  void _replace(
    String source, {
    bool asTable = false,
    bool discrete = false,
    bool preserveEditor = false,
  }) {
    if (source == _source) return;
    if (discrete) widget.onDiscreteEdit?.call();
    if (preserveEditor) {
      widget.controllerStore.remember(
        _documentOffset,
        _editor,
        unmarkTimeline(source),
      );
    }
    _source = source;
    widget.embedContext.controller.replaceText(
      // De embedknoop zelf wordt door de eerste vervanging losgekoppeld. Zijn
      // vastgelegde positie blijft wél geldig: een embed heeft lengte 1 en we
      // vervangen hem hier steeds door precies één nieuwe embed.
      _documentOffset,
      1,
      asTable ? EmbeddableTable(source) : EmbeddableTimelineTable(source),
      widget.embedContext.controller.selection,
      // De cel beheert haar eigen tekstverbinding. Laat Quill die tijdens het
      // vervangen van de embed niet overnemen of naar het blokbegin scrollen.
      ignoreFocus: true,
    );
  }

  Future<void> _sort(int column, bool ascending) async {
    final sorted = await smartSortTable(
      context,
      _tableSource,
      column: column,
      ascending: ascending,
    );
    if (mounted && sorted != null) {
      _pending = null;
      _replace(markTableAsTimeline(sorted), discrete: true);
    }
  }

  Future<void> _sortAs(int column) async {
    final choice = await chooseExplicitSort(context);
    if (!mounted || choice == null) return;
    final sorted = await smartSortTable(
      context,
      _tableSource,
      column: column,
      ascending: choice.ascending,
      kind: choice.kind,
    );
    if (mounted && sorted != null) {
      _pending = null;
      _replace(markTableAsTimeline(sorted), discrete: true);
    }
  }

  DateTime _initialDateFor(String source) {
    final parsed = DateTime.tryParse(source.trim());
    return parsed == null
        ? DateTime.now()
        : parsed.isUtc
        ? parsed.toLocal()
        : parsed;
  }

  Future<DateTime?> _pickDate(int row) => showDatePicker(
    context: context,
    initialDate: _initialDateFor(_editor.cellController(row, 0).text),
    firstDate: DateTime(1),
    lastDate: DateTime(9999, 12, 31),
  );

  void _setMarker(int row, String value) {
    final controller = _editor.cellController(row, 0);
    controller
      ..text = value
      ..selection = TextSelection.collapsed(offset: value.length);
    _editor.keepEditing(row, 0);
  }

  Future<void> _chooseDate(int row) async {
    final date = await _pickDate(row);
    if (!mounted || date == null) return;
    _setMarker(row, canonicalDocumentTimelineDate(date));
  }

  Future<void> _chooseDateTime(int row) async {
    final date = await _pickDate(row);
    if (!mounted || date == null) return;
    final initial = _initialDateFor(_editor.cellController(row, 0).text);
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted || time == null) return;
    final wallClock = DateTime.utc(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    final candidates = documentTimelineInstantCandidates(wallClock);
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.d(
              'Deze lokale tijd bestaat niet door de overgang naar zomertijd. Kies een andere tijd.',
            ),
          ),
        ),
      );
      return;
    }
    var instant = candidates.length == 1 ? candidates.single : null;
    instant ??= await _chooseRepeatedClockTime(candidates);
    if (!mounted || instant == null) return;
    _setMarker(row, canonicalDocumentTimelineInstant(instant));
  }

  Future<DateTime?> _chooseRepeatedClockTime(
    List<DateTime> candidates,
  ) => showDialog<DateTime>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Text(
        context.l10n.d(
          'Deze lokale tijd komt twee keer voor. Kies de juiste UTC-offset.',
        ),
      ),
      children: [
        for (final instant in candidates)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, instant),
            child: Text(
              formatDocumentTimelineUtcOffset(instant.toLocal().timeZoneOffset),
            ),
          ),
      ],
    ),
  );

  List<Widget> _momentToolbar(BuildContext context, ({int row, int col}) at) {
    if (at.row == 0 || at.col != 0) return const [];
    return [
      IconButton(
        tooltip: context.l10n.d('Datum kiezen'),
        onPressed: () => _chooseDate(at.row),
        icon: const Icon(Icons.calendar_today_outlined),
      ),
      IconButton(
        tooltip: context.l10n.d('Datum en tijd kiezen'),
        onPressed: () => _chooseDateTime(at.row),
        icon: const Icon(Icons.schedule_outlined),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final analysis = analyzeMarkedTimeline(_currentSource);
    final usable = analysis.isUsable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!usable)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_timelineIssueMessage(context, analysis)),
                  ),
                ],
              ),
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              _timelineActionButton(
                maxWidth: constraints.maxWidth,
                onPressed: usable
                    ? () => setState(() => _editing = !_editing)
                    : null,
                icon: _editing ? Icons.timeline : Icons.edit_outlined,
                label: _editing
                    ? l10n.d('Tijdlijn bekijken')
                    : l10n.d('Gebeurtenissen bewerken'),
              ),
              _timelineActionButton(
                maxWidth: constraints.maxWidth,
                onPressed: () =>
                    _replace(_tableSource, asTable: true, discrete: true),
                icon: Icons.table_chart_outlined,
                label: l10n.d('Als tabel weergeven'),
              ),
            ],
          ),
        ),
        if (_editing)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 6),
                child: Text(
                  l10n.d(
                    'Een datum blijft een datum. Kies je ook een tijd, dan slaat OciDeck het tijdstip op in UTC en toont het met de lokale UTC-offset.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              DocumentMarkdownView(
                _tableSource,
                maxTextWidth: null,
                themeProfile: widget.profile,
                chartTheme: widget.profile,
                tableEditController: _editor,
                tableToolbarExtras: _momentToolbar,
                onSortTableColumn: (column, intent) => switch (intent) {
                  TableSortIntent.ascending => _sort(column, true),
                  TableSortIntent.descending => _sort(column, false),
                  TableSortIntent.choose => _sortAs(column),
                },
              ),
            ],
          )
        else
          GestureDetector(
            onDoubleTap: () => setState(() => _editing = true),
            child: DocumentMarkdownView(
              _currentSource,
              maxTextWidth: null,
              themeProfile: widget.profile,
              chartTheme: widget.profile,
            ),
          ),
      ],
    );
  }

  String _timelineIssueMessage(
    BuildContext context,
    TimelineTableAnalysis analysis,
  ) => switch (analysis.issue) {
    TimelineTableIssue.wrongColumnCount => context.l10n.d(
      'Een tijdlijn werkt met twee of drie kolommen. Pas de tabel aan of toon hem als gewone tabel.',
    ),
    TimelineTableIssue.noEvents => context.l10n.d(
      'Voeg minstens één gebeurtenis toe of toon dit als gewone tabel.',
    ),
    _ => context.l10n.d(
      'Deze tijdlijn is nog niet compleet. Pas de tabel aan of toon hem als gewone tabel.',
    ),
  };

  Widget _timelineActionButton({
    required double maxWidth,
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
  }) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: TextButton(
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Flexible(child: Text(label)),
        ],
      ),
    ),
  );
}
