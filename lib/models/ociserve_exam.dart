import 'package:flutter/foundation.dart';

const _forbiddenExamContentFields = {
  'acceptedanswer',
  'acceptedanswers',
  'answer',
  'answermodel',
  'correct',
  'correctanswer',
  'correctanswers',
  'correctoptionid',
  'correctoptionids',
  'correctorder',
  'correctness',
  'iscorrect',
  'randomizationcontext',
  'rubric',
  'score',
  'scoring',
  'solution',
};

@immutable
class OciServeExamSession {
  const OciServeExamSession({
    required this.id,
    required this.status,
    this.scheduledStart,
    this.latestAdmissionAt,
    this.absoluteDeadlineAt,
  });

  final String id;
  final String status;
  final DateTime? scheduledStart;
  final DateTime? latestAdmissionAt;
  final DateTime? absoluteDeadlineAt;

  bool canStartAt(DateTime serverTime) {
    final now = serverTime.toUtc();
    return status == 'released' &&
        (scheduledStart == null || !now.isBefore(scheduledStart!)) &&
        (latestAdmissionAt == null || !now.isAfter(latestAdmissionAt!)) &&
        (absoluteDeadlineAt == null || !now.isAfter(absoluteDeadlineAt!));
  }

  factory OciServeExamSession.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const {
      'id',
      'status',
      'scheduled_start',
      'latest_admission_at',
      'absolute_deadline_at',
    });
    final id = (json['id'] as String? ?? '').trim();
    final status = (json['status'] as String? ?? '').trim();
    if (id.isEmpty ||
        !const {'scheduled', 'armed', 'released'}.contains(status)) {
      throw const FormatException('invalid participant exam session');
    }
    return OciServeExamSession(
      id: id,
      status: status,
      scheduledStart: _optionalDate(json, 'scheduled_start'),
      latestAdmissionAt: _optionalDate(json, 'latest_admission_at'),
      absoluteDeadlineAt: _optionalDate(json, 'absolute_deadline_at'),
    );
  }
}

@immutable
class OciServeExamSessionList {
  const OciServeExamSessionList({
    required this.sessions,
    required this.serverTime,
  });

  final List<OciServeExamSession> sessions;
  final DateTime serverTime;

  factory OciServeExamSessionList.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const {'exam_sessions', 'server_time'});
    final raw = json['exam_sessions'];
    final serverTime = DateTime.tryParse(json['server_time'] as String? ?? '');
    if (raw is! List || serverTime == null || raw.length > 100) {
      throw const FormatException('invalid exam session list');
    }
    return OciServeExamSessionList(
      sessions: List.unmodifiable(
        raw.map(
          (item) => OciServeExamSession.fromJson(
            Map<String, Object?>.from(item as Map),
          ),
        ),
      ),
      serverTime: serverTime.toUtc(),
    );
  }
}

@immutable
class OciServeExamAttempt {
  const OciServeExamAttempt({
    required this.id,
    required this.participantId,
    required this.blueprintVersionId,
    required this.status,
    required this.startedAt,
    this.deadlineAt,
    this.submittedAt,
  });

  final String id;
  final String participantId;
  final String blueprintVersionId;
  final String status;
  final DateTime startedAt;
  final DateTime? deadlineAt;
  final DateTime? submittedAt;

  bool get inProgress => status == 'in_progress';

  factory OciServeExamAttempt.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const {
      'id',
      'participant_id',
      'blueprint_version_id',
      'status',
      'started_at',
      'deadline_at',
      'submitted_at',
      'scored_at',
      'released_at',
    });
    final id = (json['id'] as String? ?? '').trim();
    final participantId = (json['participant_id'] as String? ?? '').trim();
    final blueprint = (json['blueprint_version_id'] as String? ?? '').trim();
    final status = (json['status'] as String? ?? '').trim();
    final startedAt = DateTime.tryParse(json['started_at'] as String? ?? '');
    if (id.isEmpty ||
        participantId.isEmpty ||
        blueprint.isEmpty ||
        startedAt == null ||
        !const {
          'in_progress',
          'paused',
          'invalidated',
          'submitted',
          'scored',
          'released',
        }.contains(status)) {
      throw const FormatException('invalid exam attempt');
    }
    return OciServeExamAttempt(
      id: id,
      participantId: participantId,
      blueprintVersionId: blueprint,
      status: status,
      startedAt: startedAt.toUtc(),
      deadlineAt: _optionalDate(json, 'deadline_at'),
      submittedAt: _optionalDate(json, 'submitted_at'),
    );
  }
}

