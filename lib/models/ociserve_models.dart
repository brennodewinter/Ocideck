import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'learning_session.dart';

@immutable
class OciServeInstallation {
  const OciServeInstallation({required this.clientId, required this.issuer});

  final String clientId;
  final Uri issuer;

  factory OciServeInstallation.fromJson(Map<String, Object?> json) {
    final oidc = json['oidc'] is Map
        ? Map<String, Object?>.from(json['oidc']! as Map)
        : const <String, Object?>{};
    String field(String key) =>
        ((json[key] ?? oidc[key]) as String? ?? '').trim();
    final clientId = field('ocideck_native_client_id');
    final issuer = Uri.tryParse(field('oidc_issuer'));
    if (clientId.isEmpty || issuer == null) {
      throw const FormatException('incomplete OciServe installation');
    }
    return OciServeInstallation(clientId: clientId, issuer: issuer);
  }
}

@immutable
class OciServeOidcConfiguration {
  const OciServeOidcConfiguration({
    required this.issuer,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.jwksUri,
    required this.metadata,
    this.signingAlgorithms = const [],
  });

  final Uri issuer;
  final Uri authorizationEndpoint;
  final Uri tokenEndpoint;
  final Uri jwksUri;
  final Map<String, Object?> metadata;
  final List<String> signingAlgorithms;

  factory OciServeOidcConfiguration.fromJson(Map<String, Object?> json) {
    final issuer = Uri.tryParse((json['issuer'] as String? ?? '').trim());
    final authorization = Uri.tryParse(
      (json['authorization_endpoint'] as String? ?? '').trim(),
    );
    final token = Uri.tryParse(
      (json['token_endpoint'] as String? ?? '').trim(),
    );
    final jwks = Uri.tryParse((json['jwks_uri'] as String? ?? '').trim());
    if (issuer == null ||
        authorization == null ||
        token == null ||
        jwks == null) {
      throw const FormatException('incomplete OIDC discovery');
    }
    return OciServeOidcConfiguration(
      issuer: issuer,
      authorizationEndpoint: authorization,
      tokenEndpoint: token,
      jwksUri: jwks,
      metadata: Map.unmodifiable(json),
      signingAlgorithms:
          (json['id_token_signing_alg_values_supported'] as List? ?? const [])
              .whereType<String>()
              .toList(growable: false),
    );
  }
}

@immutable
class OciServeAccount {
  const OciServeAccount({
    required this.id,
    this.displayName = '',
    this.email = '',
    this.avatarHash = '',
    this.memberships = const [],
  });

  final String id;
  final String displayName;
  final String email;
  final String avatarHash;
  final List<OciServeMembership> memberships;

  List<OciServeMembership> get activeMemberships => memberships
      .where((membership) => membership.isActive)
      .toList(growable: false);

  factory OciServeAccount.fromJson(Map<String, Object?> json) {
    final rawAccount = json['account'] is Map
        ? Map<String, Object?>.from(json['account']! as Map)
        : json;
    final id =
        (rawAccount['id'] as String? ?? rawAccount['user_id'] as String? ?? '')
            .trim();
    if (id.isEmpty) {
      throw const FormatException('incomplete OciServe account');
    }
    final rawMemberships = json['memberships'] is List
        ? json['memberships']! as List
        : const <Object?>[];
    return OciServeAccount(
      id: id,
      displayName:
          (rawAccount['display_name'] as String? ??
                  rawAccount['name'] as String? ??
                  '')
              .trim(),
      email: (rawAccount['email'] as String? ?? '').trim(),
      avatarHash: (rawAccount['avatar_hash'] as String? ?? '').trim(),
      memberships: rawMemberships
          .map(
            (item) => OciServeMembership.fromJson(
              Map<String, Object?>.from(item as Map),
            ),
          )
          .toList(growable: false),
    );
  }
}

@immutable
class OciServeMembership {
  const OciServeMembership({
    required this.organizationId,
    this.name = '',
    this.status = 'active',
  });

  final String organizationId;
  final String name;
  final String status;

