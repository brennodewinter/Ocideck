import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/annotation.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/git/deck_merge.dart';

/// Driewegs-merge van één deck (§8.6). Wat OciDeck zelf mag beslissen beslist
/// het; wat het niet mag beslissen komt als conflict terug. De harde eis eromheen
/// is P2: er verdwijnt nooit werk — niet dat van ons, en niet dat van de ander.
void main() {
  Slide bullets(String title, List<String> items) =>
      Slide.create(SlideType.bullets).copyWith(title: title, bullets: items);

  Deck deckOf(List<Slide> slides, {TlpLevel tlp = TlpLevel.none}) =>
      Deck(title: 'Kwartaal', slides: slides, tlp: tlp);

  final one = bullets('Eén', const ['a']);
  final two = bullets('Twee', const ['b']);
  final three = bullets('Drie', const ['c']);

  group('mergeDeckVersions — wat het zelf beslist', () {
    test('niemand raakte iets aan: schoon, deck ongewijzigd', () {
      final base = deckOf([one, two]);
      final result = mergeDeckVersions(
        base,
        deckOf([one, two]),
        deckOf([one, two]),
      );

      expect(result.isClean, isTrue);
      expect(result.merged.slides.map((s) => s.title), ['Eén', 'Twee']);
    });

    test('alleen wij bewerkten een slide: onze versie, geen conflict', () {
      final ourTwo = bullets('Twee', const ['b bijgewerkt']);
      final result = mergeDeckVersions(
        deckOf([one, two]),
        deckOf([one, ourTwo]),
        deckOf([one, two]),
      );

      expect(result.isClean, isTrue);
      expect(result.merged.slides[1].bullets, const ['b bijgewerkt']);
    });

    test('alleen de ander bewerkte een slide: hún versie komt erin', () {
      final theirTwo = bullets('Twee', const ['b van hen']);
      final result = mergeDeckVersions(
        deckOf([one, two]),
        deckOf([one, two]),
        deckOf([one, theirTwo]),
      );

      expect(result.isClean, isTrue);
      expect(result.merged.slides[1].bullets, const ['b van hen']);
    });

    test('beide kanten maakten dezelfde wijziging: niets te kiezen', () {
      final edited = bullets('Twee', const ['zelfde nieuwe tekst']);
      final result = mergeDeckVersions(
        deckOf([one, two]),
        deckOf([one, edited]),
        deckOf([one, edited]),
      );

      expect(result.isClean, isTrue);
      expect(result.merged.slides[1].bullets, const ['zelfde nieuwe tekst']);
    });

    test('allebei dezelfde slide weggegooid: weg, en geen conflict', () {
      final result = mergeDeckVersions(
        deckOf([one, two]),
        deckOf([one]),
        deckOf([one]),
      );

      expect(result.isClean, isTrue);
      expect(result.merged.slides.map((s) => s.title), ['Eén']);
    });

    test('allebei een eigen slide toegevoegd: allebei behouden', () {
      final ourNew = bullets('Onze nieuwe', const ['x']);
      final theirNew = bullets('Hun nieuwe', const ['y']);
      final result = mergeDeckVersions(
        deckOf([one]),
        deckOf([one, ourNew]),
        deckOf([one, theirNew]),
      );

      expect(result.isClean, isTrue);
      expect(result.merged.slides.map((s) => s.title), [
        'Eén',
        'Onze nieuwe',
        'Hun nieuwe',
      ]);
    });

    test('onze volgorde is de ruggengraat', () {
      final result = mergeDeckVersions(
        deckOf([one, two, three]),
        deckOf([three, one, two]), // wij hebben herschikt
        deckOf([one, two, three]),
      );

      expect(result.isClean, isTrue);
      expect(result.merged.slides.map((s) => s.title), ['Drie', 'Eén', 'Twee']);
    });
  });

  group('mergeDeckVersions — wat het niet mag beslissen', () {
    test('beide kanten bewerkten dezelfde slide anders: conflict', () {
      final ourTwo = bullets('Twee', const ['onze tekst']);
      final theirTwo = bullets('Twee', const ['hun tekst']);
      final result = mergeDeckVersions(
        deckOf([one, two]),
        deckOf([one, ourTwo]),
        deckOf([one, theirTwo]),
      );

      expect(result.isClean, isFalse);
      final conflict = result.conflicts.single;
      expect(conflict.baseIndex, 1);
      expect(conflict.ours!.bullets, const ['onze tekst']);
      expect(conflict.theirs!.bullets, const ['hun tekst']);
      expect(conflict.isDeleteAgainstEdit, isFalse);
      // Voorlopig staat ónze kant erin — nooit stil die van de ander.
      expect(result.merged.slides[1].bullets, const ['onze tekst']);
    });

    test(
      'wij gooiden weg, zij bewerkten: conflict, hun werk blijft zichtbaar',
      () {
        final theirTwo = bullets('Twee', const ['hun tekst']);
        final result = mergeDeckVersions(
          deckOf([one, two]),
          deckOf([one]), // wij verwijderden slide 2
          deckOf([one, theirTwo]),
        );

        expect(result.isClean, isFalse);
        final conflict = result.conflicts.single;
        expect(conflict.ours, isNull);
        expect(conflict.theirs, isNotNull);
        expect(conflict.isDeleteAgainstEdit, isTrue);
        // P2: hun bewerking verdwijnt niet stil omdat wij toevallig wisten.
        expect(
          result.merged.slides.map((s) => s.title),
          contains('Twee'),
          reason: 'andermans werk blijft staan tot er gekozen is',
        );
      },
    );

    test('een conflict wijst naar zijn plek in het samengevoegde deck', () {
      // Hier steunt de keuzedialoog op: hij wisselt de andere kant er op deze
      // index in, zonder de merge over te doen.
      final ourTwo = bullets('Twee', const ['onze tekst']);
      final theirTwo = bullets('Twee', const ['hun tekst']);
      final result = mergeDeckVersions(
        deckOf([one, two, three]),
        deckOf([one, ourTwo, three]),
        deckOf([one, theirTwo, three]),
      );

      final conflict = result.conflicts.single;
      expect(conflict.mergedIndex, isNotNull);
      expect(
        result.merged.slides[conflict.mergedIndex!].bullets,
        const ['onze tekst'],
        reason: 'daar staat de voorlopige keuze',
      );
      // En de andere kant erin wisselen levert een geldig deck op.
      final swapped = [...result.merged.slides];
      swapped[conflict.mergedIndex!] = conflict.theirs!;
      expect(swapped.map((s) => s.title), ['Eén', 'Twee', 'Drie']);
      expect(swapped[1].bullets, const ['hun tekst']);
    });

    test('verplaatsen botst niet met bewerken', () {
      // Wij schoven hem op, zij pasten de tekst aan: dat is geen echt conflict.
      final theirTwo = bullets('Twee', const ['hun tekst']);
      final result = mergeDeckVersions(
        deckOf([one, two, three]),
        deckOf([two, one, three]), // alleen verplaatst
        deckOf([one, theirTwo, three]),
      );

      expect(result.isClean, isTrue);
      expect(
        result.merged.slides.firstWhere((s) => s.title == 'Twee').bullets,
        const ['hun tekst'],
      );
    });
  });

  group('mergeDeckVersions — classificatie is fail-safe', () {
    test('de strengste TLP van de twee wint', () {
      // Zij verhoogden naar RED, wij niet. Onze metadata blindelings nemen zou
      // die verhoging stil weggooien; dat mag niet.
      final result = mergeDeckVersions(
        deckOf([one], tlp: TlpLevel.none),
        deckOf([one], tlp: TlpLevel.green),
        deckOf([one], tlp: TlpLevel.red),
      );

      expect(result.merged.tlp, TlpLevel.red);
    });

    test('onze hogere classificatie blijft ook staan', () {
      final result = mergeDeckVersions(
        deckOf([one], tlp: TlpLevel.none),
        deckOf([one], tlp: TlpLevel.amber),
        deckOf([one], tlp: TlpLevel.none),
      );

      expect(result.merged.tlp, TlpLevel.amber);
    });
  });

  group('de notities overleven de merge', () {
    // Sinds #541 staan de notities in de repo, en dan wordt dit verlies
    // duurzaam en gedeeld. `merged` erfde `userNotes` letterlijk van ónze kant
    // — gesleuteld op de id's van ónze parse, terwijl de samengevoegde dia's
    // grotendeels uit de basis en van de ander komen. Die id's worden bij elke
    // parse opnieuw uitgedeeld, dus geen enkele sleutel wees nog een dia aan;
    // de schrijfkant zag een deck zónder notities en verwíjderde het bestand.
    //
    // Elke toets hieronder kijkt daarom op de sleutels van de úítkomst, nooit
    // op die van de invoer: precies het verschil dat de fout was.

    /// Twee decks met dezelfde inhoud maar verse id's, zoals twee parses van
    /// hetzelfde bestand ze opleveren.
    Deck parsedCopy(List<Slide> slides, {Map<int, String> notes = const {}}) {
      final fresh = [
        for (final s in slides)
          Slide.create(s.type).copyWith(title: s.title, bullets: s.bullets),
      ];
      return Deck(
        title: 'Kwartaal',
        slides: fresh,
        userNotes: {for (final e in notes.entries) fresh[e.key].id: e.value},
      );
    }

    String? noteOn(Deck deck, String title) {
      final slide = deck.slides.firstWhere((s) => s.title == title);
      return deck.userNotes[slide.id];
    }

    test('twee auteurs, verschillende dia\'s: beide notities blijven', () {
      // Het gewoonste geval dat er is, en precies het geval dat alles wiste.
      final result = mergeDeckVersions(
        parsedCopy([one, two, three]),
        parsedCopy([one, two, three], notes: {1: 'van ons, bij Twee'}),
        parsedCopy([one, two, three], notes: {2: 'van hen, bij Drie'}),
      );

      expect(noteOn(result.merged, 'Twee'), 'van ons, bij Twee');
      expect(noteOn(result.merged, 'Drie'), 'van hen, bij Drie');
    });

    test('dezelfde dia: onze tekst wint, zoals de rest van de merge', () {
      final result = mergeDeckVersions(
        parsedCopy([one, two]),
        parsedCopy([one, two], notes: {1: 'onze lezing'}),
        parsedCopy([one, two], notes: {1: 'hun lezing'}),
      );

      expect(noteOn(result.merged, 'Twee'), 'onze lezing');
    });

    test('alleen de ander schreef iets: dat blijft ook staan', () {
      final result = mergeDeckVersions(
        parsedCopy([one, two]),
        parsedCopy([one, two]),
        parsedCopy([one, two], notes: {0: 'alleen van hen'}),
      );

      expect(noteOn(result.merged, 'Eén'), 'alleen van hen');
    });

    test('een notitie op een dia die niemand hield, verdwijnt mee', () {
      // Geen verlies om over te klagen: de dia is weg, dus de notitie erbij
      // heeft niets meer om aan te hangen. Wel bewaken dat er geen weesnotitie
      // achterblijft die de volgende merge weer laat opduiken.
      final result = mergeDeckVersions(
        parsedCopy([one, two]),
        parsedCopy([one], notes: {0: 'bij Eén'}),
        parsedCopy([one]),
      );

      expect(result.merged.userNotes.values, ['bij Eén']);
      expect(result.merged.userNotes.keys, [result.merged.slides.single.id]);
    });

    test('geen notities aan beide kanten blijft leeg', () {
      final result = mergeDeckVersions(
        parsedCopy([one, two]),
        parsedCopy([one, two]),
        parsedCopy([one, two]),
      );

      expect(result.merged.userNotes, isEmpty);
    });

    test('elke sleutel wijst een dia in de uitkomst aan', () {
      // De eigenschap waar het werkelijk om gaat: een sleutel die niets
      // aanwijst is onzichtbaar in de app en fataal bij het opslaan.
      final result = mergeDeckVersions(
        parsedCopy([one, two, three]),
        parsedCopy([one, two, three], notes: {0: 'a', 1: 'b'}),
        parsedCopy([one, two, three], notes: {2: 'c'}),
      );

      final ids = {for (final s in result.merged.slides) s.id};
      expect(result.merged.userNotes.keys, everyElement(isIn(ids)));
      expect(result.merged.userNotes, hasLength(3));
    });
  });

  group('de tekeningen verenigen bij de merge', () {
    // D7: twee mensen die op één dia tekenden waren het niet oneens — de merge
    // is een **unie op streek-id**, met één uitzondering die de grafsteen is:
    // gewist wint van niet-gewist, ongeacht de kant. Net als bij de notities
    // kijkt elke toets op de sleutels van de uitkomst, nooit die van de invoer.

    InkStroke streek(String id, {bool erased = false}) => InkStroke(
      tool: InkTool.pen,
      color: 0xFFEF4444,
      width: 0.004,
      points: const [Offset(0.1, 0.2), Offset(0.3, 0.4)],
      id: id,
      erased: erased,
    );

    Deck parsedCopy(
      List<Slide> slides, {
      Map<int, List<InkStroke>> ink = const {},
    }) {
      final fresh = [
        for (final s in slides)
          Slide.create(s.type).copyWith(title: s.title, bullets: s.bullets),
      ];
      return Deck(
        title: 'Kwartaal',
        slides: fresh,
        annotations: {for (final e in ink.entries) fresh[e.key].id: e.value},
      );
    }

    List<InkStroke> inkOn(Deck deck, String title) {
      final slide = deck.slides.firstWhere((s) => s.title == title);
      return deck.annotations[slide.id] ?? const [];
    }

    test('twee tekenaars, verschillende dia\'s: beide lagen blijven', () {
      final result = mergeDeckVersions(
        parsedCopy([one, two, three]),
        parsedCopy(
          [one, two, three],
          ink: {
            1: [streek('van-ons')],
          },
        ),
        parsedCopy(
          [one, two, three],
          ink: {
            2: [streek('van-hen')],
          },
        ),
      );

      expect(inkOn(result.merged, 'Twee').single.id, 'van-ons');
      expect(inkOn(result.merged, 'Drie').single.id, 'van-hen');
    });

    test('dezelfde dia: unie, geen keuze en geen verlies', () {
      // Dit is waar de notities "onze tekst wint" zeggen en de tekeningen
      // uitdrukkelijk niet: beide streken horen erin.
      final result = mergeDeckVersions(
        parsedCopy([one, two]),
        parsedCopy(
          [one, two],
          ink: {
            1: [streek('gedeeld'), streek('ons')],
          },
        ),
        parsedCopy(
          [one, two],
          ink: {
            1: [streek('gedeeld'), streek('hen')],
          },
        ),
      );

      final ids = inkOn(result.merged, 'Twee').map((s) => s.id).toList();
      expect(ids, ['gedeeld', 'ons', 'hen']);
    });

    test('een gewiste streek komt niet terug — de grafsteen wint', () {
      // De reden dat pure vereniging fout was: wij gumden, de ander heeft de
      // streek nog. De unie zou hem terugbrengen terwijl de gebruiker hem zág
      // verdwijnen.
      final result = mergeDeckVersions(
        parsedCopy(
          [one, two],
          ink: {
            1: [streek('s1')],
          },
        ),
        parsedCopy(
          [one, two],
          ink: {
            1: [streek('s1', erased: true)],
          },
        ),
        parsedCopy(
          [one, two],
          ink: {
            1: [streek('s1')],
          },
        ),
      );

      final strokes = inkOn(result.merged, 'Twee');
      expect(strokes.single.id, 's1');
      expect(
        strokes.single.erased,
        isTrue,
        reason:
            'de grafsteen moet ook de úítkomst in — weggooien laat de '
            'streek bij de vólgende merge alsnog terugkeren',
      );
    });

    test('andersom gumde de ander, en ook dan blijft het gewist', () {
      final result = mergeDeckVersions(
        parsedCopy(
          [one, two],
          ink: {
            1: [streek('s1')],
          },
        ),
        parsedCopy(
          [one, two],
          ink: {
            1: [streek('s1')],
          },
        ),
        parsedCopy(
          [one, two],
          ink: {
            1: [streek('s1', erased: true)],
          },
        ),
      );

      expect(inkOn(result.merged, 'Twee').single.erased, isTrue);
    });

    test('elke sleutel wijst een dia in de uitkomst aan', () {
      final result = mergeDeckVersions(
        parsedCopy([one, two, three]),
        parsedCopy(
          [one, two, three],
          ink: {
            0: [streek('a')],
          },
        ),
        parsedCopy(
          [one, two, three],
          ink: {
            2: [streek('c')],
          },
        ),
      );

      final ids = {for (final s in result.merged.slides) s.id};
      expect(result.merged.annotations.keys, everyElement(isIn(ids)));
      expect(result.merged.annotations, hasLength(2));
    });
  });
}
