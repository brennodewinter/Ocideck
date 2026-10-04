import 'package:flutter/foundation.dart';

/// The respondent goal a mailbox challenge verifies (spec `IntakePurpose`).
/// `start` creates a submission after verification; the others act on the
/// submission the locator points at.
enum IntakePurpose {
  start('start'),
  resume('resume'),
  correct('correct'),
  withdraw('withdraw');

  const IntakePurpose(this.wireName);
  final String wireName;

  static IntakePurpose parse(Object? value) => IntakePurpose.values.firstWhere(
    (candidate) => candidate.wireName == value,
    orElse: () => throw const FormatException('unknown intake purpose'),
  );
}

/// Submission lifecycle (spec `IntakeSubmissionState`). `withdrawn` is
/// terminal; `correctionOpen` lets the respondent produce revision n+1.
enum IntakeSubmissionState {
  draft('draft'),
  submitted('submitted'),
  correctionOpen('correction_open'),
  withdrawn('withdrawn');

  const IntakeSubmissionState(this.wireName);
  final String wireName;

  static IntakeSubmissionState parse(Object? value) =>
      IntakeSubmissionState.values.firstWhere(
        (candidate) => candidate.wireName == value,
        orElse: () =>
            throw const FormatException('unknown intake submission state'),
      );
}

/// Per-form organiser grant (spec `IntakeGrantRole`), orthogonal to tenant
/// capabilities. `verwerker` reads and processes submissions, `redacteur`
/// publishes versions, `beheerder` does both plus operational actions.
enum IntakeGrantRole {
  beheerder('beheerder'),
  redacteur('redacteur'),
  verwerker('verwerker');

  const IntakeGrantRole(this.wireName);
  final String wireName;

  static IntakeGrantRole parse(Object? value) =>
      IntakeGrantRole.values.firstWhere(
        (candidate) => candidate.wireName == value,
        orElse: () => throw const FormatException('unknown intake grant role'),
      );
}

/// Whether a published form accepts new submissions (spec enum shared by
/// `IntakePublicForm` and the organiser form objects).
enum IntakeOperationalStatus {
  open('open'),
  paused('paused'),
  closed('closed');

  const IntakeOperationalStatus(this.wireName);
  final String wireName;

  static IntakeOperationalStatus parse(Object? value) =>
      IntakeOperationalStatus.values.firstWhere(
        (candidate) => candidate.wireName == value,
        orElse: () =>
            throw const FormatException('unknown intake operational status'),
      );
}

/// An action the presented respondent grant may still perform (spec
/// `allowed_actions` on `IntakeRespondentSubmission`).
enum IntakeAllowedAction {
  draftPut('draft_put'),
  submit('submit'),
  withdraw('withdraw');

  const IntakeAllowedAction(this.wireName);
  final String wireName;

  static IntakeAllowedAction parse(Object? value) =>
      IntakeAllowedAction.values.firstWhere(
        (candidate) => candidate.wireName == value,
        orElse: () =>
            throw const FormatException('unknown intake allowed action'),
      );
}

/// The immutable snapshot envelope published as one form version (spec
/// `IntakeFormSnapshot`). `definition` — the form questions and layout — is
/// OciDeck's own object that the server stores opaquely; the rest is what the
/// respondent is shown and the server enforces.
@immutable
class IntakeFormSnapshot {
  const IntakeFormSnapshot({
    required this.title,
    required this.purposes,
    required this.privacyText,
    required this.retentionDraftDays,
    required this.retentionSubmittedDays,
    required this.correctionAllowed,
    this.correctionDeadlineDays,
    required this.definition,
  });

  final String title;
  final List<String> purposes;
  final String privacyText;
  final int retentionDraftDays;
  final int retentionSubmittedDays;
  final bool correctionAllowed;
  final int? correctionDeadlineDays;

