part of 'ociserve_gateway.dart';

/// Het Managed-Intake-deel van [OciServeApi]: de **organisatorroutes** onder
/// `/api/v1/organizations/{org}/intake-forms` (ADR 0016). Elke aanroep draagt
/// het OIDC-accesstoken van de organisator; de tenantcapability en de
/// per-form grant toetst de server. Het respondentdeel is bewust een aparte,
/// dunnere client (`ociserve_intake_respondent.dart`) die nooit een OIDC-token
/// vasthoudt — de twee auth-ketens delen geen referenties en geen codepad.
abstract class OciServeIntakeApi {
  /// De intake-formulieren van de organisatie, gepagineerd; `null` bij een
  /// `If-None-Match` die de server met 304 beantwoordt.
  Future<OciServeEtag<IntakeFormList>?> intakeForms({
    required String accessToken,
    required String organizationId,
    String? cursor,
    IntakeOperationalStatus? status,
    String? ifNoneMatch,
  });

  /// Maakt een formulier aan met zijn eerste snapshotversie (201).
  Future<IntakeForm> createIntakeForm({
    required String accessToken,
    required String organizationId,
    required String name,
    required IntakeFormSnapshot snapshot,
    required String idempotencyKey,
  });

  /// Eén formulier met al zijn versies; `null` bij 304.
  Future<OciServeEtag<IntakeForm>?> intakeForm({
    required String accessToken,
    required String organizationId,
    required String formId,
    String? ifNoneMatch,
  });

  /// Zet de operationele status (`open`/`paused`/`closed`). [ifMatch] is de
  /// `ETag` van de laatst gelezen toestand — zonder hem weigert de server
  /// (412), zodat twee organisatoren elkaar niet stilletjes overschrijven.
  Future<IntakeForm> patchIntakeFormStatus({
    required String accessToken,
    required String organizationId,
    required String formId,
    required IntakeOperationalStatus status,
    required String ifMatch,
  });

  /// Publiceert een nieuwe immutable versie van een formulier (201).
  Future<IntakeFormVersion> publishIntakeFormVersion({
    required String accessToken,
    required String organizationId,
    required String formId,
    required IntakeFormSnapshot snapshot,
    required String idempotencyKey,
  });

  /// Eén gepubliceerde versie, inclusief zijn snapshot.
  Future<IntakeFormVersion> intakeFormVersion({
    required String accessToken,
    required String organizationId,
    required String formId,
    required int version,
  });

  /// De inbox van één formulier, gepagineerd; `null` bij 304.
  Future<OciServeEtag<IntakeSubmissionList>?> intakeSubmissions({
    required String accessToken,
    required String organizationId,
    required String formId,
    String? cursor,
    IntakeSubmissionState? state,
    bool? handled,
    String? ifNoneMatch,
  });

  /// Eén inzending met zijn revisiegeschiedenis; `null` bij 304.
  Future<OciServeEtag<IntakeSubmissionDetail>?> intakeSubmission({
    required String accessToken,
    required String organizationId,
    required String formId,
    required String submissionId,
    String? ifNoneMatch,
  });

  /// Streamt één immutable revisie binnen. De `Digest`-header moet exact het
  /// [expectedSha256] uit de revisie-metadata zijn — anders wordt er niets
  /// aan de werkmap toevertrouwd.
  Future<Uint8List> intakeRevisionContent({
    required String accessToken,
    required String organizationId,
    required String formId,
    required String submissionId,
    required int revision,
    required String expectedSha256,
  });

  /// Opent een correctieronde: de respondent mag een revisie n+1 maken
  /// (revision 1 blijft onaantastbaar).
  Future<IntakeSubmissionDetail> openIntakeCorrection({
    required String accessToken,
    required String organizationId,
    required String formId,
    required String submissionId,
    DateTime? deadlineAt,
    String? reason,
    required String idempotencyKey,
  });

  /// Markeert een inzending als (niet) behandeld.
  Future<IntakeSubmissionDetail> markIntakeHandled({
    required String accessToken,
    required String organizationId,
    required String formId,
    required String submissionId,
    required bool handled,
    required String idempotencyKey,
  });

  /// Plant de purge van een inzending (202 — OciServe houdt het
  /// verwijderingsregister bij, niet de client).
  Future<void> purgeIntakeSubmission({
    required String accessToken,
    required String organizationId,
    required String formId,
    required String submissionId,
    required String idempotencyKey,
  });
}

