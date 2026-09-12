import 'package:flutter/foundation.dart';

/// Server-issued identity of a lesson opened for playback.
///
/// This state belongs to the tab, never to the [Deck] or its Markdown. It is
/// deliberately free of OAuth credentials and learner profile data so it
/// cannot leak into save, export, recovery, clipboard, or presentation output.
@immutable
class LearningSessionRef {
  const LearningSessionRef({
    required this.serverUrl,
    required this.accountId,
    required this.organizationId,
    required this.enrollmentId,
    required this.courseVersionId,
    required this.lessonId,
    required this.playbackSessionId,
    required this.packageHash,
    required this.startedAt,
    required this.expiresAt,
  });

  final String serverUrl;
  final String accountId;
  final String organizationId;
  final String enrollmentId;
  final String courseVersionId;
  final String lessonId;
  final String playbackSessionId;
  final String packageHash;
  final DateTime startedAt;
  final DateTime expiresAt;
}
