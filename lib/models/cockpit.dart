import 'dart:convert';

import '../utils/log.dart';

const int cockpitMaxMeters = 6;
const int cockpitDefaultAnimationDurationMs = 2800;
const int cockpitMinAnimationDurationMs = 600;
// Shared activation-duration ceiling across animated slide types (timeline,
// cockpit): a build-up tops out at the same 30s regardless of slide type.
const int cockpitMaxAnimationDurationMs = 30000;

enum CockpitMeterType {
  speedometer,
  voltmeter,
  thermometer,
  altimeter,
  climbDescent,
  horizon,
  heading,
}

CockpitMeterType _meterTypeFromName(String? name) =>
    CockpitMeterType.values.firstWhere(
      (type) => type.name == name,
      orElse: () => CockpitMeterType.speedometer,
    );

double _degrees(double value) => value % 360;

String cockpitMeterTypeLabel(CockpitMeterType type) {
  switch (type) {
    case CockpitMeterType.speedometer:
      return 'Speedometer';
    case CockpitMeterType.voltmeter:
      return 'Voltmeter';
    case CockpitMeterType.thermometer:
      return 'Thermometer';
    case CockpitMeterType.altimeter:
      return 'Altimeter';
    case CockpitMeterType.climbDescent:
      return 'Climb/descent';
    case CockpitMeterType.horizon:
      return 'Horizon';
    case CockpitMeterType.heading:
      return 'Heading';
  }
}

class CockpitMeterSpec {
  final CockpitMeterType type;
  final String label;
  final String unit;
  final double min;
  final double max;
  final double greenFrom;
  final double greenTo;
  final double redFrom;
  final double value;
  final double pitch;
  final double bank;
  final double heading;
  final String markerLabel;
  final double neutralFrom;
  final double neutralTo;

  const CockpitMeterSpec({
    this.type = CockpitMeterType.speedometer,
    this.label = 'Overall risk',
    this.unit = '%',
    this.min = 0,
    this.max = 100,
    this.greenFrom = 0,
    this.greenTo = 40,
    this.redFrom = 70,
    this.value = 50,
    this.pitch = 0,
    this.bank = 0,
    this.heading = 0,
    this.markerLabel = '',
    this.neutralFrom = -5,
    this.neutralTo = 5,
  });

  factory CockpitMeterSpec.fromJson(Map<String, dynamic> json) {
    double number(String key, double fallback) {
      final raw = json[key];
      if (raw is num) return raw.toDouble();
      return double.tryParse(raw?.toString() ?? '') ?? fallback;
    }

    final type = _meterTypeFromName(json['type']?.toString());
    return CockpitMeterSpec(
      type: type,
      label: (json['label'] ?? '').toString(),
      unit: (json['unit'] ?? '').toString(),
      min: number('min', 0),
      max: number('max', 100),
      greenFrom: number('greenFrom', 0),
      greenTo: number('greenTo', 40),
      redFrom: number('redFrom', 70),
      value: number(
        'value',
        type == CockpitMeterType.heading ? number('heading', 0) : 50,
      ),
      pitch: number('pitch', 0).clamp(-45, 45).toDouble(),
      bank: number('bank', 0).clamp(-60, 60).toDouble(),
      heading: _degrees(number('heading', 0)),
      markerLabel: (json['markerLabel'] ?? '').toString(),
      neutralFrom: number('neutralFrom', -5),
      neutralTo: number('neutralTo', 5),
    ).normalized();
  }

  CockpitMeterSpec copyWith({
    CockpitMeterType? type,
    String? label,
    String? unit,
    double? min,
    double? max,
    double? greenFrom,
    double? greenTo,
    double? redFrom,
    double? value,
    double? pitch,
    double? bank,
    double? heading,
    String? markerLabel,
    double? neutralFrom,
    double? neutralTo,
  }) => CockpitMeterSpec(
    type: type ?? this.type,
    label: label ?? this.label,
    unit: unit ?? this.unit,
    min: min ?? this.min,
    max: max ?? this.max,
    greenFrom: greenFrom ?? this.greenFrom,
    greenTo: greenTo ?? this.greenTo,
    redFrom: redFrom ?? this.redFrom,
    value: value ?? this.value,
    pitch: pitch ?? this.pitch,
    bank: bank ?? this.bank,
    heading: heading ?? this.heading,
    markerLabel: markerLabel ?? this.markerLabel,
    neutralFrom: neutralFrom ?? this.neutralFrom,
    neutralTo: neutralTo ?? this.neutralTo,
  ).normalized();

