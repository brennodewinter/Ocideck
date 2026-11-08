import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De drie ingangen van "Plak Markdown…" (#2825 AC1) plus de echte
/// eind-tot-eind: dezelfde poort als openen uit een bestand.
///
/// De knopgedragingen van de dialoog zelf (leeg, weigeren, weggooien) staan
/// in `paste_markdown_dialog_test.dart`.
void main() {
  late Directory tmp;

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    tmp = Directory.systemTemp.createTempSync('ocideck_shell_paste');
    SharedPreferences.setMockInitialValues({
      'app_consent_accepted': true,
      'storageConnections': jsonEncode([]),
    });
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Finder appBarIcon(IconData icon) =>
      find.descendant(of: find.byType(AppBar), matching: find.byIcon(icon));
  Finder menuItemIcon(IconData icon) => find.descendant(
    of: find.byWidgetPredicate((w) => w is PopupMenuItem),
    matching: find.byIcon(icon),
  );

  late ProviderContainer container;

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
  }

  /// Als pumpApp, maar met een open deck: het ⋮-menu en het commandopalet
  /// leven in de hoofdlayout en bestaan pas bij een open tabblad.
  Future<void> pumpShellWithDeck(WidgetTester tester) async {
    await pumpApp(tester);
    container
        .read(tabsProvider)
        .current!
        .deckNotifier
        .loadDeck(
          Deck(
            title: 'Testrapport',
            slides: [
              Slide.create(SlideType.title).copyWith(title: 'Testrapport'),
            ],
          ),
        );
    await tester.pumpAndSettle();
  }

  /// ⋮ → "Importeren…" → de bronkiezer met "Plak Markdown…".
  Future<void> openSourcePicker(WidgetTester tester) async {
    await tester.tap(appBarIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(menuItemIcon(Icons.file_upload_outlined));
    await tester.pumpAndSettle();
  }

  testWidgets('het welkomstscherm biedt Plak Markdown… naast Openen en URL', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('Plak Markdown…'), findsOneWidget);
    expect(find.text('Openen via URL…'), findsOneWidget);
  });

  testWidgets('de bronkiezer achter Importeren… voert hem ook', (tester) async {
    await pumpShellWithDeck(tester);
    await openSourcePicker(tester);
    expect(find.text('Plak Markdown…'), findsOneWidget);
  });

  testWidgets('het commandopalet voert hem ook', (tester) async {
    await pumpShellWithDeck(tester);
    // ⋮ → "Commandopalet"; de zoekregel heeft de focus meteen.
    await tester.tap(appBarIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(menuItemIcon(Icons.keyboard_command_key));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'plak');
    await tester.pumpAndSettle();
    expect(find.text('Plak Markdown…'), findsOneWidget);
  });

  testWidgets('geplakte tekst zonder marp opent als document in een nieuw '
      'tabblad', (tester) async {
    await pumpShellWithDeck(tester);
    await openSourcePicker(tester);
    await tester.tap(find.text('Plak Markdown…'));
    await tester.pumpAndSettle();

    expect(find.text('Markdown plakken'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '# Aantekening\n\nGewone tekst, geen presentatie.',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Open in OciDeck'));
    await tester.pumpAndSettle();

    final tabs = container.read(tabsProvider).tabs;
    // Het bestaande tabblad blijft ongemoeid; het nieuwe staat er naast (AC7).
    expect(tabs, hasLength(2));
    expect(tabs.last.documentNotifier, isNotNull);
    // De tekst is het bestand: geen pad, opslaan wordt een download.
    expect(
      tabs.last.documentNotifier!.currentState.document!.source,
      '# Aantekening\n\nGewone tekst, geen presentatie.',
    );
  });

  testWidgets('geplakte marp-tekst opent als presentatietabblad', (
    tester,
  ) async {
    await pumpShellWithDeck(tester);
    await openSourcePicker(tester);
    await tester.tap(find.text('Plak Markdown…'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '---\nmarp: true\n---\n\n# Dia één\n',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Open in OciDeck'));
    await tester.pumpAndSettle();

    final tabs = container.read(tabsProvider).tabs;
    expect(tabs, hasLength(2));
    expect(tabs.last.documentNotifier, isNull);
    expect(tabs.last.deckNotifier.currentState.deck!.title, 'Dia één');
  });
}
