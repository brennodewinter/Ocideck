import 'package:flutter/material.dart';
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
import 'table_sort_actions.dart';

/// Tekent marker en tabel als één verliesvrij tijdlijnblok in de visuele editor.
class TimelineTableEmbedBuilder extends EmbedBuilder {
  const TimelineTableEmbedBuilder({this.onDiscreteEdit});

  final VoidCallback? onDiscreteEdit;

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
      source: source,
      profile: profile,
      embedContext: embedContext,
      onDiscreteEdit: onDiscreteEdit,
    );
  }
}

class _EditableTimelineEmbed extends StatefulWidget {
  const _EditableTimelineEmbed({
    required this.source,
    required this.profile,
    required this.embedContext,
    required this.onDiscreteEdit,
  });

  final String source;
  final ThemeProfile? profile;
  final EmbedContext embedContext;
  final VoidCallback? onDiscreteEdit;

  @override
  State<_EditableTimelineEmbed> createState() => _EditableTimelineEmbedState();
}

class _EditableTimelineEmbedState extends State<_EditableTimelineEmbed> {
  late TableEditController _editor;
  bool _editing = false;
  String? _pending;
  bool _flushScheduled = false;

  String get _currentSource => _pending ?? widget.source;
  String get _tableSource => unmarkTimeline(_currentSource);

  @override
  void initState() {
    super.initState();
    _editor = _makeController();
    _editing = !analyzeMarkedTimeline(widget.source).isUsable;
  }

  @override
  void didUpdateWidget(_EditableTimelineEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _editor.dispose();
      _editor = _makeController();
    }
  }

  TableEditController _makeController() {
    final decoded = decodeMarkdownTableWithAlignment(_tableSource.split('\n'));
    return TableEditController(
      rows: decoded.rows,
      alignments: decoded.alignments,
      onChanged: _writeBack,
      // Zie table_embed_builder.dart: Quill's _TransparentTapGestureRecognizer
      // kaapt de TextInputConnection terug na een tap op de cel (#1718).
      onCellFocused: () =>
          widget.embedContext.controller.skipRequestKeyboard = true,
    );
  }

  void _writeBack(List<List<String>> rows, List<TableAlign> alignments) {
    _pending = markTableAsTimeline(
      encodeMarkdownTable(rows, alignments: alignments),
    );
    if (_flushScheduled) return;
    _flushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushScheduled = false;
      if (mounted && _pending != null) _replace(_pending!);
      _pending = null;
    });
  }

  void _replace(String source, {bool asTable = false, bool discrete = false}) {
    final node = widget.embedContext.node;
    if (node.parent == null || source == widget.source) return;
    if (discrete) widget.onDiscreteEdit?.call();
    widget.embedContext.controller.replaceText(
      node.documentOffset,
      1,
      asTable ? EmbeddableTable(source) : EmbeddableTimelineTable(source),
      null,
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

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
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
          DocumentMarkdownView(
            _tableSource,
            maxTextWidth: null,
            themeProfile: widget.profile,
            chartTheme: widget.profile,
            tableEditController: _editor,
            onSortTableColumn: (column, intent) => switch (intent) {
              TableSortIntent.ascending => _sort(column, true),
              TableSortIntent.descending => _sort(column, false),
              TableSortIntent.choose => _sortAs(column),
            },
          )
        else
          GestureDetector(
            onDoubleTap: () => setState(() => _editing = true),
            child: DocumentMarkdownView(
              widget.source,
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
