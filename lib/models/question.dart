import 'dart:convert';

import '../utils/log.dart';

/// Limits keep a question slide sane and the random pick meaningful.
const int questionMinOptionCount = 2;
const int questionMaxOptionCount = 8;
const int questionDefaultOptionCount = 4;
const int questionMaxTimeLimitSeconds = 3600;

/// The concrete kind of question. The `question` slide carries one [QuestionKind]
/// (chosen in the editor); more kinds (open answer, ordering, …) slot in here
/// without a model rebuild.
///
/// - [multipleChoice]: one correct answer + a random pick of wrong ones; pick 1.
/// - [trueFalse]: the prompt is a statement; pick Juist/Onjuist.
/// - [multipleCorrect]: several answers may be correct; pick all correct ones.
enum QuestionKind { multipleChoice, trueFalse, multipleCorrect }

QuestionKind _kindFromName(String? name) => QuestionKind.values.firstWhere(
  (k) => k.name == name,
  orElse: () => QuestionKind.multipleChoice,
);

/// What happens when the viewer answers wrong (or runs out of time).
///
/// [retry] blocks advancing — the viewer must answer again (with a freshly
/// drawn set of options). [lockAndContinue] reveals the right answer, locks the
/// slide so it cannot be retried, and allows advancing.
enum QuestionOnWrong { retry, lockAndContinue }

QuestionOnWrong _onWrongFromName(String? name) => QuestionOnWrong.values
    .firstWhere((v) => v.name == name, orElse: () => QuestionOnWrong.retry);

/// A single possible answer in the pool. The pool may hold any number of
/// correct and incorrect answers; the presentation draws a random subset.
class QuestionAnswer {
  final String text;
  final bool correct;

  const QuestionAnswer({this.text = '', this.correct = false});

  factory QuestionAnswer.fromJson(Map<String, dynamic> json) => QuestionAnswer(
    text: (json['text'] ?? '').toString(),
    correct: json['correct'] == true,
  );

  QuestionAnswer copyWith({String? text, bool? correct}) =>
      QuestionAnswer(text: text ?? this.text, correct: correct ?? this.correct);

  Map<String, dynamic> toJson() => {'text': text, 'correct': correct};
}

/// The authored specification of a question slide, stored as a fenced
/// ```` ```question ```` JSON block in [Slide.customMarkdown] — mirroring how
/// `CockpitSpec`/`ChartSpec` persist. This is the round-trip source of truth.
class QuestionSpec {
  final QuestionKind kind;
  final String prompt;
  final List<QuestionAnswer> answers;

  /// Total number of options shown to the viewer (1 correct + the rest wrong),
  /// drawn at random from [answers]. Clamped to [questionMinOptionCount] ..
  /// [questionMaxOptionCount].
  final int optionCount;

  /// Maximum answer time in seconds. 0 = no limit. When the limit elapses the
  /// answer counts as wrong.
  final int timeLimitSeconds;

  final QuestionOnWrong onWrong;

  /// For [QuestionKind.trueFalse]: whether the statement in [prompt] is true.
  final bool statementIsTrue;

  const QuestionSpec({
    this.kind = QuestionKind.multipleChoice,
    this.prompt = '',
    this.answers = const [],
    this.optionCount = questionDefaultOptionCount,
    this.timeLimitSeconds = 0,
    this.onWrong = QuestionOnWrong.retry,
    this.statementIsTrue = true,
  });

  /// A friendly starting point shown when a question slide is first created.
  factory QuestionSpec.defaultMultipleChoice() => const QuestionSpec(
    prompt: 'Wat is de juiste keuze?',
    answers: [
      QuestionAnswer(text: 'Het juiste antwoord', correct: true),
      QuestionAnswer(text: 'Een fout antwoord'),
      QuestionAnswer(text: 'Nog een fout antwoord'),
      QuestionAnswer(text: 'En nog een fout antwoord'),
    ],
  );

