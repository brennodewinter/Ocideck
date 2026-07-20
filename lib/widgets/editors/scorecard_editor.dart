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

  void _moveEntry(int from, int to) {
    if (to < 0 || to >= _entries.length) return;
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
        for (var i = 0; i < _entries.length; i++) ...[
          _entryCard(context, i),
          const SizedBox(height: 12),
        ],
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.slate300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: EditorField(
                  label: 'Label',
                  controller: entry.label,
                  hint: 'Open bevindingen',
                ),
              ),
              IconButton(
                tooltip: l10n.d('Omhoog'),
                onPressed: index > 0
                    ? () => _moveEntry(index, index - 1)
                    : null,
                icon: const Icon(Icons.arrow_upward, size: 18),
                color: AppTheme.slate500,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: l10n.d('Omlaag'),
                onPressed: index < _entries.length - 1
                    ? () => _moveEntry(index, index + 1)
                    : null,
                icon: const Icon(Icons.arrow_downward, size: 18),
                color: AppTheme.slate500,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: l10n.d('Cijfer verwijderen'),
                onPressed: _entries.length > 1
                    ? () => _removeEntry(index)
                    : null,
                icon: const Icon(Icons.delete_outline, size: 18),
                color: AppTheme.slate500,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: EditorField(
                  label: 'Nu',
                  controller: entry.value,
                  hint: '96',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: EditorField(
                  label: 'Vorige rapportage',
                  controller: entry.previous,
                  hint: '120',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: EditorField(
                  label: 'Eenheid',
                  controller: entry.unit,
                  hint: 'dagen',
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
          const SizedBox(height: 10),
          _polarityDropdown(context, index),
          const SizedBox(height: 4),
          Text(
            l10n.d(
              'Bepaalt of een stijging groen of rood kleurt. De pijl volgt altijd de cijfers.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ],
      ),
    );
  }

  Widget _polarityDropdown(BuildContext context, int index) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Richting'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.slate500,
          ),
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<ScorecardPolarity>(
          initialValue: _entries[index].polarity,
          isDense: true,
          items: [
            for (final polarity in ScorecardPolarity.values)
              DropdownMenuItem(
                value: polarity,
                child: Text(l10n.d(scorecardPolarityDutchLabel(polarity))),
              ),
          ],
          onChanged: (v) => _setPolarity(index, v ?? ScorecardPolarity.neutral),
        ),
      ],
    );
  }
}
