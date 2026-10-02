// De voorbeeldformulieren in `examples/forms/`: wie OciDeck wil uitproberen opent er
// een. Ze horen bruikbaar te blijven — een voorbeeld dat stilletjes kapot gaat is
// erger dan geen — en de talen horen dezelfde regels te hebben (FORM_INTAKE.md §4.8:
// de per-taal-sjablonen van één versie delen hun regels).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:path/path.dart' as p;

const List<String> kLanguages = ['nl', 'en'];

String read(String lang) =>
    File(p.join('examples', 'forms', 'recept.$lang.md')).readAsStringSync();

FormSpec specOf(String lang) {
  final parsed = parseForm(read(lang));
  expect(parsed, isA<ParsedForm>(), reason: lang);
  return (parsed as ParsedForm).spec;
}

void main() {
  for (final lang in kLanguages) {
    group('recept.$lang.md', () {
      test('is een formulier zonder fouten of waarschuwingen', () {
        final parsed = parseForm(read(lang)) as ParsedForm;
        expect(parsed.canFill, isTrue);
        expect(parsed.notes, isEmpty, reason: '${parsed.notes}');
        expect(parsed.spec.lang, lang);
      });

      test('kent een notice, een verantwoordelijke en een bewaartermijn', () {
        final spec = specOf(lang);
        expect(spec.notice, isNotNull);
        expect(spec.controller, isNotEmpty);
        expect(spec.contact, isNotEmpty);
        expect(spec.retainUnused, isNotEmpty);
      });

      test('opent als invulpagina en wacht op wat verplicht is', () {
        final open = FormFill.open(read(lang));
        final fill = (open as FormFillReady).fill;
        expect(fill.canSend, isFalse);
        expect(fill.openCount, greaterThan(5));
      });

      test('laat een ingevuld voorbeeld door de poort', () {
        var fill = (FormFill.open(read(lang)) as FormFillReady).fill;
        FormFill set(String id, FormAnswerValue value) {
          final step = fill.setAnswer(id, value);
          expect(step, isA<FormFillChanged>(), reason: id);
          return (step as FormFillChanged).fill;
        }

        final story = List.filled(60, 'woord').join(' ');
        fill = set('naam', const FormAnswerValue(text: 'Sari'));
        fill = set('mail', const FormAnswerValue(text: 'sari@example.org'));
        fill = set('gerecht', const FormAnswerValue(text: 'Rendang'));
        fill = set(
          'moeilijkheid',
          FormAnswerValue(
            text: specOf(lang).fields[4].rules.isEmpty ? '' : _first(lang),
          ),
        );
        fill = set(
          'ingredienten',
          const FormAnswerValue(
            rows: [
              ['Rundvlees', '1 kg'],
            ],
          ),
        );
        fill = set(
          'bereiding',
          const FormAnswerValue(items: ['Snijd', 'Kook']),
        );
        fill = set('verhaal', FormAnswerValue(text: story));
        fill = set('akkoord', const FormAnswerValue(consent: true));
        expect(fill.canSend, isTrue, reason: '${fill.allProblems}');
      });
    });
  }

  test('de talen hebben dezelfde velden met dezelfde regels', () {
    final nl = specOf('nl');
    final en = specOf('en');
    expect(nl.id, en.id);
    expect(nl.version, en.version);
    expect(nl.overview, en.overview);
    expect(
      [for (final f in nl.fields) f.id],
      [for (final f in en.fields) f.id],
    );
    for (var i = 0; i < nl.fields.length; i++) {
      final a = nl.fields[i];
      final b = en.fields[i];
      expect(a.type, b.type, reason: a.id);
      expect(a.required, b.required, reason: a.id);
      // Opties en kolomnamen zijn tekst die per taal verschilt; de rest van de regels
      // (aantallen, woordgrenzen, patronen) is gelijk.
      const perLanguage = {'options', 'columns'};
      Map<String, String> rulesOf(FormFieldSpec f) => {
        for (final e in f.rules.entries)
          if (!perLanguage.contains(e.key)) e.key: describe(e.value),
      };
      expect(rulesOf(a), rulesOf(b), reason: a.id);
    }
  });
}

/// De waarde van een regel als tekst: de regelwaarden hebben geen `toString`, en
/// dan zou elke afwijking er hetzelfde uitzien.
String describe(FormRuleValue rule) => switch (rule) {
  FlagRule() => 'flag',
  IntRule(:final value) => '$value',
  RangeRule(:final value) => '$value',
  TextRule(:final value) => value,
  ListRule(:final items) => items.join('|'),
};

String _first(String lang) => lang == 'nl' ? 'Makkelijk' : 'Easy';