  bool get isActive => status.isEmpty || status.toLowerCase() == 'active';

  factory OciServeMembership.fromJson(Map<String, Object?> json) {
    final id = (json['organization_id'] as String? ?? '').trim();
    if (id.isEmpty) throw const FormatException('incomplete membership');
    return OciServeMembership(
      organizationId: id,
      name: (json['name'] as String? ?? '').trim(),
      status: (json['status'] as String? ?? 'active').trim(),
    );
  }
}

@immutable
class OciServeFeedItem {
  const OciServeFeedItem({
    required this.versionId,
    required this.lessonId,
    required this.title,
    this.enrollmentId = '',
    this.courseTitle = '',
    this.courseId = '',
    this.courseSlug = '',
    this.courseImageHash = '',
    this.version = '',
    this.lessonOrder = 0,
    this.enrolledAt,
  });

  final String versionId;
  final String lessonId;
  final String title;
  final String enrollmentId;
  final String courseTitle;
  final String courseId;
  final String courseSlug;
  final String courseImageHash;
  final String version;
  final int lessonOrder;
  final DateTime? enrolledAt;

  factory OciServeFeedItem.fromJson(Map<String, Object?> json) {
    final versionId =
        (json['version_id'] as String? ??
                json['course_version_id'] as String? ??
                '')
            .trim();
    final lessonId = (json['lesson_id'] as String? ?? '').trim();
    if (versionId.isEmpty || lessonId.isEmpty) {
      throw const FormatException('incomplete learning-feed item');
    }
    return OciServeFeedItem(
      versionId: versionId,
      lessonId: lessonId,
      title: (json['title'] as String? ?? '').trim(),
      enrollmentId: (json['enrollment_id'] as String? ?? '').trim(),
      courseTitle: (json['course_title'] as String? ?? '').trim(),
      courseId: (json['course_id'] as String? ?? '').trim(),
      courseSlug: (json['course_slug'] as String? ?? '').trim(),
      courseImageHash: (json['image_hash'] as String? ?? '').trim(),
      version: '${json['version'] ?? ''}'.trim(),
      lessonOrder: json['order'] is num ? (json['order'] as num).toInt() : 0,
      enrolledAt: DateTime.tryParse(json['enrolled_at'] as String? ?? ''),
    );
  }
}

@immutable
class OciServePackage {
  const OciServePackage({
    required this.bytes,
    required this.sha256,
    required this.playbackPolicy,
    required this.packageProfile,
    this.etag,
  });

  final Uint8List bytes;
  final String sha256;
  final String playbackPolicy;
  final String packageProfile;
  final String? etag;
}

/// Eenmalige, kort levende toestemming om één versleutelde les te openen.
///
/// [packagePassword] mag alleen binnen de atomaire openingsaanroep bestaan en
/// wordt daarom nooit onderdeel van [LearningSessionRef] of duurzame opslag.
@immutable
class OciServeLessonSessionGrant {
  const OciServeLessonSessionGrant({
    required this.id,
    required this.packagePassword,
    required this.packageProfile,
    required this.packageUrl,
    required this.expiresAt,
    required this.digestSha256,
  });

  final String id;
  final String packagePassword;
  final String packageProfile;
  final Uri packageUrl;
  final DateTime expiresAt;
  final String digestSha256;

  factory OciServeLessonSessionGrant.fromJson(Map<String, Object?> json) {
    const fields = {
      'id',
      'package_password',
      'package_profile',
      'package_url',
      'expires_at',
      'digest',
    };
    if (json.keys.any((key) => !fields.contains(key))) {
      throw const FormatException('unexpected lesson playback field');
    }
    final id = (json['id'] as String? ?? '').trim();
    final password = (json['package_password'] as String? ?? '').trim();
    final profile = (json['package_profile'] as String? ?? '').trim();
    final packageUrl = Uri.tryParse(
      (json['package_url'] as String? ?? '').trim(),
    );
    final expiresAt = DateTime.tryParse(
      (json['expires_at'] as String? ?? '').trim(),
    );
    final digest = (json['digest'] as String? ?? '').trim().toLowerCase();
    if (id.isEmpty ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(password) ||
        profile.isEmpty ||
        packageUrl == null ||
        packageUrl.toString().isEmpty ||
        expiresAt == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      throw const FormatException('incomplete lesson playback session');
    }
    return OciServeLessonSessionGrant(
      id: id,
      packagePassword: password,
      packageProfile: profile,
      packageUrl: packageUrl,
      expiresAt: expiresAt.toUtc(),
      digestSha256: digest,
    );
  }
}

