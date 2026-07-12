import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/widgets/dialogs/miauw_compliance_panel.dart';

DeckNotifier _deckNotifier(Deck deck) {
  final md = MarkdownService();
  final file = FileService(md, ImageService(), () => const ThemeProfile());
  final notifier = DeckNotifier(md, file);
  notifier.loadDeck(deck);
  return notifier;
}

Deck _deck({Map<String, String> waivers = const {}}) => Deck(
  title: 'Demo',
  slides: [Slide.create(SlideType.title).copyWith(title: 'Welkom')],
  miauwWaivers: waivers,
);

const _localizations = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  FlutterQuillLocalizations.delegate,
];

/// Mounts a button that opens the panel with [notifier]. The panel takes the
/// notifier directly, so it needs no per-tab provider scope of its own.
Widget _host(DeckNotifier notifier) {
  AppLocalizations.setActiveLanguageCode('nl');
  return MaterialApp(
    localizationsDelegates: _localizations,
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => MiauwCompliancePanel.show(context, notifier),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

/// The panel's content area is a fixed 520px tall; give the dialog enough room
/// so its part-1 rows aren't clipped by the default 600px test surface.
Future<void> _roomySurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(900, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets('renders EIS rows and warns when a foundational EIS is waived', (
    tester,
  ) async {
    await _roomySurface(tester);
    final notifier = _deckNotifier(
      _deck(waivers: const {'1.1': 'Geen digitale aanlevering'}),
    );
    await tester.pumpWidget(_host(notifier));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Rows come from the live deck via the analyzer, grouped by part.
    expect(find.textContaining('1.1 ·'), findsOneWidget);
    expect(find.textContaining('1.6 ·'), findsOneWidget);
    // A waived foundational EIS (1.1) surfaces the warning + carries its reason.
    expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
    expect(find.text('Geen digitale aanlevering'), findsOneWidget);
  });

  testWidgets(
    'reads the tab deck when opened as a root-navigator dialog over a per-tab '
    'scope',
    (tester) async {
      // Reproduces the P2-COMP bug: the command palette opens the panel on the
      // ROOT navigator, which sits above the per-tab ProviderScope. A panel
      // that read the scoped `deckProvider` would resolve the empty root deck
      // and show no rows. Passing the tab notifier in fixes that.
      await _roomySurface(tester);
      final tabNotifier = _deckNotifier(_deck());
      AppLocalizations.setActiveLanguageCode('nl');

      await tester.pumpWidget(
        ProviderScope(
          // Root container: deckProvider is the empty base override.
          child: MaterialApp(
            localizationsDelegates: _localizations,
            // Navigator lives at the root, above the per-tab scope below.
            home: Scaffold(
              body: ProviderScope(
                // Per-tab scope, BELOW the root Navigator (mirrors AppShell).
                overrides: [deckProvider.overrideWith((ref) => tabNotifier)],
                child: Builder(
                  builder: (context) => ElevatedButton(
                    // The command captures the tab notifier here, in tab scope.
                    onPressed: () =>
                        MiauwCompliancePanel.show(context, tabNotifier),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // The panel shows the tab deck's requirements, not an empty overview.
      expect(find.textContaining('1.1 ·'), findsOneWidget);
      expect(find.textContaining('1.6 ·'), findsOneWidget);
    },
  );

  testWidgets('lifting a waiver from the panel updates it live', (
    tester,
  ) async {
    await _roomySurface(tester);
    final notifier = _deckNotifier(
      _deck(waivers: const {'1.1': 'Geen digitale aanlevering'}),
    );
    await tester.pumpWidget(_host(notifier));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 1.1 is the only waived EIS, so exactly one "Opheffen" (lift) action, and
    // the foundational warning is up.
    expect(find.widgetWithText(TextButton, 'Opheffen'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Opheffen'));
    await tester.pumpAndSettle();

    // The notifier listener recomputes the overview: the waiver is gone and the
    // warning clears, without reopening the dialog.
    expect(notifier.currentState.deck!.miauwWaivers, isEmpty);
    expect(find.widgetWithText(TextButton, 'Opheffen'), findsNothing);
    expect(find.byIcon(Icons.warning_amber_outlined), findsNothing);
    expect(find.text('Geen digitale aanlevering'), findsNothing);
  });
}
