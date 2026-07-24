// De poort tegen hardgecodeerde zichtbare tekst (tool/check_hardcoded_text.dart)
// op een kleine fixture, zodat vaststaat DAT hij het doorgeefluik ziet.
//
// Waarom dit test-bestand er is. De poort meet met een AST-analyse en landt op
// één getal. Valt die analyse stil — een analyzer-upgrade die een accessor
// verschuift, een refactor die de bezoeker sloopt — dan meldt hij nul, en nul
// LIJKT goed nieuws. De omgekeerde ratchet vangt dat in `make check` op (een
// daling zonder verlaagd plafond faalt), maar die vertelt niet waaróm. Deze
// tests wel: ze prikken precies op het gedrag dat de poort bestaansrecht geeft.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_hardcoded_text.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('hardcoded_text'));
  tearDown(() => root.deleteSync(recursive: true));

  void write(String name, String source) => File('${root.path}/$name')
    ..createSync()
    ..writeAsStringSync(source);

  Set<String> scan() =>
      scanForHardcodedText(root.path).map((v) => v.text).toSet();

  /// De echte overtredingen: tekst die het scherm bereikt zonder ooit door
  /// `d()` te gaan.
  Set<String> hardcoded() => {
    for (final v in scanForHardcodedText(root.path))
      if (!v.isSourceKey) v.text,
  };

  /// De bronsleutels: literals die via een doorgeefluik in `d()` landen.
  Set<String> sourceKeys() => sourceKeysIn(root.path);

  test('een letterlijke Text() is een overtreding', () {
    write('a.dart', "Widget b() => Text('Opslaan');\n");
    expect(scan(), contains('Opslaan'));
    expect(hardcoded(), contains('Opslaan'));
    expect(sourceKeys(), isEmpty);
  });

  test('dezelfde tekst binnen d() is juist de goede vorm', () {
    write('a.dart', "Widget b() => Text(l10n.d('Opslaan'));\n");
    expect(scan(), isEmpty);
  });

  test('een doorgeefluik via widget.<veld> wordt gevonden', () {
    // Dit is het gat waar de poort voor is gebouwd: `EditorField` vertaalt zijn
    // eigen label, dus de aanroepplaats draagt een onvertaalde bronstring die
    // een scanner op letterlijke `d('…')` nooit ziet.
    write('field.dart', '''
class EditorField extends StatefulWidget {
  final String label;
  const EditorField({required this.label});
  @override
  State<EditorField> createState() => _EditorFieldState();
}

class _EditorFieldState extends State<EditorField> {
  @override
  Widget build(BuildContext context) => Text(context.l10n.d(widget.label));
}
''');
    write('caller.dart', "Widget b() => EditorField(label: 'Titel (H1)');\n");
    expect(scan(), contains('Titel (H1)'));
    // ...maar als BRONSLEUTEL, niet als overtreding: het veld vertaalt hem
    // zelf, dus de literal staat waar hij hoort en moet enkel in alle talen
    // bestaan. De aanroepplaats herschrijven naar `l10n.d('Titel (H1)')` is
    // uitdrukkelijk niet de bedoeling.
    expect(sourceKeys(), contains('Titel (H1)'));
    expect(hardcoded(), isEmpty);
  });

  test('een doorgeefluik dat NIET vertaalt blijft een overtreding', () {
    // Hetzelfde vormgevingspatroon, maar zonder `d()` ertussen: de wizard van
    // de bevindingen deed dit en toonde zijn veldlabels in elke taal in het
    // Nederlands. Het TYPE van het doorgeefluik zegt dus niets — alleen of er
    // onderweg vertaald wordt.
    write('field.dart', '''
class RawField extends StatelessWidget {
  final String label;
  const RawField({required this.label});
  @override
  Widget build(BuildContext context) =>
      TextField(decoration: InputDecoration(labelText: label));
}
''');
    write('caller.dart', "Widget b() => RawField(label: 'Bevinding-id');\n");
    expect(hardcoded(), contains('Bevinding-id'));
    expect(sourceKeys(), isEmpty);
  });

  test('een tak zonder d() maakt het geheel een overtreding', () {
    // Eén weg localiseert, de andere niet. Dan toont het scherm hem soms rauw,
    // dus telt hij als overtreding — de voorzichtige kant van de twijfel.
    write('field.dart', '''
class HalfField extends StatelessWidget {
  final String label;
  const HalfField({required this.label});
  @override
  Widget build(BuildContext context) => Column(
    children: [Text(context.l10n.d(label)), Tooltip(message: label)],
  );
}
''');
    write('caller.dart', "Widget b() => HalfField(label: 'Half');\n");
    expect(hardcoded(), contains('Half'));
    expect(sourceKeys(), isEmpty);
  });

  test('een positioneel doorgeefluik wordt ook gevonden', () {
    write('label.dart', '''
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(context.l10n.d(text));
}
''');
    write('caller.dart', "Widget b() => const SectionLabel('Achtergrond');\n");
    expect(scan(), contains('Achtergrond'));
    expect(sourceKeys(), contains('Achtergrond'));
  });

  test('een tekst via een vrije functie naar Text() telt mee', () {
    // showErrorSnackBar-patroon: de parameter loopt door naar een Text().
    write('snack.dart', '''
void showError(String message) {
  messenger.showSnackBar(SnackBar(content: Text(message)));
}
''');
    write('caller.dart', "void go() => showError('Opslaan mislukt');\n");
    expect(scan(), contains('Opslaan mislukt'));
    expect(hardcoded(), contains('Opslaan mislukt'));
  });

  test('een titel op een datamodel is geen interfacetekst', () {
    // De ~1.000 `title:`-regels van de MASTG/WSTG-catalogi mogen niet meetellen:
    // het TYPE beslist, niet de parameternaam.
    write('catalog.dart', '''
class MastgTest {
  final String title;
  const MastgTest({required this.title});
}

const tests = [MastgTest(title: 'Testing Data Storage')];
''');
    expect(scan(), isEmpty);
  });

  test('een logregel is geen zichtbare tekst', () {
    write('a.dart', "void f() => logError('kon niet opslaan', e, st);\n");
    expect(scan(), isEmpty);
  });

  test('isVisibleText laat tekens zonder taal door de mazen vallen', () {
    expect(isVisibleText(''), isFalse);
    expect(isVisibleText('•'), isFalse);
    expect(isVisibleText('—'), isFalse);
    expect(isVisibleText('12'), isFalse);
    // × en ÷ vallen binnen het Latin-1-lettersblok van de regex maar zijn
    // rekentekens. Een scheidingsteken tussen twee vertaalde stukken is geen
    // tekst om te vertalen.
    expect(isVisibleText('  ·   × '), isFalse);
    expect(isVisibleText(' ÷ '), isFalse);
    expect(isVisibleText('Opslaan'), isTrue);
    expect(isVisibleText(' min'), isTrue);
    // Maar een × tússen woorden mag de tekst niet onzichtbaar maken.
    expect(isVisibleText('2 × per dag'), isTrue);
  });

  test('areaOf deelt in naar de gebieden waarin de opruiming gaat', () {
    expect(areaOf('lib/widgets/editors/title_editor.dart'), 'editors');
    expect(areaOf('lib/widgets/dialogs/export_dialog.dart'), 'dialogen');
    expect(areaOf('lib/widgets/panels/preview_panel.dart'), 'panelen');
    expect(areaOf('lib/services/slide_quality_analyzer.dart'), 'services');
  });

  test('de lijst noemt bestand, regel en de string', () {
    write('a.dart', "Widget b() => Text('Opslaan');\n");
    final rendered = renderList(scanForHardcodedText(root.path));
    expect(rendered, contains('a.dart'));
    expect(rendered, contains('Opslaan'));
    expect(rendered, contains('1:'));
  });

  test('de lijst scheidt overtredingen van bronsleutels', () {
    write('field.dart', '''
class EditorField extends StatefulWidget {
  final String label;
  const EditorField({required this.label});
  @override
  State<EditorField> createState() => _EditorFieldState();
}

class _EditorFieldState extends State<EditorField> {
  @override
  Widget build(BuildContext context) => Text(context.l10n.d(widget.label));
}
''');
    write('caller.dart', '''
Widget a() => Text('Rauw');
Widget b() => EditorField(label: 'Sleutel');
''');
    final rendered = renderList(scanForHardcodedText(root.path));
    final split = rendered.indexOf('BRONSLEUTELS');
    expect(split, greaterThan(0));
    expect(rendered.substring(0, split), contains('"Rauw"'));
    expect(rendered.substring(0, split), isNot(contains('"Sleutel"')));
    expect(rendered.substring(split), contains('"Sleutel"'));
  });

  group('een aanroep binnen een extension hoort bij de klasse eronder', () {
    // #803. Deze repo hakt grote widgets in `part of`-bestanden met elk een
    // extension op dezelfde state-klasse, om onder de bestandsgrensratchet te
    // blijven. De aanroep staat dan in `extension _Menu on _ShellState` terwijl
    // de declaratie in `_ShellState` zelf zit, en die twee sleutels kwamen nooit
    // bij elkaar. Gevolg: het achtervoegsel `(Ctrl/Cmd+K)` van het commandopalet
    // stond onvertaald in het ⋮-menu zonder dat de poort iets zei — en dezelfde
    // helper naar top-level tillen liet hem meteen wél opvallen. Dat de VORM van
    // de aanroeper besliste of er gekeken werd, is precies wat een poort niet
    // mag doen: dan groeit het patroon ongemerkt door.
    void writeShell(String body) => write('shell.dart', '''
class _ShellState extends State<Shell> {
  Widget _menuItem(String label) => $body;
}
''');

    test('een rauwe doorgifte is een overtreding', () {
      writeShell('Text(label)');
      write('menu.dart', '''
extension _Menu on _ShellState {
  Widget build() => _menuItem('Commandopalet  (Ctrl/Cmd+K)');
}
''');
      expect(hardcoded(), contains('Commandopalet  (Ctrl/Cmd+K)'));
    });

    test('en een vertalende doorgifte levert een bronsleutel', () {
      writeShell('Text(context.l10n.d(label))');
      write('menu.dart', '''
extension _Menu on _ShellState {
  Widget build() => _menuItem('Commandopalet');
}
''');
      expect(sourceKeys(), contains('Commandopalet'));
      expect(hardcoded(), isEmpty);
    });
  });
}