@immutable
class OciServeLearningState {
  const OciServeLearningState(this.lessons);

  final List<OciServeLessonState> lessons;

  factory OciServeLearningState.fromJson(Map<String, Object?> json) =>
      OciServeLearningState(
        (json['lessons'] as List? ?? const [])
            .map(
              (item) => OciServeLessonState.fromJson(
                Map<String, Object?>.from(item as Map),
              ),
            )
            .toList(growable: false),
      );
}

/// A completed, self-scoped copy of the personal data OciServe has registered
/// for the learner in one organization. The payload deliberately stays
/// generic so a newly added server category is visible without a client
/// release instead of being silently discarded by a typed projection.
@immutable
class OciServePrivacyData {
  const OciServePrivacyData({
    required this.participantId,
    required this.generatedAt,
    required this.data,
    this.schemaVersion = 'privacy-data/v1',
    this.omissions = const [],
  });

  final String participantId;
  final DateTime generatedAt;
  final Map<String, Object?> data;
  final String schemaVersion;
  final List<OciServePrivacyOmission> omissions;

  factory OciServePrivacyData.fromJson(Map<String, Object?> json) {
    final participantId = (json['participant_id'] as String? ?? '').trim();
    final generatedAt = DateTime.tryParse(
      json['generated_at'] as String? ?? '',
    );
    final data = json['data'];
    final schemaVersion = (json['schema_version'] as String? ?? '').trim();
    final omissionsValue = json['omissions'];
    if (participantId.isEmpty || generatedAt == null || data is! Map) {
      throw const FormatException('incomplete OciServe privacy data');
    }
    if (omissionsValue != null && omissionsValue is! List) {
      throw const FormatException('invalid OciServe privacy omissions');
    }
    return OciServePrivacyData(
      participantId: participantId,
      generatedAt: generatedAt,
      data: Map.unmodifiable(Map<String, Object?>.from(data)),
      schemaVersion: schemaVersion.isEmpty ? 'privacy-data/v1' : schemaVersion,
      omissions: List.unmodifiable(
        (omissionsValue as List? ?? const []).map(
          (value) => OciServePrivacyOmission.fromJson(
            Map<String, Object?>.from(value as Map),
          ),
        ),
      ),
    );
  }
}

/// A server-declared reason why one value in [OciServePrivacyData.data] is
/// intentionally unavailable. [path] is an RFC 6901 JSON Pointer into the
/// complete response, so future reason codes remain visible without guessing
/// their meaning in the client.
@immutable
class OciServePrivacyOmission {
  const OciServePrivacyOmission({required this.path, required this.reason});

  final String path;
  final String reason;

  factory OciServePrivacyOmission.fromJson(Map<String, Object?> json) {
    final path = (json['path'] as String? ?? '').trim();
    final reason = (json['reason'] as String? ?? '').trim();
    if (!path.startsWith('/data/') || reason.isEmpty) {
      throw const FormatException('invalid OciServe privacy omission');
    }
    return OciServePrivacyOmission(path: path, reason: reason);
  }
}

@immutable
class OciServeLessonState {
  const OciServeLessonState({
    required this.courseVersionId,
    required this.lessonId,
    required this.completed,
    required this.displayedMilliseconds,
    this.lastSlideAnchor,
    this.lastPlayedAt,
  });

  final String courseVersionId;
  final String lessonId;
  final bool completed;
  final String? lastSlideAnchor;
  final int displayedMilliseconds;
  final DateTime? lastPlayedAt;

