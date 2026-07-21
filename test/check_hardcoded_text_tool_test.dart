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

  test('een letterlijke Text() is een overtreding', () {
    write('a.dart', "Widget b() => Text('Opslaan');\n");
    expect(scan(), contains('Opslaan'));
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
    expect(isVisibleText('Opslaan'), isTrue);
    expect(isVisibleText(' min'), isTrue);
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
}
