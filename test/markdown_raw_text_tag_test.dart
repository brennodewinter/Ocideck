import 'package:flutter_test/flutter_test.dart';

import '../tool/check_conventions.dart';

/// Het meetinstrument achter de rauwe-teksttagregel in
/// `tool/check_conventions.dart` (`rawTextTagsIn`, #2612).
///
/// Een losse `<title>` in lopende tekst liet Forgejo de hele rest van
/// USER_GUIDE en ACCESSIBILITY inslikken: de browser leest alles tot
/// `</title>` als titeltekst. Binnen code is dezelfde tag onschuldig, dus de
/// regel moet code overslaan, en dat is wat hieronder met verzonnen bestanden
/// wordt getoetst.
void main() {
  List<int> meet(String source) =>
      rawTextTagsIn({'docs/X.md': source})['docs/X.md'] ?? const <int>[];

  test('een plaatshouder <title> in lopende tekst wordt gevonden', () {
    // De echte zin uit USER_GUIDE vóór #2612.
    expect(meet('(*Stijl van\n<title>* by default, the title being\n'), [2]);
  });

  test('ook midden in een regel en in andere vormen', () {
    expect(meet('"Slide 3/12: <title>", plus\n'), [1]);
    expect(meet('a <SCRIPT src="x"> b\n'), [1]);
    expect(meet('a <style>\n'), [1]);
  });

  test('tussen backticks is het code', () {
    expect(meet('*Stijl van `<title>`* by default\n'), isEmpty);
    expect(meet('the ``<title>`` tag\n'), isEmpty);
  });

  test('een geëscapete < is gewone tekst', () {
    expect(
      meet(
        r'Stijl van \<title>'
        '\n',
      ),
      isEmpty,
    );
  });

  test('binnen een codeblok telt het niet, erna weer wel', () {
    expect(
      meet(
        '```\n'
        '<title>.ocideck   (zip)\n'
        '```\n'
        'na het blok <title>\n',
      ),
      [4],
    );
  });

  test('een binnenhek met infotekst sluit het buitenblok niet', () {
    expect(
      meet(
        '````markdown\n'
        '```html\n'
        '<title>x</title>\n'
        '```\n'
        '````\n',
      ),
      isEmpty,
    );
  });

  test('een tag die op title lijkt is geen title', () {
    expect(meet('standaard *Stijl van <titel>*\n'), isEmpty);
    expect(meet('the <titlebar> widget\n'), isEmpty);
  });
}