  factory OciServeLessonState.fromJson(Map<String, Object?> json) =>
      OciServeLessonState(
        courseVersionId: (json['course_version_id'] as String? ?? '').trim(),
        lessonId: (json['lesson_id'] as String? ?? '').trim(),
        completed: json['completed'] as bool? ?? false,
        lastSlideAnchor: (json['last_slide_anchor'] as String?)?.trim(),
        displayedMilliseconds:
            (json['displayed_milliseconds'] as num?)?.toInt() ?? 0,
        lastPlayedAt: DateTime.tryParse(
          json['last_played_at'] as String? ?? '',
        ),
      );
}

// — Planning: zelfinschrijving —
//
// Modellen voor het self-service planningsoppervlak (OciServe `me/`):
// aanbod met klassikale sessies en toelatingseisen, en de eigen boekingen.
// Zelfde parseervorm als de rest van dit bestand: verplichte velden
// ontbreken of zijn onleesbaar → FormatException; extra velden worden
// getolereerd zodat een nieuwere server de client niet breekt.

/// Eén klassikale les binnen een uitvoering (voor deze les is een sessie te
/// kiezen bij het inschrijven).
@immutable
class OciServeClassroomLesson {
  const OciServeClassroomLesson({required this.id, required this.title});

  final String id;
  final String title;

  factory OciServeClassroomLesson.fromJson(Map<String, Object?> json) =>
      OciServeClassroomLesson(
        id: (json['id'] as String? ?? '').trim(),
        title: (json['title'] as String? ?? '').trim(),
      );
}

/// Eén instructeur op een klassikale sessie.
@immutable
class OciServeSessionInstructor {
  const OciServeSessionInstructor({
    required this.membershipId,
    required this.role,
    required this.displayName,
  });

  final String membershipId;
  final String role;
  final String displayName;

  factory OciServeSessionInstructor.fromJson(Map<String, Object?> json) =>
      OciServeSessionInstructor(
        membershipId: (json['membership_id'] as String? ?? '').trim(),
        role: (json['role'] as String? ?? '').trim(),
        displayName: (json['display_name'] as String? ?? '').trim(),
      );
}

/// Levenscyclus van een boeking; `attended`/`noShow` zijn serverwaarden voor
/// sessies waarvan de aanwezigheid is vastgelegd.
enum OciServeBookingStatus {
  booked,
  waitlisted,
  offered,
  cancelled,
  attended,
  noShow,
  unknown,
}

OciServeBookingStatus _bookingStatus(String raw) => switch (raw) {
  'booked' => OciServeBookingStatus.booked,
  'waitlisted' => OciServeBookingStatus.waitlisted,
  'offered' => OciServeBookingStatus.offered,
  'cancelled' => OciServeBookingStatus.cancelled,
  'attended' => OciServeBookingStatus.attended,
  'no_show' => OciServeBookingStatus.noShow,
  _ => OciServeBookingStatus.unknown,
};

/// Eén klassikale sessie zoals de self-catalogus hem toont: capaciteit,
/// vrije plaatsen en de eigen wachtlijstpositie — nooit andermans naam.
@immutable
class OciServeTrainingSession {
  const OciServeTrainingSession({
    required this.id,
    required this.offeringId,
    required this.lessonId,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.timezone,
    required this.capacity,
    required this.booked,
    required this.waitlisted,
    required this.offered,
    required this.status,
    required this.freeSeats,
    this.location,
    this.roomId,
    this.instructors = const [],
    this.waitlistPosition,
  });

  final String id;
  final String offeringId;
  final String lessonId;
  final String title;
  final DateTime startsAt;
  final DateTime endsAt;

  /// IANA-zoals `Europe/Amsterdam` — de wandklok waarin de sessie plaatsvindt.
  final String timezone;
  final int capacity;
  final int booked;
  final int waitlisted;
  final int offered;
  final String status;
  final int freeSeats;
  final String? location;
  final String? roomId;
  final List<OciServeSessionInstructor> instructors;

