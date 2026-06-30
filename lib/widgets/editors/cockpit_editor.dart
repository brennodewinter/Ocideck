import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/cockpit.dart';
import '../../models/slide.dart';
import '../../theme/app_theme.dart';

/// Dutch source labels for the meter types; translated at display time via
/// [AppLocalizations.d]. The model's [cockpitMeterTypeLabel] stays English for
/// non-localized contexts (e.g. the painter fallback).
String _meterTypeSourceLabel(CockpitMeterType type) {
  switch (type) {
    case CockpitMeterType.speedometer:
      return 'Snelheidsmeter';
    case CockpitMeterType.voltmeter:
      return 'Voltmeter';
    case CockpitMeterType.thermometer:
      return 'Thermometer';
    case CockpitMeterType.altimeter:
      return 'Hoogtemeter';
    case CockpitMeterType.climbDescent:
      return 'Stijgen/dalen';
    case CockpitMeterType.horizon:
      return 'Kunstmatige horizon';
    case CockpitMeterType.heading:
      return 'Koers';
  }
}

class CockpitEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final bool nestedInScrollView;

  const CockpitEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.nestedInScrollView = false,
  });

  @override
  State<CockpitEditor> createState() => _CockpitEditorState();
}

class _CockpitEditorState extends State<CockpitEditor> {
  late CockpitSpec _spec;
  late final TextEditingController _titleController;

  @override
  void initState() {
    super.initState();
    _spec = CockpitSpec.parse(widget.slide.customMarkdown);
    _titleController = TextEditingController(text: widget.slide.title);
  }

