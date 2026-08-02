import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/slides/video_playhead_bus.dart';

/// Mirrors what the real video previews do: publish while alive and
/// [VideoPlayheadBus.clearFor] on dispose. The clear on dispose is the crash
/// site — dispose runs while Flutter finalises the (locked) element tree.
class _PublishingPreview extends StatefulWidget {
  const _PublishingPreview(this.slideId);

  final String slideId;

  @override
  State<_PublishingPreview> createState() => _PublishingPreviewState();
}

class _PublishingPreviewState extends State<_PublishingPreview> {
  @override
  void dispose() {
    VideoPlayheadBus.clearFor(widget.slideId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  // A stray playhead must never leak into the next test's listener.
  tearDown(() => VideoPlayheadBus.current.value = null);

  testWidgets('clearFor on dispose does not crash a live playhead listener', (
    tester,
  ) async {
    // The tree holds both roles at once: the editor's "cut here" button
    // (a ValueListenableBuilder on the bus) and the video preview that clears
    // the bus when it is disposed.
    Widget frame({required bool showPreview}) {
      return MaterialApp(
        home: Column(
          children: [
            ValueListenableBuilder<VideoPlayhead?>(
              valueListenable: VideoPlayheadBus.current,
              builder: (context, playhead, _) =>
                  Text('pos=${playhead?.positionMs ?? -1}'),
            ),
            if (showPreview) const _PublishingPreview('s1'),
          ],
        ),
      );
    }

    await tester.pumpWidget(frame(showPreview: true));
    // A video is playing on slide s1.
    VideoPlayheadBus.publish(
      const VideoPlayhead(slideId: 's1', positionMs: 1200, durationMs: 5000),
    );
    await tester.pump();
    expect(find.text('pos=1200'), findsOneWidget);

    // Navigate away from the slide: the preview is removed and disposes while
    // the tree is locked (finalizeTree). Its clearFor used to notify the
    // still-mounted listener synchronously, throwing
    // "setState() ... called when widget tree was locked".
    await tester.pumpWidget(frame(showPreview: false));
    expect(
      tester.takeException(),
      isNull,
      reason: 'clearFor must not mutate the bus under the tree lock',
    );

    // The playhead is still cleared (deferred to just after the frame), so a
    // stale reading cannot survive into the editor.
    expect(VideoPlayheadBus.current.value, isNull);
    await tester.pump();
    expect(find.text('pos=-1'), findsOneWidget);
  });
}
