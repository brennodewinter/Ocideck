import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:markdown_quill/markdown_quill.dart';

import '../../l10n/app_localizations.dart';
import '../../models/settings.dart' show ThemeProfile;
import '../../services/markdown_table_codec.dart';
import '../../services/ocideck_marked_table.dart';
import '../../services/ocideck_markers.dart';
import '../../services/risk_calc.dart';
import '../../services/risk_dossier.dart';
import '../../services/risk_view.dart';
import '../../utils/markdown_quill_codec.dart';
import '../../utils/ocideck_table_embed_syntax.dart';
import '../../utils/table_row_permutation.dart';
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
      wrapTable: (table) {
        final wrapped = markOciTable(_markerLines, table);
        _guardCalcOverwrite(wrapped);
        return wrapped;
      },
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

  /// "Gekoppelde weergave…" op een brontabel: kies de projectie en de
  /// materialisatie landt als eigen embed direct ná dit blok (#2489). De
  /// weergave is meteen bruikbaar — de cellen staan er al, de marker is de
  /// enige koppeling die OciDeck extra begrijpt.
  Future<void> _insertLinkedView() async {
    final table = scanOciMarkedTables(_source).tables.firstOrNull;
    final id = table?.id;
    if (table == null || id == null) return;
    final l10n = context.l10n;
    final projection = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.d('Gekoppelde weergave toevoegen')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'bruto'),
            child: Text(
              l10n.d('Bruto — alleen de oorspronkelijke inschatting'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'netto'),
            child: Text(l10n.d('Netto — alleen de inschatting ná maatregelen')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'overview'),
            child: Text(l10n.d('Overzicht — bruto én netto naast elkaar')),
          ),
        ],
      ),
    );
    if (!mounted || projection == null) return;
    final docMd = MarkdownQuillCodec.markdownFromDocument(
      widget.embedContext.controller.document,
    );
    final block = createOciViewBlock(RiskDossier.read(docMd), id, projection);
    if (block == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.d('Deze projectie past niet bij de methode van de bron.'),
          ),
        ),
      );
      return;
    }
    // Na dit blok invoegen: de embed zelf is één positie, de witregel ertussen
    // de tweede — zoals elke blokinvoeging in deze editor werkt.
    final controller = widget.embedContext.controller;
    final at =
        widget.embedContext.node.documentOffset +
        widget.embedContext.node.length;
    controller.compose(
      Delta()
        ..retain(at)
        ..insert('\n')
        ..insert(EmbeddableOciMarkedTable(block).toJson()),
      const TextSelection.collapsed(offset: 0),
      ChangeSource.local,
    );
    widget.onDiscreteEdit?.call();
  }

  /// "Verversen" op een gekoppelde weergave: herbouw de materialisatie uit
  /// de brontabel in dít document en zet `gen=` op diens `rev`. Expliciete
  /// handeling — een handedit in de weergave verdwijnt dan wel, maar alleen
  /// na een bewuste knop, nooit stilletjes (D2, #2490 laat de discrepantie
  /// eerst zien).
  void _refreshView() {
    final view = scanOciMarkedTables(_source).tables.firstOrNull;
    if (view == null) return;
    final docMd = MarkdownQuillCodec.markdownFromDocument(
      widget.embedContext.controller.document,
    );
    final dossier = RiskDossier.read(docMd);
    final rows = ociViewMaterialize(dossier, view);
    if (rows == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.d('De brontabel van deze weergave is niet gevonden.'),
          ),
        ),
      );
      return;
    }
    final carrier = view.marker!;
    final sourceTable = dossier.tableById(carrier.attr('source')!);
    final rev = sourceTable?.rev;
    final markers = [
      for (final m in view.markers)
        identical(m, carrier)
            ? carrier.withAttr('gen', rev == null ? null : '$rev')
            : m,
    ];
    _binding.clearPending();
    _binding.replaceSource(
      markOciTable([
        for (final m in markers) m.toComment(),
      ], encodeMarkdownTable(rows)),
      discrete: true,
      onDiscreteEdit: widget.onDiscreteEdit,
    );
  }

  /// De overschrijf-poort van #2491: een calc-kolom is afgeleid — typen
  /// erin verwijdert de formule niet (de marker reist gewoon mee), maar de
  /// cel staat dan in drift. De poort biedt meteen de keuze die de
  /// specificatie vraagt: terug, de formule bewerken, of de formule
  /// bewust vervangen. Een rij-permutatie (sortering) is géén overschrijving —
  /// verwijzingen volgen ID's, niet posities (§3.7).
  bool _calcGuardOpen = false;

  void _guardCalcOverwrite(String newSource) {
    if (_calcGuardOpen) return;
    final oldTable = scanOciMarkedTables(_source).tables.firstOrNull;
    final newTable = scanOciMarkedTables(newSource).tables.firstOrNull;
    if (oldTable == null || newTable == null) return;
    final defs = ociCalcDefs(oldTable);
    if (defs.isEmpty) return;
    final oldRows = oldTable.bodyRows;
    final newRows = newTable.bodyRows;
    if (isTableRowPermutation(oldRows, newRows) ||
        isTableRowPermutation(newRows, oldRows)) {
      return;
    }
    final changed = <String>{};
    for (final def in defs) {
      final c = oldTable.colIndexOf(def.col);
      if (c < 0) continue;
      for (var r = 0; r < oldRows.length && r < newRows.length; r++) {
        final o = c < oldRows[r].length ? oldRows[r][c] : '';
        final n = c < newRows[r].length ? newRows[r][c] : '';
        if (o.trim() != n.trim()) changed.add(def.col);
      }
    }
    if (changed.isEmpty) return;
    _calcGuardOpen = true;
    final before = _source;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_offerCalcOverwrite(changed.toList(), before));
      } else {
        _calcGuardOpen = false;
      }
    });
  }

  /// De keuze bij een overschrijving van een afgeleide kolom (#2491):
  /// invoer ongedaan maken, de formule bewerken, of de formule bewust
  /// vervangen — die laatste noemt zijn gevolg. Annuleren laat alles
  /// intact; elke keuze is één ongedaan-bare stap.
  Future<void> _offerCalcOverwrite(List<String> cols, String before) async {
    final l10n = context.l10n;
    try {
      final choice = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.d('Afgeleide cel overschreven')),
          content: Text(
            l10n.d(
              'Je typte in een berekende kolom (${cols.join(', ')}). '
              'De formule is nog niet weg — wat was de bedoeling?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: Text(l10n.d('Terugzetten')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'edit'),
              child: Text(l10n.d('Formule bewerken')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, 'replace'),
              child: Text(l10n.d('Formule vervangen')),
            ),
          ],
        ),
      );
      if (!mounted || choice == null || choice == 'cancel') {
        if (choice == 'cancel') _revertTo(before);
        return;
      }
      if (choice == 'edit') {
        _revertTo(before);
        unawaited(_editCalc(col: cols.first));
        return;
      }
      // 'replace': de formule gaat weg, de getypte tekst blijft — het
      // expliciete, ongedaan-bare einde van de calc-marker.
      var next = _source;
      for (final col in cols) {
        final t = scanOciMarkedTables(next).tables.firstOrNull;
        if (t == null) break;
        next = removeOciCalcFromTable(next, t, col);
      }
      _binding.clearPending();
      _binding.replaceSource(
        next,
        discrete: true,
        onDiscreteEdit: widget.onDiscreteEdit,
      );
    } finally {
      _calcGuardOpen = false;
    }
  }

  void _revertTo(String before) {
    _binding.clearPending();
    _binding.replaceSource(
      before,
      discrete: true,
      onDiscreteEdit: widget.onDiscreteEdit,
    );
  }

  /// "Berekening toevoegen" / "Formule bewerken" (#2491): kies een
  /// contractkolom, schrijf de §3.7-expressie, zie de uitkomst op de
  /// eerste rijen — en pas dan landt hij, meteen materialiseerd.
  Future<void> _editCalc({String? col}) async {
    final table = scanOciMarkedTables(_source).tables.firstOrNull;
    if (table == null) return;
    final defs = ociCalcDefs(table);
    final existing = col == null
        ? null
        : defs.where((d) => d.col == col).firstOrNull;
    final freeCols = [
      for (final key in table.cols)
        if (!defs.any((d) => d.col == key) || key == col) key,
    ];
    if (freeCols.isEmpty) return;
    final l10n = context.l10n;
    final exprController = TextEditingController(text: existing?.expr ?? '');
    var chosen = existing?.col ?? freeCols.first;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setD) {
          // Preview door de echte evaluator: de probe-tabel draagt de
          // formule alsof hij al landde — dezelfde uitkomst, geen aparte
          // rekenweg.
          final probeCalc = OciTableMarker(
            kind: OciMarkerKinds.calc,
            attrs: {'col': chosen, 'expr': exprController.text},
          );
          final probeBlock = markOciTable([
            for (final m in _markerLines)
              if (parseOciTableMarker(m)?.kind != OciMarkerKinds.calc ||
                  parseOciTableMarker(m)?.attr('col') != chosen)
                m,
            probeCalc.toComment(),
          ], _binding.tableSource);
          final probeTable = scanOciMarkedTables(probeBlock).tables.first;
          final probeEval = evaluateOciTableCalc(probeTable);
          final previews = <String>[
            for (var r = 0; r < probeEval.results.length && r < 2; r++)
              formatCalcValue(probeEval.results[r].last.value),
          ];
          return AlertDialog(
            title: Text(
              existing == null
                  ? l10n.d('Berekening toevoegen')
                  : l10n.d('Formule bewerken'),
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: chosen,
                    decoration: InputDecoration(
                      labelText: l10n.d('Afgeleide kolom'),
                    ),
                    items: [
                      for (final key in freeCols)
                        DropdownMenuItem(value: key, child: Text(key)),
                    ],
                    onChanged: (v) => setD(() => chosen = v ?? chosen),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: exprController,
                    onChanged: (_) => setD(() {}),
                    decoration: InputDecoration(
                      labelText: l10n.d('Expressie'),
                      hintText: 's_n * o_n * d_n',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${l10n.d('Voorbeeld')}: ${previews.join('  ·  ')}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.d(
                      '+ - * / ( ), kolomsleutels, sleutel@ID, '
                      'sum avg min max count wsum. Onbekend is nooit 0.',
                    ),
                    style: const TextStyle(fontSize: 10.5),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.t('cancel')),
              ),
              ElevatedButton(
                onPressed: exprController.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: Text(l10n.t('save')),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || confirmed != true) return;
    final calc = OciTableMarker(
      kind: OciMarkerKinds.calc,
      attrs: {'col': chosen, 'expr': exprController.text.trim()},
    );
    // De marker komt bij het blok (of vervangt zijn voorganger op die
    // kolom) en de kolom materialiseert meteen — de eerste afschrijving
    // klopt al voor elke lezer.
    final markers = [
      for (final m in _markerLines)
        if (parseOciTableMarker(m)?.attr('col') != chosen ||
            parseOciTableMarker(m)?.kind != OciMarkerKinds.calc)
          m,
      calc.toComment(),
    ];
    final block = markOciTable(markers, _binding.tableSource);
    final t = scanOciMarkedTables(block).tables.first;
    _binding.clearPending();
    _binding.replaceSource(
      recalculateOciTable(block, t),
      discrete: true,
      onDiscreteEdit: widget.onDiscreteEdit,
    );
  }

  /// "Formule verwijderen" — bevestigd, met zijn gevolg benoemd: de cellen
  /// houden hun laatste waarde als gewone tekst. De formule verdwijnt
  /// nooit zonder die keuze.
  Future<void> _removeCalc(String col) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.d('Formule verwijderen?')),
        content: Text(
          l10n.d(
            'De kolom "$col" wordt een gewone kolom: de cellen houden '
            'hun laatste berekende waarde als platte tekst.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.t('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.d('Verwijderen')),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final table = scanOciMarkedTables(_source).tables.firstOrNull;
    if (table == null) return;
    _binding.clearPending();
    _binding.replaceSource(
      removeOciCalcFromTable(_source, table, col),
      discrete: true,
      onDiscreteEdit: widget.onDiscreteEdit,
    );
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
    final isView = carrier?.kind == OciMarkerKinds.view;
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
            // Op een bronregister: een gekoppelde projectie eronder maken.
            if (carrier?.kind == OciMarkerKinds.risks)
              TextButton.icon(
                onPressed: () => unawaited(_insertLinkedView()),
                icon: const Icon(Icons.table_view_outlined, size: 16),
                label: Text(
                  l10n.d('Gekoppelde weergave…'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            // Eén chip per afgeleide kolom: "ƒ kolom = formule", met de
            // enige twee handelingen die erop passen — bewerken of de
            // bewuste, bevestigde verwijdering (#2491).
            if (table != null && !isView)
              for (final def in ociCalcDefs(table))
                InputChip(
                  avatar: const Icon(Icons.functions, size: 15),
                  label: Text(
                    'ƒ ${def.col} = ${def.expr}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => unawaited(_editCalc(col: def.col)),
                  onDeleted: () => unawaited(_removeCalc(def.col)),
                  deleteButtonTooltipMessage: l10n.d('Formule verwijderen'),
                ),
            // "Berekening toevoegen" kan op elke contracttabel met
            // kolomsleutels.
            if (carrier != null && !isView && (table?.cols.isNotEmpty ?? false))
              TextButton.icon(
                onPressed: () => unawaited(_editCalc()),
                icon: const Icon(Icons.functions, size: 16),
                label: Text(
                  l10n.d('Berekening…'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            // Een weergave is een materialisatie: de cellen horen bij de
            // bron, niet bij handedit — verversen is de enige schrijfweg.
            if (isView)
              TextButton.icon(
                onPressed: _refreshView,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(
                  l10n.d('Verversen'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            TextButton.icon(
              onPressed: _detach,
              icon: const Icon(Icons.link_off, size: 16),
              label: Text(
                isView
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
          // Een gekoppelde weergave is lees-only in de editor: de cellen
          // zijn afschriften van de bron en zouden bij de volgende verversing
          // toch verdwijnen (D2). Bron- en registertabellen bewerk je wel.
          tableEditController: isView ? null : _editor,
          onSortTableColumn: isView ? null : _sort,
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
