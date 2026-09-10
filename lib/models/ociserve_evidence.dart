import 'package:flutter/foundation.dart';

/// Quarantine lifecycle of an evidence upload.
///
/// Mirrors OciServe's `EvidenceResponse.status`:
/// - `pending` — slot reserved, bytes not yet uploaded.
/// - `uploaded` — bytes received, awaiting server-side verification.
/// - `clean` — verified, safe to show.
/// - `rejected` — verification failed, carries `rejectionReason`.
/// - `failed` — dead-letter, carries `rejectionReason`.
enum EvidenceUploadStatus {
  pending,
  uploaded,
  clean,
  rejected,
  failed;

  static EvidenceUploadStatus fromString(String value) => switch (value) {
    'pending' => EvidenceUploadStatus.pending,
    'uploaded' => EvidenceUploadStatus.uploaded,
    'clean' => EvidenceUploadStatus.clean,
    'rejected' => EvidenceUploadStatus.rejected,
    'failed' => EvidenceUploadStatus.failed,
    _ => EvidenceUploadStatus.pending,
  };
}

/// One evidence upload slot in the quarantine protocol.
///
/// Maps to OciServe's `EvidenceResponse` schema. The participant uploads
/// a file (step 1: reserve slot, step 2: upload bytes); the server
/// verifies it asynchronously and transitions the status.
@immutable
class EvidenceUpload {
  const EvidenceUpload({
    required this.id,
    required this.filename,
    required this.declaredType,
    required this.declaredSize,
    required this.declaredHash,
    required this.status,
    required this.createdAt,
    this.participantId = '',
    this.blobHash = '',
    this.blobSize = 0,
    this.rejectionReason,
    this.completedAt,
    this.verifiedAt,
  });

  final String id;
  final String participantId;
  final String filename;
  final String declaredType;
  final int declaredSize;
  final String declaredHash;
  final String blobHash;
  final int blobSize;
  final EvidenceUploadStatus status;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime? completedAt;
  final DateTime? verifiedAt;

  /// Whether the server has verified the file and it may be shown.
  bool get isClean => status == EvidenceUploadStatus.clean;

  /// Whether the upload is still in progress (slot reserved, bytes not
  /// yet received or not yet verified).
  bool get isInProgress =>
      status == EvidenceUploadStatus.pending ||
      status == EvidenceUploadStatus.uploaded;

  factory EvidenceUpload.fromJson(Map<String, Object?> json) {
    final id = (json['id'] as String? ?? '').trim();
    if (id.isEmpty) throw const FormatException('incomplete evidence upload');
    return EvidenceUpload(
      id: id,
      participantId: (json['participant_id'] as String? ?? '').trim(),
      filename: (json['filename'] as String? ?? '').trim(),
      declaredType: (json['declared_type'] as String? ?? '').trim(),
      declaredSize: (json['declared_size'] as num?)?.toInt() ?? 0,
      declaredHash: (json['declared_hash'] as String? ?? '').trim(),
      blobHash: (json['blob_hash'] as String? ?? '').trim(),
      blobSize: (json['blob_size'] as num?)?.toInt() ?? 0,
      status: EvidenceUploadStatus.fromString(
        (json['status'] as String? ?? 'pending').trim(),
      ),
      rejectionReason: (json['rejection_reason'] as String?)?.trim(),
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      completedAt: DateTime.tryParse(json['completed_at'] as String? ?? ''),
      verifiedAt: DateTime.tryParse(json['verified_at'] as String? ?? ''),
    );
  }
}

/// Request body for reserving an evidence upload slot.
///
/// Maps to OciServe's `EvidenceSlotRequest` schema. The `participantId`
/// is optional — when omitted, the server uses the authenticated
/// participant.
@immutable
class EvidenceUploadRequest {
  const EvidenceUploadRequest({
    required this.filename,
    required this.declaredType,
    required this.declaredSize,
    required this.declaredHash,
    this.participantId,
  });

  final String filename;
  final String declaredType;
  final int declaredSize;
  final String declaredHash;
  final String? participantId;

  Map<String, Object?> toJson() => {
    if (participantId != null && participantId!.isNotEmpty)
      'participant_id': participantId,
    'filename': filename,
    'declared_type': declaredType,
    'declared_size': declaredSize,
    'declared_hash': declaredHash,
  };
}

