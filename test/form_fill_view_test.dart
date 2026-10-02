// De invulpagina van een formulier: wat er staat, wat een antwoord met het
// document doet, en wat er gebeurt als dat antwoord niet mag (FORM_INTAKE.md §8).
//
// De pagina krijgt de tekst van het document en meldt elke wijziging als een nieuwe
// tekst; de testgastheer speelt het document, zoals het tabblad dat doet.

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/widgets/forms/form_field_card.dart';
import 'package:ocideck/widgets/markdown_editor/markdown_editor_theme.dart';
import 'package:ocideck/widgets/forms/form_fill_view.dart';

const String formulier = '''<!-- form id=kookboek version=2 -->
# Inzending Kookboek

Kook je graag? Dit kost zo'n 45 minuten.

<!-- notice -->
UNIEKNOTICE we bewaren je gegevens.
<!-- /notice -->

## A. Jij

<!-- field id=naam type=text required max-chars=20 -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->

<!-- field id=akkoord type=consent required -->
Ik ga akkoord met publicatie.
<!-- answer -->
- [ ]
<!-- /field id=akkoord -->

## B. Het recept

<!-- field id=verhaal type=prose required words=3..6 -->
**Het verhaal**
<!-- answer -->
<!-- /field id=verhaal -->
''';

const String soorten = '''<!-- form id=soorten version=1 -->
<!-- field id=keuze type=choice options="Makkelijk|Gemiddeld" other -->
**Moeilijkheid**
<!-- answer -->
<!-- /field id=keuze -->

<!-- field id=meer type=multichoice options="Vegan|Halal" -->
**Dieet**
<!-- answer -->
<!-- /field id=meer -->

<!-- field id=lijst type=list ordered items=1..3 -->
**Ingrediënten**
<!-- answer -->
<!-- /field id=lijst -->

<!-- field id=tabel type=table columns="Naam|Hoeveelheid" -->
**Tabel**
<!-- answer -->
<!-- /field id=tabel -->

<!-- field id=datum type=date -->
**Datum**
<!-- answer -->
<!-- /field id=datum -->

<!-- field id=getal type=number min=1 max=9 -->
**Getal**
<!-- answer -->
<!-- /field id=getal -->
''';

/// Speelt het document: houdt de tekst bij en geeft hem terug aan de pagina.
class _Host extends StatefulWidget {
  const _Host(this.initial, {super.key, required this.log, this.onShowSource});

  final String initial;
  final List<String> log;
  final VoidCallback? onShowSource;

  @override
  State<_Host> createState() => FillHostState();
}

class FillHostState extends State<_Host> {
  late String body = widget.initial;

  void replace(String text) => setState(() => body = text);

  @override
  Widget build(BuildContext context) => FormFillView(
    body: body,
    onChanged: (text, fieldId) {
      widget.log.add(fieldId);
      setState(() => body = text);
    },
    onShowSource: widget.onShowSource,
  );
}

Future<GlobalKey<FillHostState>> pumpFill(
  WidgetTester tester,
  String text, {
  List<String>? log,
  VoidCallback? onShowSource,
}) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final key = GlobalKey<FillHostState>();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('nl'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: _Host(text, key: key, log: log ?? [], onShowSource: onShowSource),
      ),
    ),
  );
  await tester.pump();
  return key;
}

String bodyOf(GlobalKey<FillHostState> key) => key.currentState!.body;

