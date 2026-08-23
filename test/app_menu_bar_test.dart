import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/shell/app_menu_bar.dart';
import 'package:ocideck/widgets/shell/shell_deck_commands.dart';

/// De macOS-menubalk. Er wás er geen: ongedaan maken en opnieuw bestonden
/// alleen als twee kleine icoontjes in de werkbalk, en de rest van wat de app
/// kan zat verspreid over een `…`-menu en een commandopalet dat je moet kennen
/// om te vinden.
void main() {
  const l10n = AppLocalizations(Locale('nl'));
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  var fired = <String>[];
  void note(String what) => fired.add(what);

  AppMenuActions appActions() => AppMenuActions(
    newDeck: () => note('newDeck'),
    newDocument: () => note('newDocument'),
    open: () => note('open'),
    save: () => note('appSave'),
    settings: () => note('settings'),
    userGuide: () => note('userGuide'),
    shortcuts: () => note('shortcuts'),
  );

  AppDeckMenuActions deckActions({
    bool canExport = true,
    bool canUndo = true,
    bool canRedo = true,
  }) => AppDeckMenuActions(
    save: () => note('save'),
    export: () => note('export'),
    present: () => note('present'),
    fullDeckPreview: () => note('fullDeckPreview'),
    properties: () => note('properties'),
    find: () => note('find'),
    findReplace: () => note('findReplace'),
    commandPalette: () => note('commandPalette'),
    undo: () => note('undo'),
    redo: () => note('redo'),
    canExport: canExport,
    canUndo: canUndo,
    canRedo: canRedo,
  );

  setUp(() => fired = <String>[]);

  /// Elk blad in de menuboom, plat.
  List<PlatformMenuItem> leaves(List<PlatformMenuItem> menus) => [
    for (final item in menus)
      if (item is PlatformMenu)
        ...leaves(item.menus)
      else if (item is PlatformMenuItemGroup)
        ...leaves(item.members)
      else
        item,
  ];

  test('de balk heeft de menus die een macOS-gebruiker verwacht', () {
    final menus = buildAppMenus(l10n, appActions(), deckActions());
    final labels = menus.whereType<PlatformMenu>().map((m) => m.label).toList();
    expect(labels, [
      'OciDeck',
      'Bestand',
      'Bewerken',
      'Presentatie',
      'Venster',
      'Help',
    ]);
  });

  test('Opslaan werkt óók voor een documenttabblad (geen deck)', () {
    // De regressie: File → Opslaan (en Cmd+S) hing aan de deck-only opslag, dus
    // op een documenttabblad — waar er geen deck is — was het item uitgeschakeld
    // en sloeg er niets op (het duidelijkst in de visuele modus). Nu valt het
    // terug op de soort-agnostische app-opslag.
    final menus = buildAppMenus(l10n, appActions(), null);
    final save = leaves(menus).firstWhere((i) => i.label == l10n.d('Opslaan'));
    expect(
      save.onSelected,
      isNotNull,
      reason: 'ingeschakeld voor een document',
    );
    save.onSelected!();
    expect(fired, contains('appSave'));
  });

  test('Opslaan gebruikt de deck-opslag zodra er een deck is', () {
    final menus = buildAppMenus(l10n, appActions(), deckActions());
    final save = leaves(menus).firstWhere((i) => i.label == l10n.d('Opslaan'));
    save.onSelected!();
    expect(fired, contains('save'));
    expect(fired, isNot(contains('appSave')));
  });

  test('ongedaan maken en opnieuw staan in het menu en werken', () {
    // Ze bestonden alleen als icoontje in de werkbalk.
    final menus = buildAppMenus(l10n, appActions(), deckActions());
    final undo = leaves(
      menus,
    ).firstWhere((i) => i.label == l10n.d('Ongedaan maken'));
    final redo = leaves(menus).firstWhere((i) => i.label == l10n.d('Opnieuw'));
    expect(undo.shortcut, isNotNull);
    expect(redo.shortcut, isNotNull);
    undo.onSelected!();
    redo.onSelected!();
    expect(fired, ['undo', 'redo']);
  });

  test('een uitgeputte geschiedenis grijst de items uit', () {
    // Uitgeschakeld en niet verdwenen: een item dat komt en gaat, leert niemand
    // wat de app kan.
    final menus = buildAppMenus(
      l10n,
      appActions(),
      deckActions(canUndo: false, canRedo: false, canExport: false),
    );
    final items = leaves(menus);
    for (final label in [
      l10n.d('Ongedaan maken'),
      l10n.d('Opnieuw'),
      l10n.t('export'),
    ]) {
      final item = items.firstWhere((i) => i.label == label);
      expect(item.onSelected, isNull, reason: '$label hoort uit te staan');
    }
  });

  test('zonder open presentatie blijven de deck-items staan, maar uit', () {
    // Opslaan is bewust de uitzondering: dat valt terug op de app-brede opslag
    // (een document heeft geen deck) — zie de aparte test hierboven. De écht
    // deck-gebonden items blijven uit.
    final menus = buildAppMenus(l10n, appActions(), null);
    final items = leaves(menus);
    for (final label in [
      l10n.d('Presenteren'),
      l10n.d('Eigenschappen'),
      l10n.d('Opdrachten…'),
    ]) {
      final item = items.firstWhere(
        (i) => i.label == label,
        orElse: () => throw StateError('menu-item "$label" ontbreekt'),
      );
      expect(item.onSelected, isNull, reason: '$label hoort uit te staan');
    }
    // De app-brede items blijven wél bruikbaar: nieuw, openen, instellingen en
    // de handleiding hebben geen deck nodig.
    items.firstWhere((i) => i.label == l10n.t('newPresentation')).onSelected!();
    items
        .firstWhere((i) => i.label == l10n.d('Gebruikershandleiding'))
        .onSelected!();
    expect(fired, ['newDeck', 'userGuide']);
  });

  test('tekstbewerking blijft in het menu staan', () {
    // Deze balk vervangt het standaardmenu van macOS. Wat daar stond moet hier
    // terugkomen, anders neemt een menubalk toevoegen knippen en plakken wég
    // bij wie met het menu werkt.
    final items = leaves(buildAppMenus(l10n, appActions(), deckActions()));
    for (final label in [
      l10n.d('Knippen'),
      l10n.d('Kopiëren'),
      l10n.d('Plakken'),
      l10n.d('Alles selecteren'),
    ]) {
      final item = items.firstWhere(
        (i) => i.label == label,
        orElse: () => throw StateError('menu-item "$label" ontbreekt'),
      );
      // Via een Intent, zodat hij bij het veld landt dat focus heeft.
      expect(item.onSelectedIntent, isNotNull);
      expect(item.shortcut, isNotNull);
    }
  });

  test('elk bruikbaar item heeft een label', () {
    // Een leeg label komt als lege regel in de menubalk terecht; alleen de
    // door het platform geleverde items mogen er geen hebben.
    final items = leaves(buildAppMenus(l10n, appActions(), deckActions()));
    for (final item in items) {
      if (item is PlatformProvidedMenuItem) continue;
      expect(item.label, isNotEmpty);
    }
  });

  testWidgets('buiten macOS levert de balk alleen zijn kind', (tester) async {
    // PlatformProvidedMenuItem gooit daar in debug een ArgumentError, dus de
    // menus mogen er niet eens opgebouwd worden.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(
      MaterialApp(
        home: AppPlatformMenuBar(
          actions: appActions(),
          deckActions: deckActions(),
          child: const Text('werkruimte'),
        ),
      ),
    );
    expect(find.text('werkruimte'), findsOneWidget);
    expect(find.byType(PlatformMenuBar), findsNothing);
    // Terugzetten vóór het einde van de test: het testraamwerk controleert
    // tussen twee tests dat geen debug-variabele blijft hangen.
    debugDefaultTargetPlatformOverride = null;
  });

  test('alleen een gewijzigde stand hoort de menubalk te bereiken', () {
    // De werkruimte bouwt elke frame nieuwe closures; die opnieuw publiceren
    // zou het menu elke frame naar het platform laten schrijven.
    ShellDeckCommands commands({bool canUndo = true}) => ShellDeckCommands(
      present: () {},
      export: () {},
      save: () {},
      find: () {},
      findReplace: () {},
      properties: () {},
      commandPalette: () {},
      fullDeckPreview: () {},
      undo: () {},
      redo: () {},
      canExport: true,
      canUndo: canUndo,
      canRedo: true,
    );
    expect(commands().sameEnablement(commands()), isTrue);
    expect(commands().sameEnablement(commands(canUndo: false)), isFalse);
  });
}