  /// Eigen plaats op de wachtlijst als de kijker `waitlisted`/`offered` is.
  final int? waitlistPosition;

  bool get isScheduled => status == 'scheduled';
  bool get isFull => freeSeats <= 0;

  factory OciServeTrainingSession.fromJson(Map<String, Object?> json) {
    final id = (json['id'] as String? ?? '').trim();
    final startsAt = DateTime.tryParse(json['starts_at'] as String? ?? '');
    final endsAt = DateTime.tryParse(json['ends_at'] as String? ?? '');
    if (id.isEmpty || startsAt == null || endsAt == null) {
      throw const FormatException('incomplete training session');
    }
    int count(String key) => (json[key] as num?)?.toInt() ?? 0;
    final rawInstructors = json['instructors'] is List
        ? json['instructors']! as List
        : const <Object?>[];
    return OciServeTrainingSession(
      id: id,
      offeringId: (json['course_offering_id'] as String? ?? '').trim(),
      lessonId: (json['lesson_id'] as String? ?? '').trim(),
      title: (json['title'] as String? ?? '').trim(),
      startsAt: startsAt.toUtc(),
      endsAt: endsAt.toUtc(),
      timezone: (json['timezone'] as String? ?? '').trim(),
      capacity: count('capacity'),
      booked: count('booked'),
      waitlisted: count('waitlisted'),
      offered: count('offered'),
      status: (json['status'] as String? ?? '').trim(),
      freeSeats: count('free_seats'),
      location: (json['location'] as String?)?.trim(),
      roomId: (json['room_id'] as String?)?.trim(),
      instructors: rawInstructors
          .map(
            (item) => OciServeSessionInstructor.fromJson(
              Map<String, Object?>.from(item as Map),
            ),
          )
          .toList(growable: false),
      waitlistPosition: (json['waitlist_position'] as num?)?.toInt(),
    );
  }
}

/// Toelatingsstatus van één eis: `expiresBeforeStart` is de eis die wel
/// geldt maar voor de startdatum afloopt.
enum OciServeRequirementStatus {
  met,
  notMet,
  waived,
  expiresBeforeStart,
  unknown,
}

OciServeRequirementStatus _requirementStatus(String raw) => switch (raw) {
  'met' => OciServeRequirementStatus.met,
  'not_met' => OciServeRequirementStatus.notMet,
  'waived' => OciServeRequirementStatus.waived,
  'expires_before_start' => OciServeRequirementStatus.expiresBeforeStart,
  _ => OciServeRequirementStatus.unknown,
};

/// Uitkomst van één toelatingseis; [reason] is de toonbare, feitelijke
/// toelichting die de server meestuurt en beschrijft de eis, niet de persoon.
@immutable
class OciServeRequirementOutcome {
  const OciServeRequirementOutcome({
    required this.requirementId,
    required this.kind,
    required this.targetId,
    required this.status,
    required this.reason,
    this.label = '',
  });

  final String requirementId;
  final String kind;
  final String targetId;
  final OciServeRequirementStatus status;
  final String reason;
  final String label;

  factory OciServeRequirementOutcome.fromJson(Map<String, Object?> json) {
    final id = (json['requirement_id'] as String? ?? '').trim();
    if (id.isEmpty) {
      throw const FormatException('incomplete requirement outcome');
    }
    return OciServeRequirementOutcome(
      requirementId: id,
      kind: (json['kind'] as String? ?? '').trim(),
      targetId: (json['target_id'] as String? ?? '').trim(),
      status: _requirementStatus((json['status'] as String? ?? '').trim()),
      reason: (json['reason'] as String? ?? '').trim(),
      label: (json['label'] as String? ?? '').trim(),
    );
  }
}

/// Eigen toelatingsevaluatie voor één uitvoering — zelf-gescoped, nooit de
/// uitkomst van een andere cursist.
@immutable
class OciServeEligibility {
  const OciServeEligibility({required this.eligible, this.outcomes = const []});

  final bool eligible;
  final List<OciServeRequirementOutcome> outcomes;