@immutable
class OciServeExamOption {
  const OciServeExamOption({required this.id, required this.text});

  final String id;
  final String text;
}

@immutable
class OciServeCurrentExamItem {
  const OciServeCurrentExamItem({
    required this.attemptId,
    required this.attemptItemId,
    required this.position,
    required this.question,
    required this.options,
    required this.revision,
    required this.challenge,
    required this.challengeExpiresAt,
    this.deadlineAt,
  });

  final String attemptId;
  final String attemptItemId;
  final int position;
  final String question;
  final List<OciServeExamOption> options;
  final int revision;
  final String challenge;
  final DateTime challengeExpiresAt;
  final DateTime? deadlineAt;

  bool get usesOptions => options.isNotEmpty;

  Map<String, Object?> answerData(String value) =>
      usesOptions ? {'selected_option_id': value} : {'text': value};

  factory OciServeCurrentExamItem.fromJson(Map<String, Object?> json) {
    const exactKeys = {
      'attempt_id',
      'attempt_item_id',
      'position',
      'content',
      'option_order',
      'deadline_at',
      'revision',
      'challenge',
      'challenge_expires_at',
    };
    if (json.keys.any((key) => !exactKeys.contains(key))) {
      throw const FormatException('unexpected exam item field');
    }
    final attemptId = (json['attempt_id'] as String? ?? '').trim();
    final itemId = (json['attempt_item_id'] as String? ?? '').trim();
    final position = (json['position'] as num?)?.toInt();
    final revision = (json['revision'] as num?)?.toInt();
    final challenge = (json['challenge'] as String? ?? '').trim();
    final challengeExpiry = DateTime.tryParse(
      json['challenge_expires_at'] as String? ?? '',
    );
    final rawContent = json['content'];
    final rawOrder = json['option_order'];
    if (attemptId.isEmpty ||
        itemId.isEmpty ||
        position == null ||
        position < 0 ||
        revision == null ||
        revision < 0 ||
        !RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(challenge) ||
        challengeExpiry == null ||
        rawContent is! Map ||
        rawOrder is! List ||
        _containsForbiddenContent(rawContent)) {
      throw const FormatException('invalid current exam item');
    }
    final content = Map<String, Object?>.from(rawContent);
    final question = (content['question'] as String? ?? '').trim();
    if (question.isEmpty) throw const FormatException('missing exam question');
    final byId = <String, OciServeExamOption>{};
    for (final raw in content['options'] as List? ?? const []) {
      final option = Map<String, Object?>.from(raw as Map);
      final id = (option['id'] as String? ?? '').trim();
      final text = (option['text'] as String? ?? '').trim();
      if (id.isEmpty || text.isEmpty || byId.containsKey(id)) {
        throw const FormatException('invalid exam option');
      }
      byId[id] = OciServeExamOption(id: id, text: text);
    }
    final order = rawOrder.map((id) => '$id').toList(growable: false);
    if (order.length != byId.length ||
        order.toSet().length != order.length ||
        order.any((id) => !byId.containsKey(id))) {
      throw const FormatException('invalid exam option order');
    }
    return OciServeCurrentExamItem(
      attemptId: attemptId,
      attemptItemId: itemId,
      position: position,
      question: question,
      options: List.unmodifiable(order.map((id) => byId[id]!)),
      revision: revision,
      challenge: challenge,
      challengeExpiresAt: challengeExpiry.toUtc(),
      deadlineAt: _optionalDate(json, 'deadline_at'),
    );
  }
}

/// Minimal, replayable answer mutation. It deliberately excludes question
/// content, option text, scoring material and participant metadata.
@immutable
class OciServeExamAnswerMutation {
  const OciServeExamAnswerMutation({
    required this.organizationId,
    required this.attemptId,
    required this.attemptItemId,
    required this.answerData,
    required this.challenge,
    required this.revision,
    required this.idempotencyKey,
  });

  final String organizationId;
  final String attemptId;
  final String attemptItemId;
  final Map<String, Object?> answerData;
  final String challenge;
  final int revision;
  final String idempotencyKey;

