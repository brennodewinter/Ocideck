// De brug houdt een formulierblok bij elkaar (FORM_INTAKE.md §4.9, rij 8).
//
// Een veld heeft vaak zelf een kop als label. Zonder de formulier-tak knipt de
// kopsplitsing het label van zijn antwoord, en de scanner leest een antwoord
// zonder de vraag. Eén dia per blok is de eenheid waarop de projectie werkt.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/document_deck_bridge.dart';

void main() {
  const formulier =
      '<!-- form id=f version=1 -->\n'
      '\n'
      '# Aanmelding\n'
      '\n'
      '<!-- notice -->\n'
      'Wordt bewaard.\n'
      '<!-- /notice -->\n'
      '\n'
      '<!-- field id=verhaal type=prose -->\n'
      '## Het verhaal\n'
      '> uitleg\n'
      '<!-- answer -->\n'
      '## kop in een antwoord\n'
      '\n'
      'Tekst van het antwoord.\n'
      '<!-- /field id=verhaal -->\n'
      '\n'
      '<!-- field id=naam type=text -->\n'
      '**Naam**\n'
      '<!-- answer -->\n'
      'Sari\n'
      '<!-- /field id=naam -->\n'
      '\n'
      'Tot slot.\n';

  test('een veld met koppen erin wordt één dia', () {
    final deck = DocumentDeckBridge.documentToDeck(formulier);
    final verhaal = deck.slides.where(
      (s) => s.customMarkdown.contains('Het verhaal'),
    );

    expect(verhaal, hasLength(1));
    final body = verhaal.single.customMarkdown;
    // Label, antwoord én beide markers zitten in dezelfde dia.
    expect(body, startsWith('<!-- field id=verhaal type=prose -->'));
    expect(body, contains('kop in een antwoord'));
    expect(body, contains('Tekst van het antwoord.'));
    expect(body, endsWith('<!-- /field id=verhaal -->'));
    // En het volgende veld hoort er niet bij.
    expect(body, isNot(contains('Sari')));
    expect(verhaal.single.type, SlideType.freeMarkdown);
  });

  test('kop, notice en elk veld zijn elk een eigen dia', () {
    final deck = DocumentDeckBridge.documentToDeck(formulier);
    expect(deck.slides.map((s) => s.customMarkdown.split('\n').first), [
      '<!-- form id=f version=1 -->',
      '# Aanmelding',
      '<!-- notice -->',
      '<!-- field id=verhaal type=prose -->',
      '<!-- field id=naam type=text -->',
      'Tot slot.',
    ]);
  });

  test('de rondgang is byte-getrouw', () {
    final deck = DocumentDeckBridge.documentToDeck(formulier);
    expect(DocumentDeckBridge.deckToDocumentMarkdown(deck), formulier);
  });

  test(
    'een blok dat midden in een ander blok binnenkomt wordt niet verdubbeld',
    () {
      // Een bevinding eindigt op de eerstvolgende kop van gelijk of hoger niveau —
      // hier de `##` in het label van een veld, dus midden in dat veld. Zonder de
      // controle op het begin van het blok zou de brug het héle veld nog eens
      // als dia wegschrijven, mét de regels die de bevinding al had.
      const gemengd =
          '<!-- form id=f -->\n'
          '\n'
          '<!-- finding -->\n'
          '### F-01 · X\n'
          '\n'
          'tekst\n'
          '\n'
          '<!-- field id=a type=text -->\n'
          '## Het label\n'
          '<!-- answer -->\n'
          'UNIEKANTWOORD\n'
          '<!-- /field id=a -->\n';
      final deck = DocumentDeckBridge.documentToDeck(gemengd);
      final terug = DocumentDeckBridge.deckToDocumentMarkdown(deck);
      for (final regel in ['<!-- field id=a', 'UNIEKANTWOORD', '/field id=a']) {
        expect(
          regel.allMatches(terug),
          hasLength(1),
          reason: '"$regel" komt niet precies één keer terug',
        );
      }
    },
  );

  test('een kapot formulier blijft gewone tekst — niets wordt weggeknipt', () {
    const kapot =
        '<!-- field id=naam type=text -->\n'
        '**Naam**\n'
        '<!-- answer -->\n'
        'Sari\n';
    final deck = DocumentDeckBridge.documentToDeck(kapot);
    expect(DocumentDeckBridge.deckToDocumentMarkdown(deck), kapot);
  });
}
