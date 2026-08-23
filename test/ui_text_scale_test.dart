import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('the interface text-scale setting scales the editor UI', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );

    TextScaler scalerAtShell() =>
        MediaQuery.textScalerOf(tester.element(find.byType(AppShell)));
    expect(scalerAtShell().scale(10), 10);

    await container.read(settingsProvider.notifier).setUiTextScale(1.5);
    await tester.pump();
    expect(scalerAtShell().scale(10), 15);

    // The setting is clamped to WCAG's 200%.
    await container.read(settingsProvider.notifier).setUiTextScale(5.0);
    await tester.pump();
    expect(scalerAtShell().scale(10), 20);
  });

  testWidgets('the wide welcome screen fits at 200% interface text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );

    await container.read(settingsProvider.notifier).setUiTextScale(2);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('the slide canvas opts out of text scaling', (tester) async {
    final slide = Slide.create(
      SlideType.bullets,
    ).copyWith(title: 'Titel', bullets: const ['Punt een']);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 450,
            child: SlidePreviewWidget(slide: slide),
          ),
        ),
      ),
    );
    await tester.pump();

    // The slide is a fixed design surface: its text must render unscaled so
    // the auto-fit measuring stays truthful.
    final inSlide = MediaQuery.textScalerOf(
      tester.element(find.text('Punt een')),
    );
    expect(inSlide.scale(10), 10);
  });
}