  factory OciServeEligibility.fromJson(Map<String, Object?> json) {
    final rawOutcomes = json['outcomes'] is List
        ? json['outcomes']! as List
        : const <Object?>[];
    return OciServeEligibility(
      eligible: json['eligible'] as bool? ?? false,
      outcomes: rawOutcomes
          .map(
            (item) => OciServeRequirementOutcome.fromJson(
              Map<String, Object?>.from(item as Map),
            ),
          )
          .toList(growable: false),
    );
  }
}

/// Eén uitvoering in het self-aanbod: naam, inschrijfbeleid, de klassikale
/// lessen, de kiesbare sessies en de eigen toelatingsevaluatie.
@immutable
class OciServeOfferingSummary {
  const OciServeOfferingSummary({
    required this.id,
    required this.courseVersionId,
    required this.name,
    required this.status,
    required this.selfEnrollmentEnabled,
    required this.voucherRequired,
    required this.maxSelfEnrollmentsPerParticipant,
    this.imageHash,
    this.enrollmentOpensAt,
    this.enrollmentClosesAt,
    this.cancellationNoticeHours,
    this.classroomLessons = const [],
    this.sessions = const [],
    this.eligibility = const OciServeEligibility(eligible: true),
  });

  final String id;
  final String courseVersionId;
  final String name;
  final String status;
  final bool selfEnrollmentEnabled;
  final bool voucherRequired;
  final int maxSelfEnrollmentsPerParticipant;
  final String? imageHash;
  final DateTime? enrollmentOpensAt;
  final DateTime? enrollmentClosesAt;

  /// Zelf afmelden is geweigerd binnen dit aantal uur vóór de sessie;
  /// `null` betekent dat afmelden altijd kan tot de sessie begint.
  final int? cancellationNoticeHours;
  final List<OciServeClassroomLesson> classroomLessons;
  final List<OciServeTrainingSession> sessions;
  final OciServeEligibility eligibility;

  /// Sessies van één klassikale les, op starttijd.
  List<OciServeTrainingSession> sessionsForLesson(String lessonId) =>
      sessions.where((session) => session.lessonId == lessonId).toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

  /// Laatste moment waarop afmelden voor [session] nog kan; `null` betekent
  /// "tot de sessie begint".
  DateTime cancellationDeadline(OciServeTrainingSession session) =>
      cancellationNoticeHours == null
      ? session.startsAt
      : session.startsAt.subtract(Duration(hours: cancellationNoticeHours!));

