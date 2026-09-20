part of 'ociserve_gateway.dart';

/// Het examendeel van [OciServeApi]: pogingen en items voor de cursist. De
/// declaraties en implementatie staan hier zodat het hoofdbestand onder de
/// bestandsgrens blijft.
abstract class OciServeExamApi {
  Future<OciServeExamSessionList> examSessions({
    required String accessToken,
    required String organizationId,
  });
  Future<OciServeExamAttempt> startExamAttempt({
    required String accessToken,
    required String organizationId,
    required String sessionId,
    required String idempotencyKey,
  });
  Future<OciServeCurrentExamItem?> currentExamItem({
    required String accessToken,
    required String organizationId,
    required String attemptId,
  });
  Future<OciServeAcceptedExamAnswer> answerExamItem({
    required String accessToken,
    required OciServeExamAnswerMutation mutation,
  });
  Future<OciServeExamAttempt> submitExamAttempt({
    required String accessToken,
    required String organizationId,
    required String attemptId,
    required String idempotencyKey,
  });
}

/// Implementatie van [OciServeExamApi]. Examenantwoorden mogen nooit in een
/// publieke cache belanden — elke respons wordt daarom op `Cache-Control:
/// no-store` gecontroleerd vóór er iets van gelezen wordt.
mixin _OciServeExams on OciServeGatewayBase {
  bool _isNoStore(OciServeHttpResponse response) =>
      response.headers['cache-control']
          ?.toLowerCase()
          .split(',')
          .map((part) => part.trim())
          .contains('no-store') ??
      false;

  Map<String, Object?> _examJson(OciServeHttpResponse response) {
    if (!_isNoStore(response)) {
      throw const OciServeException('exam_cache_policy_refused');
    }
    return _jsonObject(response);
  }

  @override
  Future<OciServeExamSessionList> examSessions({
    required String accessToken,
    required String organizationId,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api(['organizations', organizationId, 'me', 'exam-sessions']),
      accessToken: accessToken,
    );
    try {
      return OciServeExamSessionList.fromJson(_examJson(response));
    } catch (error, stack) {
      if (error is OciServeException) rethrow;
      logError('OciServe: examenlijst lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<OciServeExamAttempt> startExamAttempt({
    required String accessToken,
    required String organizationId,
    required String sessionId,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      method: 'POST',
      url: _api([
        'organizations',
        organizationId,
        'me',
        'exam-sessions',
        sessionId,
        'attempts',
      ]),
      accessToken: accessToken,
      headers: {'idempotency-key': idempotencyKey},
      body: const [],
    );
    if (response.statusCode != 201) {
      throw const OciServeException('invalid_response');
    }
    return OciServeExamAttempt.fromJson(_examJson(response));
  }

  @override
  Future<OciServeCurrentExamItem?> currentExamItem({
    required String accessToken,
    required String organizationId,
    required String attemptId,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api([
        'organizations',
        organizationId,
        'me',
        'attempts',
        attemptId,
        'items',
        'current',
      ]),
      accessToken: accessToken,
    );
    if (response.statusCode == 204) {
      if (response.body.isNotEmpty || !_isNoStore(response)) {
        throw const OciServeException('invalid_response');
      }
      return null;
    }
    return OciServeCurrentExamItem.fromJson(_examJson(response));
  }

  @override
  Future<OciServeAcceptedExamAnswer> answerExamItem({
    required String accessToken,
    required OciServeExamAnswerMutation mutation,
  }) async {
    final response = await _send(
      method: 'PUT',
      url: _api([
        'organizations',
        mutation.organizationId,
        'me',
        'attempts',
        mutation.attemptId,
        'items',
        mutation.attemptItemId,
        'answer',
      ]),
      accessToken: accessToken,
      headers: {
        'content-type': 'application/json',
        'idempotency-key': mutation.idempotencyKey,
      },
      body: utf8.encode(
        jsonEncode({
          'answer_data': mutation.answerData,
          'challenge': mutation.challenge,
          'revision': mutation.revision,
        }),
      ),
    );
    return OciServeAcceptedExamAnswer.fromJson(_examJson(response));
  }

  @override
  Future<OciServeExamAttempt> submitExamAttempt({
    required String accessToken,
    required String organizationId,
    required String attemptId,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      method: 'POST',
      url: _api([
        'organizations',
        organizationId,
        'me',
        'attempts',
        attemptId,
        'submit',
      ]),
      accessToken: accessToken,
      headers: {'idempotency-key': idempotencyKey},
      body: const [],
    );
    return OciServeExamAttempt.fromJson(_examJson(response));
  }
}
