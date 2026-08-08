// Part of the settings library — see ../settings.dart.
//
// Het kleurenschema en de visuele stijl van een cockpit-slide. Losgeknipt van
// settings.dart om dat bestand onder het regelplafond te houden; het blijft één
// library met AppSettings (die een lijst van deze schema's bewaart), dus elke
// aanroeper haalt het nog steeds via `models/settings.dart` — geen tweede import.
part of '../settings.dart';

enum CockpitVisualStyle {
  authentic,
  classic;

  static CockpitVisualStyle fromName(String? name) =>
      CockpitVisualStyle.values.firstWhere(
        (style) => style.name == name,
        orElse: () => CockpitVisualStyle.authentic,
      );
}

class CockpitColorScheme {
  final String name;
  final bool isBuiltIn;
  final CockpitVisualStyle visualStyle;
  final String good;
  final String warning;
  final String critical;
  final String cold;
  final String sky;
  final String ground;

  const CockpitColorScheme({
    required this.name,
    this.isBuiltIn = false,
    this.visualStyle = CockpitVisualStyle.authentic,
    this.good = '#22C55E',
    this.warning = '#F59E0B',
    this.critical = '#EF4444',
    this.cold = '#3B82F6',
    this.sky = '#2563EB',
    this.ground = '#9A5A22',
  });

  static const standard = CockpitColorScheme(
    name: 'Standaard',
    isBuiltIn: true,
  );

  static const builtIns = [standard];

  CockpitColorScheme copyWith({
    String? name,
    bool? isBuiltIn,
    CockpitVisualStyle? visualStyle,
    String? good,
    String? warning,
    String? critical,
    String? cold,
    String? sky,
    String? ground,
  }) {
    return CockpitColorScheme(
      name: name ?? this.name,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      visualStyle: visualStyle ?? this.visualStyle,
      good: good ?? this.good,
      warning: warning ?? this.warning,
      critical: critical ?? this.critical,
      cold: cold ?? this.cold,
      sky: sky ?? this.sky,
      ground: ground ?? this.ground,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'isBuiltIn': isBuiltIn,
      'visualStyle': visualStyle.name,
      'good': good,
      'warning': warning,
      'critical': critical,
      'cold': cold,
      'sky': sky,
      'ground': ground,
    };
  }

  factory CockpitColorScheme.fromJson(Map<String, Object?> json) {
    return CockpitColorScheme(
      name: json['name'] as String? ?? 'Eigen schema',
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      visualStyle: CockpitVisualStyle.fromName(json['visualStyle'] as String?),
      good: json['good'] as String? ?? standard.good,
      warning: json['warning'] as String? ?? standard.warning,
      critical: json['critical'] as String? ?? standard.critical,
      cold: json['cold'] as String? ?? standard.cold,
      sky: json['sky'] as String? ?? standard.sky,
      ground: json['ground'] as String? ?? standard.ground,
    );
  }
}
