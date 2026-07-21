import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';

/// De tweekolomsdia als contract: wat er op het scherm van een teksteditor
/// staat, ís de inhoud. Niet een base64-blok erboven dat toevallig hetzelfde
/// zegt — en dat won zodra iemand de zichtbare tekst aanpaste.

Slide _leesEen(String slideBody) {
  final md = '---\nmarp: true\n---\n\n$slideBody\n';
  final deck = MarkdownService().parseDeck(md);
  expect(deck, isNotNull, reason: 'parseDeck gaf null voor:\n$md');
  expect(deck!.slides, hasLength(1));
  return deck.slides.single;
}

String _schrijf(Slide slide, {ThemeProfile? profiel}) => MarkdownService()
    .generateDeck(
      Deck(
        title: 'D',
        slides: [slide],
        themeProfile: profiel ?? const ThemeProfile(),
      ),
    );

Slide _heenEnTerug(Slide slide) => _leesEen(
  _schrijf(slide).split('---\n').last.trim(),
);

void main() {
  group('een handgeschreven tweekolomsdia leest gewoon in', () {
    // Precies wat iemand met een teksteditor en de handleiding zou typen: geen
    // stijlattributen, geen commentaren, alleen de structuur.
    const handgeschreven = '''
<!-- _class: two-bullets -->

# Vergelijking

<div class="ocideck-two-bullets">
<div>
<h3>Voordelen</h3>
<ul>
<li>Snel</li>
<li>Goedkoop</li>
</ul>
</div>
<div>
<h3>Nadelen</h3>
<ul>
<li>Duur</li>
</ul>
</div>
</div>''';

    test('beide kolommen komen binnen', () {
      final slide = _leesEen(handgeschreven);
      expect(slide.type, SlideType.twoBullets);
      expect(slide.title, 'Vergelijking');
      expect(slide.bullets, ['Snel', 'Goedkoop']);
      expect(slide.bullets2, ['Duur']);
    });

    test('de kopjes boven de kolommen komen mee', () {
      final slide = _leesEen(handgeschreven);
      expect(slide.columnTitle1, 'Voordelen');
      expect(slide.columnTitle2, 'Nadelen');
    });

    test('zonder lijst-HTML vullen gewone streepjes de eerste kolom', () {
      // Wie `_class: two-bullets` typt en dan Markdown-bullets schrijft, kreeg
      // twee lege kolommen. Eén gevulde kolom is eerlijker dan niets.
      final slide = _leesEen(
        '<!-- _class: two-bullets -->\n\n# T\n\n- Links een\n- Links twee\n',
      );
      expect(slide.bullets, ['Links een', 'Links twee']);
      expect(slide.bullets2, isEmpty);
    });
  });

  group('de zichtbare opmaak bepaalt de lijststijl', () {
    test('☑ en ☐ maken er een checklist van, zonder directive', () {
      final slide = _leesEen('''
<!-- _class: two-bullets -->

# T

<div class="ocideck-two-bullets">
<div><ul>
<li>☑ Klaar</li>
<li>☐ Open</li>
</ul></div>
<div><ul><li>☐ Ook open</li></ul></div>
</div>''');
      expect(slide.listStyle, ListStyle.checklist);
      expect(slide.bullets, ['[x] Klaar', '[ ] Open']);
      expect(slide.bullets2, ['[ ] Ook open']);
    });

    test('een <ol> maakt er een genummerde lijst van', () {
      final slide = _leesEen('''
<!-- _class: two-bullets -->

# T

<div class="ocideck-two-bullets">
<div><ol><li value="1">Een</li></ol></div>
<div><ol><li value="1">Twee</li></ol></div>
</div>''');
      expect(slide.listStyle, ListStyle.numbered);
    });

    test('gewone items overrulen een achtergebleven checklist-directive', () {
      // Het asymmetrische geval: de zichtbare opmaak kon de stijl wél omhoog
      // zetten maar nooit terug. Wie de vinkjes weghaalt, wil geen checklist
      // meer — en de directive is niet meer dan een aanwijzing.
      final slide = _leesEen('''
<!-- _class: two-bullets -->
<!-- ocideck_list_style: checklist -->

# T

<div class="ocideck-two-bullets">
<div><ul><li>Gewoon punt</li></ul></div>
<div><ul><li>Ook gewoon</li></ul></div>
</div>''');
      expect(slide.listStyle, ListStyle.bullets);
    });

    test('een enkele kolom valt net zo goed terug op gewone bullets', () {
      final slide = _leesEen(
        '<!-- ocideck_list_style: checklist -->\n\n# T\n\n- Gewoon punt\n',
      );
      expect(slide.type, SlideType.bullets);
      expect(slide.listStyle, ListStyle.bullets);
    });
  });

  group('de rondgang overleeft wat de base64 ooit moest afdekken', () {
    test('een bullet met HTML en een pipe komt ongeschonden terug', () {
      const lastig = 'Punt <b>vet</b> | met pipe & "aanhaling"';
      final uit = _heenEnTerug(
        Slide.create(SlideType.twoBullets).copyWith(
          title: 'T',
          bullets: [lastig],
          bullets2: const ['Rechts'],
        ),
      );
      expect(uit.bullets, [lastig]);
      expect(uit.bullets2, const ['Rechts']);
    });

    test('een kolomkop met HTML erin komt ongeschonden terug', () {
      const lastig = 'Kop <i>schuin</i> & meer';
      final uit = _heenEnTerug(
        Slide.create(SlideType.twoBullets).copyWith(
          title: 'T',
          columnTitle1: lastig,
          bullets: const ['A'],
          bullets2: const ['B'],
        ),
      );
      expect(uit.columnTitle1, lastig);
    });

    test('inspringing, tussenkoppen en scheidingslijnen overleven', () {
      final uit = _heenEnTerug(
        Slide.create(SlideType.twoBullets).copyWith(
          title: 'T',
          bullets: [
            groupHeadingBullet('Blok A'),
            'Punt',
            '\tSubpunt',
            groupHeadingBullet(''),
            'Na de streep',
          ],
          bullets2: const ['Rechts'],
        ),
      );
      expect(uit.bullets, [
        groupHeadingBullet('Blok A'),
        'Punt',
        '\tSubpunt',
        groupHeadingBullet(''),
        'Na de streep',
      ]);
    });

    test('een checklist met vinkjes en doorhaling overleeft', () {
      final uit = _heenEnTerug(
        Slide.create(SlideType.twoBullets).copyWith(
          title: 'T',
          bullets: const ['[x] Klaar', '[ ] Open'],
          bullets2: const ['[ ] Rechts'],
          listStyle: ListStyle.checklist,
        ),
      );
      expect(uit.listStyle, ListStyle.checklist);
      expect(uit.bullets, const ['[x] Klaar', '[ ] Open']);
      expect(uit.bullets2, const ['[ ] Rechts']);
    });

    test('een genummerde tweekolomslijst overleeft', () {
      final uit = _heenEnTerug(
        Slide.create(SlideType.twoBullets).copyWith(
          title: 'T',
          bullets: const ['Een', '\tEen-a'],
          bullets2: const ['Twee'],
          listStyle: ListStyle.numbered,
        ),
      );
      expect(uit.listStyle, ListStyle.numbered);
      expect(uit.bullets, const ['Een', '\tEen-a']);
    });
  });

  group('geen base64 meer, en oude bestanden gaan mee', () {
    test('een opgeslagen tweekolomsdia bevat geen base64-richtlijn', () {
      final md = _schrijf(
        Slide.create(SlideType.twoBullets).copyWith(
          title: 'T',
          columnTitle1: 'L',
          columnTitle2: 'R',
          bullets: const ['A'],
          bullets2: const ['B'],
        ),
      );
      expect(md, isNot(contains('ocideck_two_bullets_left')));
      expect(md, isNot(contains('ocideck_two_bullets_right')));
      expect(md, isNot(contains('ocideck_two_bullets_left_title')));
      expect(md, isNot(contains('ocideck_two_bullets_right_title')));
    });

    test('een oud bestand mét base64 blijft leesbaar', () {
      // Zoals OciDeck het tot nu toe schreef: de base64 bovenaan én de
      // zichtbare HTML eronder.
      final slide = _leesEen('''
<!-- _class: two-bullets -->

# Titel

<!-- ocideck_two_bullets_left: WyJBIiwiQiJd -->
<!-- ocideck_two_bullets_right: WyJDIl0= -->
<!-- ocideck_two_bullets_left_title: TGlua3M= -->
<!-- ocideck_two_bullets_right_title: UmVjaHRz -->
<div class="ocideck-two-bullets" style="display:grid; grid-template-columns:1fr 1fr; gap:3rem; align-items:start;">
<div>
<h3 style="margin:0 0 .5rem;">Links</h3>
<ul style="margin:0; padding-left:1.3em;">
<li style="">A</li>
<li style="">B</li>
</ul>
</div>
<div>
<h3 style="margin:0 0 .5rem;">Rechts</h3>
<ul style="margin:0; padding-left:1.3em;">
<li style="">C</li>
</ul>
</div>
</div>''');
      expect(slide.bullets, ['A', 'B']);
      expect(slide.bullets2, ['C']);
      expect(slide.columnTitle1, 'Links');
      expect(slide.columnTitle2, 'Rechts');
    });

    test('een oud bestand zonder zichtbare lijst valt op de base64 terug', () {
      // Kan alleen in een met de hand gekortwiekt bestand voorkomen, maar het
      // alternatief is inhoud weggooien die er nog wél staat.
      final slide = _leesEen(
        '<!-- _class: two-bullets -->\n\n# T\n\n'
        '<!-- ocideck_two_bullets_left: WyJBIl0= -->\n'
        '<!-- ocideck_two_bullets_right: WyJCIl0= -->\n',
      );
      expect(slide.bullets, ['A']);
      expect(slide.bullets2, ['B']);
    });

    test('bij opslaan verdwijnt de base64 uit een oud bestand', () {
      final slide = _leesEen('''
<!-- _class: two-bullets -->

# Titel

<!-- ocideck_two_bullets_left: WyJBIl0= -->
<!-- ocideck_two_bullets_right: WyJCIl0= -->
<div class="ocideck-two-bullets">
<div><ul><li>A</li></ul></div>
<div><ul><li>B</li></ul></div>
</div>''');
      final opnieuw = _schrijf(slide);
      expect(opnieuw, isNot(contains('ocideck_two_bullets')));
      expect(opnieuw, contains('<li>A</li>'));
    });
  });
}
