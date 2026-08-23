import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/eis_entry.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/miauw_codec.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/widgets/dialogs/miauw_compliance_panel.dart';

DeckNotifier _deckNotifier(Deck deck) {
  final md = MarkdownService();
  final file = FileService(md, ImageService(), () => const ThemeProfile());
  final notifier = DeckNotifier(md, file);
  notifier.loadDeck(deck);
  return notifier;
}

Deck _deck({
  Map<String, String> waivers = const {},
  Map<String, String> confirmations = const {},
}) => Deck(
  title: 'Demo',
  slides: [Slide.create(SlideType.title).copyWith(title: 'Welkom')],
  miauw: MiauwDisposition.fromTexts(waivers, confirmations),
);

const _localizations = [
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
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
    // The header discloses the denominator (count / full schema) so the tally
    // can't be mistaken for full MIAUW conformance.
    expect(find.textContaining('/$kMiauwFullSchemaSize ·'), findsOneWidget);
    // A waived foundational EIS (1.1) surfaces the warning + carries its reason.
    expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
    expect(find.text('Geen digitale aanlevering'), findsOneWidget);
    // The other foundational EIS (1.6) is further down the full 88-EIS list;
    // scroll it into view by its unique title (avoids the 4.1.6 id substring).
    await tester.scrollUntilVisible(
      find.textContaining('Handtekening voor waarheidsgetrouwe'),
      80,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      find.textContaining('Handtekening voor waarheidsgetrouwe'),
      findsOneWidget,
    );
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

  testWidgets('confirming a manual EIS reads as voldaan and can be withdrawn', (
    tester,
  ) async {
    await _roomySurface(tester);
    final notifier = _deckNotifier(
      _deck(confirmations: const {'1.2': 'Rapporteur OSCP-gecertificeerd'}),
    );
    await tester.pumpWidget(_host(notifier));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // A confirmed manual EIS carries its attestation note and offers to
    // withdraw it (rather than the confirm/exclude actions of an open one).
    expect(find.text('Rapporteur OSCP-gecertificeerd'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Intrekken'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Intrekken'));
    await tester.pumpAndSettle();

    // Withdrawing returns it to open: the note and the withdraw action are gone.
    expect(notifier.currentState.deck!.miauwConfirmations, isEmpty);
    expect(find.text('Rapporteur OSCP-gecertificeerd'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Intrekken'), findsNothing);
  });
}
