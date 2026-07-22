import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/dialogs/command_palette.dart';
import 'package:ocideck/widgets/dialogs/finalize_seal_dialog.dart';
import 'package:ocideck/widgets/dialogs/find_replace_dialog.dart';
import 'package:ocideck/widgets/dialogs/presentation_info_dialog.dart';
import 'package:ocideck/widgets/panels/preview_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the real [AppShell] (via [OciDeckApp]) with a loaded deck to cover the
/// shell's editor layout and its toolbar/command-palette actions — the code that
/// only runs once a presentation is open. Non-driveable actions (native present
/// window, file pickers, network) are left to their own units; here we exercise
/// the in-process paths: markdown toggle, properties, find/replace, the command
/// palette, and running a command from it.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    // Past the consent gate so the shell renders instead of the consent screen.
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
  });

  Deck sampleDeck() => Deck(
    title: 'Testrapport',
    slides: [
      Slide.create(SlideType.title).copyWith(title: 'Testrapport'),
      Slide.create(
        SlideType.bullets,
      ).copyWith(title: 'Bevindingen', bullets: const ['Een', 'Twee']),
    ],
  );

  // Icons repeat across the shell (app bar + slide thumbnails), so scope taps:
  // toolbar buttons live in the AppBar, menu entries in a PopupMenuItem.
  Finder appBarIcon(IconData icon) =>
      find.descendant(of: find.byType(AppBar), matching: find.byIcon(icon));
  Finder menuItemIcon(IconData icon) => find.descendant(
    of: find.byWidgetPredicate((w) => w is PopupMenuItem),
    matching: find.byIcon(icon),
  );

  /// Het commando met dit label, uit het palet zoals de shell het opbouwt.
  ///
  /// Leest de commandolijst in plaats van erin te scrollen of te typen. De
  /// lijst bouwt alleen wat zichtbaar is — een commando verderop bestaat nog
  /// niet in de boom — en `find.byType(TextField).first` (waarmee deze tests
  /// eerder filterden) pakt het zoekveld van de slidelijst eronder, zodat er
  /// niets gefilterd werd. Dat viel alleen niet op zolang het gezochte
  /// commando toevallig nog boven de vouw stond.
  Future<PaletteCommand> paletteCommand(
    WidgetTester tester,
    String label,
  ) async {
    final palette = tester.widget<CommandPalette>(find.byType(CommandPalette));
    final command = palette.commands.firstWhere(
      (c) => c.label == label,
      orElse: () =>
          throw StateError('commando "$label" staat niet in het palet'),
    );
    // Eerst sluiten, dan uitvoeren — dat is ook de volgorde die het palet zelf
    // aanhoudt, en een handeling uitvoeren terwijl de dialoog open blijft laat
    // het scherm in een stand achter die in werkelijkheid niet bestaat.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    return command;
  }

  // Pumps the whole app, opens a deck in the current tab, and returns that tab
  // so tests can assert on its (tab-scoped) deck/editor notifiers directly.
  Future<TabInfo> pumpShell(WidgetTester tester, {Deck? deck}) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final tab = container.read(tabsProvider).current!;
    tab.deckNotifier.loadDeck(deck ?? sampleDeck());
    await tester.pumpAndSettle();
    return tab;
  }

  testWidgets('opening a deck swaps the welcome screen for the editor', (
    tester,
  ) async {
    await pumpShell(tester);

    // The main layout's app bar (slideshow marker + save/toggle actions).
    expect(appBarIcon(Icons.slideshow_outlined), findsOneWidget);
    expect(appBarIcon(Icons.save_outlined), findsOneWidget);
    expect(find.text('Testrapport'), findsWidgets);
  });

  testWidgets('the toolbar toggles between visual and markdown mode', (
    tester,
  ) async {
    final tab = await pumpShell(tester);
    expect(tab.editorNotifier.state.mode, EditorMode.visual);

    await tester.tap(appBarIcon(Icons.code));
    await tester.pumpAndSettle();
    expect(tab.editorNotifier.state.mode, EditorMode.markdown);

    // In markdown mode the icon flips to the "back to visual" glyph.
    await tester.tap(appBarIcon(Icons.view_quilt));
    await tester.pumpAndSettle();
    expect(tab.editorNotifier.state.mode, EditorMode.visual);
  });

  testWidgets('the info button opens the presentation properties dialog', (
    tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(appBarIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.byType(PresentationInfoDialog), findsOneWidget);
  });

  testWidgets('the overflow menu opens the command palette', (tester) async {
    await pumpShell(tester);

    await tester.tap(appBarIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(menuItemIcon(Icons.keyboard_command_key));
    await tester.pumpAndSettle();

    expect(find.byType(CommandPalette), findsOneWidget);
  });

  testWidgets('security commands are hidden from the palette when the module '
      'is off', (tester) async {
    await pumpShell(tester);

    await tester.tap(appBarIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(menuItemIcon(Icons.keyboard_command_key));
    await tester.pumpAndSettle();

    // The Informatieveiligheid module is off by default, so its commands are
    // omitted entirely — not shown as dead greyed-out entries.
    final palette = tester.widget<CommandPalette>(find.byType(CommandPalette));
    expect(
      palette.commands.map((c) => c.label),
      isNot(contains('MIAUW-compliance')),
    );
  });

  testWidgets('ongedaan maken staat in het palet en werkt', (tester) async {
    // Undo en redo bestonden alleen als twee kleine icoontjes in de werkbalk en
    // ontbraken in het palet — de plek waar in deze app een functie gevonden
    // wordt.
    final tab = await pumpShell(tester);
    final before = tab.deckNotifier.currentState.deck!.slides.length;
    tab.deckNotifier.addSlide(SlideType.bullets);
    await tester.pumpAndSettle();
    expect(tab.deckNotifier.currentState.deck!.slides.length, before + 1);

    await tester.tap(appBarIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(menuItemIcon(Icons.keyboard_command_key));
    await tester.pumpAndSettle();

    final undo = await paletteCommand(tester, 'Ongedaan maken');
    expect(undo.enabled, isTrue);
    undo.onInvoke();
    await tester.pumpAndSettle();

    expect(tab.deckNotifier.currentState.deck!.slides.length, before);
  });

  testWidgets('running "Nieuwe grafiek" from the palette adds a chart slide', (
    tester,
  ) async {
    final tab = await pumpShell(tester);
    final before = tab.deckNotifier.currentState.deck!.slides.length;

    await tester.tap(appBarIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(menuItemIcon(Icons.keyboard_command_key));
    await tester.pumpAndSettle();

    (await paletteCommand(tester, 'Nieuwe grafiek')).onInvoke();
    await tester.pumpAndSettle();

    final slides = tab.deckNotifier.currentState.deck!.slides;
    expect(slides.length, before + 1);
    expect(slides.any((s) => s.type == SlideType.chart), isTrue);
  });

  testWidgets('the overflow menu opens find & replace', (tester) async {
    await pumpShell(tester);

    await tester.tap(appBarIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(menuItemIcon(Icons.find_replace));
    await tester.pumpAndSettle();

    expect(find.byType(FindReplaceDialog), findsOneWidget);
  });

  // Verzegelen is documentintegriteit uit de informatieveiligheidsmodule: het
  // hoort achter dezelfde schakelaar als het RFC3161-tijdstempel dat erop volgt.
  testWidgets(
    'the overflow menu offers finalise & seal once the module is on',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'app_consent_accepted': true,
        'secModuleEnabled': true,
      });
      await pumpShell(tester);

      await tester.tap(appBarIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(menuItemIcon(Icons.verified_user_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(FinalizeSealDialog), findsOneWidget);
    },
  );

  testWidgets('finalise & seal stays hidden while the module is off', (
    tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(appBarIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(menuItemIcon(Icons.verified_user_outlined), findsNothing);
  });

  // Zonder ingestelde repository kan geen enkele git-handeling slagen. Ze horen
  // dan niet in het menu te staan: een item dat altijd op dezelfde "stel eerst
  // een repository in"-melding uitkomt leest als een kapotte functie.
  testWidgets('git items stay out of the overflow menu without a repo', (
    tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(appBarIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    // Zonder énige verbinding blijven ook de gedeelde openen/opslaan-ingangen
    // weg: ze zouden altijd op dezelfde "stel eerst iets in"-melding uitkomen.
    expect(menuItemIcon(Icons.cloud_download_outlined), findsNothing);
    expect(menuItemIcon(Icons.cloud_upload_outlined), findsNothing);
    expect(menuItemIcon(Icons.sync), findsNothing);
    expect(menuItemIcon(Icons.manage_search), findsNothing);
    expect(menuItemIcon(Icons.photo_library_outlined), findsNothing);
    // De niet-git-items staan er wél, zodat dit geen leeg menu bewijst.
    expect(menuItemIcon(Icons.find_replace), findsOneWidget);
  });

  testWidgets('git items appear once a repo is configured', (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_consent_accepted': true,
      'gitRepo':
          '{"baseUrl":"https://git.example.org","owner":"acme",'
          '"repo":"decks","provider":"forgejo","defaultBranch":"main",'
          '"trustedInternal":true}',
    });
    await pumpShell(tester);

    await tester.tap(appBarIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    // Openen en opslaan lopen via de gedeelde ingangen, samen met WebDAV en S3.
    expect(menuItemIcon(Icons.cloud_download_outlined), findsOneWidget);
    expect(menuItemIcon(Icons.cloud_upload_outlined), findsOneWidget);
    // Wat git écht toevoegt, staat nog in zijn eigen blok.
    expect(menuItemIcon(Icons.sync), findsOneWidget);
    expect(menuItemIcon(Icons.manage_search), findsOneWidget);
  });

  // De hulpmiddelenbijlage is MIAUW-vastlegging (EIS 4.8.2). Zonder de
  // informatieveiligheidsmodule is er nooit een ingevulde lijst, dus hoort het
  // item niet in het menu van een gewone presentatie.
  testWidgets('the tools appendix stays hidden while the module is off', (
    tester,
  ) async {
    await pumpShell(tester);

    await tester.tap(appBarIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(menuItemIcon(Icons.handyman_outlined), findsNothing);
  });

  testWidgets('the tools appendix appears once the module is on', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'app_consent_accepted': true,
      'secModuleEnabled': true,
    });
    await pumpShell(tester);

    await tester.tap(appBarIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(menuItemIcon(Icons.handyman_outlined), findsOneWidget);
  });

  testWidgets('the overflow menu opens the full-deck preview', (tester) async {
    await pumpShell(tester);

    await tester.tap(appBarIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(menuItemIcon(Icons.preview_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(FullDeckPreview), findsOneWidget);
  });

  testWidgets('clearing checkboxes reports when there is nothing to clear', (
    tester,
  ) async {
    // The sample deck has no checklist slides, so the action is a no-op that
    // explains itself in a snackbar rather than silently doing nothing.
    await pumpShell(tester);

    await tester.tap(appBarIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(menuItemIcon(Icons.check_box_outline_blank));
    await tester.pump();

    expect(
      find.text('Er zijn geen aangevinkte checklist-items om te legen.'),
      findsOneWidget,
    );
  });
}
