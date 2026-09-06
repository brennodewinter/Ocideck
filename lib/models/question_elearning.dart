part of 'question.dart';

/// Een koppel voor een [QuestionKind.matching]-vraag: een left-item hoort bij
/// het right-item op dezelfde index in [QuestionSpec.pairs]. De `id` is stabiel
/// binnen de vraag (niet de bron-id; die zit in de eLearning-sidecar).
class MatchPair {
  final String id;
  final String left;
  final String right;

  const MatchPair({this.id = '', this.left = '', this.right = ''});

  factory MatchPair.fromJson(Map<String, dynamic> json) => MatchPair(
    id: (json['id'] ?? '').toString(),
    left: (json['left'] ?? '').toString(),
    right: (json['right'] ?? '').toString(),
  );

  MatchPair copyWith({String? id, String? left, String? right}) => MatchPair(
    id: id ?? this.id,
    left: left ?? this.left,
    right: right ?? this.right,
  );

  Map<String, dynamic> toJson() => {'id': id, 'left': left, 'right': right};

  bool get isFilled => left.trim().isNotEmpty && right.trim().isNotEmpty;
}

/// Een klikbaar gebied op een [QuestionKind.hotspot]-vraag. Coördinaten zijn
/// genormaliseerd (0–1) in de referentieruimte van de afbeelding, niet in
/// pixels — zo overleeft het resize/crop/export. `rect` = `[x, y, w, h]`.
class HotspotRegion {
  final String id;
  final String shape;
  final List<double> coords;
  final bool correct;
  final String label;

  const HotspotRegion({
    this.id = '',
    this.shape = 'rect',
    this.coords = const [],
    this.correct = false,
    this.label = '',
  });

  factory HotspotRegion.fromJson(Map<String, dynamic> json) => HotspotRegion(
    id: (json['id'] ?? '').toString(),
    shape: (json['shape'] ?? 'rect').toString(),
    coords: [
      for (final c in (json['coords'] as List? ?? const []))
        (c is num ? c.toDouble() : double.tryParse('$c') ?? 0),
    ],
    correct: json['correct'] == true,
    label: (json['label'] ?? '').toString(),
  );

  HotspotRegion copyWith({
    String? id,
    String? shape,
    List<double>? coords,
    bool? correct,
    String? label,
  }) => HotspotRegion(
    id: id ?? this.id,
    shape: shape ?? this.shape,
    coords: coords ?? this.coords,
    correct: correct ?? this.correct,
    label: label ?? this.label,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'shape': shape,
    'coords': coords,
    'correct': correct,
    if (label.isNotEmpty) 'label': label,
  };
}

/// Hoe een [FillField]-antwoord wordt geëvalueerd.
enum FillMatchMode { exact, contains, similar, numericRange }

FillMatchMode _fillMatchModeFromName(String? name) => FillMatchMode.values
    .firstWhere((m) => m.name == name, orElse: () => FillMatchMode.exact);

/// Een invulveld voor een [QuestionKind.fillIn]-vraag. De evaluatiestrategie
/// ([matchMode], [normalize]) wordt expliciet vastgelegd, nooit impliciet
/// afgeleid uit tekst.
class FillField {
  /// De normalisaties die gelden wanneer het veld er geen noemt. Staat hier als
  /// constante omdat zowel de constructor als [FillField.fromJson] hem nodig
  /// heeft, en die twee niet mogen verschillen.
  static const defaultNormalize = ['trim', 'collapseWhitespace'];

  final String id;
  final List<String> accepted;
  final FillMatchMode matchMode;
  final bool caseSensitive;
  final List<String> normalize;
  final String placeholder;
  final int maxLength;

  /// Toegestane afwijking bij [FillMatchMode.numericRange], en de eenheid
  /// waarin het antwoord staat (ontwerp §3.2, allebei optioneel).
  ///
  /// Ze dragen mee zonder dat er al iets mee rekent: de evaluatie van fillIn
  /// bestaat nog niet. Dat is precies waarom ze hier staan — zonder deze velden
  /// gooide één lees-schrijfronde in OciDeck de tolerantie en de eenheid uit het
  /// bestand van de auteur, en dat is andermans antwoordsleutel.
  final double tolerance;
  final String unit;

  const FillField({
    this.id = '',
    this.accepted = const [],
    this.matchMode = FillMatchMode.exact,
    this.caseSensitive = false,
    this.normalize = defaultNormalize,
    this.placeholder = '',
    this.maxLength = 0,
    this.tolerance = 0,
    this.unit = '',
  });

  factory FillField.fromJson(Map<String, dynamic> json) => FillField(
    id: (json['id'] ?? '').toString(),
    accepted: [for (final a in (json['accepted'] as List? ?? const [])) '$a'],
    matchMode: _fillMatchModeFromName(json['matchMode']?.toString()),
    caseSensitive: json['caseSensitive'] == true,
    // Géén sleutel betekent "de standaard", een lege lijst betekent "expliciet
    // niets normaliseren". Die twee gelijktrekken op [] veranderde de betekenis
    // van een handgeschreven veld zodra het door OciDeck heen ging.
    normalize: json.containsKey('normalize')
        ? [for (final n in (json['normalize'] as List? ?? const [])) '$n']
        : defaultNormalize,
    placeholder: (json['placeholder'] ?? '').toString(),
    maxLength: (json['maxLength'] as num?)?.toInt() ?? 0,
    tolerance: (json['tolerance'] as num?)?.toDouble() ?? 0,
    unit: (json['unit'] ?? '').toString(),
  );

