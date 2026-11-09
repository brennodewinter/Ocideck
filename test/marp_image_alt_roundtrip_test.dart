import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';

/// Een handgeschreven Marp-deck draagt zijn alt-tekst in `![alt](pad)`, niet in
/// OciDecks `<!-- ocideck_image_alt: … -->`. Die alt-tekst verdween bij de
/// eerste opslag stil: de parser nam alleen het pad over, de serialiser schreef
/// `![](pad)` terug. Elke test leest een Marp-vorm in, schrijft opnieuw, leest
/// weer in, en eist dat de beschrijving er nog is — in het model én in het
/// bestand.

const _front = '---\nmarp: true\n---\n\n';

({Slide first, Slide second, String written}) _twice(String body) {
  final service = MarkdownService();
  final deck = service.parseDeck('$_front$body\n');
  expect(deck, isNotNull);
  final written = service.generateDeck(deck!);
  final again = service.parseDeck(written);
  expect(again, isNotNull, reason: written);
  return (
    first: deck.slides.single,
    second: again!.slides.single,
    written: written,
  );
}

const _splitBody = '''
<!-- _class: split -->

<div class="split-text">

# Sleutelbeheer

- Wie heeft de sleutel?

</div>

<div class="split-image">

![Kat met een sleutel boven een maquette](images/x.png)

</div>''';

void main() {
  test('split: Marp-alt in de split-image-div overleeft de rondgang', () {
    final r = _twice(_splitBody);
    expect(r.first.type, SlideType.bulletsImage);
    expect(r.first.imagePath, 'images/x.png');
    expect(r.first.imageAltText, 'Kat met een sleutel boven een maquette');
    expect(
      r.written,
      contains(
        '<!-- ocideck_image_alt: Kat met een sleutel boven een maquette -->',
      ),
    );
    expect(r.second.imageAltText, 'Kat met een sleutel boven een maquette');
  });

  test('split met vrije tekst: ook de richText-tak leest de Marp-alt', () {
    final r = _twice(
      _splitBody.replaceFirst(
        '<!-- _class: split -->',
        '<!-- _class: split -->\n<!-- ocideck_list_style: richText -->',
      ),
    );
    expect(r.first.imageAltText, 'Kat met een sleutel boven een maquette');
    expect(r.second.imageAltText, 'Kat met een sleutel boven een maquette');
  });

  test('het ocideck_image_alt-commentaar wint van de Marp-alt', () {
    final r = _twice(
      _splitBody.replaceFirst(
        '](images/x.png)',
        '](images/x.png)\n<!-- ocideck_image_alt: De echte beschrijving -->',
      ),
    );
    expect(r.first.imageAltText, 'De echte beschrijving');
    expect(r.second.imageAltText, 'De echte beschrijving');
  });

  test('w:/h:-maten en filters horen niet in de alt-tekst', () {
    final r = _twice(
      _splitBody.replaceFirst(
        '![Kat met',
        '![w:300 h:200 sepia blur:2px Kat met',
      ),
    );
    expect(r.first.imageAltText, 'Kat met een sleutel boven een maquette');
  });

  test('titel met ![bg alt]: blijft een titeldia en houdt de alt', () {
    final r = _twice('''
<!-- _class: title -->

![bg Skyline van Den Haag bij nacht](images/bg.png)

# Hybride dreiging''');
    expect(r.first.type, SlideType.title);
    expect(r.first.imageAltText, 'Skyline van Den Haag bij nacht');
    expect(r.written, contains('ocideck_image_alt: Skyline van Den Haag'));
    expect(r.second.type, SlideType.title);
    expect(r.second.imageAltText, 'Skyline van Den Haag bij nacht');
  });

  test('sectie met ![bg alt] houdt de alt', () {
    final r = _twice('''
<!-- _class: section -->

![bg Een lege vergaderzaal](images/bg.png)

# Deel twee''');
    expect(r.first.type, SlideType.section);
    expect(r.second.imageAltText, 'Een lege vergaderzaal');
  });

  test('grote afbeelding: Marp-opties vallen weg, de alt blijft', () {
    final r = _twice('''
<!-- _class: image -->

![bg contain sepia Netwerkkaart van de haven](images/kaart.png)''');
    expect(r.first.type, SlideType.image);
    expect(r.first.imageAltText, 'Netwerkkaart van de haven');
    expect(r.first.marpStyle.imageFit, 'contain');
    expect(r.second.imageAltText, 'Netwerkkaart van de haven');
    expect(r.second.marpStyle.imageFilters, ['sepia']);
  });

  test('twee afbeeldingen: elke kant houdt zijn eigen alt', () {
    final r = _twice('''
<!-- _class: two-images -->

![bg left:50% Het oude ontwerp](images/a.png)
![bg right:50% Het nieuwe ontwerp](images/b.png)

# Voor en na''');
    expect(r.first.type, SlideType.twoImages);
    expect(r.second.imageAltText, 'Het oude ontwerp');
    expect(r.second.imageAltText2, 'Het nieuwe ontwerp');
  });

  test('citaat met achtergrond houdt de alt', () {
    final r = _twice('''
<!-- _class: quote -->

![bg Portret van de spreker](images/p.png)

> Vertrouwen is goed.

— Iemand''');
    expect(r.first.type, SlideType.quote);
    expect(r.first.imageAltText, 'Portret van de spreker');
    expect(r.written, contains('ocideck_image_alt: Portret van de spreker'));
    expect(r.second.imageAltText, 'Portret van de spreker');
  });

  test('vraag met afbeelding houdt de alt', () {
    final r = _twice('''
<!-- _class: question -->

# Wat zie je?

![Een phishingmail met een valse afzender](images/q.png)

```question
{"kind":"single","prompt":"Echt of nep?","answers":[{"text":"Echt"},{"text":"Nep","correct":true}]}
```''');
    expect(r.first.type, SlideType.question);
    expect(r.first.imageAltText, 'Een phishingmail met een valse afzender');
    expect(r.second.imageAltText, 'Een phishingmail met een valse afzender');
  });

  test(
    'een onbekend Marp-sleutelwoord bewaart het blok nog steeds letterlijk',
    () {
      final r = _twice('''
<!-- _class: image -->

![bg vertical Kat](images/k.png)''');
      expect(r.first.type, SlideType.freeMarkdown);
      expect(r.written, contains('![bg vertical Kat](images/k.png)'));
    },
  );

  test('een OciDeck-dia zonder alt schrijft nog steeds geen alt', () {
    final service = MarkdownService();
    final md = service.generateDeck(
      Deck(
        title: 'Demo',
        slides: [
          Slide.create(
            SlideType.bulletsImage,
          ).copyWith(imagePath: 'images/x.png', bullets: ['a']),
        ],
      ),
    );
    expect(md, isNot(contains('ocideck_image_alt')));
    expect(service.parseDeck(md)!.slides.single.imageAltText, isEmpty);
  });
}
