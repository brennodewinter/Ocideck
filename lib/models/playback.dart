import 'package:flutter/foundation.dart';

import 'rehearsal.dart';

/// Generic result of one presenter playback.
///
/// It contains only navigation and displayed-duration data. Question answers,
/// correctness, notes, annotations, deck content and account data are
/// intentionally excluded from this reporting boundary.
@immutable
class PlaybackReport {
  const PlaybackReport({
    required this.run,
    required this.lastSlideId,
    required this.completed,
  });

  final RehearsalRun run;
  final String? lastSlideId;
  final bool completed;
}
