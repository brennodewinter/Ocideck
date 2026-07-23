import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/scorecard_spec.dart';
import '../../models/slide.dart';
import '../../theme/app_theme.dart';
import '_editor_field.dart';

/// Editor for a `scorecard` slide: a title plus up to [scorecardMaxEntries]
/// headline figures, each with the figure from the previous report and a
/// polarity saying whether a rise is good news. Emits the slide title and
/// `tableRows` via [ScorecardSpec]; storage stays a Markdown table.
///
/// The previous figure is typed in, not computed: a deck holds one report, so
/// the app has nothing to compare against. That also means the figure can come
/// straight from a generator that already knows both numbers.
///
/// One figure is one compact card of two rows, and the two explanations that
/// used to be repeated under every card now sit once under the section heading
/// and on the polarity field itself — with five figures on screen the repetition
/// was most of the panel. Ordering is a drag handle, as everywhere else in the
/// app that has a reorderable list (bullets, timeline, slides, connections).
class ScorecardEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final bool nestedInScrollView;

  const ScorecardEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.nestedInScrollView = false,
  });

  @override
  State<ScorecardEditor> createState() => _ScorecardEditorState();
}

class _EntryControllers {
  _EntryControllers(ScorecardEntry entry, VoidCallback onChanged)
    : label = TextEditingController(text: entry.label)..addListener(onChanged),
      value = TextEditingController(
        text: entry.value == null ? '' : formatScorecardNumber(entry.value!),
      )..addListener(onChanged),
      previous = TextEditingController(
        text: entry.previous == null
            ? ''
            : formatScorecardNumber(entry.previous!),
      )..addListener(onChanged),
      unit = TextEditingController(text: entry.unit)..addListener(onChanged),
      polarity = entry.polarity;

  final TextEditingController label;
  final TextEditingController value;
  final TextEditingController previous;
  final TextEditingController unit;
  ScorecardPolarity polarity;

  ScorecardEntry toEntry() => ScorecardEntry(
    label: label.text.trim(),
    value: parseScorecardNumber(value.text),
    previous: parseScorecardNumber(previous.text),
    unit: unit.text.trim(),
    polarity: polarity,
  );

  void dispose() {
    label.dispose();
    value.dispose();
    previous.dispose();
    unit.dispose();
  }
}

class _ScorecardEditorState extends State<ScorecardEditor> {
  late final TextEditingController _title;
  late List<_EntryControllers> _entries;

  @override
  void initState() {
    super.initState();
    final spec = ScorecardSpec.fromSlide(
      widget.slide.title,
      widget.slide.tableRows,
    );
    _title = TextEditingController(text: spec.title)..addListener(_emit);
    _entries = spec.entries.map((e) => _EntryControllers(e, _emit)).toList();
    // A fresh slide carries only the header, because blank rows have no
    // business on disk. The editor hands out the first one to fill in.
    if (_entries.isEmpty) {
      _entries = [_EntryControllers(const ScorecardEntry(), _emit)];
    }
  }

  @override
  void dispose() {
    _title.dispose();
    for (final entry in _entries) {
      entry.dispose();
    }
    super.dispose();
  }

  void _emit() {
    final spec = ScorecardSpec(
      title: _title.text.trim(),
      entries: _entries.map((e) => e.toEntry()).toList(),
    );
    widget.onUpdate(
      widget.slide.copyWith(title: spec.title, tableRows: spec.toTableRows()),
    );
  }

  void _addEntry() {
    setState(
      () => _entries.add(_EntryControllers(const ScorecardEntry(), _emit)),
    );
    _emit();
  }

  void _removeEntry(int index) {
    setState(() => _entries.removeAt(index).dispose());
    _emit();
  }

  /// Both indexes count in the final list — [ReorderableListView.onReorderItem]
  /// hands them over pre-adjusted, so no off-by-one correction here.
  void _reorder(int from, int to) {
    setState(() => _entries.insert(to, _entries.removeAt(from)));
    _emit();
  }