  /// The form's questions and layout, owned by OciDeck and opaque to the
  /// server. Kept as decoded JSON — the form engine reads it, not this type.
  final Map<String, Object?> definition;

  Map<String, Object?> toJson() => {
    'format': 'ociserve-intake-form/1',
    'title': title,
    'purposes': purposes,
    'privacy_text': privacyText,
    'retention': {
      'draft_days': retentionDraftDays,
      'submitted_days': retentionSubmittedDays,
    },
    'correction_policy': {
      'allowed': correctionAllowed,
      if (correctionDeadlineDays != null)
        'deadline_days': correctionDeadlineDays,
    },
    'definition': definition,
  };

  factory IntakeFormSnapshot.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const {
      'format',
      'title',
      'purposes',
      'privacy_text',
      'retention',
      'correction_policy',
      'definition',
    });
    final retention = json['retention'];
    final correction = json['correction_policy'];
    if (retention is! Map ||
        correction is! Map ||
        json['format'] != 'ociserve-intake-form/1') {
      throw const FormatException('invalid intake snapshot');
    }
    _requireOnlyKeys(retention, const {'draft_days', 'submitted_days'});
    final correctionMap = Map<String, Object?>.from(correction);
    _requireOnlyKeys(correctionMap, const {'allowed', 'deadline_days'});
    final deadline = correctionMap['deadline_days'];
    if (deadline != null && deadline is! int) {
      throw const FormatException('invalid correction deadline');
    }
    return IntakeFormSnapshot(
      title: _requiredString(json, 'title'),
      purposes: _stringList(json['purposes'], 'purposes'),
      privacyText: _requiredString(json, 'privacy_text'),
      retentionDraftDays: _requiredInt(retention, 'draft_days'),
      retentionSubmittedDays: _requiredInt(retention, 'submitted_days'),
      correctionAllowed: correctionMap['allowed'] is bool
          ? correctionMap['allowed'] as bool
          : throw const FormatException('invalid correction policy'),
      correctionDeadlineDays: deadline as int?,
      definition: json['definition'] is Map
          ? Map<String, Object?>.from(json['definition']! as Map)
          : throw const FormatException('invalid definition'),
    );
  }
}

/// The published form as the respondent sees it (`GET /intake/forms/{ref}`).
@immutable
class IntakePublicForm {
  const IntakePublicForm({
    required this.formRef,
    required this.version,
    required this.accepting,
    required this.operationalStatus,
    required this.snapshot,
  });

  final String formRef;
  final int version;
  final bool accepting;
  final IntakeOperationalStatus operationalStatus;
  final IntakeFormSnapshot snapshot;

  factory IntakePublicForm.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const {
      'form_ref',
      'version',
      'accepting',
      'operational_status',
      'snapshot',
    });
    final snapshot = json['snapshot'];
    if (snapshot is! Map) {
      throw const FormatException('invalid public form');
    }
    return IntakePublicForm(
      formRef: _requiredString(json, 'form_ref'),
      version: _requiredInt(json, 'version', minimum: 1),
      accepting: json['accepting'] is bool
          ? json['accepting'] as bool
          : throw const FormatException('invalid public form'),
      operationalStatus: IntakeOperationalStatus.parse(
        json['operational_status'],
      ),
      snapshot: IntakeFormSnapshot.fromJson(
        Map<String, Object?>.from(snapshot),
      ),
    );
  }
}

/// Answer to `POST /intake/challenges` (202): the handle to verify against.
/// `challengeId` is an identifier, not a secret — the mailed code is the
/// proof, and the server shows the same response for unknown input.
@immutable
class IntakeChallenge {
  const IntakeChallenge({
    required this.challengeId,
    required this.expiresIn,
    required this.resendAfter,
  });

  final String challengeId;
  final Duration expiresIn;
  final Duration resendAfter;

