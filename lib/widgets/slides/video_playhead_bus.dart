import 'package:flutter/foundation.dart';

/// The current playhead of the video that is playing in the active slide
/// preview. [slideId] ties the reading to a specific slide so the editor's
/// "cut here" only acts on the playhead of the slide it is editing.
@immutable
class VideoPlayhead {
  final String slideId;
  final int positionMs;
  final int durationMs;

  const VideoPlayhead({
    required this.slideId,
    required this.positionMs,
    required this.durationMs,
  });
}

/// A tiny cross-widget channel for the video playhead. The slide preview (file,
/// remote and embed alike) publishes the live position here; the video-slide
/// editor reads it when the user clicks "cut here". A plain [ValueNotifier]
/// keeps the preview library free of Riverpod plumbing — the preview widgets are
/// `part of` the preview library and have no `ref`.
///
/// Only one video plays at a time in the app (the active slide), so a single
/// shared value is sufficient; the [slideId] guard prevents a stale reading from
/// another slide leaking into a cut.
class VideoPlayheadBus {
  VideoPlayheadBus._();

  static final ValueNotifier<VideoPlayhead?> current =
      ValueNotifier<VideoPlayhead?>(null);

  static void publish(VideoPlayhead value) => current.value = value;

  /// The current position for [slideId] in ms, or null when the active playhead
  /// is for a different slide / nothing is playing.
  static int? positionFor(String slideId) {
    final v = current.value;
    return (v != null && v.slideId == slideId) ? v.positionMs : null;
  }

  /// Clears the published playhead if it belongs to [slideId] (on dispose).
  static void clearFor(String slideId) {
    if (current.value?.slideId == slideId) current.value = null;
  }
}
