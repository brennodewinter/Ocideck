import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/ociserve_exam.dart';
import 'package:ocideck/state/ociserve_exam_provider.dart';
import 'package:ocideck/state/ociserve_provider.dart';

class _ExamApi extends OciServeNotifier {
  int answers = 0;
  final answerKeys = <String>[];
  bool failFirstAnswer = false;
  bool failCurrent = false;
  int currentCalls = 0;

  @override
  Future<OciServeExamSessionList> examSessions(String organizationId) async =>
      OciServeExamSessionList(
        sessions: const [
          OciServeExamSession(id: 'session-1', status: 'released'),
        ],
        serverTime: DateTime.utc(2026, 9, 12),
      );

  @override
  Future<OciServeExamAttempt> startExamAttempt({
    required String organizationId,
    required String sessionId,
    required String idempotencyKey,
  }) async => OciServeExamAttempt(
    id: 'attempt-1',
    participantId: 'participant-1',
    blueprintVersionId: 'blueprint-1',
    status: 'in_progress',
    startedAt: DateTime.utc(2026, 9, 12),
  );

  @override
  Future<OciServeCurrentExamItem?> currentExamItem({
    required String organizationId,
    required String attemptId,
  }) async {
    currentCalls++;
    if (failCurrent) throw StateError('conflict');
    if (currentCalls > 1) return null;
    return OciServeCurrentExamItem(
      attemptId: attemptId,
      attemptItemId: 'item-1',
      position: 0,
      question: 'Vraag?',
      options: const [OciServeExamOption(id: 'a', text: 'A')],
      revision: 0,
      challenge: 'AAAAAAAAAAAAAAAAAAAAAA',
      challengeExpiresAt: DateTime.utc(2026, 9, 12, 1),
    );
  }

  @override
  Future<OciServeAcceptedExamAnswer> answerExamItem({
    required String organizationId,
    required OciServeCurrentExamItem item,
    required Map<String, Object?> answerData,
    required String idempotencyKey,
  }) async {
    answers++;
    answerKeys.add(idempotencyKey);
    if (failFirstAnswer && answers == 1) throw StateError('offline');
    return OciServeAcceptedExamAnswer(
      attemptId: item.attemptId,
      attemptItemId: item.attemptItemId,
      revision: item.revision + 1,
      acceptedAt: DateTime.utc(2026, 9, 12),
    );
  }

  @override
  Future<OciServeExamAttempt> submitExamAttempt({
    required String organizationId,
    required String attemptId,
    required String idempotencyKey,
  }) async => OciServeExamAttempt(
    id: attemptId,
    participantId: 'participant-1',
    blueprintVersionId: 'blueprint-1',
    status: 'submitted',
    startedAt: DateTime.utc(2026, 9, 12),
    submittedAt: DateTime.utc(2026, 9, 12, 1),
  );
}

void main() {
  test('never prefetches beyond the current unanswered item', () async {
    final api = _ExamApi();
    final notifier = OciServeExamNotifier(organizationId: 'org', api: api);
    addTearDown(notifier.dispose);

    await notifier.load();
    await notifier.start(notifier.state.sessions.single);

    expect(notifier.state.phase, OciServeExamPhase.question);
    expect(api.currentCalls, 1);
  });

  test('answer retry reuses challenge, revision and idempotency key', () async {
    final api = _ExamApi()..failFirstAnswer = true;
    final notifier = OciServeExamNotifier(organizationId: 'org', api: api);
    addTearDown(notifier.dispose);
    await notifier.load();
    await notifier.start(notifier.state.sessions.single);

    final originalItem = notifier.state.item;
    await notifier.answer('a');
    expect(notifier.state.phase, OciServeExamPhase.failed);
    await notifier.retry();

    expect(api.answerKeys, hasLength(2));
    expect(api.answerKeys.first, api.answerKeys.last);
    expect(originalItem!.challenge, 'AAAAAAAAAAAAAAAAAAAAAA');
    expect(notifier.state.phase, OciServeExamPhase.readyToSubmit);
  });

  test('submit response exposes status but no local score', () async {
    final api = _ExamApi();
    final notifier = OciServeExamNotifier(organizationId: 'org', api: api);
    addTearDown(notifier.dispose);
    await notifier.load();
    await notifier.start(notifier.state.sessions.single);
    await notifier.answer('a');
    await notifier.submit();

    expect(notifier.state.phase, OciServeExamPhase.submitted);
    expect(notifier.state.attempt!.status, 'submitted');
  });

  test('a current-item conflict never unlocks definitive submit', () async {
    final api = _ExamApi()..failCurrent = true;
    final notifier = OciServeExamNotifier(organizationId: 'org', api: api);
    addTearDown(notifier.dispose);

    await notifier.load();
    await notifier.start(notifier.state.sessions.single);

    expect(notifier.state.phase, OciServeExamPhase.failed);
    expect(notifier.state.phase, isNot(OciServeExamPhase.readyToSubmit));
  });
}