  factory IntakeChallenge.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const {
      'challenge_id',
      'expires_in',
      'resend_after',
    });
    return IntakeChallenge(
      challengeId: _requiredString(json, 'challenge_id'),
      expiresIn: Duration(seconds: _requiredInt(json, 'expires_in')),
      resendAfter: Duration(seconds: _requiredInt(json, 'resend_after')),
    );
  }
}

/// Answer to `POST /intake/challenges/{id}/verify`: the short-lived bearer
/// grant for one submission, one form and one purpose. [token] goes in the
/// `Authorization` header only — never in a URL, a log or an error.
@immutable
class IntakeGrant {
  const IntakeGrant({
    required this.token,
    required this.expiresIn,
    required this.purpose,
    required this.locator,
    this.formRef,
    this.state,
  });

  final String token;
  final Duration expiresIn;
  final IntakePurpose purpose;
  final String locator;
  final String? formRef;
  final IntakeSubmissionState? state;

  factory IntakeGrant.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const {
      'grant',
      'expires_in',
      'purpose',
      'locator',
      'form_ref',
      'state',
    });
    final state = json['state'];
    return IntakeGrant(
      token: _requiredString(json, 'grant'),
      expiresIn: Duration(seconds: _requiredInt(json, 'expires_in')),
      purpose: IntakePurpose.parse(json['purpose']),
      locator: _requiredString(json, 'locator'),
      formRef: (json['form_ref'] as String?)?.trim(),
      state: state == null ? null : IntakeSubmissionState.parse(state),
    );
  }
}

/// The respondent's own submission (`GET /intake/submissions/{locator}`).
@immutable
class IntakeRespondentSubmission {
  const IntakeRespondentSubmission({
    required this.locator,
    required this.state,
    required this.revision,
    required this.draftPresent,
    required this.allowedActions,
    this.correctionDeadline,
    this.submittedAt,
  });

  final String locator;
  final IntakeSubmissionState state;
  final int revision;
  final bool draftPresent;
  final List<IntakeAllowedAction> allowedActions;
  final DateTime? correctionDeadline;
  final DateTime? submittedAt;

  factory IntakeRespondentSubmission.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const {
      'locator',
      'state',
      'revision',
      'draft_present',
      'allowed_actions',
      'correction_deadline',
      'submitted_at',
    });
    final actions = json['allowed_actions'];
    if (actions is! List) {
      throw const FormatException('invalid respondent submission');
    }
    return IntakeRespondentSubmission(
      locator: _requiredString(json, 'locator'),
      state: IntakeSubmissionState.parse(json['state']),
      revision: _requiredInt(json, 'revision'),
      draftPresent: json['draft_present'] is bool
          ? json['draft_present'] as bool
          : throw const FormatException('invalid respondent submission'),
      allowedActions: List.unmodifiable(actions.map(IntakeAllowedAction.parse)),
      correctionDeadline: _optionalDate(json, 'correction_deadline'),
      submittedAt: _optionalDate(json, 'submitted_at'),
    );
  }
}

/// Receipt for `PUT …/draft`: what the server stored of the uploaded bytes.
/// The client compares [sha256] and [size] with what it sent.
@immutable
class IntakeDraftReceipt {
  const IntakeDraftReceipt({required this.sha256, required this.size});

  final String sha256;
  final int size;

  factory IntakeDraftReceipt.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const {'sha256', 'size'});
    return IntakeDraftReceipt(
      sha256: _hexDigest(json['sha256']),
      size: _requiredInt(json, 'size'),
    );
  }
}

/// Receipt for `POST …/submit`: the immutable revision the server stored.
@immutable
class IntakeSubmitReceipt {
  const IntakeSubmitReceipt({
    required this.revision,
    required this.submittedAt,
    required this.sha256,
    required this.size,
  });

  final int revision;
  final DateTime submittedAt;
  final String sha256;
  final int size;

