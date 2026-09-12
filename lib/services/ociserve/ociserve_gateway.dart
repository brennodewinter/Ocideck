import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../models/ociserve_evidence.dart';
import '../../models/ociserve_exam.dart';
import '../../models/ociserve_models.dart';
import '../../models/ociserve_settings.dart';
import '../../utils/log.dart';
import '../../utils/zip_encryption.dart';
import 'ociserve_http.dart';
import 'ociserve_http_factory.dart';

/// Typed, bounded gateway for OciServe's learner-facing API.
abstract class OciServeApi {
  Future<OciServeInstallation> installation();
  Future<OciServeOidcConfiguration> discoverOidc(
    OciServeInstallation installation,
  );
  Future<OciServeAccount> me(String accessToken);
  Future<List<OciServeFeedItem>> learningFeed({
    required String accessToken,
    required String organizationId,
  });
  Future<OciServeLessonSessionGrant> startLessonSession({
    required String accessToken,
    required String organizationId,
    required String versionId,
    required String lessonId,
  });
  Future<OciServePackage> lessonSessionPackage({
    required String accessToken,
    required String organizationId,
    required OciServeLessonSessionGrant grant,
  });
  Future<void> closeLessonSession({
    required String accessToken,
    required String organizationId,
    required String sessionId,
  });
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
  Future<OciServeCurrentExamItem> currentExamItem({
    required String accessToken,
    required String organizationId,
    required String attemptId,
  });
  Future<OciServeAcceptedExamAnswer> answerExamItem({
    required String accessToken,
    required String organizationId,
    required OciServeCurrentExamItem item,
    required Map<String, Object?> answerData,
    required String idempotencyKey,
  });
  Future<OciServeExamAttempt> submitExamAttempt({
    required String accessToken,
    required String organizationId,
    required String attemptId,
    required String idempotencyKey,
  });
  Future<Uint8List> courseImage({
    required String accessToken,
    required String organizationId,
    required String imageHash,
  });
  Future<Uint8List> accountAvatar({
    required String accessToken,
    required String avatarHash,
  });
  Future<OciServeLearningState> learningState({
    required String accessToken,
    required String organizationId,
  });
  Future<OciServePrivacyData> privacyData({
    required String accessToken,
    required String organizationId,
  });
  Future<void> reportPlayback({
    required String accessToken,
    required String organizationId,
    required OciServePlaybackSnapshot snapshot,
  });

  // — Evidence & badges (bewijs bij badges) —

  /// Lists all evidence uploads for a participant.
  Future<List<EvidenceUpload>> listEvidence({
    required String accessToken,
    required String organizationId,
    required String participantId,
  });

  /// Lists all qualifications (badges) for a participant.
  Future<List<OciServeQualification>> listQualifications({
    required String accessToken,
    required String organizationId,
    required String participantId,
  });

  /// Reserves an evidence upload slot (step 1 of the quarantine protocol).
  Future<EvidenceUpload> requestEvidenceSlot({
    required String accessToken,
    required String organizationId,
    required EvidenceUploadRequest request,
  });

  /// Uploads evidence bytes to a reserved slot (step 2).
  Future<EvidenceUpload> uploadEvidenceContent({
    required String accessToken,
    required String organizationId,
    required String evidenceId,
    required Uint8List bytes,
    required String contentType,
  });

  /// Returns the current state of an evidence upload slot.
  Future<EvidenceUpload> evidenceDetail({
    required String accessToken,
    required String organizationId,
    required String evidenceId,
  });

  /// Downloads the verified evidence bytes (slot must be `clean`).
  Future<Uint8List> downloadEvidence({
    required String accessToken,
    required String organizationId,
    required String evidenceId,
  });

  /// Returns the external Open Badges administration URL.
  Future<Uri> badgeAdministrationUrl({
    required String accessToken,
    required String organizationId,
  });
}

class OciServeGateway implements OciServeApi {
  OciServeGateway({required this.settings, OciServeHttpTransport? transport})
    : _transport = transport ?? createOciServeHttpTransport();

  static const _uuid = Uuid();

  static const int _jsonCap = 2 * 1024 * 1024;
  // Mirrors OciServe's published package limit so an oversized response is
  // stopped client-side before it can consume more memory than the contract.
  static const int _packageCap = 32 * 1024 * 1024;
  static const int _imageCap = 64 * 1024 * 1024;
  static const int _avatarCap = 5 * 1024 * 1024;
  static const int _privacyDataCap = 32 * 1024 * 1024;
  static const int _evidenceCap = 64 * 1024 * 1024;

