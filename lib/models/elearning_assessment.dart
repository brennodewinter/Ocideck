import 'dart:convert';

import '../utils/log.dart';

/// Het versienummer van de eLearning-sidecar die deze build ondersteunt.
/// Een bestand dat een hoger versie declareert wordt niet ingelezen en niet
/// overschreven (zie `sidecar_format.dart`).
const int kElearningSidecarVersion = 1;

/// Navigatiemodus voor een assessment (#2006).
enum AssessmentNavigation { linear, free }

/// Wanneer een assessment als voltooid geldt (#2006).
enum AssessmentCompletion { allAnswered, allCorrect, manual }

/// Hoe een sectie zijn vragen selecteert (#2006).
enum AssessmentSelection { fixed, random }

/// Een sectie binnen een assessment (#2006).
class AssessmentSection {
  final String title;
  final List<String> questionRefs;
  final AssessmentSelection selection;
  final int poolSize;
  final int drawCount;
  final int timeLimitSeconds;

  const AssessmentSection({
    this.title = '',
    this.questionRefs = const [],
    this.selection = AssessmentSelection.fixed,
    this.poolSize = 0,
    this.drawCount = 0,
    this.timeLimitSeconds = 0,
  });

  factory AssessmentSection.fromJson(Map<String, dynamic> json) =>
      AssessmentSection(
        title: (json['title'] ?? '').toString(),
        questionRefs: [
          for (final r in (json['questionRefs'] as List? ?? const [])) '$r',
        ],
        selection: _selectionFromName(json['selection']?.toString()),
        poolSize: (json['poolSize'] as num?)?.toInt() ?? 0,
        drawCount: (json['drawCount'] as num?)?.toInt() ?? 0,
        timeLimitSeconds: (json['timeLimitSeconds'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'title': title,
    'questionRefs': questionRefs,
    if (selection != AssessmentSelection.fixed) 'selection': selection.name,
    if (poolSize > 0) 'poolSize': poolSize,
    if (drawCount > 0) 'drawCount': drawCount,
    if (timeLimitSeconds > 0) 'timeLimitSeconds': timeLimitSeconds,
  };
}

/// De assessment-test-definitie — deck-brede structuur, geen enkele slide
/// (#2006). Staat in de sidecar `<name>.elearning.json`.
class ElearningAssessment {
  final String title;
  final int maxScore;
  final int passThreshold;
  final int timeLimitSeconds;
  final AssessmentNavigation navigation;
  final AssessmentCompletion completionRule;
  final List<String> prerequisites;
  final List<String> objectiveRefs;
  final List<AssessmentSection> sections;

  const ElearningAssessment({
    this.title = '',
    this.maxScore = 100,
    this.passThreshold = 60,
    this.timeLimitSeconds = 0,
    this.navigation = AssessmentNavigation.linear,
    this.completionRule = AssessmentCompletion.allAnswered,
    this.prerequisites = const [],
    this.objectiveRefs = const [],
    this.sections = const [],
  });

  factory ElearningAssessment.fromJson(Map<String, dynamic> json) =>
      ElearningAssessment(
        title: (json['title'] ?? '').toString(),
        maxScore: (json['maxScore'] as num?)?.toInt() ?? 100,
        passThreshold: (json['passThreshold'] as num?)?.toInt() ?? 60,
        timeLimitSeconds: (json['timeLimitSeconds'] as num?)?.toInt() ?? 0,
        navigation: _navigationFromName(json['navigation']?.toString()),
        completionRule: _completionFromName(json['completionRule']?.toString()),
        prerequisites: [
          for (final r in (json['prerequisites'] as List? ?? const [])) '$r',
        ],
        objectiveRefs: [
          for (final r in (json['objectiveRefs'] as List? ?? const [])) '$r',
        ],
        sections: [
          for (final s in (json['sections'] as List? ?? const []))
            if (s is Map)
              AssessmentSection.fromJson(Map<String, dynamic>.from(s)),
        ],
      );

  Map<String, dynamic> toJson() => {
    'title': title,
    'maxScore': maxScore,
    'passThreshold': passThreshold,
    if (timeLimitSeconds > 0) 'timeLimitSeconds': timeLimitSeconds,
    'navigation': navigation.name,
    'completionRule': completionRule.name,
    if (prerequisites.isNotEmpty) 'prerequisites': prerequisites,
    if (objectiveRefs.isNotEmpty) 'objectiveRefs': objectiveRefs,
    'sections': [for (final s in sections) s.toJson()],
  };

  bool get isEmpty =>
      title.isEmpty && sections.isEmpty && timeLimitSeconds == 0;
}

/// Toegankelijkheidsmetadata "over de content" — QTI AfA-extensions en
/// alternatieve-presentatie-vlaggen die niet in gewone Markdown passen (#2007).
/// Niet-ondersteunde alternatives worden bewaard, niet uitgevoerd.
class ElearningAccessibility {
  /// Onbewerkte AfA-extension data uit QTI-import; bewaard voor round-trip.
  final Map<String, dynamic> extensions;

  /// Waarschuwingen over niet-ondersteunde alternatieve presentaties.
  final List<String> warnings;

  const ElearningAccessibility({
    this.extensions = const {},
    this.warnings = const [],
  });

  factory ElearningAccessibility.fromJson(Map<String, dynamic> json) =>
      ElearningAccessibility(
        extensions: json['extensions'] is Map
            ? Map<String, dynamic>.from(json['extensions'] as Map)
            : const {},
        warnings: [
          for (final w in (json['warnings'] as List? ?? const [])) '$w',
        ],
      );

  Map<String, dynamic> toJson() => {
    if (extensions.isNotEmpty) 'extensions': extensions,
    if (warnings.isNotEmpty) 'warnings': warnings,
  };

  bool get isEmpty => extensions.isEmpty && warnings.isEmpty;
}

/// De volledige eLearning-sidecar (#2006, #2007, #2008).
class ElearningSidecar {
  final int version;
  final ElearningAssessment? assessment;
  final ElearningAccessibility? accessibility;

  const ElearningSidecar({
    this.version = kElearningSidecarVersion,
    this.assessment,
    this.accessibility,
  });

  factory ElearningSidecar.fromJson(Map<String, dynamic> json) =>
      ElearningSidecar(
        version: (json['version'] as num?)?.toInt() ?? kElearningSidecarVersion,
        assessment: json['assessment'] is Map
            ? ElearningAssessment.fromJson(
                Map<String, dynamic>.from(json['assessment'] as Map),
              )
            : null,
        accessibility: json['accessibility'] is Map
            ? ElearningAccessibility.fromJson(
                Map<String, dynamic>.from(json['accessibility'] as Map),
              )
            : null,
      );

  Map<String, dynamic> toJson() => {
    'version': version,
    if (assessment != null) 'assessment': assessment!.toJson(),
    if (accessibility != null && !accessibility!.isEmpty)
      'accessibility': accessibility!.toJson(),
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static ElearningSidecar? parse(String raw) {
    try {
      final data = jsonDecode(raw.trim());
      if (data is! Map) return null;
      return ElearningSidecar.fromJson(Map<String, dynamic>.from(data));
    } catch (e, s) {
      logError('ElearningSidecar.parse', e, s);
      return null;
    }
  }
}

AssessmentNavigation _navigationFromName(String? name) =>
    AssessmentNavigation.values.firstWhere(
      (n) => n.name == name,
      orElse: () => AssessmentNavigation.linear,
    );

AssessmentCompletion _completionFromName(String? name) =>
    AssessmentCompletion.values.firstWhere(
      (n) => n.name == name,
      orElse: () => AssessmentCompletion.allAnswered,
    );

AssessmentSelection _selectionFromName(String? name) => AssessmentSelection
    .values
    .firstWhere((n) => n.name == name, orElse: () => AssessmentSelection.fixed);
