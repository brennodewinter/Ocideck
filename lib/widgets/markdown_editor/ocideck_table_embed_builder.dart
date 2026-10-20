import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:markdown_quill/markdown_quill.dart';

import '../../l10n/app_localizations.dart';
import '../../models/settings.dart' show ThemeProfile;
import '../../services/ocideck_marked_table.dart';
import '../../services/ocideck_markers.dart';
import '../../utils/ocideck_table_embed_syntax.dart';
import '../reader/document_markdown_view.dart';
import '../reader/table_edit_controller.dart';
import 'markdown_editor_theme.dart';
import 'table_embed_binding.dart';
import 'table_sort_actions.dart';

/// Tekent een `<!-- ocideck:* -->`-gemarkeerde contracttabel (risicodossier,
/// RISK_FORMAT) als één bewerkbare tabel mét contractbadge in de visuele
/// editor.
///
/// De badge vertelt welke rol de tabel speelt (`risks`, `view`, `bowtie`, …)
/// en met welke `id`. Dat is de "expliciete bronbadge" uit #2489: wie een
/// gekoppelde weergave ziet, ziet ook waar zijn brongegevens wonen. De tabel
/// zelf bewerk je als elke andere; mutaties aan de marker zelf (loskoppelen,
/// weergave verversen) zijn knoppen, geen onzichtbare rewrites.
class OciMarkedTableEmbedBuilder extends EmbedBuilder {
  const OciMarkedTableEmbedBuilder({
    required this.controllerStore,
    this.onDiscreteEdit,
  });

  final VoidCallback? onDiscreteEdit;
  final TableEmbedControllerStore controllerStore;

  @override
  String get key => EmbeddableOciMarkedTable.blockType;

  @override
  bool get expanded => true;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final source = (embedContext.node.value.data ?? '').toString();
    final profile = DocumentStyleScope.maybeOf(context);
    if (embedContext.readOnly) {
      return DocumentMarkdownView(
        splitOciMarkedBlock(source).table,
        maxTextWidth: null,
        themeProfile: profile,
        chartTheme: profile,
      );
    }
    return _EditableOciMarkedTable(
      source: source,
      profile: profile,
      embedContext: embedContext,
      onDiscreteEdit: onDiscreteEdit,
      controllerStore: controllerStore,
    );
  }
}

class _EditableOciMarkedTable extends StatefulWidget {
  const _EditableOciMarkedTable({
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
  State<_EditableOciMarkedTable> createState() =>
      _EditableOciMarkedTableState();
}

class _EditableOciMarkedTableState extends State<_EditableOciMarkedTable> {
  late TableEmbedBinding _binding;
  final GlobalKey _boundsKey = GlobalKey();

  TableEditController get _editor => _binding.editor;

  List<String> get _markerLines => splitOciMarkedBlock(_source).markerLines;
  String get _source => _binding.currentSource;

  @override
  void initState() {
    super.initState();
    widget.controllerStore.registerTableBounds(_boundsKey);
    _binding = TableEmbedBinding(
      controllerStore: widget.controllerStore,
      embedContext: widget.embedContext,
      source: widget.source,
      unwrapSource: (s) => splitOciMarkedBlock(s).table,
      wrapTable: (table) => markOciTable(_markerLines, table),
      makeEmbed: EmbeddableOciMarkedTable.new,
      isMounted: () => mounted,
    );
  }

  @override
  void didUpdateWidget(_EditableOciMarkedTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    _binding.reconnect(widget.embedContext, widget.source);
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

  /// "Loskoppelen als momentopname" (#2489/D2): de markerregels verdwijnen en
  /// wat overblijft is een gewone, leesbare tabel — dezelfde uitstap als de
  /// instap. Expliciet en ongedaan te maken, nooit stilletjes.
  void _detach() {
    final table = _binding.tableSource;
    _binding.clearPending();
    _binding.replaceSource(
      table,
      discrete: true,
      onDiscreteEdit: widget.onDiscreteEdit,
      embed: EmbeddableTable(table),
    );
  }

  /// De badge-tekst per contractsoort. Bewust geen vertaalde labels in het
  /// bestand — de badge is UI en lokaliseert, de marker blijft machinetaal.
  String _badgeText(BuildContext context, OciTableMarker marker) {
    final l10n = context.l10n;
    final kind = switch (marker.kind) {
      OciMarkerKinds.risks => l10n.d('Risicoregister'),
      OciMarkerKinds.measures => l10n.d('Maatregelenregister'),
      OciMarkerKinds.scale => l10n.d('Beoordelingsschaal'),
      OciMarkerKinds.view => l10n.d('Gekoppelde weergave'),
      OciMarkerKinds.bowtie => l10n.d('Bowtie-model'),
      _ => marker.kind,
    };
    final id = marker.attr('id');
    final source = marker.attr('source');
    final method = marker.attr('method');
    final parts = <String>[
      kind,
      if (id != null) '· $id',
      if (method != null) '· $method',
      if (marker.kind == OciMarkerKinds.view && source != null)
        '· ${l10n.d('bron')}: $source',
    ];
    return parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scan = scanOciMarkedTables(_source);
    final table = scan.tables.firstOrNull;
    final carrier = table?.marker;
    return Column(
      key: _boundsKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (carrier != null)
              Chip(
                avatar: const Icon(Icons.policy_outlined, size: 16),
                label: Text(
                  _badgeText(context, carrier),
                  style: const TextStyle(fontSize: 12),
                ),
                visualDensity: VisualDensity.compact,
              ),
            TextButton.icon(
              onPressed: _detach,
              icon: const Icon(Icons.link_off, size: 16),
              label: Text(
                carrier?.kind == OciMarkerKinds.view
                    ? l10n.d('Loskoppelen als momentopname')
                    : l10n.d('Marker verwijderen'),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        DocumentMarkdownView(
          _binding.tableSource,
          maxTextWidth: null,
          themeProfile: widget.profile,
          chartTheme: widget.profile,
          tableEditController: _editor,
          onSortTableColumn: _sort,
        ),
      ],
    );
  }

  @override
  void dispose() {
    widget.controllerStore.unregisterTableBounds(_boundsKey);
    _binding.dispose();
    super.dispose();
  }
}