  CockpitMeterSpec normalized() {
    final hi = max <= min ? min + 1 : max;
    double within(double v) => v.clamp(min, hi).toDouble();
    return CockpitMeterSpec(
      type: type,
      label: label.trim(),
      unit: unit.trim(),
      min: min,
      max: hi,
      greenFrom: within(greenFrom),
      greenTo: within(greenTo),
      redFrom: within(redFrom),
      value: type == CockpitMeterType.horizon
          ? value
          : type == CockpitMeterType.heading
          ? _degrees(value)
          : within(value),
      pitch: pitch.clamp(-45, 45).toDouble(),
      bank: bank.clamp(-60, 60).toDouble(),
      heading: _degrees(heading),
      markerLabel: markerLabel.trim(),
      neutralFrom: neutralFrom.clamp(min, hi).toDouble(),
      neutralTo: neutralTo.clamp(min, hi).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'type': type.name,
      if (label.isNotEmpty) 'label': label,
      if (unit.isNotEmpty) 'unit': unit,
    };
    switch (type) {
      case CockpitMeterType.horizon:
        map
          ..['pitch'] = pitch
          ..['bank'] = bank;
        break;
      case CockpitMeterType.heading:
        map
          ..['value'] = value
          ..['heading'] = heading
          ..['markerLabel'] = markerLabel;
        break;
      case CockpitMeterType.climbDescent:
        map
          ..['min'] = min
          ..['max'] = max
          ..['neutralFrom'] = neutralFrom
          ..['neutralTo'] = neutralTo
          ..['value'] = value;
        break;
      case CockpitMeterType.speedometer:
      case CockpitMeterType.voltmeter:
      case CockpitMeterType.thermometer:
      case CockpitMeterType.altimeter:
        map
          ..['min'] = min
          ..['max'] = max
          ..['greenFrom'] = greenFrom
          ..['greenTo'] = greenTo
          ..['redFrom'] = redFrom
          ..['value'] = value;
        break;
    }
    return map;
  }
}

class CockpitSpec {
  final String layout;
  final bool animateOnEnter;

  /// Per-slide activation duration override (ms). `null` = inherit the theme's
  /// ThemeProfile.animationDurationMs. Only a non-null value is serialised.
  final int? animationDurationMs;
  final List<CockpitMeterSpec> meters;

  const CockpitSpec({
    this.layout = 'auto',
    this.animateOnEnter = true,
    this.animationDurationMs,
    this.meters = const [],
  });

  factory CockpitSpec.pentestPreset() => const CockpitSpec(
    meters: [
      CockpitMeterSpec(
        type: CockpitMeterType.speedometer,
        label: 'Overall risk',
        unit: '%',
        value: 78,
        greenFrom: 0,
        greenTo: 40,
        redFrom: 70,
      ),
      CockpitMeterSpec(
        type: CockpitMeterType.thermometer,
        label: 'Exploitability heat',
        unit: '/10',
        min: 0,
        max: 10,
        greenFrom: 0,
        greenTo: 3,
        redFrom: 7,
        value: 8.4,
      ),
      CockpitMeterSpec(
        type: CockpitMeterType.voltmeter,
        label: 'Evidence confidence',
        unit: '%',
        greenFrom: 75,
        greenTo: 100,
        redFrom: 50,
        value: 92,
      ),
      CockpitMeterSpec(
        type: CockpitMeterType.climbDescent,
        label: 'Findings trend',
        unit: '',
        min: -20,
        max: 20,
        neutralFrom: -3,
        neutralTo: 3,
        value: 12,
      ),
    ],
  );

  factory CockpitSpec.parse(String raw) {
    try {
      final data = jsonDecode(raw.trim());
      if (data is! Map) return CockpitSpec.pentestPreset();
      return CockpitSpec(
        layout: (data['layout'] ?? 'auto').toString(),
        animateOnEnter: data['animateOnEnter'] != false,
        animationDurationMs: _durationMs(data['animationDurationMs']),
        meters: [
          for (final item in (data['meters'] as List? ?? const []))
            if (item is Map)
              CockpitMeterSpec.fromJson(Map<String, dynamic>.from(item)),
        ].take(cockpitMaxMeters).toList(),
      );
    } catch (e, s) {
      logError('CockpitSpec.parse: decode cockpit JSON block', e, s);
      return CockpitSpec.pentestPreset();
    }
  }

  CockpitSpec copyWith({
    String? layout,
    bool? animateOnEnter,
    int? animationDurationMs,
    bool inheritAnimationDuration = false,
    List<CockpitMeterSpec>? meters,
  }) => CockpitSpec(
    layout: layout ?? this.layout,
    animateOnEnter: animateOnEnter ?? this.animateOnEnter,
    animationDurationMs: inheritAnimationDuration
        ? null
        : (animationDurationMs != null
              ? _durationMs(animationDurationMs)
              : this.animationDurationMs),
    meters: (meters ?? this.meters).take(cockpitMaxMeters).toList(),
  );

  String toBlock() {
    final map = <String, dynamic>{
      'layout': layout,
      'animateOnEnter': animateOnEnter,
      // Omitted when inheriting the theme's duration, so a clean slide stays
      // clean and a theme change reaches it.
      if (animationDurationMs != null)
        'animationDurationMs': animationDurationMs,
      'meters': [
        for (final meter in meters.take(cockpitMaxMeters)) meter.toJson(),
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Parses and clamps an explicit duration; `null` (absent or unparseable) =
  /// inherit the theme's duration.
  static int? _durationMs(Object? raw) {
    final parsed = switch (raw) {
      num value => value.round(),
      _ => int.tryParse(raw?.toString() ?? ''),
    };
    if (parsed == null) return null;
    return parsed
        .clamp(cockpitMinAnimationDurationMs, cockpitMaxAnimationDurationMs)
        .toInt();
  }
}
