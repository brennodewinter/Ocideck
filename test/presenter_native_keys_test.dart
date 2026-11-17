import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/models/presentation_timing.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';
import 'package:ocideck/widgets/presentation/presentation_key_scope.dart';

void main() {
  test(
    'Windows key mapping preserves modifiers and ignores unrelated keys',
    () {
      final seen = <LogicalKeyboardKey>[];
      final scope = PresentationKeyScope(
        onKey: (key, {meta = false, control = false, shift = false}) {
          expect(meta && control && shift, isTrue);
          seen.add(key);
          return KeyEventResult.handled;
        },
        child: const SizedBox(),
      );
      for (final key in [0x25, 0x27, 0x21, 0x22, 0x1b, 0x24, 0x23, 0x41]) {
        scope.dispatchWindowsKey(key, meta: true, control: true, shift: true);
      }
      expect(seen, [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.pageUp,
        LogicalKeyboardKey.pageDown,
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.end,
      ]);
      expect(scope.updateShouldNotify(scope), isFalse);
    },
  );

  for (final timed in [false, true]) {
    testWidgets('native canvas keys use presenter rules (timed=$timed)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FullscreenPresenter(
            slides: [
              Slide.create(SlideType.bullets).copyWith(title: 'Native first'),
              Slide.create(SlideType.bullets).copyWith(title: 'Native second'),
            ],
            projectPath: null,
            themeProfile: const ThemeProfile(),
            initialIndex: 0,
            presentationTiming: timed
                ? const PresentationTimingConfig.pechaKuchaPreset()
                : PresentationTimingConfig.disabled,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Native first'), findsWidgets);
      final scope = tester.widget<PresentationKeyScope>(
        find.byType(PresentationKeyScope).first,
      );
      scope.dispatchWindowsKey(0x27);
      await tester.pump();
      expect(find.text(timed ? 'Native first' : 'Native second'), findsWidgets);
      if (!timed) {
        tester
            .widget<PresentationKeyScope>(
              find.byType(PresentationKeyScope).first,
            )
            .dispatchWindowsKey(0x25);
        await tester.pump();
        expect(find.text('Native first'), findsWidgets);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