  factory IntakeSubmitReceipt.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const {
      'revision',
      'submitted_at',
      'sha256',
      'size',
    });
    return IntakeSubmitReceipt(
      revision: _requiredInt(json, 'revision', minimum: 1),
      submittedAt: _requiredDate(json, 'submitted_at'),
      sha256: _hexDigest(json['sha256']),
      size: _requiredInt(json, 'size'),
    );
  }
}

/// Receipt for `POST …/withdraw` — the state must be `withdrawn`.
@immutable
class IntakeWithdrawReceipt {
  const IntakeWithdrawReceipt({required this.state});

  final IntakeSubmissionState state;

  factory IntakeWithdrawReceipt.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const {'state'});
    return IntakeWithdrawReceipt(
      state: IntakeSubmissionState.parse(json['state']),
    );
  }
}

// — Organiser side —

/// One row of the organiser's form list; `myGrant` is the caller's own
/// per-form role, which drives what the UI may offer.
@immutable
class IntakeFormSummary {
  const IntakeFormSummary({
    required this.formId,
    required this.name,
    required this.operationalStatus,
    required this.activeVersion,
    required this.myGrant,
  });

  final String formId;
  final String name;
  final IntakeOperationalStatus operationalStatus;
  final int activeVersion;
  final IntakeGrantRole myGrant;

  factory IntakeFormSummary.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const {
      'form_id',
      'name',
      'operational_status',
      'active_version',
      'my_grant',
    });
    return IntakeFormSummary(
      formId: _requiredString(json, 'form_id'),
      name: _requiredString(json, 'name'),
      operationalStatus: IntakeOperationalStatus.parse(
        json['operational_status'],
      ),
      activeVersion: _requiredInt(json, 'active_version', minimum: 1),
      myGrant: IntakeGrantRole.parse(json['my_grant']),
    );
  }
}

/// `GET …/intake-forms` — a page of summaries plus an optional cursor.
@immutable
class IntakeFormList {
  const IntakeFormList({required this.items, this.nextCursor});

  final List<IntakeFormSummary> items;
  final String? nextCursor;

  factory IntakeFormList.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const {'items', 'next_cursor'});
    final items = json['items'];
    if (items is! List || items.length > 500) {
      throw const FormatException('invalid intake form list');
    }
    return IntakeFormList(
      items: List.unmodifiable(
        items.map(
          (item) => IntakeFormSummary.fromJson(
            Map<String, Object?>.from(item as Map),
          ),
        ),
      ),
      nextCursor: (json['next_cursor'] as String?)?.trim(),
    );
  }
}

/// One published version inside a form (summary — the snapshot itself is
/// fetched per version).
@immutable
class IntakeFormVersionSummary {
  const IntakeFormVersionSummary({
    required this.version,
    required this.sha256,
    required this.publishedAt,
    required this.active,
  });

  final int version;
  final String sha256;
  final DateTime publishedAt;
  final bool active;

  factory IntakeFormVersionSummary.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const {
      'version',
      'sha256',
      'published_at',
      'active',
    });
    return IntakeFormVersionSummary(
      version: _requiredInt(json, 'version', minimum: 1),
      sha256: _hexDigest(json['sha256']),
      publishedAt: _requiredDate(json, 'published_at'),
      active: json['active'] is bool
          ? json['active'] as bool
          : throw const FormatException('invalid version summary'),
    );
  }
}

/// A full published version including its snapshot.
@immutable
class IntakeFormVersion {
  const IntakeFormVersion({
    required this.version,
    required this.sha256,
    required this.publishedAt,
    required this.snapshot,
  });

  final int version;
  final String sha256;
  final DateTime publishedAt;
  final IntakeFormSnapshot snapshot;

  factory IntakeFormVersion.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const {
      'version',
      'sha256',
      'published_at',
      'snapshot',
    });
    final snapshot = json['snapshot'];
    if (snapshot is! Map) {
      throw const FormatException('invalid form version');
    }
    return IntakeFormVersion(
      version: _requiredInt(json, 'version', minimum: 1),
      sha256: _hexDigest(json['sha256']),
      publishedAt: _requiredDate(json, 'published_at'),
      snapshot: IntakeFormSnapshot.fromJson(
        Map<String, Object?>.from(snapshot),
      ),
    );
  }
}