  factory OciServeExamAnswerMutation.fromItem({
    required String organizationId,
    required OciServeCurrentExamItem item,
    required Map<String, Object?> answerData,
    required String idempotencyKey,
  }) => OciServeExamAnswerMutation(
    organizationId: organizationId,
    attemptId: item.attemptId,
    attemptItemId: item.attemptItemId,
    answerData: Map.unmodifiable(answerData),
    challenge: item.challenge,
    revision: item.revision,
    idempotencyKey: idempotencyKey,
  );

  Map<String, Object?> toJson() => {
    'kind': 'exam_answer_v1',
    'organization_id': organizationId,
    'attempt_id': attemptId,
    'attempt_item_id': attemptItemId,
    'answer_data': answerData,
    'challenge': challenge,
    'revision': revision,
    'idempotency_key': idempotencyKey,
  };

  factory OciServeExamAnswerMutation.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const {
      'kind',
      'organization_id',
      'attempt_id',
      'attempt_item_id',
      'answer_data',
      'challenge',
      'revision',
      'idempotency_key',
    });
    final answer = json['answer_data'];
    final revision = (json['revision'] as num?)?.toInt();
    final challenge = (json['challenge'] as String? ?? '').trim();
    final key = (json['idempotency_key'] as String? ?? '').trim();
    if (json['kind'] != 'exam_answer_v1' ||
        answer is! Map ||
        !_validStoredAnswer(answer) ||
        revision == null ||
        revision < 0 ||
        !RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(challenge) ||
        key.isEmpty ||
        key.length > 128) {
      throw const FormatException('invalid stored exam answer');
    }
    String requiredId(String field) {
      final value = (json[field] as String? ?? '').trim();
      if (value.isEmpty || value.length > 256) {
        throw const FormatException('invalid stored exam answer id');
      }
      return value;
    }

    return OciServeExamAnswerMutation(
      organizationId: requiredId('organization_id'),
      attemptId: requiredId('attempt_id'),
      attemptItemId: requiredId('attempt_item_id'),
      answerData: Map.unmodifiable(Map<String, Object?>.from(answer)),
      challenge: challenge,
      revision: revision,
      idempotencyKey: key,
    );
  }
}

@immutable
class OciServeAcceptedExamAnswer {
  const OciServeAcceptedExamAnswer({
    required this.attemptId,
    required this.attemptItemId,
    required this.revision,
    required this.acceptedAt,
  });

  final String attemptId;
  final String attemptItemId;
  final int revision;
  final DateTime acceptedAt;

  factory OciServeAcceptedExamAnswer.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const {
      'attempt_id',
      'attempt_item_id',
      'revision',
      'accepted_at',
    });
    final attemptId = (json['attempt_id'] as String? ?? '').trim();
    final itemId = (json['attempt_item_id'] as String? ?? '').trim();
    final revision = (json['revision'] as num?)?.toInt();
    final acceptedAt = DateTime.tryParse(json['accepted_at'] as String? ?? '');
    if (attemptId.isEmpty ||
        itemId.isEmpty ||
        revision == null ||
        revision < 0 ||
        acceptedAt == null) {
      throw const FormatException('invalid accepted exam answer');
    }
    return OciServeAcceptedExamAnswer(
      attemptId: attemptId,
      attemptItemId: itemId,
      revision: revision,
      acceptedAt: acceptedAt.toUtc(),
    );
  }
}

void _requireOnlyKeys(Map<String, Object?> json, Set<String> allowed) {
  if (json.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('unexpected formal exam field');
  }
}

DateTime? _optionalDate(Map<String, Object?> json, String key) {
  final raw = json[key];
  if (raw == null) return null;
  final value = DateTime.tryParse(raw as String? ?? '');
  if (value == null) throw FormatException('invalid $key');
  return value.toUtc();
}

bool _containsForbiddenContent(Object? value) {
  final pending = <Object?>[value];
  while (pending.isNotEmpty) {
    final current = pending.removeLast();
    if (current is List) {
      pending.addAll(current);
      continue;
    }
    if (current is Map) {
      for (final entry in current.entries) {
        final normalized = '${entry.key}'
            .replaceAll(RegExp('[^a-zA-Z]'), '')
            .toLowerCase();
        if (_forbiddenExamContentFields.contains(normalized)) return true;
        pending.add(entry.value);
      }
    }
  }
  return false;
}

bool _validStoredAnswer(Map<Object?, Object?> answer) {
  if (answer.length != 1) return false;
  final entry = answer.entries.single;
  if (!const {'selected_option_id', 'text'}.contains(entry.key)) return false;
  final value = entry.value;
  return value is String && value.isNotEmpty && value.length <= 4096;
}
