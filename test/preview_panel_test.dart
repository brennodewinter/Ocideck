import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/panels/preview_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Smoke tests for the live preview panel: it reads the deck, editor and
/// settings providers, so set up a real deck in a container and render.
///
/// These deliberately use bounded `pump()` calls rather than `pumpAndSettle()`:
/// the preview can host a perpetually-animating element (a blinking caret), and
/// a leaked ticker from another suite test would make `pumpAndSettle` spin for
/// its full 10-minute timeout.
ProviderContainer _deckWith(List<SlideType> types) {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer();
  final deck = container.read(deckProvider.notifier);
  deck.newDeck('Preview test');
  for (final t in types) {
    deck.addSlide(t);
  }
  container.read(editorProvider.notifier).select(0);
  return container;
}

Future<void> _pumpPanel(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.binding.setSurfaceSize(const Size(1100, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: PreviewPanel()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('renders the current slide preview without error', (
    tester,
  ) async {
    final container = _deckWith([SlideType.bullets]);
    addTearDown(container.dispose);

    await _pumpPanel(tester, container);

    expect(find.byType(PreviewPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders across several slide types without error', (
    tester,
  ) async {
    final container = _deckWith([
      SlideType.title,
      SlideType.bullets,
      SlideType.table,
      SlideType.quote,
    ]);
    addTearDown(container.dispose);

    await _pumpPanel(tester, container);
    expect(tester.takeException(), isNull);

    // Step the editor selection through each slide; the panel follows.
    for (var i = 1; i < 4; i++) {
      container.read(editorProvider.notifier).select(i);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    }
  });
}
