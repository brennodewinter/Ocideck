import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/theme/appearance_scope.dart';

/// Een blad dat zich uit [AppTheme] kleurt en verder nergens van afhangt: geen
/// `Theme.of(context)`, geen provider, geen `modeOf`.
///
/// Dat is niet kunstmatig maar de nórm in deze app — 776 gebruiksplekken in 139
/// bestanden lezen zo'n token — en precies daarom bleef het kwaliteitspaneel na
/// een themawissel donkergroen op een lichte interface staan (#780, #814).
class _LosgekoppeldBlad extends StatelessWidget {
  const _LosgekoppeldBlad();

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: AppTheme.paper, child: const SizedBox(width: 10));
}

/// Houdt bij of zijn `State` bewaard blijft. Een sleutel op de modus zou die
/// weggooien — en met de deckstaat eraan vast was dat het niet-opgeslagen deck
/// van de gebruiker (#780).
class _StaatDrager extends StatefulWidget {
  const _StaatDrager();

  @override
  State<_StaatDrager> createState() => _StaatDragerState();
}

class _StaatDragerState extends State<_StaatDrager> {
  static int aanmaak = 0;
  int bouwrondes = 0;

  @override
  void initState() {
    super.initState();
    aanmaak++;
  }

  @override
  Widget build(BuildContext context) {
    bouwrondes++;
    return const SizedBox(width: 5);
  }
}

/// De opstelling van de échte app, en dat is hier het halve werk.
///
/// De modus komt van bóven de `MaterialApp` (in de app: een Riverpod-watch in
/// `OciDeckApp`), en het blad hangt eronder achter een **`const`** kind. Dat
/// laatste is precies waarom de bug bestaat: `Element.updateChild` slaat een
/// herbouw over zodra het nieuwe widget identiek is aan het oude, en twee
/// `const`-instanties ván hetzelfde zíjn identiek. De scope herbouwt dus wel,
/// maar de boom eronder niet.
///
/// Een toets die in plaats hiervan twee keer `pumpWidget` doet, meet niets: dat
/// vervangt de wortel en herbouwt alles, waardoor het blad "vanzelf" de goede
/// kleur krijgt. Die versie stond hier eerst, was groen, en bewees niets.
class _App extends StatelessWidget {
  final ValueNotifier<AppAppearanceProfile> profiel;

  const _App(this.profiel);

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<AppAppearanceProfile>(
        valueListenable: profiel,
        builder: (context, p, _) => MaterialApp(
          home: AppearanceScope(
            appearance: p,
            child: const Column(
              children: [_LosgekoppeldBlad(), _StaatDrager()],
            ),
          ),
        ),
      );
}

void main() {
  tearDown(() {
    AppTheme.isDark = false;
    _StaatDragerState.aanmaak = 0;
  });

  Color kleurVanBlad(WidgetTester tester) => tester
      .widget<ColoredBox>(
        find.descendant(
          of: find.byType(_LosgekoppeldBlad),
          matching: find.byType(ColoredBox),
        ),
      )
      .color;

  /// Wisselt de modus zoals de gebruiker dat doet, en pompt het extra frame
  /// waarin de markering (een post-frame callback) zijn werk doet.
  Future<void> wissel(
    WidgetTester tester,
    ValueNotifier<AppAppearanceProfile> profiel,
    AppAppearanceProfile naar,
  ) async {
    profiel.value = naar;
    await tester.pump();
    await tester.pump();
  }

  testWidgets('de vlag staat goed vóór het eerste frame bouwt', (tester) async {
    final profiel = ValueNotifier(AppAppearanceProfile.dark);
    addTearDown(profiel.dispose);
    await tester.pumpWidget(_App(profiel));

    expect(AppTheme.isDark, isTrue);
    // Het blad las de vlag tijdens dat eerste frame; had de scope hem pas in
    // zijn `build` gezet, dan stond hier de lichte kleur.
    expect(kleurVanBlad(tester), AppTheme.paper);
  });

  testWidgets('een losgekoppeld blad herkleurt na een moduswisseling', (
    tester,
  ) async {
    final profiel = ValueNotifier(AppAppearanceProfile.dark);
    addTearDown(profiel.dispose);
    await tester.pumpWidget(_App(profiel));
    final donker = kleurVanBlad(tester);

    await wissel(tester, profiel, AppAppearanceProfile.europa);

    expect(
      kleurVanBlad(tester),
      isNot(donker),
      reason:
          'Dit is de hele bug van #814. Zonder de markering herbouwt dit blad '
          'niet — het hangt van niets af en zit achter een const kind — en '
          'blijft de kleur van het vorige thema staan.',
    );
    expect(kleurVanBlad(tester), AppTheme.paper);
  });

  testWidgets('de moduswisseling gooit geen State weg', (tester) async {
    final profiel = ValueNotifier(AppAppearanceProfile.dark);
    addTearDown(profiel.dispose);
    await tester.pumpWidget(_App(profiel));
    final eerste = tester.state<_StaatDragerState>(find.byType(_StaatDrager));
    final rondesVoor = eerste.bouwrondes;

    await wissel(tester, profiel, AppAppearanceProfile.europa);

    expect(
      tester.state<_StaatDragerState>(find.byType(_StaatDrager)),
      same(eerste),
      reason:
          'Dezelfde State moet blijven staan. Werd hij opnieuw aangemaakt, dan '
          'is de boom weggegooid in plaats van gemarkeerd — en dan neemt deze '
          'reparatie het niet-opgeslagen deck mee, zoals in #780 gebeurde.',
    );
    expect(
      _StaatDragerState.aanmaak,
      1,
      reason: 'één keer aangemaakt, niet twee',
    );
    expect(
      eerste.bouwrondes,
      greaterThan(rondesVoor),
      reason: 'hij moet wél opnieuw gebouwd hebben — daar gaat het om',
    );
  });

  testWidgets('een kleurwijziging binnen dezelfde modus herbouwt niets', (
    tester,
  ) async {
    // Die kleuren lopen via ThemeData en propageren zelf. De hele boom ervoor
    // herbouwen is verspilling, en bij elke tik op een kleurenkiezer merkbare
    // verspilling.
    final profiel = ValueNotifier(AppAppearanceProfile.europa);
    addTearDown(profiel.dispose);
    await tester.pumpWidget(_App(profiel));
    final drager = tester.state<_StaatDragerState>(find.byType(_StaatDrager));
    final rondesVoor = drager.bouwrondes;

    await wissel(
      tester,
      profiel,
      AppAppearanceProfile.europa.copyWith(primaryColor: '#123456'),
    );

    expect(
      drager.bouwrondes,
      rondesVoor,
      reason:
          'de markering hangt aan de modus, niet aan het profiel — anders '
          'herbouwt de hele boom bij elke kleurtik',
    );
  });

  testWidgets('markAppearanceSubtreeDirty raakt de hele diepte', (
    tester,
  ) async {
    // De functie apart, zonder de scope eromheen: hij moet tot in het diepste
    // blad komen en niet bij de eerste laag stoppen.
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(children: [_LosgekoppeldBlad(), _StaatDrager()]),
      ),
    );
    final drager = tester.state<_StaatDragerState>(find.byType(_StaatDrager));
    final rondesVoor = drager.bouwrondes;

    markAppearanceSubtreeDirty(tester.element(find.byType(MaterialApp)));
    await tester.pump();

    expect(drager.bouwrondes, greaterThan(rondesVoor));
  });
}