  void _setPolarity(int index, ScorecardPolarity polarity) {
    setState(() => _entries[index].polarity = polarity);
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final full = _entries.length >= scorecardMaxEntries;
    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        EditorField(
          label: 'Titel',
          controller: _title,
          hint: 'Sinds de vorige rapportage',
        ),
        const SizedBox(height: 16),
        // Heading with the running count, like the cockpit's meter list: the
        // ceiling is a design limit, so say how much room is left before the
        // author runs into it.
        Row(
          children: [
            Icon(Icons.insights_outlined, size: 16, color: AppTheme.tealFg),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l10n.d('Cijfers'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.brandFg,
                ),
              ),
            ),
            Text(
              '${_entries.length}/$scorecardMaxEntries',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.slate500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          l10n.d(
            'Laat de vorige rapportage leeg als er nog geen meting was; de slide toont dan geen verandering.',
          ),
          style: TextStyle(fontSize: 11, color: AppTheme.slate400),
        ),
        const SizedBox(height: 8),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: _reorder,
          children: [
            for (var i = 0; i < _entries.length; i++) _entryCard(context, i),
          ],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Tooltip(
            // Say why the button is dead rather than leaving the author to
            // wonder — the ceiling is a deliberate readability limit.
            message: full
                ? l10n.d(
                    'Een scorecard toont hoogstens vijf cijfers; meer leest niet meer als een oordeel.',
                  )
                : '',
            child: OutlinedButton.icon(
              onPressed: full ? null : _addEntry,
              icon: const Icon(Icons.add, size: 16),
              label: Text(l10n.d('Cijfer toevoegen')),
            ),
          ),
        ),
      ],
    );
  }

  Widget _entryCard(BuildContext context, int index) {
    final l10n = context.l10n;
    final entry = _entries[index];
    return Padding(
      key: ValueKey(entry),
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.slate300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(
                    Icons.drag_indicator,
                    size: 16,
                    color: AppTheme.slate300,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${l10n.d('Cijfer')} ${index + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.brandFg,
                  ),
                ),
                const Spacer(),
                // The change as the slide will show it, next to the numbers
                // that produce it: the polarity choice is abstract until you
                // see it come out green or red.
                _changeChip(entry),
                IconButton(
                  tooltip: l10n.d('Cijfer verwijderen'),
                  onPressed: _entries.length > 1
                      ? () => _removeEntry(index)
                      : null,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: AppTheme.slate500,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _field(
                    controller: entry.label,
                    label: l10n.d('Label'),
                    hint: l10n.d('Open bevindingen'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _field(
                    controller: entry.unit,
                    label: l10n.d('Eenheid'),
                    hint: l10n.d('dagen'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // The two figures and the direction fit one row in a normally sized
            // editor panel; in a narrow one the direction drops to its own row
            // rather than squeezing "Vorige rapportage" into an unreadable
            // sliver. The panel is user-resizable, so this is a real case.
            LayoutBuilder(
              builder: (context, constraints) {
                final numbers = [
                  Expanded(
                    flex: 2,
                    child: _field(
                      controller: entry.value,
                      label: l10n.d('Nu'),
                      hint: '96',
                      numeric: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: _field(
                      controller: entry.previous,
                      label: l10n.d('Vorige rapportage'),
                      hint: '120',
                      numeric: true,
                    ),
                  ),
                ];
                if (constraints.maxWidth < 380) {
                  return Column(
                    children: [
                      Row(children: numbers),
                      const SizedBox(height: 8),
                      _polarityDropdown(context, index),
                    ],
                  );
                }
                return Row(
                  children: [
                    ...numbers,
                    const SizedBox(width: 8),
                    Expanded(flex: 3, child: _polarityDropdown(context, index)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// A dense bordered field: the label lives inside the border instead of above
  /// it, which is what buys the compact two-row card (same shape as the cockpit
  /// meter fields).
  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool numeric = false,
  }) => TextField(
    controller: controller,
    keyboardType: numeric
        ? const TextInputType.numberWithOptions(decimal: true, signed: true)
        : null,
    style: const TextStyle(fontSize: 13),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    ),
  );

  Widget _polarityDropdown(BuildContext context, int index) {
    final l10n = context.l10n;
    return Tooltip(
      message: l10n.d(
        'Bepaalt of een stijging groen of rood kleurt. De pijl volgt altijd de cijfers.',
      ),
      child: DropdownButtonFormField<ScorecardPolarity>(
        initialValue: _entries[index].polarity,
        isDense: true,
        isExpanded: true,
        style: TextStyle(fontSize: 13, color: AppTheme.brandFg),
        decoration: InputDecoration(
          labelText: l10n.d('Richting'),
          isDense: true,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 12,
          ),
        ),
        items: [
          for (final polarity in ScorecardPolarity.values)
            DropdownMenuItem(
              value: polarity,
              child: Text(
                l10n.d(scorecardPolarityDutchLabel(polarity)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (v) => _setPolarity(index, v ?? ScorecardPolarity.neutral),
      ),
    );
  }

  /// The change this row will put on the slide, in the colour it will have
  /// there. Nothing at all while there is no previous figure to compare
  /// against — the slide shows nothing then either.
  ///
  /// Rebuilt straight off the two number fields, so it tracks typing without
  /// rebuilding the whole panel on every keystroke. A polarity change already
  /// goes through `setState`.
  Widget _changeChip(_EntryControllers controllers) => ListenableBuilder(
    listenable: Listenable.merge([controllers.value, controllers.previous]),
    builder: (context, _) => _changeChipFor(controllers.toEntry()),
  );

  Widget _changeChipFor(ScorecardEntry entry) {
    final direction = entry.direction;
    final delta = entry.delta;
    if (direction == null || delta == null) return const SizedBox.shrink();
    final color = switch (entry.sentiment) {
      ScorecardSentiment.good => AppTheme.successFg,
      ScorecardSentiment.bad => AppTheme.dangerFg,
      ScorecardSentiment.neutral => AppTheme.slate500,
    };
    final icon = switch (direction) {
      ScorecardDirection.up => Icons.arrow_upward_rounded,
      ScorecardDirection.down => Icons.arrow_downward_rounded,
      ScorecardDirection.flat => Icons.remove_rounded,
    };
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(
            direction == ScorecardDirection.flat
                ? context.l10n.d('ongewijzigd')
                : formatScorecardDelta(delta),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