  factory OciServeOfferingSummary.fromJson(Map<String, Object?> json) {
    final id = (json['id'] as String? ?? '').trim();
    if (id.isEmpty) {
      throw const FormatException('incomplete course offering');
    }
    List<T> list<T>(String key, T Function(Map<String, Object?>) parse) =>
        json[key] is List
        ? (json[key]! as List)
              .map((item) => parse(Map<String, Object?>.from(item as Map)))
              .toList(growable: false)
        : const [];
    return OciServeOfferingSummary(
      id: id,
      courseVersionId: (json['course_version_id'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      status: (json['status'] as String? ?? '').trim(),
      selfEnrollmentEnabled: json['self_enrollment_enabled'] as bool? ?? false,
      voucherRequired: json['voucher_required'] as bool? ?? false,
      maxSelfEnrollmentsPerParticipant:
          (json['max_self_enrollments_per_participant'] as num?)?.toInt() ?? 1,
      imageHash: (json['image_hash'] as String?)?.trim(),
      enrollmentOpensAt: DateTime.tryParse(
        json['enrollment_opens_at'] as String? ?? '',
      )?.toUtc(),
      enrollmentClosesAt: DateTime.tryParse(
        json['enrollment_closes_at'] as String? ?? '',
      )?.toUtc(),
      cancellationNoticeHours: (json['cancellation_notice_hours'] as num?)
          ?.toInt(),
      classroomLessons: list(
        'classroom_lessons',
        OciServeClassroomLesson.fromJson,
      ),
      sessions: list('sessions', OciServeTrainingSession.fromJson),
      eligibility: json['eligibility'] is Map
          ? OciServeEligibility.fromJson(
              Map<String, Object?>.from(json['eligibility']! as Map),
            )
          : const OciServeEligibility(eligible: true),
    );
  }
}

/// Eén pagina uit het self-aanbod.
@immutable
class OciServeOfferingList {
  const OciServeOfferingList({required this.offerings, this.nextCursor});

  final List<OciServeOfferingSummary> offerings;
  final String? nextCursor;

  factory OciServeOfferingList.fromJson(Map<String, Object?> json) {
    final raw = json['offerings'] is List
        ? json['offerings']! as List
        : throw const FormatException('offering list without offerings');
    return OciServeOfferingList(
      offerings: raw
          .map(
            (item) => OciServeOfferingSummary.fromJson(
              Map<String, Object?>.from(item as Map),
            ),
          )
          .toList(growable: false),
      nextCursor: (json['next_cursor'] as String?)?.trim(),
    );
  }
}

/// De eigen boeking op één sessie, aangevuld met sessie- en uitvoeringsnaam.
///
/// `me/bookings` stuurt de boekingvelden op dit moment hoofdlettergevoelig
/// uit (de Go-struct heeft geen json-tags voor de ingebedde kern) — daarom
/// worden `id`/`ID`, `session_id`/`SessionID` e.d. allebei gelezen.
@immutable
class OciServeBooking {
  const OciServeBooking({
    required this.id,
    required this.sessionId,
    required this.enrollmentId,
    required this.status,
    required this.participantId,
    required this.sessionTitle,
    required this.startsAt,
    required this.endsAt,
    required this.timezone,
    required this.offeringId,
    required this.offeringName,
  });

  final String id;
  final String sessionId;
  final String enrollmentId;
  final OciServeBookingStatus status;
  final String participantId;
  final String sessionTitle;
  final DateTime startsAt;
  final DateTime endsAt;
  final String timezone;
  final String offeringId;
  final String offeringName;

  bool get isUpcoming => startsAt.isAfter(DateTime.now().toUtc());

  static String _field(
    Map<String, Object?> json,
    String snake,
    String pascal,
  ) => (json[snake] as String? ?? json[pascal] as String? ?? '').trim();

  factory OciServeBooking.fromJson(Map<String, Object?> json) {
    final id = _field(json, 'id', 'ID');
    final sessionId = _field(json, 'session_id', 'SessionID');
    final startsAt = DateTime.tryParse(json['starts_at'] as String? ?? '');
    final endsAt = DateTime.tryParse(json['ends_at'] as String? ?? '');
    if (id.isEmpty || sessionId.isEmpty || startsAt == null || endsAt == null) {
      throw const FormatException('incomplete booking');
    }
    return OciServeBooking(
      id: id,
      sessionId: sessionId,
      enrollmentId: _field(json, 'enrollment_id', 'EnrollmentID'),
      status: _bookingStatus(_field(json, 'status', 'Status')),
      participantId: _field(json, 'participant_id', 'ParticipantID'),
      sessionTitle: (json['session_title'] as String? ?? '').trim(),
      startsAt: startsAt.toUtc(),
      endsAt: endsAt.toUtc(),
      timezone: (json['timezone'] as String? ?? '').trim(),
      offeringId: (json['offering_id'] as String? ?? '').trim(),
      offeringName: (json['offering_name'] as String? ?? '').trim(),
    );
  }
}

/// Eén pagina eigen boekingen.
@immutable
class OciServeBookingList {
  const OciServeBookingList({required this.bookings, this.nextCursor});

  final List<OciServeBooking> bookings;
  final String? nextCursor;

  factory OciServeBookingList.fromJson(Map<String, Object?> json) {
    final raw = json['bookings'] is List
        ? json['bookings']! as List
        : throw const FormatException('booking list without bookings');
    return OciServeBookingList(
      bookings: raw
          .map(
            (item) => OciServeBooking.fromJson(
              Map<String, Object?>.from(item as Map),
            ),
          )
          .toList(growable: false),
      nextCursor: (json['next_cursor'] as String?)?.trim(),
    );
  }
}

/// De kern van een boeking zoals mutaties (inschrijven, afmelden, bevestigen,
/// afzien) hem teruggeven.
@immutable
class OciServeSessionBooking {
  const OciServeSessionBooking({
    required this.id,
    required this.sessionId,
    required this.status,
  });

  final String id;
  final String sessionId;
  final OciServeBookingStatus status;

  factory OciServeSessionBooking.fromJson(Map<String, Object?> json) {
    final id = (json['id'] as String? ?? '').trim();
    final sessionId = (json['session_id'] as String? ?? '').trim();
    if (id.isEmpty || sessionId.isEmpty) {
      throw const FormatException('incomplete session booking');
    }
    return OciServeSessionBooking(
      id: id,
      sessionId: sessionId,
      status: _bookingStatus((json['status'] as String? ?? '').trim()),
    );
  }
}

/// Resultaat van een inschrijving: de enrollment plus per gekozen sessie de
/// aangemaakte boeking.
@immutable
class OciServeRegistration {
  const OciServeRegistration({
    required this.enrollmentId,
    required this.bookings,
  });

  final String enrollmentId;
  final List<OciServeSessionBooking> bookings;

  factory OciServeRegistration.fromJson(Map<String, Object?> json) {
    final enrollmentId = (json['enrollment_id'] as String? ?? '').trim();
    final raw = json['bookings'] is List
        ? json['bookings']! as List
        : throw const FormatException('registration without bookings');
    if (enrollmentId.isEmpty) {
      throw const FormatException('incomplete registration');
    }
    return OciServeRegistration(
      enrollmentId: enrollmentId,
      bookings: raw
          .map(
            (item) => OciServeSessionBooking.fromJson(
              Map<String, Object?>.from(item as Map),
            ),
          )
          .toList(growable: false),
    );
  }
}

@immutable
class OciServePlaybackSnapshot {
  const OciServePlaybackSnapshot({
    required this.sessionId,
    required this.lessonId,
    required this.courseVersionId,
    required this.startedAt,
    this.endedAt,
    this.lastSlideAnchor,
    required this.completed,
    required this.slideTimeMs,
  });

  final String sessionId;
  final String lessonId;
  final String courseVersionId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? lastSlideAnchor;
  final bool completed;
  final Map<String, int> slideTimeMs;

  Map<String, Object?> toJson() => {
    'client_session_id': sessionId,
    'course_version_id': courseVersionId,
    'lesson_id': lessonId,
    'started_at': startedAt.toUtc().toIso8601String(),
    if (endedAt != null) 'ended_at': endedAt!.toUtc().toIso8601String(),
    if (lastSlideAnchor != null) 'last_slide_anchor': lastSlideAnchor,
    'completed': completed,
    'slides': [
      for (final entry in slideTimeMs.entries)
        {'anchor': entry.key, 'displayed_milliseconds': entry.value},
    ],
  };

  String encode() => jsonEncode(toJson());

  factory OciServePlaybackSnapshot.fromJson(Map<String, Object?> json) {
    final slides = <String, int>{};
    for (final raw in json['slides'] as List? ?? const []) {
      final item = Map<String, Object?>.from(raw as Map);
      final anchor = item['anchor'] as String? ?? '';
      if (anchor.isNotEmpty) {
        slides[anchor] = (item['displayed_milliseconds'] as num?)?.toInt() ?? 0;
      }
    }
    return OciServePlaybackSnapshot(
      sessionId: json['client_session_id'] as String? ?? '',
      courseVersionId: json['course_version_id'] as String? ?? '',
      lessonId: json['lesson_id'] as String? ?? '',
      startedAt: DateTime.parse(json['started_at'] as String),
      endedAt: DateTime.tryParse(json['ended_at'] as String? ?? ''),
      lastSlideAnchor: json['last_slide_anchor'] as String?,
      completed: json['completed'] as bool? ?? false,
      slideTimeMs: slides,
    );
  }
}
