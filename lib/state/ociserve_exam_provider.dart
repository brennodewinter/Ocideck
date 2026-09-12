import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

import '../models/ociserve_exam.dart';
import '../services/ociserve/ociserve_http.dart';
import '../utils/log.dart';
import 'ociserve_provider.dart';

const _examUuid = Uuid();

final ociServeExamProvider = StateNotifierProvider.autoDispose
    .family<OciServeExamNotifier, OciServeExamState, String>((ref, orgId) {
      return OciServeExamNotifier(
        organizationId: orgId,
        api: ref.read(ociServeProvider.notifier),
      )..load();
    });

enum OciServeExamPhase {
  loading,
  sessions,
  starting,
  question,
  sending,
  readyToSubmit,
  submitting,
  submitted,
  failed,
}

class OciServeExamState {
  const OciServeExamState({
    this.phase = OciServeExamPhase.loading,
    this.sessions = const [],
    this.serverTime,
    this.attempt,
    this.item,
    this.errorCode,
  });

  final OciServeExamPhase phase;
  final List<OciServeExamSession> sessions;
  final DateTime? serverTime;
  final OciServeExamAttempt? attempt;
  final OciServeCurrentExamItem? item;
  final String? errorCode;

  OciServeExamState copyWith({
    OciServeExamPhase? phase,
    List<OciServeExamSession>? sessions,
    DateTime? serverTime,
    OciServeExamAttempt? attempt,
    OciServeCurrentExamItem? item,
    bool clearItem = false,
    String? errorCode,
    bool clearError = false,
  }) => OciServeExamState(
    phase: phase ?? this.phase,
    sessions: sessions ?? this.sessions,
    serverTime: serverTime ?? this.serverTime,
    attempt: attempt ?? this.attempt,
    item: clearItem ? null : item ?? this.item,
    errorCode: clearError ? null : errorCode ?? this.errorCode,
  );
}

class OciServeExamNotifier extends StateNotifier<OciServeExamState> {
  OciServeExamNotifier({required this.organizationId, required this.api})
    : super(const OciServeExamState());

  final String organizationId;
  final OciServeNotifier api;
  _PendingExamRequest? _pending;

  Future<void> load() async {
    state = state.copyWith(phase: OciServeExamPhase.loading, clearError: true);
    try {
      final result = await api.examSessions(organizationId);
      if (!mounted) return;
      state = state.copyWith(
        phase: OciServeExamPhase.sessions,
        sessions: result.sessions,
        serverTime: result.serverTime,
      );
    } catch (error, stack) {
      _fail('exam_load_failed', error, stack);
    }
  }

  Future<void> start(OciServeExamSession session) async {
    final serverTime = state.serverTime;
    if (serverTime == null || !session.canStartAt(serverTime)) return;
    final request = _PendingExamStart(session.id, _examUuid.v4());
    _pending = request;
    state = state.copyWith(phase: OciServeExamPhase.starting, clearError: true);
    await _runStart(request);
  }

  Future<void> _runStart(_PendingExamStart request) async {
    try {
      final attempt = await api.startExamAttempt(
        organizationId: organizationId,
        sessionId: request.sessionId,
        idempotencyKey: request.idempotencyKey,
      );
      if (!mounted) return;
      _pending = null;
      state = state.copyWith(attempt: attempt, clearError: true);
      await _loadCurrent(attempt.id);
    } catch (error, stack) {
      _fail('exam_start_failed', error, stack);
    }
  }

  Future<void> answer(String value) async {
    final item = state.item;
    if (item == null || value.trim().isEmpty) return;
    final request = _PendingExamAnswer(
      item,
      item.answerData(value.trim()),
      _examUuid.v4(),
    );
    _pending = request;
    state = state.copyWith(phase: OciServeExamPhase.sending, clearError: true);
    await _runAnswer(request);
  }

  Future<void> _runAnswer(_PendingExamAnswer request) async {
    try {
      await api.answerExamItem(
        organizationId: organizationId,
        item: request.item,
        answerData: request.answerData,
        idempotencyKey: request.idempotencyKey,
      );
      if (!mounted) return;
      _pending = null;
      await _loadCurrent(request.item.attemptId);
    } catch (error, stack) {
      _fail('exam_answer_failed', error, stack);
    }
  }

  Future<void> _loadCurrent(String attemptId) async {
    try {
      final item = await api.currentExamItem(
        organizationId: organizationId,
        attemptId: attemptId,
      );
      if (!mounted) return;
      state = state.copyWith(
        phase: OciServeExamPhase.question,
        item: item,
        clearError: true,
      );
    } on OciServeException catch (error, stack) {
      // Het endpoint gebruikt 409 wanneer er geen onbeantwoorde vraag meer is.
      // Er wordt geen inhoud of score uit afgeleid: alleen de submitknop komt
      // beschikbaar. Elke andere fout blijft een zichtbare gesloten toestand.
      if (error.statusCode == 409 && mounted) {
        state = state.copyWith(
          phase: OciServeExamPhase.readyToSubmit,
          clearItem: true,
          clearError: true,
        );
        return;
      }
      _fail('exam_question_failed', error, stack);
    } catch (error, stack) {
      _fail('exam_question_failed', error, stack);
    }
  }

  Future<void> submit() async {
    final attempt = state.attempt;
    if (attempt == null || state.phase != OciServeExamPhase.readyToSubmit) {
      return;
    }
    final request = _PendingExamSubmit(attempt.id, _examUuid.v4());
    _pending = request;
    state = state.copyWith(
      phase: OciServeExamPhase.submitting,
      clearError: true,
    );
    await _runSubmit(request);
  }

  Future<void> _runSubmit(_PendingExamSubmit request) async {
    try {
      final attempt = await api.submitExamAttempt(
        organizationId: organizationId,
        attemptId: request.attemptId,
        idempotencyKey: request.idempotencyKey,
      );
      if (!mounted) return;
      _pending = null;
      state = state.copyWith(
        phase: OciServeExamPhase.submitted,
        attempt: attempt,
        clearItem: true,
        clearError: true,
      );
    } catch (error, stack) {
      _fail('exam_submit_failed', error, stack);
    }
  }

  Future<void> retry() async {
    final request = _pending;
    if (request is _PendingExamStart) return _runStart(request);
    if (request is _PendingExamAnswer) return _runAnswer(request);
    if (request is _PendingExamSubmit) return _runSubmit(request);
    final attempt = state.attempt;
    if (attempt != null) return _loadCurrent(attempt.id);
    return load();
  }

  void _fail(String code, Object error, StackTrace stack) {
    logError('OciServe: formeel examen', error.runtimeType, stack);
    if (mounted) {
      state = state.copyWith(phase: OciServeExamPhase.failed, errorCode: code);
    }
  }
}

sealed class _PendingExamRequest {
  const _PendingExamRequest(this.idempotencyKey);

  final String idempotencyKey;
}

class _PendingExamStart extends _PendingExamRequest {
  const _PendingExamStart(this.sessionId, super.idempotencyKey);

  final String sessionId;
}

class _PendingExamAnswer extends _PendingExamRequest {
  const _PendingExamAnswer(this.item, this.answerData, super.idempotencyKey);

  final OciServeCurrentExamItem item;
  final Map<String, Object?> answerData;
}

class _PendingExamSubmit extends _PendingExamRequest {
  const _PendingExamSubmit(this.attemptId, super.idempotencyKey);

  final String attemptId;
}