  factory QuestionSpec.parse(String raw) {
    try {
      final data = jsonDecode(raw.trim());
      if (data is! Map) return QuestionSpec.defaultMultipleChoice();
      return QuestionSpec(
        kind: _kindFromName(data['kind']?.toString()),
        prompt: (data['prompt'] ?? '').toString(),
        answers: [
          for (final item in (data['answers'] as List? ?? const []))
            if (item is Map)
              QuestionAnswer.fromJson(Map<String, dynamic>.from(item)),
        ],
        optionCount: _clampOptionCount(data['optionCount']),
        timeLimitSeconds: _clampTimeLimit(data['timeLimitSeconds']),
        onWrong: _onWrongFromName(data['onWrong']?.toString()),
        statementIsTrue: data['statementIsTrue'] != false,
      ).normalized();
    } catch (e, s) {
      logError('QuestionSpec.parse: decode question JSON block', e, s);
      return QuestionSpec.defaultMultipleChoice();
    }
  }

  QuestionSpec copyWith({
    QuestionKind? kind,
    String? prompt,
    List<QuestionAnswer>? answers,
    int? optionCount,
    int? timeLimitSeconds,
    QuestionOnWrong? onWrong,
    bool? statementIsTrue,
  }) => QuestionSpec(
    kind: kind ?? this.kind,
    prompt: prompt ?? this.prompt,
    answers: answers ?? this.answers,
    optionCount: _clampOptionCount(optionCount ?? this.optionCount),
    timeLimitSeconds: _clampTimeLimit(
      timeLimitSeconds ?? this.timeLimitSeconds,
    ),
    onWrong: onWrong ?? this.onWrong,
    statementIsTrue: statementIsTrue ?? this.statementIsTrue,
  );

  /// Answers with non-empty text, partitioned for quick access.
  List<QuestionAnswer> get _filled =>
      answers.where((a) => a.text.trim().isNotEmpty).toList();
  List<QuestionAnswer> get correctAnswers =>
      _filled.where((a) => a.correct).toList();
  List<QuestionAnswer> get wrongAnswers =>
      _filled.where((a) => !a.correct).toList();

  /// Whether the spec can actually be presented. True/false always can; the
  /// answer-based kinds need at least one correct and one wrong answer.
  bool get isPresentable {
    if (kind == QuestionKind.trueFalse) return true;
    return correctAnswers.isNotEmpty && wrongAnswers.isNotEmpty;
  }

  QuestionSpec normalized() => QuestionSpec(
    kind: kind,
    prompt: prompt.trim(),
    answers: answers,
    optionCount: _clampOptionCount(optionCount),
    timeLimitSeconds: _clampTimeLimit(timeLimitSeconds),
    onWrong: onWrong,
    statementIsTrue: statementIsTrue,
  );