  @override
  void didUpdateWidget(CockpitEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slide.id != widget.slide.id ||
        oldWidget.slide.customMarkdown != widget.slide.customMarkdown) {
      _spec = CockpitSpec.parse(widget.slide.customMarkdown);
    }
    if (oldWidget.slide.id != widget.slide.id ||
        oldWidget.slide.title != widget.slide.title) {
      if (_titleController.text != widget.slide.title) {
        _titleController.text = widget.slide.title;
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _emit(CockpitSpec spec) {
    final normalized = spec.copyWith();
    setState(() => _spec = normalized);
    widget.onUpdate(
      widget.slide.copyWith(customMarkdown: normalized.toBlock()),
    );
  }

  void _updateMeter(int index, CockpitMeterSpec meter) {
    final meters = [..._spec.meters];
    meters[index] = meter;
    _emit(_spec.copyWith(meters: meters));
  }

  void _addMeter() {
    if (_spec.meters.length >= cockpitMaxMeters) return;
    _emit(
      _spec.copyWith(
        meters: [
          ..._spec.meters,
          CockpitMeterSpec(
            label: 'Metric ${_spec.meters.length + 1}',
            value: 50,
          ),
        ],
      ),
    );
  }

  void _removeMeter(int index) {
    final meters = [..._spec.meters]..removeAt(index);
    _emit(_spec.copyWith(meters: meters));
  }

  void _moveMeter(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _spec.meters.length) return;
    final meters = [..._spec.meters];
    final item = meters.removeAt(index);
    meters.insert(target, item);
    _emit(_spec.copyWith(meters: meters));
  }

  @override
  Widget build(BuildContext context) {
    final meters = _spec.meters.isEmpty
        ? CockpitSpec.pentestPreset().meters
        : _spec.meters;
    if (_spec.meters.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _emit(_spec.copyWith(meters: meters)),
      );
    }

    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: l10n.d('Slidetitel'),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) =>
                widget.onUpdate(widget.slide.copyWith(title: value)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.speed_outlined, color: AppTheme.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.d('Cockpitmeters'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Text(
                '${meters.length}/$cockpitMaxMeters',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: meters.length >= cockpitMaxMeters ? null : _addMeter,
                icon: const Icon(Icons.add, size: 16),
                label: Text(l10n.d('Meter toevoegen')),
              ),
              FilterChip(
                label: Text(l10n.d('Animeren bij binnenkomst')),
                selected: _spec.animateOnEnter,
                onSelected: (value) =>
                    _emit(_spec.copyWith(animateOnEnter: value)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.palette_outlined,
                size: 15,
                color: Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.d(
                    'De statuskleuren volgen het cockpit-kleurschema; pas het aan of maak varianten via Instellingen → Cockpit.',
                  ),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          if (_spec.animateOnEnter) ...[
            const SizedBox(height: 10),
            _AnimationDurationControl(
              durationMs: _spec.animationDurationMs,
              onChanged: (value) =>
                  _emit(_spec.copyWith(animationDurationMs: value)),
            ),
          ],
          const SizedBox(height: 14),
          for (var i = 0; i < meters.length; i++) ...[
            _MeterCard(
              key: ValueKey('cockpit-meter-$i-${meters[i].type.name}'),
              index: i,
              meter: meters[i],
              onChanged: (meter) => _updateMeter(i, meter),
              onRemove: meters.length <= 1 ? null : () => _removeMeter(i),
              onMoveUp: i == 0 ? null : () => _moveMeter(i, -1),
              onMoveDown: i == meters.length - 1
                  ? null
                  : () => _moveMeter(i, 1),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _AnimationDurationControl extends StatelessWidget {
  final int durationMs;
  final ValueChanged<int> onChanged;

  const _AnimationDurationControl({
    required this.durationMs,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final seconds = durationMs / 1000;
    return Row(
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
            min: cockpitMinAnimationDurationMs.toDouble(),
            max: cockpitMaxAnimationDurationMs.toDouble(),
            divisions:
                (cockpitMaxAnimationDurationMs -
                    cockpitMinAnimationDurationMs) ~/
                200,
            label: '${seconds.toStringAsFixed(1)}s',
            value: durationMs
                .clamp(
                  cockpitMinAnimationDurationMs,
                  cockpitMaxAnimationDurationMs,
                )
                .toDouble(),
            onChanged: (value) => onChanged((value / 100).round() * 100),
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
    );
  }
}

class _MeterCard extends StatelessWidget {
  final int index;
  final CockpitMeterSpec meter;
  final ValueChanged<CockpitMeterSpec> onChanged;
  final VoidCallback? onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _MeterCard({
    super.key,
    required this.index,
    required this.meter,
    required this.onChanged,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    final type = meter.type;
    final l10n = context.l10n;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFCBD5E1)),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '${l10n.d('Meter')} ${index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.navy,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: l10n.d('Omhoog'),
                  onPressed: onMoveUp,
                  icon: const Icon(Icons.arrow_upward, size: 16),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: l10n.d('Omlaag'),
                  onPressed: onMoveDown,
                  icon: const Icon(Icons.arrow_downward, size: 16),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: l10n.d('Verwijderen'),
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline, size: 17),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            _meterFields(type, l10n),
          ],
        ),
      ),
    );
  }

  Widget _meterFields(CockpitMeterType type, AppLocalizations l10n) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        SizedBox(
          width: 210,
          child: DropdownButtonFormField<CockpitMeterType>(
            initialValue: type,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.d('Type'),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final value in CockpitMeterType.values)
                DropdownMenuItem(
                  value: value,
                  child: Text(
                    l10n.d(_meterTypeSourceLabel(value)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                onChanged(meter.copyWith(type: value));
              }
            },
          ),
        ),
        _TextField(
          width: 180,
          label: l10n.d('Label'),
          value: meter.label,
          onChanged: (value) => onChanged(meter.copyWith(label: value)),
        ),
        if (type != CockpitMeterType.horizon &&
            type != CockpitMeterType.heading)
          _NumberField(
            label: l10n.d('Waarde'),
            value: meter.value,
            onChanged: (value) => onChanged(meter.copyWith(value: value)),
          ),
        if (type != CockpitMeterType.horizon &&
            type != CockpitMeterType.heading)
          _TextField(
            width: 84,
            label: l10n.d('Eenheid'),
            value: meter.unit,
            onChanged: (value) => onChanged(meter.copyWith(unit: value)),
          ),
        if (type == CockpitMeterType.horizon) ...[
          _NumberField(
            label: l10n.d('Pitch'),
            value: meter.pitch,
            onChanged: (value) => onChanged(meter.copyWith(pitch: value)),
          ),
          _NumberField(
            label: l10n.d('Bank'),
            value: meter.bank,
            onChanged: (value) => onChanged(meter.copyWith(bank: value)),
          ),
        ] else if (type == CockpitMeterType.heading) ...[
          _NumberField(
            label: l10n.d('Werkelijk'),
            value: meter.value,
            onChanged: (value) => onChanged(meter.copyWith(value: value)),
          ),
          _NumberField(
            label: l10n.d('Doel'),
            value: meter.heading,
            onChanged: (value) => onChanged(meter.copyWith(heading: value)),
          ),
          _TextField(
            width: 130,
            label: l10n.d('Markeringslabel'),
            value: meter.markerLabel,
            onChanged: (value) => onChanged(meter.copyWith(markerLabel: value)),
          ),
        ] else ...[
          _NumberField(
            label: l10n.d('Min'),
            value: meter.min,
            onChanged: (value) => onChanged(meter.copyWith(min: value)),
          ),
          _NumberField(
            label: l10n.d('Max'),
            value: meter.max,
            onChanged: (value) => onChanged(meter.copyWith(max: value)),
          ),
          if (type == CockpitMeterType.climbDescent) ...[
            _NumberField(
              label: l10n.d('Neutraal van'),
              value: meter.neutralFrom,
              onChanged: (value) =>
                  onChanged(meter.copyWith(neutralFrom: value)),
            ),
            _NumberField(
              label: l10n.d('Neutraal tot'),
              value: meter.neutralTo,
              onChanged: (value) => onChanged(meter.copyWith(neutralTo: value)),
            ),
          ] else ...[
            _NumberField(
              label: l10n.d('Groen van'),
              value: meter.greenFrom,
              onChanged: (value) => onChanged(meter.copyWith(greenFrom: value)),
            ),
            _NumberField(
              label: l10n.d('Groen tot'),
              value: meter.greenTo,
              onChanged: (value) => onChanged(meter.copyWith(greenTo: value)),
            ),
            _NumberField(
              label: l10n.d('Rood van'),
              value: meter.redFrom,
              onChanged: (value) => onChanged(meter.copyWith(redFrom: value)),
            ),
          ],
        ],
      ],
    );
  }
}

class _TextField extends StatefulWidget {
  final double width;
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const _TextField({
    required this.width,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_TextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: TextFormField(
        controller: _controller,
        decoration: InputDecoration(
          labelText: widget.label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}

class _NumberField extends StatefulWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _fmt(widget.value));
  }

  @override
  void didUpdateWidget(_NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _fmt(widget.value);
    if (widget.value != oldWidget.value && next != _controller.text) {
      _controller.text = next;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      child: TextFormField(
        controller: _controller,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        decoration: InputDecoration(
          labelText: widget.label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (raw) {
          final parsed = double.tryParse(raw.replaceAll(',', '.'));
          if (parsed != null) widget.onChanged(parsed);
        },
      ),
    );
  }

  String _fmt(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';
}