void main() {
  group('de pagina', () {
    testWidgets(
      'toont titel, inleiding, notice, koppen en labels — geen marker',
      (tester) async {
        await pumpFill(tester, formulier);
        for (final tekst in [
          'Inzending Kookboek',
          'Kook je graag?',
          'UNIEKNOTICE',
          'A. Jij',
          'B. Het recept',
          'Naam',
          'Ik ga akkoord met publicatie.',
          'Het verhaal',
        ]) {
          expect(find.textContaining(tekst, findRichText: true), findsWidgets);
        }
        for (final marker in ['<!--', '-->', 'field id', 'answer']) {
          expect(
            find.textContaining(marker, findRichText: true),
            findsNothing,
            reason: '"$marker" lekt als tekst',
          );
        }
      },
    );

    testWidgets(
      'de samenvatting telt wat er openstaat, per sectie en in totaal',
      (tester) async {
        await pumpFill(tester, formulier);
        expect(
          find.text('Nog 3 te doen voordat je kunt versturen:'),
          findsOneWidget,
        );
        expect(find.text('2 open'), findsOneWidget);
        expect(find.text('1 open'), findsOneWidget);
      },
    );

    testWidgets(
      'een leeg verplicht veld is nog niet rood voor het is aangeraakt',
      (tester) async {
        await pumpFill(tester, formulier);
        expect(
          find.textContaining('Dit veld is verplicht'),
          findsNothing,
          reason: 'een formulier dat schreeuwt zodra het opent',
        );
      },
    );

    testWidgets('alleen verplichte velden dragen het woord Verplicht', (
      tester,
    ) async {
      // Twee verplichte velden met een gewoon label; het toestemmingsveld heeft
      // geen aparte labelregel en zijn vakje is zelf al de eis.
      await pumpFill(tester, formulier);
      expect(find.text('Verplicht'), findsNWidgets(2));
    });

    testWidgets('een veld zonder eis draagt het niet', (tester) async {
      await pumpFill(tester, soorten);
      expect(find.text('Verplicht'), findsNothing);
    });

    testWidgets(
      'het label van een toestemming staat bij het vakje, niet erboven',
      (tester) async {
        await pumpFill(tester, formulier);
        final label = find.textContaining(
          'Ik ga akkoord met publicatie.',
          findRichText: true,
        );
        // In de kaart van het veld één keer, naast het vakje; de samenvatting
        // bovenaan noemt het veld ook, maar dat is een andere plek.
        expect(
          find.descendant(of: find.byType(FormFieldCard), matching: label),
          findsOneWidget,
        );
        expect(
          find.descendant(of: find.byType(CheckboxListTile), matching: label),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'wie een verplicht veld invult en weer leegmaakt krijgt de eis te zien',
      (tester) async {
        await pumpFill(tester, formulier);
        await tester.enterText(find.byType(TextField).first, 'Sari');
        await tester.pump();
        expect(find.textContaining('Dit veld is verplicht'), findsNothing);
        await tester.enterText(find.byType(TextField).first, '');
        await tester.pump();
        expect(find.textContaining('Dit veld is verplicht'), findsOneWidget);
      },
    );

    testWidgets('een kop zonder velden draagt geen status', (tester) async {
      await pumpFill(
        tester,
        '<!-- form id=f -->\n## Alleen uitleg\n\nTekst.\n'
        '## Met veld\n<!-- field id=a type=text -->\nL\n<!-- answer -->\n<!-- /field id=a -->\n',
      );
      expect(find.text('Alleen uitleg'), findsOneWidget);
      // De ene kop met een veld heeft er één; de kop zonder velden niet.
      expect(find.text('klaar'), findsOneWidget);
    });

    testWidgets('een sprong uit de samenvatting toont de eis bij het veld', (
      tester,
    ) async {
      await pumpFill(tester, formulier);
      await tester.tap(find.widgetWithText(TextButton, 'Naam'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Dit veld is verplicht'), findsOneWidget);
    });

    testWidgets(
      'een kapot formulier zegt dat het niet kan, en wijst naar de bron',
      (tester) async {
        var naarBron = 0;
        await pumpFill(
          tester,
          '<!-- form id=f -->\n<!-- field id=a type=text -->\nL\n',
          onShowSource: () => naarBron++,
        );
        expect(
          find.text('Dit formulier kan niet worden ingevuld.'),
          findsOneWidget,
        );
        expect(find.textContaining('Er is per ongeluk iets'), findsOneWidget);
        await tester.tap(find.text('Naar de bron'));
        expect(naarBron, 1);
      },
    );
  });

  group('een antwoord', () {
    testWidgets('verandert alleen de bytes van zijn zone', (tester) async {
      final log = <String>[];
      final host = await pumpFill(tester, formulier, log: log);
      await tester.enterText(find.byType(TextField).first, 'Sari');
      await tester.pump();
      expect(
        bodyOf(host),
        formulier.replaceFirst(
          '<!-- answer -->\n<!-- /field id=naam -->',
          '<!-- answer -->\nSari\n<!-- /field id=naam -->',
        ),
      );
      expect(log, ['naam']);
    });

    testWidgets('sluit het veld in de samenvatting en in zijn sectie', (
      tester,
    ) async {
      await pumpFill(tester, formulier);
      await tester.enterText(find.byType(TextField).first, 'Sari');
      await tester.pump();
      expect(
        find.text('Nog 2 te doen voordat je kunt versturen:'),
        findsOneWidget,
      );
      expect(find.text('1 open'), findsNWidgets(2));
    });

    testWidgets('een overtreding verschijnt bij het veld, in woorden', (
      tester,
    ) async {
      await pumpFill(tester, formulier);
      await tester.enterText(
        find.byType(TextField).first,
        'een veel te lange naam voor dit veld',
      );
      await tester.pump();
      expect(
        find.textContaining('Je hebt 36 tekens geschreven'),
        findsOneWidget,
      );
    });

    testWidgets('de teller loopt mee met het typen', (tester) async {
      await pumpFill(tester, formulier);
      expect(find.textContaining('Woorden: 0'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'een twee drie');
      await tester.pump();
      expect(find.text('Woorden: 3 (minimaal 3, maximaal 6)'), findsOneWidget);
    });

    testWidgets('het toestemmingsvakje zet een kruis in het document', (
      tester,
    ) async {
      final host = await pumpFill(tester, formulier);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(
        bodyOf(host),
        contains('<!-- answer -->\n- [x]\n<!-- /field id=akkoord -->'),
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(
        bodyOf(host),
        contains('<!-- answer -->\n- [ ]\n<!-- /field id=akkoord -->'),
      );
    });

    testWidgets(
      'een regel die het formulier zou breken wordt geweigerd, de tekst blijft',
      (tester) async {
        final host = await pumpFill(tester, formulier);
        const kwaad = '<!-- /field id=verhaal -->';
        await tester.enterText(find.byType(TextField).last, kwaad);
        await tester.pump();
        expect(bodyOf(host), formulier, reason: 'het document is onaangetast');
        expect(
          find.textContaining('lijkt op een besturingscode'),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(TextField, kwaad),
          findsOneWidget,
          reason: 'de invuller verliest zijn tekst niet',
        );
      },
    );

    testWidgets(
      'herstelt de invuller de tekst, dan gaat hij weer in het document',
      (tester) async {
        final host = await pumpFill(tester, formulier);
        await tester.enterText(
          find.byType(TextField).last,
          '<!-- /field id=verhaal -->',
        );
        await tester.pump();
        await tester.enterText(find.byType(TextField).last, 'een twee drie');
        await tester.pump();
        expect(bodyOf(host), contains('een twee drie'));
        expect(
          find.textContaining('lijkt op een besturingscode'),
          findsNothing,
        );
      },
    );
  });

  group('een wijziging van buitenaf', () {
    testWidgets('ongedaan maken zet het veld terug', (tester) async {
      final host = await pumpFill(tester, formulier);
      await tester.enterText(find.byType(TextField).first, 'Sari');
      await tester.pump();
      host.currentState!.replace(formulier);
      await tester.pump();
      expect(find.widgetWithText(TextField, 'Sari'), findsNothing);
      expect(
        find.text('Nog 3 te doen voordat je kunt versturen:'),
        findsOneWidget,
      );
    });

    testWidgets('een eigen spatie wordt niet onder de vingers weggehaald', (
      tester,
    ) async {
      await pumpFill(tester, formulier);
      await tester.enterText(find.byType(TextField).first, 'Sari ');
      await tester.pump();
      // Het document kent "Sari"; het veld houdt wat de invuller typte.
      expect(find.widgetWithText(TextField, 'Sari '), findsOneWidget);
    });
  });

  group('de veldtypen', () {
    testWidgets('een keuze zet de gekozen optie in het document', (
      tester,
    ) async {
      final host = await pumpFill(tester, soorten);
      await tester.tap(find.text('Gemiddeld'));
      await tester.pump();
      expect(
        bodyOf(host),
        contains('<!-- answer -->\nGemiddeld\n<!-- /field id=keuze -->'),
      );
    });

    testWidgets('"anders" neemt de eigen tekst op', (tester) async {
      final host = await pumpFill(tester, soorten);
      await tester.tap(find.text('Anders, namelijk:').first);
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'Expert');
      await tester.pump();
      expect(
        bodyOf(host),
        contains('<!-- answer -->\nExpert\n<!-- /field id=keuze -->'),
      );
    });

    testWidgets('meerdere keuzes staan als takenlijst', (tester) async {
      final host = await pumpFill(tester, soorten);
      await tester.tap(find.text('Halal'));
      await tester.pump();
      expect(bodyOf(host), contains('- [ ] Vegan\n- [x] Halal\n'));
    });

    testWidgets('een lijst groeit en nummert', (tester) async {
      final host = await pumpFill(tester, soorten);
      await tester.tap(find.text('Punt toevoegen'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(1), 'bloem');
      await tester.pump();
      await tester.tap(find.text('Punt toevoegen'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(2), 'eieren');
      await tester.pump();
      expect(bodyOf(host), contains('1. bloem\n2. eieren\n'));
      expect(find.text('Punten: 2 (minimaal 1, maximaal 3)'), findsOneWidget);
      await tester.tap(find.byTooltip('Punt 1 verwijderen'));
      await tester.pump();
      expect(bodyOf(host), contains('1. eieren\n'));
      expect(bodyOf(host), isNot(contains('bloem')));
    });

    testWidgets('een tabel krijgt een rij en schrijft een pijptabel', (
      tester,
    ) async {
      final host = await pumpFill(tester, soorten);
      await tester.tap(find.text('Rij toevoegen'));
      await tester.pump();
      // Velden op de pagina: het keuzeveld "anders" (0), dan de twee cellen van
      // de nieuwe rij (1, 2), dan de datum en het getal.
      final velden = find.byType(TextField);
      await tester.enterText(velden.at(1), 'bloem');
      await tester.enterText(velden.at(2), '200 g');
      await tester.pump();
      expect(
        bodyOf(host),
        contains('| Naam | Hoeveelheid |\n| --- | --- |\n| bloem | 200 g |\n'),
      );
    });

    testWidgets('een slechte datum krijgt een zin met een voorbeeld', (
      tester,
    ) async {
      await pumpFill(tester, soorten);
      final velden = find.byType(TextField);
      await tester.enterText(velden.at(velden.evaluate().length - 2), 'morgen');
      await tester.pump();
      expect(find.textContaining('is geen datum'), findsOneWidget);
    });

    testWidgets('een getal buiten de grenzen krijgt zijn grenzen', (
      tester,
    ) async {
      await pumpFill(tester, soorten);
      final velden = find.byType(TextField);
      await tester.enterText(velden.at(velden.evaluate().length - 1), '12');
      await tester.pump();
      expect(find.text('Het getal moet tussen 1 en 9 liggen.'), findsOneWidget);
    });
  });

  group('de veldtypen, de randen', () {
    const keuze =
        '<!-- form id=f -->\n'
        '<!-- field id=k type=choice options="Makkelijk|Gemiddeld" other -->\n'
        '**K**\n'
        '<!-- answer -->\n'
        '%ANTWOORD%'
        '<!-- /field id=k -->\n';

    String metAntwoord(String antwoord) =>
        keuze.replaceFirst('%ANTWOORD%', antwoord);

    testWidgets('een eigen antwoord in het document staat bij "anders"', (
      tester,
    ) async {
      await pumpFill(tester, metAntwoord('Expert\n'));
      expect(find.widgetWithText(TextField, 'Expert'), findsOneWidget);
      final radio = tester.widget<RadioGroup<String>>(
        find.byType(RadioGroup<String>),
      );
      expect(radio.groupValue, isNotNull);
      expect(radio.groupValue, isNot('Makkelijk'));
      expect(radio.groupValue, isNot('Gemiddeld'));
    });

    testWidgets('een optie in het document haalt "anders" weg', (tester) async {
      final host = await pumpFill(tester, metAntwoord('Expert\n'));
      host.currentState!.replace(metAntwoord('Makkelijk\n'));
      await tester.pump();
      final radio = tester.widget<RadioGroup<String>>(
        find.byType(RadioGroup<String>),
      );
      expect(radio.groupValue, 'Makkelijk');
    });

    testWidgets('een eigen antwoord van buitenaf komt in het veld te staan', (
      tester,
    ) async {
      final host = await pumpFill(tester, metAntwoord('Makkelijk\n'));
      host.currentState!.replace(metAntwoord('Anders dan jullie\n'));
      await tester.pump();
      expect(
        find.widgetWithText(TextField, 'Anders dan jullie'),
        findsOneWidget,
      );
      final radio = tester.widget<RadioGroup<String>>(
        find.byType(RadioGroup<String>),
      );
      expect(radio.groupValue, isNotNull, reason: '"anders" is gekozen');
    });

    const meer =
        '<!-- form id=f -->\n'
        '<!-- field id=m type=multichoice options="Vegan|Halal" other -->\n'
        '**M**\n'
        '<!-- answer -->\n'
        '<!-- /field id=m -->\n';

    testWidgets('een eigen keuze komt achter de aangevinkte opties', (
      tester,
    ) async {
      final host = await pumpFill(tester, meer);
      await tester.tap(find.text('Halal'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'Koosjer');
      await tester.pump();
      expect(
        bodyOf(host),
        contains('- [ ] Vegan\n- [x] Halal\n- [x] Koosjer\n'),
      );
    });

    testWidgets('een eigen keuze van alleen spaties telt niet mee', (
      tester,
    ) async {
      await pumpFill(tester, meer.replaceFirst('other', 'other count=1..2'));
      await tester.enterText(find.byType(TextField).first, '   ');
      await tester.pump();
      expect(find.text('Keuzes: 0 (minimaal 1, maximaal 2)'), findsOneWidget);
    });

    testWidgets('een leeg gemaakte eigen keuze verdwijnt weer', (tester) async {
      final host = await pumpFill(tester, meer);
      await tester.enterText(find.byType(TextField).first, 'Koosjer');
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, '  ');
      await tester.pump();
      expect(bodyOf(host), isNot(contains('Koosjer')));
      expect(bodyOf(host), contains('- [ ] Vegan\n- [ ] Halal\n'));
    });

    const lijst =
        '<!-- form id=f -->\n'
        '<!-- field id=l type=list %ORDERED% -->\n'
        '**L**\n'
        '<!-- answer -->\n'
        '- een\n- twee\n- drie\n'
        '<!-- /field id=l -->\n';

    testWidgets('een punt verwijderen haalt dat punt weg, geen ander', (
      tester,
    ) async {
      final host = await pumpFill(tester, lijst.replaceFirst('%ORDERED%', ''));
      await tester.tap(find.byTooltip('Punt 2 verwijderen'));
      await tester.pump();
      expect(bodyOf(host), contains('- een\n- drie\n'));
      expect(bodyOf(host), isNot(contains('twee')));
    });

    testWidgets('een genummerde lijst toont nummers, een gewone bolletjes', (
      tester,
    ) async {
      await pumpFill(tester, lijst.replaceFirst('%ORDERED%', 'ordered'));
      expect(find.text('1.'), findsOneWidget);
      expect(find.text('3.'), findsOneWidget);
      expect(find.text('•'), findsNothing);
    });

    testWidgets('een gewone lijst toont bolletjes', (tester) async {
      await pumpFill(tester, lijst.replaceFirst('%ORDERED%', ''));
      expect(find.text('•'), findsNWidgets(3));
      expect(find.text('1.'), findsNothing);
    });

    testWidgets('een rij verwijderen haalt die rij weg, geen andere', (
      tester,
    ) async {
      const tabel =
          '<!-- form id=f -->\n'
          '<!-- field id=t type=table columns="A|B" -->\n'
          '**T**\n'
          '<!-- answer -->\n'
          '| A | B |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |\n| 5 | 6 |\n'
          '<!-- /field id=t -->\n';
      final host = await pumpFill(tester, tabel);
      await tester.tap(find.byTooltip('Rij 2 verwijderen'));
      await tester.pump();
      expect(bodyOf(host), contains('| 1 | 2 |\n| 5 | 6 |\n'));
      expect(bodyOf(host), isNot(contains('| 3 | 4 |')));
    });
  });

  group('wanneer iets rood is', () {
    Color? kleurVan(WidgetTester tester, String tekst) =>
        tester.widget<Text>(find.text(tekst)).style?.color;

    testWidgets(
      'een toestemming die nog niet is gegeven staat er niet bij het openen',
      (tester) async {
        await pumpFill(tester, formulier);
        expect(find.textContaining('Zet het vinkje'), findsNothing);
      },
    );

    testWidgets('wie het vakje aanvinkt en weer uitzet krijgt de eis te zien', (
      tester,
    ) async {
      await pumpFill(tester, formulier);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(find.textContaining('Zet het vinkje'), findsOneWidget);
    });

    testWidgets(
      'een teller die nog niet aan zijn minimum toe is blijft rustig',
      (tester) async {
        await pumpFill(tester, formulier);
        const tekst = 'Woorden: 0 (minimaal 3, maximaal 6)';
        final scheme = Theme.of(tester.element(find.text(tekst))).colorScheme;
        expect(kleurVan(tester, tekst), scheme.onSurfaceVariant);
      },
    );

    testWidgets('dezelfde teller wordt rood nadat het veld is aangeraakt', (
      tester,
    ) async {
      await pumpFill(tester, formulier);
      await tester.enterText(find.byType(TextField).last, 'een');
      await tester.pump();
      const tekst = 'Woorden: 1 (minimaal 3, maximaal 6)';
      final scheme = Theme.of(tester.element(find.text(tekst))).colorScheme;
      expect(kleurVan(tester, tekst), scheme.error);
    });

    testWidgets('een teller boven zijn maximum is meteen rood', (tester) async {
      await pumpFill(
        tester,
        formulier.replaceFirst(
          '<!-- answer -->\n<!-- /field id=verhaal -->',
          '<!-- answer -->\neen twee drie vier vijf zes zeven\n<!-- /field id=verhaal -->',
        ),
      );
      const tekst = 'Woorden: 7 (minimaal 3, maximaal 6)';
      final scheme = Theme.of(tester.element(find.text(tekst))).colorScheme;
      expect(kleurVan(tester, tekst), scheme.error);
    });
  });

  group('de stijl van het document', () {
    testWidgets(
      'zonder stijl is het papier de oppervlaktekleur van het thema',
      (tester) async {
        await pumpFill(tester, formulier);
        final buitenste = tester.widget<ColoredBox>(
          find
              .descendant(
                of: find.byType(FormFillView),
                matching: find.byType(ColoredBox),
              )
              .first,
        );
        final scheme = Theme.of(
          tester.element(find.byType(FormFillView)),
        ).colorScheme;
        expect(buitenste.color, scheme.surface);
        expect(buitenste.color, isNot(const Color(0xFFFFF3D6)));
      },
    );

    testWidgets('het papier en de inkt van de stijl gaan ook voor de invoer', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const stijl = ThemeProfile(
        name: 'Crème',
        slideBackgroundColor: '#FFF3D6',
        textColor: '#1A2B3C',
      );
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('nl'),
          // Een donkere app met een lichte documentstijl: de inkt moet de stijl
          // volgen, anders staat er lichte tekst op crème papier.
          theme: ThemeData(brightness: Brightness.dark),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DocumentStyleScope(
              profile: stijl,
              child: FormFillView(body: formulier, onChanged: (_, _) {}),
            ),
          ),
        ),
      );
      await tester.pump();
      // De buitenste ondergrond van de pagina zelf — niet die van een Markdown-
      // blok erin, die hetzelfde papier tekent en dit zou verbergen.
      final buitenste = tester.widget<ColoredBox>(
        find
            .descendant(
              of: find.byType(FormFillView),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(buitenste.color, const Color(0xFFFFF3D6));
      final titel = tester.widget<Text>(find.text('Inzending Kookboek'));
      expect(titel.style?.color, const Color(0xFF1A2B3C));
    });
  });
}
