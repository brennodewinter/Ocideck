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
import 'markdown_editor_theme.dart';
import 'table_embed_builder.dart' show smartSortTable;

/// Tekent marker en tabel als één verliesvrij tijdlijnblok in de visuele editor.
class TimelineTableEmbedBuilder extends EmbedBuilder {
  const TimelineTableEmbedBuilder();

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
    );
  }
}

class _EditableTimelineEmbed extends StatefulWidget {
  const _EditableTimelineEmbed({
    required this.source,
    required this.profile,
    required this.embedContext,
  });

  final String source;
  final ThemeProfile? profile;
  final EmbedContext embedContext;

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

  void _replace(String source, {bool asTable = false}) {
    final node = widget.embedContext.node;
    if (node.parent == null || source == widget.source) return;
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
      _replace(markTableAsTimeline(sorted));
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.end,
          children: [
            TextButton.icon(
              onPressed: () => setState(() => _editing = !_editing),
              icon: Icon(_editing ? Icons.timeline : Icons.edit_outlined),
              label: Text(
                _editing
                    ? l10n.d('Tijdlijn bekijken')
                    : l10n.d('Gebeurtenissen bewerken'),
              ),
            ),
            TextButton.icon(
              onPressed: () => _replace(_tableSource, asTable: true),
              icon: const Icon(Icons.table_chart_outlined),
              label: Text(l10n.d('Als tabel weergeven')),
            ),
          ],
        ),
        if (_editing)
          DocumentMarkdownView(
            _tableSource,
            maxTextWidth: null,
            themeProfile: widget.profile,
            chartTheme: widget.profile,
            tableEditController: _editor,
            onSortTableColumn: _sort,
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
}