/// One managed intake form as the organiser sees it.
@immutable
class IntakeForm {
  const IntakeForm({
    required this.formId,
    required this.formRef,
    required this.name,
    required this.operationalStatus,
    required this.activeVersion,
    required this.versions,
    required this.createdAt,
  });

  /// Internal organiser identifier — never shared with a respondent.
  final String formId;

  /// High-entropy public identifier that goes in the respondent link.
  final String formRef;
  final String name;
  final IntakeOperationalStatus operationalStatus;
  final int activeVersion;
  final List<IntakeFormVersionSummary> versions;
  final DateTime createdAt;

  factory IntakeForm.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const {
      'form_id',
      'form_ref',
      'name',
      'operational_status',
      'active_version',
      'versions',
      'created_at',
    });
    final versions = json['versions'];
    if (versions is! List) {
      throw const FormatException('invalid intake form');
    }
    return IntakeForm(
      formId: _requiredString(json, 'form_id'),
      formRef: _requiredString(json, 'form_ref'),
      name: _requiredString(json, 'name'),
      operationalStatus: IntakeOperationalStatus.parse(
        json['operational_status'],
      ),
      activeVersion: _requiredInt(json, 'active_version', minimum: 1),
      versions: List.unmodifiable(
        versions.map(
          (item) => IntakeFormVersionSummary.fromJson(
            Map<String, Object?>.from(item as Map),
          ),
        ),
      ),
      createdAt: _requiredDate(json, 'created_at'),
    );
  }
}

/// One immutable revision inside a submission.
@immutable
class IntakeRevisionSummary {
  const IntakeRevisionSummary({
    required this.revision,
    required this.submittedAt,
    required this.sha256,
    required this.size,
  });

  final int revision;
  final DateTime submittedAt;
  final String sha256;
  final int size;

  factory IntakeRevisionSummary.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const {
      'revision',
      'submitted_at',
      'sha256',
      'size',
    });
    return IntakeRevisionSummary(
      revision: _requiredInt(json, 'revision', minimum: 1),
      submittedAt: _requiredDate(json, 'submitted_at'),
      sha256: _hexDigest(json['sha256']),
      size: _requiredInt(json, 'size'),
    );
  }
}

/// One row of the organiser's submission inbox — deliberately without
/// answers, e-mail address or locator.
@immutable
class IntakeSubmissionSummary {
  const IntakeSubmissionSummary({
    required this.submissionId,
    required this.state,
    required this.revision,
    required this.handled,
    required this.submittedAt,
  });

  final String submissionId;
  final IntakeSubmissionState state;
  final int revision;
  final bool handled;
  final DateTime submittedAt;

  factory IntakeSubmissionSummary.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const {
      'submission_id',
      'state',
      'revision',
      'handled',
      'submitted_at',
    });
    return IntakeSubmissionSummary(
      submissionId: _requiredString(json, 'submission_id'),
      state: IntakeSubmissionState.parse(json['state']),
      revision: _requiredInt(json, 'revision'),
      handled: json['handled'] is bool
          ? json['handled'] as bool
          : throw const FormatException('invalid submission summary'),
      submittedAt: _requiredDate(json, 'submitted_at'),
    );
  }
}

/// `GET …/submissions` — a page of inbox rows plus an optional cursor.
@immutable
class IntakeSubmissionList {
  const IntakeSubmissionList({required this.items, this.nextCursor});

  final List<IntakeSubmissionSummary> items;
  final String? nextCursor;

