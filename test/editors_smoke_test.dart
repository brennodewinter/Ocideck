import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/widgets/editors/cockpit_editor.dart';
import 'package:ocideck/widgets/editors/question_editor.dart';
import 'package:ocideck/widgets/editors/two_bullets_editor.dart';

/// Render-and-edit smoke tests for the typed slide editors. Pumping each editor
/// exercises its full build, and typing into the first field exercises the
/// emit/onUpdate path (every field is wired to push an updated Slide).
Widget _host(Widget child) => ProviderScope(
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  // A tall surface so editors that lay out without their own scroll don't
  // overflow the default 800x600 test viewport.
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  Future<void> withTallSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('QuestionEditor renders and emits on edit', (tester) async {
    await withTallSurface(tester);
    Slide? updated;
    await tester.pumpWidget(
      _host(
        QuestionEditor(
          slide: Slide.create(SlideType.question),
          onUpdate: (s) => updated = s,
          imageService: ImageService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'Question title');
    await tester.pump();
    expect(updated, isNotNull);
    expect(updated!.type, SlideType.question);
  });

  testWidgets('TwoBulletsEditor renders and emits on edit', (tester) async {
    await withTallSurface(tester);
    Slide? updated;
    await tester.pumpWidget(
      _host(
        TwoBulletsEditor(
          slide: Slide.create(SlideType.twoBullets),
          onUpdate: (s) => updated = s,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'Two-bullets title');
    await tester.pump();
    expect(updated, isNotNull);
    expect(updated!.title, 'Two-bullets title');
  });

  testWidgets('CockpitEditor renders and emits on edit', (tester) async {
    await withTallSurface(tester);
    Slide? updated;
    await tester.pumpWidget(
      _host(
        CockpitEditor(
          slide: Slide.create(SlideType.cockpit),
          onUpdate: (s) => updated = s,
          themeAnimationDurationMs: kThemeDefaultAnimationDurationMs,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'Cockpit title');
    await tester.pump();
    expect(updated, isNotNull);
    expect(updated!.type, SlideType.cockpit);
  });
}
