import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    // Past the consent gate so the app shell renders. We only seed the consent
    // key, never wiping the whole prefs domain other tests may rely on.
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
  });

  testWidgets('Welcome screen shows startup logo', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('De Winter Information Solutions'),
      findsOneWidget,
    );
  });

  testWidgets('Welcome screen exposes settings', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('the only open presentation can be closed', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final tab = container.read(tabsProvider).current!;
    tab.deckNotifier.loadDeck(
      Deck(
        title: 'Test',
        slides: [Slide.create(SlideType.title).copyWith(title: 'Test')],
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(container.read(tabsProvider).current!.isOpen, isFalse);
  });
}