  String toBlock() {
    final map = <String, dynamic>{
      'kind': kind.name,
      'prompt': prompt,
      'optionCount': optionCount,
      'timeLimitSeconds': timeLimitSeconds,
      'onWrong': onWrong.name,
      if (kind == QuestionKind.trueFalse) 'statementIsTrue': statementIsTrue,
      'answers': [for (final a in answers) a.toJson()],
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  static int _clampOptionCount(Object? raw) {
    final v = _asInt(raw, questionDefaultOptionCount);
    return v.clamp(questionMinOptionCount, questionMaxOptionCount);
  }

  static int _clampTimeLimit(Object? raw) {
    final v = _asInt(raw, 0);
    return v.clamp(0, questionMaxTimeLimitSeconds);
  }

  static int _asInt(Object? raw, int fallback) {
    if (raw is num) return raw.round();
    return int.tryParse(raw?.toString() ?? '') ?? fallback;
  }
}

/// The outcome of the current answer attempt.
enum QuestionResult { none, correct, wrong }

/// The live, per-presentation state of a question slide, shared between the
/// presenter view and the (interactive) audience window. It is built by the
/// presenter — the single source of truth — and pushed over the window channel,
/// so it carries [toJson]/[fromJson]. It is never persisted to the .md file.
///
/// [options] is the randomly drawn subset actually shown (one correct answer +
/// the rest wrong), already in display order, so both screens render an
/// identical question.
class QuestionView {
  final List<String> options;

  /// Indices into [options] of the correct answer(s). One entry for single-pick
  /// kinds (multiple choice, true/false); one or more for [multi].
  final List<int> correctIndices;

  /// The option(s) the viewer picked. Empty while unanswered. For single-pick
  /// kinds this holds at most one index.
  final List<int> selectedIndices;

  /// Whether several options may be selected before submitting (multipleCorrect).
  /// Single-pick kinds reveal immediately on tap; [multi] toggles and waits for
  /// an explicit submit.
  final bool multi;

  final QuestionResult result;

  /// Whether to colour the options (correct = green, wrong pick = red). True
  /// after an answer or a timeout.
  final bool revealed;

  /// When locked, the options are no longer tappable (answered, or wrong with
  /// "lock & continue").
  final bool locked;

  /// Total answer time in seconds (0 = no timer).
  final int totalSeconds;

  /// Remaining time in milliseconds, for the countdown bar.
  final int remainingMs;

  const QuestionView({
    this.options = const [],
    this.correctIndices = const [],
    this.selectedIndices = const [],
    this.multi = false,
    this.result = QuestionResult.none,
    this.revealed = false,
    this.locked = false,
    this.totalSeconds = 0,
    this.remainingMs = 0,
  });

  bool get hasTimer => totalSeconds > 0;

  bool isCorrect(int i) => correctIndices.contains(i);
  bool isSelected(int i) => selectedIndices.contains(i);
  bool get hasSelection => selectedIndices.isNotEmpty;

  /// Whether navigation past this slide is permitted: a correct answer, or a
  /// wrong answer that is locked (the "lock & continue" path).
  bool get passed =>
      result == QuestionResult.correct ||
      (result == QuestionResult.wrong && locked);

  QuestionView copyWith({
    List<String>? options,
    List<int>? correctIndices,
    List<int>? selectedIndices,
    bool? multi,
    QuestionResult? result,
    bool? revealed,
    bool? locked,
    int? totalSeconds,
    int? remainingMs,
  }) => QuestionView(
    options: options ?? this.options,
    correctIndices: correctIndices ?? this.correctIndices,
    selectedIndices: selectedIndices ?? this.selectedIndices,
    multi: multi ?? this.multi,
    result: result ?? this.result,
    revealed: revealed ?? this.revealed,
    locked: locked ?? this.locked,
    totalSeconds: totalSeconds ?? this.totalSeconds,
    remainingMs: remainingMs ?? this.remainingMs,
  );

  Map<String, dynamic> toJson() => {
    'options': options,
    'correctIndices': correctIndices,
    'selectedIndices': selectedIndices,
    'multi': multi,
    'result': result.name,
    'revealed': revealed,
    'locked': locked,
    'totalSeconds': totalSeconds,
    'remainingMs': remainingMs,
  };

  factory QuestionView.fromJson(Map<String, dynamic> json) => QuestionView(
    options: [for (final o in (json['options'] as List? ?? const [])) '$o'],
    correctIndices: [
      for (final i in (json['correctIndices'] as List? ?? const []))
        (i as num).toInt(),
    ],
    selectedIndices: [
      for (final i in (json['selectedIndices'] as List? ?? const []))
        (i as num).toInt(),
    ],
    multi: json['multi'] == true,
    result: QuestionResult.values.firstWhere(
      (r) => r.name == json['result'],
      orElse: () => QuestionResult.none,
    ),
    revealed: json['revealed'] == true,
    locked: json['locked'] == true,
    totalSeconds: (json['totalSeconds'] as num?)?.toInt() ?? 0,
    remainingMs: (json['remainingMs'] as num?)?.toInt() ?? 0,
  );
}
