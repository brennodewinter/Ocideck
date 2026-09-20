part of 'ociserve_provider.dart';

/// Examensessies: dunne doorgeeflaag naar de gateway, met dezelfde
/// lidmaatschap- en tokenchecks als de rest van de notifier. In een eigen
/// part-bestand om de provider onder de bestandsgrens te houden.
mixin _OciServeExamMethods on OciServeNotifierBase {
  Future<OciServeExamSessionList> examSessions(String organizationId) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    return _gatewayFactory(
      state.settings,
    ).examSessions(accessToken: access, organizationId: organizationId);
  }

  Future<OciServeExamAttempt> startExamAttempt({
    required String organizationId,
    required String sessionId,
    required String idempotencyKey,
  }) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    return _gatewayFactory(state.settings).startExamAttempt(
      accessToken: access,
      organizationId: organizationId,
      sessionId: sessionId,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<OciServeCurrentExamItem?> currentExamItem({
    required String organizationId,
    required String attemptId,
  }) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    return _gatewayFactory(state.settings).currentExamItem(
      accessToken: access,
      organizationId: organizationId,
      attemptId: attemptId,
    );
  }

  Future<OciServeAcceptedExamAnswer> answerExamItem({
    required OciServeExamAnswerMutation mutation,
  }) async {
    _requireMembership(mutation.organizationId);
    final access = await _accessToken();
    return _gatewayFactory(
      state.settings,
    ).answerExamItem(accessToken: access, mutation: mutation);
  }

  Future<OciServeExamAttempt> submitExamAttempt({
    required String organizationId,
    required String attemptId,
    required String idempotencyKey,
  }) async {
    _requireMembership(organizationId);
    final access = await _accessToken();
    return _gatewayFactory(state.settings).submitExamAttempt(
      accessToken: access,
      organizationId: organizationId,
      attemptId: attemptId,
      idempotencyKey: idempotencyKey,
    );
  }
}