  factory IntakeSubmissionList.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const {'items', 'next_cursor'});
    final items = json['items'];
    if (items is! List || items.length > 500) {
      throw const FormatException('invalid submission list');
    }
    return IntakeSubmissionList(
      items: List.unmodifiable(
        items.map(
          (item) => IntakeSubmissionSummary.fromJson(
            Map<String, Object?>.from(item as Map),
          ),
        ),
      ),
      nextCursor: (json['next_cursor'] as String?)?.trim(),
    );
  }
}

/// Submission detail for an assigned processor — the verified mailbox
/// address is deliberately absent (access metadata, not inbox content).
@immutable
class IntakeSubmissionDetail {
  const IntakeSubmissionDetail({
    required this.submissionId,
    required this.state,
    required this.revision,
    required this.handled,
    required this.createdAt,
    required this.revisions,
    this.submittedAt,
    this.correctionDeadline,
  });

  final String submissionId;
  final IntakeSubmissionState state;
  final int revision;
  final bool handled;
  final DateTime createdAt;
  final List<IntakeRevisionSummary> revisions;
  final DateTime? submittedAt;
  final DateTime? correctionDeadline;

  factory IntakeSubmissionDetail.fromJson(Map<String, Object?> json) {
    _requireOnlyKeys(json, const {
      'submission_id',
      'state',
      'revision',
      'handled',
      'created_at',
      'submitted_at',
      'revisions',
      'correction_deadline',
    });
    final revisions = json['revisions'];
    if (revisions is! List) {
      throw const FormatException('invalid submission detail');
    }
    return IntakeSubmissionDetail(
      submissionId: _requiredString(json, 'submission_id'),
      state: IntakeSubmissionState.parse(json['state']),
      revision: _requiredInt(json, 'revision'),
      handled: json['handled'] is bool
          ? json['handled'] as bool
          : throw const FormatException('invalid submission detail'),
      createdAt: _requiredDate(json, 'created_at'),
      revisions: List.unmodifiable(
        revisions.map(
          (item) => IntakeRevisionSummary.fromJson(
            Map<String, Object?>.from(item as Map),
          ),
        ),
      ),
      submittedAt: _optionalDate(json, 'submitted_at'),
      correctionDeadline: _optionalDate(json, 'correction_deadline'),
    );
  }
}

// — strict readers: every field is checked, unknown values refuse —

void _requireOnlyKeys(Map<dynamic, dynamic> json, Set<String> allowed) {
  if (json.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('unexpected intake field');
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = (json[key] as String?)?.trim() ?? '';
  if (value.isEmpty) {
    throw FormatException('missing intake field $key');
  }
  return value;
}

int _requiredInt(Map<dynamic, dynamic> json, String key, {int? minimum}) {
  final value = json[key];
  if (value is! int || (minimum != null && value < minimum) || value < 0) {
    throw FormatException('missing intake field $key');
  }
  return value;
}

DateTime _requiredDate(Map<String, Object?> json, String key) {
  final parsed = DateTime.tryParse(json[key] as String? ?? '');
  if (parsed == null) {
    throw FormatException('missing intake field $key');
  }
  return parsed.toUtc();
}

DateTime? _optionalDate(Map<String, Object?> json, String key) {
  final raw = json[key];
  if (raw == null) return null;
  final parsed = DateTime.tryParse(raw as String? ?? '');
  if (parsed == null) {
    throw FormatException('invalid intake date $key');
  }
  return parsed.toUtc();
}

List<String> _stringList(Object? raw, String key) {
  if (raw is! List || raw.isEmpty) {
    throw FormatException('missing intake field $key');
  }
  return List.unmodifiable(
    raw.map(
      (item) => (item is String && item.trim().isNotEmpty)
          ? item
          : throw FormatException('invalid intake field $key'),
    ),
  );
}

String _hexDigest(Object? value) {
  final hex = value is String ? value.trim().toLowerCase() : '';
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hex)) {
    throw const FormatException('invalid intake sha256');
  }
  return hex;
}