/// Lifecycle state of a qualification (an issued badge).
///
/// Mirrors OciServe's `QualificationResponse.status`:
/// - `pending` — issued, awaiting review.
/// - `approved` — reviewed and accepted.
/// - `rejected` — reviewed and refused.
/// - `revoked` — withdrawn by an administrator.
/// - `expired` — past its expiry date.
enum QualificationStatus {
  pending,
  approved,
  rejected,
  revoked,
  expired;

  static QualificationStatus fromString(String value) => switch (value) {
    'pending' => QualificationStatus.pending,
    'approved' => QualificationStatus.approved,
    'rejected' => QualificationStatus.rejected,
    'revoked' => QualificationStatus.revoked,
    'expired' => QualificationStatus.expired,
    _ => QualificationStatus.pending,
  };
}

/// An issued qualification (badge) for a participant.
///
/// Maps to OciServe's `QualificationResponse` schema. The `snapshot`
/// holds the skill definition at issue time, so a later change to the
/// skill does not rewrite history.
@immutable
class OciServeQualification {
  const OciServeQualification({
    required this.id,
    required this.participantId,
    required this.skillVersionId,
    required this.status,
    required this.issuedBy,
    required this.issuedAt,
    required this.snapshot,
    required this.createdAt,
    this.expiresAt,
  });

  final String id;
  final String participantId;
  final String skillVersionId;
  final QualificationStatus status;
  final String issuedBy;
  final DateTime issuedAt;
  final DateTime? expiresAt;
  final Map<String, Object?> snapshot;
  final DateTime createdAt;

  /// Whether the badge is currently valid (approved and not expired).
  bool get isActive =>
      status == QualificationStatus.approved &&
      (expiresAt == null || expiresAt!.isAfter(DateTime.now()));

  /// The skill title from the immutable snapshot, if present.
  String get skillTitle => (snapshot['title'] as String? ?? '').trim();

  /// The validity months from the snapshot, if present.
  int get validityMonths => (snapshot['validity_months'] as num?)?.toInt() ?? 0;

  factory OciServeQualification.fromJson(Map<String, Object?> json) {
    final id = (json['id'] as String? ?? '').trim();
    if (id.isEmpty) throw const FormatException('incomplete qualification');
    return OciServeQualification(
      id: id,
      participantId: (json['participant_id'] as String? ?? '').trim(),
      skillVersionId: (json['skill_version_id'] as String? ?? '').trim(),
      status: QualificationStatus.fromString(
        (json['status'] as String? ?? 'pending').trim(),
      ),
      issuedBy: (json['issued_by'] as String? ?? '').trim(),
      issuedAt:
          DateTime.tryParse(json['issued_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
      snapshot: json['snapshot'] is Map
          ? Map<String, Object?>.from(json['snapshot']! as Map)
          : const {},
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

/// A course requirement in a skill definition.
///
/// Maps to the items in `SkillDefinition.requirements`.
@immutable
class OciServeSkillRequirement {
  const OciServeSkillRequirement({required this.courseId, required this.title});

  final String courseId;
  final String title;

  factory OciServeSkillRequirement.fromJson(Map<String, Object?> json) =>
      OciServeSkillRequirement(
        courseId: (json['course_id'] as String? ?? '').trim(),
        title: (json['title'] as String? ?? '').trim(),
      );
}

/// The definition of a skill (badge class) at a point in time.
///
/// Maps to OciServe's `SkillDefinition` schema. The `requirements`
/// are course requirements; evidence requirements are part of
/// OciServe#517 and not yet in the API.
@immutable
class OciServeSkillDefinition {
  const OciServeSkillDefinition({
    this.description = '',
    this.badgeClassUrl,
    this.validityMonths = 0,
    this.requirements = const [],
    this.publishedAt,
    this.createdAt,
  });

  final String description;
  final Uri? badgeClassUrl;
  final int validityMonths;
  final List<OciServeSkillRequirement> requirements;
  final DateTime? publishedAt;
  final DateTime? createdAt;

  factory OciServeSkillDefinition.fromJson(Map<String, Object?> json) {
    final requirementsRaw = json['requirements'] as List? ?? const [];
    return OciServeSkillDefinition(
      description: (json['description'] as String? ?? '').trim(),
      badgeClassUrl: Uri.tryParse(
        (json['badge_class_url'] as String? ?? '').trim(),
      ),
      validityMonths: (json['validity_months'] as num?)?.toInt() ?? 0,
      requirements: requirementsRaw
          .map(
            (item) => OciServeSkillRequirement.fromJson(
              Map<String, Object?>.from(item as Map),
            ),
          )
          .toList(growable: false),
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }
}