  final OciServeSettings settings;
  final OciServeHttpTransport _transport;

  Uri _api(List<String> segments) {
    final base = Uri.parse(settings.normalizedBaseUrl);
    return base.replace(
      pathSegments: [
        ...base.pathSegments.where((part) => part.isNotEmpty),
        'api',
        'v1',
        ...segments,
      ],
      query: null,
      fragment: null,
    );
  }

  void _requireConfigured() {
    final refusal = validateOciServeBaseUrl(settings.baseUrl);
    if (!settings.enabled) throw const OciServeException('disabled');
    if (refusal != null) throw OciServeException(refusal);
  }

  Future<OciServeHttpResponse> _send({
    required String method,
    required Uri url,
    String? accessToken,
    Map<String, String> headers = const {},
    List<int>? body,
    int cap = _jsonCap,
  }) async {
    _requireConfigured();
    if (accessToken != null && accessToken.trim().isEmpty) {
      throw const OciServeException('not_authenticated');
    }
    try {
      final response = await _transport.send(
        method: method,
        url: url,
        trustedInternal: settings.trustedInternal,
        headers: {
          'accept': 'application/json',
          if (accessToken != null)
            'authorization': 'Bearer ${accessToken.trim()}',
          ...headers,
        },
        body: body,
        maxResponseBytes: cap,
        timeout: const Duration(seconds: 30),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OciServeException(
          response.statusCode == 401 ? 'unauthorized' : 'http_error',
          statusCode: response.statusCode,
        );
      }
      return response;
    } on OciServeException {
      rethrow;
    } on OciServeTransportException catch (e) {
      throw OciServeException(e.code);
    } catch (error, stack) {
      logError('OciServe: antwoord ontvangen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  Map<String, Object?> _jsonObject(OciServeHttpResponse response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.body));
      if (decoded is! Map) throw const FormatException();
      return Map<String, Object?>.from(decoded);
    } catch (error, stack) {
      logError('OciServe: JSON-antwoord lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<OciServeInstallation> installation() async {
    final response = await _send(method: 'GET', url: _api(['installation']));
    try {
      final value = OciServeInstallation.fromJson(_jsonObject(response));
      _requireHttps(value.issuer);
      return value;
    } catch (e) {
      if (e is OciServeException) rethrow;
      throw const OciServeException('invalid_installation');
    }
  }

  @override
  Future<OciServeOidcConfiguration> discoverOidc(
    OciServeInstallation installation,
  ) async {
    _requireHttps(installation.issuer);
    final issuer = installation.issuer;
    final discovery = issuer.replace(
      pathSegments: [
        ...issuer.pathSegments.where((part) => part.isNotEmpty),
        '.well-known',
        'openid-configuration',
      ],
      query: null,
      fragment: null,
    );
    final response = await _send(method: 'GET', url: discovery);
    try {
      final value = OciServeOidcConfiguration.fromJson(_jsonObject(response));
      _requireHttps(value.issuer);
      _requireHttps(value.authorizationEndpoint);
      _requireHttps(value.tokenEndpoint);
      _requireHttps(value.jwksUri);
      if (value.issuer.toString() != issuer.toString()) {
        throw const OciServeException('issuer_mismatch');
      }
      return value;
    } catch (e) {
      if (e is OciServeException) rethrow;
      throw const OciServeException('invalid_oidc_discovery');
    }
  }

  @override
  Future<OciServeAccount> me(String accessToken) async {
    final response = await _send(
      method: 'GET',
      url: _api(['me']),
      accessToken: accessToken,
    );
    try {
      return OciServeAccount.fromJson(_jsonObject(response));
    } catch (error, stack) {
      logError('OciServe: accountantwoord lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<List<OciServeFeedItem>> learningFeed({
    required String accessToken,
    required String organizationId,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api(['organizations', organizationId, 'me', 'learning-feed']),
      accessToken: accessToken,
    );
    try {
      final decoded = jsonDecode(utf8.decode(response.body));
      final raw = decoded is Map && decoded['courses'] is List
          ? decoded['courses']! as List
          : throw const FormatException();
      final result = <OciServeFeedItem>[];
      for (final item in raw) {
        final parent = Map<String, Object?>.from(item as Map);
        if (parent['lessons'] is List) {
          for (final lesson in parent['lessons']! as List) {
            result.add(
              OciServeFeedItem.fromJson({
                ...parent,
                ...Map<String, Object?>.from(lesson as Map),
                'lesson_id': lesson['id'],
                'course_title': parent['course_title'] ?? parent['title'],
              }),
            );
          }
        } else {
          result.add(OciServeFeedItem.fromJson(parent));
        }
      }
      return List.unmodifiable(result);
    } catch (error, stack) {
      logError('OciServe: opleidingenantwoord lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<OciServeLessonSessionGrant> startLessonSession({
    required String accessToken,
    required String organizationId,
    required String versionId,
    required String lessonId,
  }) async {
    final response = await _send(
      method: 'POST',
      url: _api([
        'organizations',
        organizationId,
        'me',
        'course-versions',
        versionId,
        'lessons',
        lessonId,
        'playback-sessions',
      ]),
      accessToken: accessToken,
      headers: {'idempotency-key': _uuid.v4()},
      body: const [],
    );
    try {
      if (response.statusCode != 201) throw const FormatException();
      final grant = OciServeLessonSessionGrant.fromJson(_jsonObject(response));
      if (grant.packageProfile != ociServeAesPackageProfile ||
          grant.expiresAt.isBefore(DateTime.now().toUtc())) {
        throw const FormatException('unsupported or expired package grant');
      }
      final expected = _lessonSessionPackageUri(organizationId, grant.id);
      final advertised = grant.packageUrl.isAbsolute
          ? grant.packageUrl
          : Uri.parse(settings.normalizedBaseUrl).resolveUri(grant.packageUrl);
      if (advertised != expected) {
        throw const FormatException('unexpected lesson package URL');
      }
      return grant;
    } catch (error, stack) {
      logError('OciServe: lessessieantwoord lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  Uri _lessonSessionPackageUri(String organizationId, String sessionId) =>
      _api([
        'organizations',
        organizationId,
        'me',
        'lesson-playback-sessions',
        sessionId,
        'package',
      ]);

  @override
  Future<OciServePackage> lessonSessionPackage({
    required String accessToken,
    required String organizationId,
    required OciServeLessonSessionGrant grant,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _lessonSessionPackageUri(organizationId, grant.id),
      accessToken: accessToken,
      headers: const {'accept': 'application/octet-stream'},
      cap: _packageCap,
    );
    final profile =
        response.headers['x-ociserve-package-profile']?.trim() ?? '';
    final cacheControl = response.headers['cache-control']?.toLowerCase() ?? '';
    if (profile != grant.packageProfile ||
        !cacheControl
            .split(',')
            .map((part) => part.trim())
            .contains('no-store')) {
      throw const OciServeException('package_policy_refused');
    }
    final actual = sha256.convert(response.body);
    final headerDigest = _digestBytes(response.headers['digest']);
    final grantDigest = _hexBytes(grant.digestSha256);
    if (headerDigest == null ||
        grantDigest == null ||
        !_constantTimeEquals(actual.bytes, headerDigest) ||
        !_constantTimeEquals(actual.bytes, grantDigest)) {
      throw const OciServeException('package_digest_mismatch');
    }
    final bytes = Uint8List.fromList(response.body);
    if (!hasExactOciServeAesPackageProfile(bytes, profile: profile)) {
      throw const OciServeException('package_profile_refused');
    }
    return OciServePackage(
      bytes: bytes,
      sha256: actual.toString(),
      playbackPolicy: 'play-only',
      packageProfile: profile,
      etag: response.headers['etag'],
    );
  }

  @override
  Future<void> closeLessonSession({
    required String accessToken,
    required String organizationId,
    required String sessionId,
  }) async {
    final response = await _send(
      method: 'POST',
      url: _api([
        'organizations',
        organizationId,
        'me',
        'lesson-playback-sessions',
        sessionId,
        'close',
      ]),
      accessToken: accessToken,
      headers: {'idempotency-key': _uuid.v4()},
      body: const [],
    );
    if (response.statusCode != 204 || response.body.isNotEmpty) {
      throw const OciServeException('invalid_response');
    }
  }

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
  Future<OciServeCurrentExamItem> currentExamItem({
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
    return OciServeCurrentExamItem.fromJson(_examJson(response));
  }

  @override
  Future<OciServeAcceptedExamAnswer> answerExamItem({
    required String accessToken,
    required String organizationId,
    required OciServeCurrentExamItem item,
    required Map<String, Object?> answerData,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      method: 'PUT',
      url: _api([
        'organizations',
        organizationId,
        'me',
        'attempts',
        item.attemptId,
        'items',
        item.attemptItemId,
        'answer',
      ]),
      accessToken: accessToken,
      headers: {
        'content-type': 'application/json',
        'idempotency-key': idempotencyKey,
      },
      body: utf8.encode(
        jsonEncode({
          'answer_data': answerData,
          'challenge': item.challenge,
          'revision': item.revision,
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

  @override
  Future<Uint8List> courseImage({
    required String accessToken,
    required String organizationId,
    required String imageHash,
  }) async {
    final normalizedHash = imageHash.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizedHash)) {
      throw const OciServeException('invalid_image_hash');
    }
    final response = await _send(
      method: 'GET',
      url: _api(['organizations', organizationId, 'assets', normalizedHash]),
      accessToken: accessToken,
      headers: const {'accept': 'image/png, image/jpeg, image/webp'},
      cap: _imageCap,
    );
    final contentType = (response.headers['content-type'] ?? '')
        .split(';')
        .first
        .trim()
        .toLowerCase();
    if (!_hasMatchingImageSignature(response.body, contentType)) {
      throw const OciServeException('invalid_course_image');
    }
    if (sha256.convert(response.body).toString() != normalizedHash) {
      throw const OciServeException('image_digest_mismatch');
    }
    return Uint8List.fromList(response.body);
  }

  @override
  Future<Uint8List> accountAvatar({
    required String accessToken,
    required String avatarHash,
  }) async {
    final normalizedHash = avatarHash.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizedHash)) {
      throw const OciServeException('invalid_avatar_hash');
    }
    final response = await _send(
      method: 'GET',
      url: _api(['me', 'avatar']),
      accessToken: accessToken,
      headers: const {'accept': 'image/png, image/jpeg, image/webp'},
      cap: _avatarCap,
    );
    final contentType = (response.headers['content-type'] ?? '')
        .split(';')
        .first
        .trim()
        .toLowerCase();
    if (!_hasMatchingImageSignature(response.body, contentType)) {
      throw const OciServeException('invalid_avatar_image');
    }
    if (sha256.convert(response.body).toString() != normalizedHash) {
      throw const OciServeException('avatar_digest_mismatch');
    }
    return Uint8List.fromList(response.body);
  }

  @override
  Future<OciServeLearningState> learningState({
    required String accessToken,
    required String organizationId,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api(['organizations', organizationId, 'me', 'learning-state']),
      accessToken: accessToken,
    );
    try {
      return OciServeLearningState.fromJson(_jsonObject(response));
    } catch (error, stack) {
      logError('OciServe: voortgangsantwoord lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<OciServePrivacyData> privacyData({
    required String accessToken,
    required String organizationId,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api(['organizations', organizationId, 'me', 'privacy-data']),
      accessToken: accessToken,
      cap: _privacyDataCap,
    );
    try {
      return OciServePrivacyData.fromJson(_jsonObject(response));
    } catch (error, stack) {
      logError('OciServe: gegevensinzage lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<void> reportPlayback({
    required String accessToken,
    required String organizationId,
    required OciServePlaybackSnapshot snapshot,
  }) async {
    if (snapshot.sessionId.trim().isEmpty) {
      throw const OciServeException('invalid_session');
    }
    await _send(
      method: 'POST',
      url: _api(['organizations', organizationId, 'me', 'playback-sessions']),
      accessToken: accessToken,
      headers: {
        'content-type': 'application/json',
        'idempotency-key': snapshot.sessionId,
      },
      body: utf8.encode(snapshot.encode()),
    );
  }

  // — Evidence & badges —

  @override
  Future<List<EvidenceUpload>> listEvidence({
    required String accessToken,
    required String organizationId,
    required String participantId,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api([
        'organizations',
        organizationId,
        'participants',
        participantId,
        'evidence',
      ]),
      accessToken: accessToken,
    );
    try {
      final decoded = jsonDecode(utf8.decode(response.body));
      final raw = decoded is Map && decoded['uploads'] is List
          ? decoded['uploads']! as List
          : throw const FormatException();
      return raw
          .map(
            (item) =>
                EvidenceUpload.fromJson(Map<String, Object?>.from(item as Map)),
          )
          .toList(growable: false);
    } catch (error, stack) {
      logError('OciServe: bewijsstukken lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<List<OciServeQualification>> listQualifications({
    required String accessToken,
    required String organizationId,
    required String participantId,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api([
        'organizations',
        organizationId,
        'participants',
        participantId,
        'qualifications',
      ]),
      accessToken: accessToken,
    );
    try {
      final decoded = jsonDecode(utf8.decode(response.body));
      final raw = decoded is Map && decoded['qualifications'] is List
          ? decoded['qualifications']! as List
          : throw const FormatException();
      return raw
          .map(
            (item) => OciServeQualification.fromJson(
              Map<String, Object?>.from(item as Map),
            ),
          )
          .toList(growable: false);
    } catch (error, stack) {
      logError('OciServe: badges lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<EvidenceUpload> requestEvidenceSlot({
    required String accessToken,
    required String organizationId,
    required EvidenceUploadRequest request,
  }) async {
    final idempotencyKey = _uuid.v4();
    final response = await _send(
      method: 'POST',
      url: _api(['organizations', organizationId, 'evidence-uploads']),
      accessToken: accessToken,
      headers: {
        'content-type': 'application/json',
        'idempotency-key': idempotencyKey,
      },
      body: utf8.encode(jsonEncode(request.toJson())),
    );
    try {
      return EvidenceUpload.fromJson(_jsonObject(response));
    } catch (error, stack) {
      logError('OciServe: bewijsslot aanvragen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<EvidenceUpload> uploadEvidenceContent({
    required String accessToken,
    required String organizationId,
    required String evidenceId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final response = await _send(
      method: 'PUT',
      url: _api([
        'organizations',
        organizationId,
        'evidence-uploads',
        evidenceId,
        'content',
      ]),
      accessToken: accessToken,
      headers: {'content-type': contentType},
      body: bytes,
      cap: _evidenceCap,
    );
    try {
      return EvidenceUpload.fromJson(_jsonObject(response));
    } catch (error, stack) {
      logError('OciServe: bewijs uploaden', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<EvidenceUpload> evidenceDetail({
    required String accessToken,
    required String organizationId,
    required String evidenceId,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api([
        'organizations',
        organizationId,
        'evidence-uploads',
        evidenceId,
      ]),
      accessToken: accessToken,
    );
    try {
      return EvidenceUpload.fromJson(_jsonObject(response));
    } catch (error, stack) {
      logError('OciServe: bewijsdetail lezen', error.runtimeType, stack);
      throw const OciServeException('invalid_response');
    }
  }

  @override
  Future<Uint8List> downloadEvidence({
    required String accessToken,
    required String organizationId,
    required String evidenceId,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api([
        'organizations',
        organizationId,
        'evidence-uploads',
        evidenceId,
        'content',
      ]),
      accessToken: accessToken,
      headers: const {'accept': 'application/octet-stream'},
      cap: _evidenceCap,
    );
    return Uint8List.fromList(response.body);
  }

  @override
  Future<Uri> badgeAdministrationUrl({
    required String accessToken,
    required String organizationId,
  }) async {
    final response = await _send(
      method: 'GET',
      url: _api(['organizations', organizationId, 'badges']),
      accessToken: accessToken,
    );
    try {
      final json = _jsonObject(response);
      final url = (json['url'] as String? ?? '').trim();
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasAuthority) {
        throw const OciServeException('invalid_response');
      }
      _requireHttps(uri);
      return uri;
    } catch (e) {
      if (e is OciServeException) rethrow;
      throw const OciServeException('invalid_response');
    }
  }

  static void _requireHttps(Uri uri) {
    if (!uri.hasAuthority || uri.scheme.toLowerCase() != 'https') {
      throw const OciServeException('https_required');
    }
  }

  static List<int>? _digestBytes(String? header) {
    if (header == null) return null;
    final match = RegExp(
      r'(?:^|,)\s*sha-256\s*=\s*:?(?<value>[A-Za-z0-9+/=]+):?',
      caseSensitive: false,
    ).firstMatch(header);
    if (match == null) return null;
    try {
      final bytes = base64.decode(match.namedGroup('value')!);
      return bytes.length == 32 ? bytes : null;
    } catch (error, stack) {
      logError('OciServe: Digest lezen', error.runtimeType, stack);
      return null;
    }
  }

  static List<int>? _hexBytes(String value) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) return null;
    return [
      for (var i = 0; i < value.length; i += 2)
        int.parse(value.substring(i, i + 2), radix: 16),
    ];
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var i = 0; i < left.length; i++) {
      difference |= left[i] ^ right[i];
    }
    return difference == 0;
  }

  static bool _hasMatchingImageSignature(List<int> bytes, String contentType) {
    bool startsWith(List<int> signature) =>
        bytes.length >= signature.length &&
        List.generate(
          signature.length,
          (i) => bytes[i] == signature[i],
        ).every((matches) => matches);
    return switch (contentType) {
      'image/png' => startsWith(const [
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]),
      'image/jpeg' => startsWith(const [0xff, 0xd8, 0xff]),
      'image/webp' =>
        bytes.length >= 12 &&
            ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
            ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP',
      _ => false,
    };
  }
}
