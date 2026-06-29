import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/widgets/editors/bullets_image_editor.dart';
import 'package:ocideck/widgets/editors/video_slide_editor.dart';

/// Render-and-edit smoke tests for two more typed slide editors. Pumping each
/// editor exercises its full build, and typing into the first field exercises
/// the emit/onUpdate path (the first field is the title, wired to push an
/// updated Slide).
Widget _host(Widget child) => ProviderScope(
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  // A tall surface so editors that lay out without their own scroll don't
  // overflow the default 800x600 test viewport.
  Future<void> withTallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('VideoSlideEditor renders and emits on edit', (tester) async {
    await withTallSurface(tester);
    Slide? updated;
    await tester.pumpWidget(
      _host(
        VideoSlideEditor(
          slide: Slide.create(SlideType.video),
          onUpdate: (Slide s) => updated = s,
          imageService: ImageService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'Video title');
    await tester.pump();
    expect(updated, isNotNull);
    expect(updated!.type, SlideType.video);
    expect(updated!.title, 'Video title');
  });

  testWidgets('BulletsImageEditor renders and emits on edit', (tester) async {
    await withTallSurface(tester);
    Slide? updated;
    await tester.pumpWidget(
      _host(
        BulletsImageEditor(
          slide: Slide.create(SlideType.bulletsImage),
          onUpdate: (Slide s) => updated = s,
          imageService: ImageService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'Bullets-image title');
    await tester.pump();
    expect(updated, isNotNull);
    expect(updated!.type, SlideType.bulletsImage);
    expect(updated!.title, 'Bullets-image title');
  });
}
