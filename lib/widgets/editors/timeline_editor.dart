import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/slide.dart';
import '../../models/timeline.dart';
import '../../theme/app_theme.dart';
import '_editor_field.dart';

/// Editor for a timeline slide: a title, a reorderable list of events (each with
/// a marker, title and optional description) and the layout/animation options.
/// Events are stored in [Slide.bullets] as `marker :: title :: description`.
class TimelineEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final bool nestedInScrollView;

  const TimelineEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.nestedInScrollView = false,
  });

  @override
  State<TimelineEditor> createState() => _TimelineEditorState();
}

class _EventRow {
  final TextEditingController marker;
  final TextEditingController title;
  final TextEditingController description;
  final FocusNode titleFocus;

  _EventRow(TimelineEvent e)
    : marker = TextEditingController(text: e.marker),
      title = TextEditingController(text: e.title),
      description = TextEditingController(text: e.description),
      titleFocus = FocusNode();

  TimelineEvent toEvent() => TimelineEvent(
    marker: marker.text.trim(),
    title: title.text.trim(),
    description: description.text.trim(),
  );

  void dispose() {
    marker.dispose();
    title.dispose();
    description.dispose();
    titleFocus.dispose();
  }
}

class _TimelineEditorState extends State<TimelineEditor> {
  late final TextEditingController _title;
  late List<_EventRow> _rows;
  late TimelineLayout _layout;
  late TimelineReveal _reveal;
  late int _animationMs;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.slide.title);
    _title.addListener(_emit);
    _layout = widget.slide.timelineLayout;
    _reveal = widget.slide.timelineReveal;
    _animationMs = clampTimelineDuration(widget.slide.timelineAnimationMs);
    _initRows(parseTimelineEvents(widget.slide.bullets));
  }

  void _initRows(List<TimelineEvent> events) {
    _rows = (events.isEmpty ? [const TimelineEvent()] : events)
        .map(_makeRow)
        .toList();
  }

  _EventRow _makeRow(TimelineEvent e) {
    final row = _EventRow(e);
    row.marker.addListener(_emit);
    row.title.addListener(_emit);
    row.description.addListener(_emit);
    return row;
  }

  @override
  void dispose() {
    _title.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _emit() {
    final events = _rows.map((r) => r.toEvent()).where((e) => !e.isEmpty);
    widget.onUpdate(
      widget.slide.copyWith(
        title: _title.text,
        bullets: timelineEventsToBullets(events.toList()),
        timelineLayout: _layout,
        timelineReveal: _reveal,
        timelineAnimationMs: _animationMs,
      ),
    );
  }

  void _addEvent() {
    setState(() => _rows.add(_makeRow(const TimelineEvent())));
    _emit();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rows.last.titleFocus.requestFocus();
    });
  }

  void _removeEvent(int i) {
    if (_rows.length == 1) {
      setState(() {
        _rows[i].marker.clear();
        _rows[i].title.clear();
        _rows[i].description.clear();
      });
      _emit();
      return;
    }
    setState(() {
      _rows.removeAt(i).dispose();
    });
    _emit();
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final row = _rows.removeAt(oldIndex);
      _rows.insert(newIndex, row);
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        EditorField(label: 'Titel', controller: _title, hint: 'Slide titel'),
        const SizedBox(height: 16),
        _choiceRow<TimelineLayout>(
          label: l10n.d('Indeling'),
          value: _layout,
          options: [
            (TimelineLayout.auto, l10n.d('Automatisch')),
            (TimelineLayout.horizontal, l10n.d('Horizontaal')),
            (TimelineLayout.vertical, l10n.d('Verticaal')),
          ],
          onChanged: (v) {
            setState(() => _layout = v);
            _emit();
          },
        ),
        const SizedBox(height: 12),
        _choiceRow<TimelineReveal>(
          label: l10n.d('Animatie'),
          value: _reveal,
          options: [
            (TimelineReveal.onEnter, l10n.d('Intekenen bij openen')),
            (TimelineReveal.steps, l10n.d('Stap voor stap')),
            (TimelineReveal.instant, l10n.d('Geen animatie')),
          ],
          onChanged: (v) {
            setState(() => _reveal = v);
            _emit();
          },
        ),
        if (_reveal == TimelineReveal.onEnter) _buildSpeedSlider(),
        const SizedBox(height: 16),
        SectionLabel(l10n.d('Gebeurtenissen')),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: _reorder,
          children: [for (var i = 0; i < _rows.length; i++) _buildEventRow(i)],
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addEvent,
            icon: const Icon(Icons.add, size: 16),
            label: Text(l10n.d('Gebeurtenis toevoegen')),
          ),
        ),
      ],
    );
  }

  Widget _buildEventRow(int i) {
    final l10n = context.l10n;
    final row = _rows[i];
    return Padding(
      key: ValueKey(row),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ReorderableDragStartListener(
                index: i,
                child: const Icon(
                  Icons.drag_indicator,
                  size: 16,
                  color: Color(0xFFCBD5E1),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 96,
                        child: TextField(
                          controller: row.marker,
                          decoration: InputDecoration(
                            labelText: l10n.d('Markering'),
                            hintText: l10n.d('bijv. 2024'),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: row.title,
                          focusNode: row.titleFocus,
                          decoration: InputDecoration(
                            labelText: l10n.d('Titel van gebeurtenis'),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: row.description,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      labelText: l10n.d('Omschrijving (optioneel)'),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.remove_circle_outline,
                size: 18,
                color: Color(0xFF64748B),
              ),
              onPressed: () => _removeEvent(i),
              tooltip: l10n.d('Verwijder'),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(minWidth: 28),
            ),
          ],
        ),
      ),
    );
  }

  /// Draw-in duration slider, mirroring the cockpit animation control: the
  /// value is the duration itself (left = short/fast, right = long/slow), with a
  /// seconds readout, so it behaves like every other animation bar in the app.
  Widget _buildSpeedSlider() {
    final seconds = _animationMs / 1000;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined, size: 18, color: Color(0xFF64748B)),
          const SizedBox(width: 8),
          Text(
            context.l10n.d('Activatieduur'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.navy,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Slider(
              min: timelineMinAnimationDurationMs.toDouble(),
              max: timelineMaxAnimationDurationMs.toDouble(),
              divisions:
                  (timelineMaxAnimationDurationMs -
                      timelineMinAnimationDurationMs) ~/
                  200,
              label: '${seconds.toStringAsFixed(1)}s',
              value: _animationMs
                  .clamp(
                    timelineMinAnimationDurationMs,
                    timelineMaxAnimationDurationMs,
                  )
                  .toDouble(),
              onChanged: (value) {
                setState(
                  () => _animationMs = clampTimelineDuration(
                    (value / 100).round() * 100,
                  ),
                );
                _emit();
              },
            ),
          ),
          SizedBox(
            width: 42,
            child: Text(
              '${seconds.toStringAsFixed(1)}s',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _choiceRow<T>({
    required String label,
    required T value,
    required List<(T, String)> options,
    required ValueChanged<T> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(label),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (option, optionLabel) in options)
              ChoiceChip(
                label: Text(optionLabel),
                selected: value == option,
                onSelected: (_) => onChanged(option),
              ),
          ],
        ),
      ],
    );
  }
}