/// De respondent- en organisatorketen zijn bewust gescheiden (FORM_INTAKE.md
/// §6.6): alles hieronder eist `BearerAuth` + tenantcontext.
mixin _OciServeIntake on OciServeGatewayBase {
  static const _intakeContentCap = 120 * 1024 * 1024;
  static const _payloadTimeout = Duration(minutes: 2);

  List<String> _intakePath(String organizationId, [List<String>? rest]) => [
    'organizations',
    organizationId,
    'intake-forms',
    ...?rest,
  ];

  T _intakeParse<T>(
    OciServeHttpResponse response,
    String what,
    T Function(Map<String, Object?>) parse,
  ) {
    try {
      return parse(_jsonObject(response));
    } catch (error, stack) {
      if (error is OciServeException) rethrow;
      logError('OciServe: $what lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  /// `null` als de server met 304 antwoordde; anders de waarde plus ETag.
  OciServeEtag<T>? _intakeFetch<T>(
    OciServeHttpResponse response,
    String what,
    T Function(Map<String, Object?>) parse,
  ) {
    if (response.statusCode == 304) return null;
    return OciServeEtag(_intakeParse(response, what, parse), _etag(response));
  }

  static String? _etag(OciServeHttpResponse response) {
    final value = response.headers['etag']?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<OciServeEtag<IntakeFormList>?> intakeForms({
    required String accessToken,
    required String organizationId,
    String? cursor,
    IntakeOperationalStatus? status,
    String? ifNoneMatch,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api(_intakePath(organizationId)).replace(
        queryParameters: {
          'limit': '100',
          if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
          if (status != null) 'operational_status': status.wireName,
        },
      ),
      accessToken: accessToken,
      headers: {'if-none-match': ?ifNoneMatch},
      allowNotModified: true,
    );
    return _intakeFetch(response, 'intake-lijst', IntakeFormList.fromJson);
  }

  @override
  Future<IntakeForm> createIntakeForm({
    required String accessToken,
    required String organizationId,
    required String name,
    required IntakeFormSnapshot snapshot,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      method: 'POST',
      url: _api(_intakePath(organizationId)),
      accessToken: accessToken,
      headers: {
        'content-type': 'application/json',
        'idempotency-key': idempotencyKey,
      },
      body: utf8.encode(
        jsonEncode({'name': name, 'snapshot': snapshot.toJson()}),
      ),
    );
    if (response.statusCode != 201) {
      throw const OciServeException('invalid_response');
    }
    return _intakeParse(
      response,
      'nieuw intake-formulier',
      IntakeForm.fromJson,
    );
  }

  @override
  Future<OciServeEtag<IntakeForm>?> intakeForm({
    required String accessToken,
    required String organizationId,
    required String formId,
    String? ifNoneMatch,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api(_intakePath(organizationId, [formId])),
      accessToken: accessToken,
      headers: {'if-none-match': ?ifNoneMatch},
      allowNotModified: true,
    );
    return _intakeFetch(response, 'intake-formulier', IntakeForm.fromJson);
  }

  @override
  Future<IntakeForm> patchIntakeFormStatus({
    required String accessToken,
    required String organizationId,
    required String formId,
    required IntakeOperationalStatus status,
    required String ifMatch,
  }) async {
    final response = await _send(
      method: 'PATCH',
      url: _api(_intakePath(organizationId, [formId])),
      accessToken: accessToken,
      headers: {
        'content-type': 'application/merge-patch+json',
        'if-match': ifMatch,
      },
      body: utf8.encode(jsonEncode({'operational_status': status.wireName})),
    );
    return _intakeParse(response, 'intake-status', IntakeForm.fromJson);
  }

  @override
  Future<IntakeFormVersion> publishIntakeFormVersion({
    required String accessToken,
    required String organizationId,
    required String formId,
    required IntakeFormSnapshot snapshot,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      method: 'POST',
      url: _api(_intakePath(organizationId, [formId, 'versions'])),
      accessToken: accessToken,
      headers: {
        'content-type': 'application/json',
        'idempotency-key': idempotencyKey,
      },
      body: utf8.encode(jsonEncode({'snapshot': snapshot.toJson()})),
    );
    if (response.statusCode != 201) {
      throw const OciServeException('invalid_response');
    }
    return _intakeParse(
      response,
      'nieuwe intake-versie',
      IntakeFormVersion.fromJson,
    );
  }

  @override
  Future<IntakeFormVersion> intakeFormVersion({
    required String accessToken,
    required String organizationId,
    required String formId,
    required int version,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api(_intakePath(organizationId, [formId, 'versions', '$version'])),
      accessToken: accessToken,
    );
    return _intakeParse(response, 'intake-versie', IntakeFormVersion.fromJson);
  }

  @override
  Future<OciServeEtag<IntakeSubmissionList>?> intakeSubmissions({
    required String accessToken,
    required String organizationId,
    required String formId,
    String? cursor,
    IntakeSubmissionState? state,
    bool? handled,
    String? ifNoneMatch,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api(_intakePath(organizationId, [formId, 'submissions'])).replace(
        queryParameters: {
          'limit': '100',
          if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
          if (state != null) 'state': state.wireName,
          if (handled != null) 'handled': '$handled',
        },
      ),
      accessToken: accessToken,
      headers: {'if-none-match': ?ifNoneMatch},
      allowNotModified: true,
    );
    return _intakeFetch(
      response,
      'intake-inbox',
      IntakeSubmissionList.fromJson,
    );
  }

  @override
  Future<OciServeEtag<IntakeSubmissionDetail>?> intakeSubmission({
    required String accessToken,
    required String organizationId,
    required String formId,
    required String submissionId,
    String? ifNoneMatch,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api(
        _intakePath(organizationId, [formId, 'submissions', submissionId]),
      ),
      accessToken: accessToken,
      headers: {'if-none-match': ?ifNoneMatch},
      allowNotModified: true,
    );
    return _intakeFetch(
      response,
      'intake-inzending',
      IntakeSubmissionDetail.fromJson,
    );
  }

  @override
  Future<Uint8List> intakeRevisionContent({
    required String accessToken,
    required String organizationId,
    required String formId,
    required String submissionId,
    required int revision,
    required String expectedSha256,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api(
        _intakePath(organizationId, [
          formId,
          'submissions',
          submissionId,
          'revisions',
          '$revision',
          'content',
        ]),
      ),
      accessToken: accessToken,
      headers: const {'accept': 'application/octet-stream'},
      cap: _intakeContentCap,
      timeout: _payloadTimeout,
    );
    final expected = OciServeGatewayBase._hexBytes(
      expectedSha256.toLowerCase(),
    );
    final headerDigest = OciServeGatewayBase._digestBytes(
      response.headers['digest'],
    );
    final actual = sha256.convert(response.body).bytes;
    if (expected == null ||
        headerDigest == null ||
        !OciServeGatewayBase._constantTimeEquals(actual, expected) ||
        !OciServeGatewayBase._constantTimeEquals(actual, headerDigest)) {
      throw const OciServeException('intake_digest_mismatch');
    }
    return Uint8List.fromList(response.body);
  }

  @override
  Future<IntakeSubmissionDetail> openIntakeCorrection({
    required String accessToken,
    required String organizationId,
    required String formId,
    required String submissionId,
    DateTime? deadlineAt,
    String? reason,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      method: 'POST',
      url: _api(
        _intakePath(organizationId, [
          formId,
          'submissions',
          submissionId,
          'open-correction',
        ]),
      ),
      accessToken: accessToken,
      headers: {
        'content-type': 'application/json',
        'idempotency-key': idempotencyKey,
      },
      body: utf8.encode(
        jsonEncode({
          'deadline_at': ?deadlineAt?.toUtc().toIso8601String(),
          'reason': ?() {
            final trimmed = reason?.trim();
            return trimmed == null || trimmed.isEmpty ? null : trimmed;
          }(),
        }),
      ),
    );
    return _intakeParse(
      response,
      'intake-correctie',
      IntakeSubmissionDetail.fromJson,
    );
  }

  @override
  Future<IntakeSubmissionDetail> markIntakeHandled({
    required String accessToken,
    required String organizationId,
    required String formId,
    required String submissionId,
    required bool handled,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      method: 'POST',
      url: _api(
        _intakePath(organizationId, [
          formId,
          'submissions',
          submissionId,
          'mark-handled',
        ]),
      ),
      accessToken: accessToken,
      headers: {
        'content-type': 'application/json',
        'idempotency-key': idempotencyKey,
      },
      body: utf8.encode(jsonEncode({'handled': handled})),
    );
    return _intakeParse(
      response,
      'intake-afhandeling',
      IntakeSubmissionDetail.fromJson,
    );
  }

  @override
  Future<void> purgeIntakeSubmission({
    required String accessToken,
    required String organizationId,
    required String formId,
    required String submissionId,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      method: 'POST',
      url: _api(
        _intakePath(organizationId, [
          formId,
          'submissions',
          submissionId,
          'purge',
        ]),
      ),
      accessToken: accessToken,
      headers: {'idempotency-key': idempotencyKey},
      body: const [],
    );
    if (response.statusCode != 202 || response.body.isNotEmpty) {
      throw const OciServeException('invalid_response');
    }
  }
}
