import 'package:flutter/foundation.dart';

/// De uitslag van één formele examenpoging van de cursist, zoals de server
/// hem geeft. OciDeck toont het oordeel en rekent niets na: percentage en
/// geslaagd komen van OciServe, dat ze bepaalt tegen de norm van de versie
/// waarop het examen is afgenomen.
@immutable
class OciServeExamResult {
  const OciServeExamResult({
    required this.attemptId,
    required this.examSessionId,
    required this.title,
    required this.status,
    this.imageHash,
    this.submittedAt,
    this.releasedAt,
    this.totalItems,
    this.correctItems,
    this.percentage,
    this.passed,
  });

  final String attemptId;
  final String examSessionId;
  final String title;

  /// `submitted`, `scored` of `released`. Alleen bij `released` staan er cijfers.
  final String status;
  final String? imageHash;
  final DateTime? submittedAt;
  final DateTime? releasedAt;
  final int? totalItems;
  final int? correctItems;
  final double? percentage;

  /// Het oordeel van de server. `null` als de toetsversie geen norm kent.
  final bool? passed;

  bool get released => status == 'released';

  factory OciServeExamResult.fromJson(Map<String, Object?> json) {
    _requireOnly(json, const {
      'attempt_id',
      'exam_session_id',
      'title',
      'image_hash',
      'status',
      'submitted_at',
      'released_at',
      'total_items',
      'correct_items',
      'percentage',
      'passed',
    });
    final attemptId = (json['attempt_id'] as String? ?? '').trim();
    final sessionId = (json['exam_session_id'] as String? ?? '').trim();
    final title = (json['title'] as String? ?? '').trim();
    final status = (json['status'] as String? ?? '').trim();
    if (attemptId.isEmpty ||
        sessionId.isEmpty ||
        title.isEmpty ||
        !const {'submitted', 'scored', 'released'}.contains(status)) {
      throw const FormatException('invalid exam result');
    }
    final hasNumbers = const [
      'total_items',
      'correct_items',
      'percentage',
      'passed',
    ].any(json.containsKey);
    // Cijfers voor de vrijgave zijn een contractbreuk: de server stuurt ze niet.
    if (status != 'released' && hasNumbers) {
      throw const FormatException('invalid exam result');
    }
    final total = json['total_items'];
    final correct = json['correct_items'];
    final percentage = json['percentage'];
    final passed = json['passed'];
    if (status == 'released' &&
        (total is! int ||
            correct is! int ||
            total < 0 ||
            correct < 0 ||
            correct > total ||
            (percentage != null &&
                (percentage is! num || percentage < 0 || percentage > 100)) ||
            (passed != null && passed is! bool))) {
      throw const FormatException('invalid exam result');
    }
    return OciServeExamResult(
      attemptId: attemptId,
      examSessionId: sessionId,
      title: title,
      status: status,
      imageHash: _imageHash(json['image_hash']),
      submittedAt: _date(json['submitted_at']),
      releasedAt: _date(json['released_at']),
      totalItems: total as int?,
      correctItems: correct as int?,
      percentage: (percentage as num?)?.toDouble(),
      passed: passed as bool?,
    );
  }
}

@immutable
class OciServeExamResultList {
  const OciServeExamResultList({
    required this.results,
    required this.serverTime,
  });

  final List<OciServeExamResult> results;
  final DateTime serverTime;

  factory OciServeExamResultList.fromJson(Map<String, Object?> json) {
    _requireOnly(json, const {'results', 'server_time'});
    final raw = json['results'];
    final serverTime = DateTime.tryParse(json['server_time'] as String? ?? '');
    if (raw is! List || serverTime == null || raw.length > 50) {
      throw const FormatException('invalid exam result list');
    }
    return OciServeExamResultList(
      results: List.unmodifiable(
        raw.map(
          (item) => OciServeExamResult.fromJson(
            Map<String, Object?>.from(item as Map),
          ),
        ),
      ),
      serverTime: serverTime.toUtc(),
    );
  }
}

void _requireOnly(Map<String, Object?> json, Set<String> allowed) {
  if (!json.keys.every(allowed.contains)) {
    throw const FormatException('unexpected exam result field');
  }
}

DateTime? _date(Object? raw) {
  if (raw == null) return null;
  final value = DateTime.tryParse(raw as String? ?? '');
  if (value == null) throw const FormatException('invalid exam result date');
  return value.toUtc();
}

/// Een afbeeldingshash wordt later een pad naar de server, dus alleen een
/// SHA-256 in kleine hex komt erdoor.
String? _imageHash(Object? raw) {
  if (raw == null) return null;
  if (raw is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(raw)) {
    throw const FormatException('invalid exam result image');
  }
  return raw;
}
