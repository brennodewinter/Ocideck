import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../models/findings_summary_spec.dart';
import '../../models/slide.dart';
import '../../services/cvss/cvss4.dart';
import '../../theme/app_theme.dart';
import '../../theme/finding_severity_palette.dart';
import '_editor_field.dart';

/// Editor for a `findingsSummary` slide (PENTEST_MIAUW §4.3.4 / §11): a title
/// plus the number of findings per CVSS 4.0 severity band. **Vernieuw uit deck**
/// recomputes the counts from the deck's finding slides ([deckFindingSeverities],
/// supplied by the editor panel, which has the deck); the counts remain editable
/// by hand afterwards. Emits the slide title + `tableRows` via
/// [FindingsSummarySpec]; storage stays a Markdown table.
class FindingsSummaryEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final bool nestedInScrollView;

  /// The severity band of every finding currently in the deck (see
  /// [deckFindingSeverities]); the source for "refresh from deck".
  final List<Cvss4Severity> deckFindingSeverities;

  /// How many deck findings are resolved after retest (see
  /// [deckRetestResolvedCount]); refreshed alongside the band counts.
  final int deckResolvedCount;

  const FindingsSummaryEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.deckFindingSeverities = const [],
    this.deckResolvedCount = 0,
    this.nestedInScrollView = false,
  });

  @override
  State<FindingsSummaryEditor> createState() => _FindingsSummaryEditorState();
}

class _FindingsSummaryEditorState extends State<FindingsSummaryEditor>
    with EditorTextControllers {
  late final TextEditingController _title;
  late final Map<Cvss4Severity, TextEditingController> _counts;
  late final TextEditingController _resolved;

  @override
  void initState() {
    super.initState();
    final spec = FindingsSummarySpec.fromSlide(
      widget.slide.title,
      widget.slide.tableRows,
    );
    _title = newController(spec.title, _emit);
    _counts = {
      for (final band in FindingsSummarySpec.order)
        band: newController('${spec.countOf(band)}', _emit),
    };
    _resolved = newController('${spec.resolved}', _emit);
  }

  void _emit() {
    final spec = FindingsSummarySpec(
      title: _title.text.trim(),
      counts: {
        for (final entry in _counts.entries)
          entry.key: int.tryParse(entry.value.text.trim()) ?? 0,
      },
      resolved: int.tryParse(_resolved.text.trim()) ?? 0,
    );
    widget.onUpdate(
      widget.slide.copyWith(title: spec.title, tableRows: spec.toTableRows()),
    );
  }

  void _refreshFromDeck() {
    final derived = FindingsSummarySpec.fromSeverities(
      '',
      widget.deckFindingSeverities,
    );
    for (final band in FindingsSummarySpec.order) {
      // Setting .text fires the controller's _emit listener; the trailing
      // _emit() covers the no-change case (all counts already equal).
      _counts[band]!.text = '${derived.countOf(band)}';
    }
    _resolved.text = '${widget.deckResolvedCount}';
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        EditorField(
          label: 'Titel',
          controller: _title,
          hint: 'Bevindingenoverzicht',
        ),
        const SizedBox(height: 16),
        const SectionLabel('Aantal bevindingen per ernst'),
        for (final band in FindingsSummarySpec.order) ...[
          _bandField(context, band),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 12),
        const SectionLabel('Hertest'),
        _resolvedField(context),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _refreshFromDeck,
            icon: const Icon(Icons.autorenew, size: 16),
            label: Text(l10n.d('Vernieuw uit deck')),
          ),
        ),
      ],
    );
  }

  Widget _bandField(BuildContext context, Cvss4Severity band) {
    final l10n = context.l10n;
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: FindingSeverityPalette.of(band),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            l10n.d(findingsSeverityDutchLabel(band)),
            style: TextStyle(fontSize: 13, color: AppTheme.slate700),
          ),
        ),
        SizedBox(
          width: 76,
          child: TextField(
            controller: _counts[band],
            keyboardType: TextInputType.number,
            textAlign: TextAlign.right,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(isDense: true),
          ),
        ),
      ],
    );
  }

  /// The "opgelost na hertest" total: derived from the deck's resolved findings
  /// on refresh, editable by hand afterwards (like the band counts).
  Widget _resolvedField(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: AppTheme.successFg,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            l10n.d('Opgelost na hertest'),
            style: TextStyle(fontSize: 13, color: AppTheme.slate700),
          ),
        ),
        SizedBox(
          width: 76,
          child: TextField(
            controller: _resolved,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.right,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(isDense: true),
          ),
        ),
      ],
    );
  }
}
