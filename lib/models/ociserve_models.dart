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
  });

  final String participantId;
  final DateTime generatedAt;
  final Map<String, Object?> data;

  factory OciServePrivacyData.fromJson(Map<String, Object?> json) {
    final participantId = (json['participant_id'] as String? ?? '').trim();
    final generatedAt = DateTime.tryParse(
      json['generated_at'] as String? ?? '',
    );
    final data = json['data'];
    if (participantId.isEmpty || generatedAt == null || data is! Map) {
      throw const FormatException('incomplete OciServe privacy data');
    }
    return OciServePrivacyData(
      participantId: participantId,
      generatedAt: generatedAt,
      data: Map.unmodifiable(Map<String, Object?>.from(data)),
    );
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