  FillField copyWith({
    String? id,
    List<String>? accepted,
    FillMatchMode? matchMode,
    bool? caseSensitive,
    List<String>? normalize,
    String? placeholder,
    int? maxLength,
    double? tolerance,
    String? unit,
  }) => FillField(
    id: id ?? this.id,
    accepted: accepted ?? this.accepted,
    matchMode: matchMode ?? this.matchMode,
    caseSensitive: caseSensitive ?? this.caseSensitive,
    normalize: normalize ?? this.normalize,
    placeholder: placeholder ?? this.placeholder,
    maxLength: maxLength ?? this.maxLength,
    tolerance: tolerance ?? this.tolerance,
    unit: unit ?? this.unit,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'accepted': accepted,
    'matchMode': matchMode.name,
    if (caseSensitive) 'caseSensitive': caseSensitive,
    'normalize': normalize,
    if (placeholder.isNotEmpty) 'placeholder': placeholder,
    if (maxLength > 0) 'maxLength': maxLength,
    if (tolerance != 0) 'tolerance': tolerance,
    if (unit.isNotEmpty) 'unit': unit,
  };
}

/// Hoe de score wordt berekend over de deelitems van een vraag.
enum QuestionScoring {
  allOrNothing,
  partialPerCorrect,
  partialPerPair,
  partialPerAnswer,
}

QuestionScoring _scoringFromName(String? name) =>
    QuestionScoring.values.firstWhere(
      (s) => s.name == name,
      orElse: () => QuestionScoring.allOrNothing,
    );

/// Feedback per uitkomst. Markdown, alleen geschreven wanneer gevuld.
class QuestionFeedback {
  final String correct;
  final String wrong;
  final String partial;
  final String timeout;

  const QuestionFeedback({
    this.correct = '',
    this.wrong = '',
    this.partial = '',
    this.timeout = '',
  });

  factory QuestionFeedback.fromJson(Map<String, dynamic> json) =>
      QuestionFeedback(
        correct: (json['correct'] ?? '').toString(),
        wrong: (json['wrong'] ?? '').toString(),
        partial: (json['partial'] ?? '').toString(),
        timeout: (json['timeout'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
    if (correct.isNotEmpty) 'correct': correct,
    if (wrong.isNotEmpty) 'wrong': wrong,
    if (partial.isNotEmpty) 'partial': partial,
    if (timeout.isNotEmpty) 'timeout': timeout,
  };

  bool get isEmpty =>
      correct.isEmpty && wrong.isEmpty && partial.isEmpty && timeout.isEmpty;

  QuestionFeedback copyWith({
    String? correct,
    String? wrong,
    String? partial,
    String? timeout,
  }) => QuestionFeedback(
    correct: correct ?? this.correct,
    wrong: wrong ?? this.wrong,
    partial: partial ?? this.partial,
    timeout: timeout ?? this.timeout,
  );
}

/// Leesbare metadata voor een vraag. Authoring content die de auteur met de
/// hand kan invullen; bronmetadata (source-id's, mapping) zit in de sidecar.
class QuestionMetadata {
  final String title;
  final String language;
  final String subject;
  final String difficulty;
  final int estimatedDurationSeconds;
  final List<String> tags;

  const QuestionMetadata({
    this.title = '',
    this.language = '',
    this.subject = '',
    this.difficulty = '',
    this.estimatedDurationSeconds = 0,
    this.tags = const [],
  });

  factory QuestionMetadata.fromJson(Map<String, dynamic> json) =>
      QuestionMetadata(
        title: (json['title'] ?? '').toString(),
        language: (json['language'] ?? '').toString(),
        subject: (json['subject'] ?? '').toString(),
        difficulty: (json['difficulty'] ?? '').toString(),
        estimatedDurationSeconds:
            (json['estimatedDurationSeconds'] as num?)?.toInt() ?? 0,
        tags: [for (final t in (json['tags'] as List? ?? const [])) '$t'],
      );

  Map<String, dynamic> toJson() => {
    if (title.isNotEmpty) 'title': title,
    if (language.isNotEmpty) 'language': language,
    if (subject.isNotEmpty) 'subject': subject,
    if (difficulty.isNotEmpty) 'difficulty': difficulty,
    if (estimatedDurationSeconds > 0)
      'estimatedDurationSeconds': estimatedDurationSeconds,
    if (tags.isNotEmpty) 'tags': tags,
  };

  bool get isEmpty =>
      title.isEmpty &&
      language.isEmpty &&
      subject.isEmpty &&
      difficulty.isEmpty &&
      estimatedDurationSeconds == 0 &&
      tags.isEmpty;

  QuestionMetadata copyWith({
    String? title,
    String? language,
    String? subject,
    String? difficulty,
    int? estimatedDurationSeconds,
    List<String>? tags,
  }) => QuestionMetadata(
    title: title ?? this.title,
    language: language ?? this.language,
    subject: subject ?? this.subject,
    difficulty: difficulty ?? this.difficulty,
    estimatedDurationSeconds:
        estimatedDurationSeconds ?? this.estimatedDurationSeconds,
    tags: tags ?? this.tags,
  );
}
