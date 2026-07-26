import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/annotation.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/annotation_codec.dart';

/// Streekidentiteit en de grafsteen — de formaathelft van de ink-merge
/// (GIT_STORAGE D7, #541).
///
/// De merge vereent de streken van twee kanten, want twee mensen die op één dia
/// tekenen zijn het niet oneens. Twee dingen moeten daarvoor kloppen in het
/// formaat, en geen van beide is vanzelfsprekend:
///
///  * elke streek heeft een **stabiele identiteit**, anders vereent dezelfde
///    tekening met zichzelf tot een dubbel getrokken lijn;
///  * wissen laat een **grafsteen** achter in plaats van de streek weg te
///    gooien, anders brengt de andere kant hem terug. Een verwijdering die
///    terugkomt is erger dan een die niet werkt, want de gebruiker zag hem
///    verdwijnen.
void main() {
  InkStroke streek(String id, {bool erased = false}) => InkStroke(
    id: id,
    tool: InkTool.pen,
    color: 0xFFEF4444,
    width: 0.004,
    points: const [Offset(0.1, 0.1), Offset(0.2, 0.2)],
    erased: erased,
  );

  group('newStrokeId', () {
    test('geeft elke keer iets anders', () {
      final ids = {for (var i = 0; i < 200; i++) newStrokeId()};
      expect(ids, hasLength(200));
    });

    test(
      'loopt ruwweg op met de tijd, zodat een diff leesbaar blijft',
      () async {
        // Een meetbare tussenpoos, want het contract is "ruwweg" oplopend, niet
        // strikt: twee dádelijk opeenvolgende id's kunnen dezelfde tijdstempel
        // dragen (op Windows tikt de klok grover dan een microseconde), en dan
        // beslist de random staart de volgorde. 25 ms ligt ruim boven die tik.
        final eerst = newStrokeId();
        await Future<void>.delayed(const Duration(milliseconds: 25));
        final later = newStrokeId();
        expect(eerst.compareTo(later), lessThan(0));
      },
    );
  });

  group('de rondgang', () {
    test('identiteit en grafsteen overleven encode/decode', () {
      final slide = Slide.create(SlideType.bullets).copyWith(title: 'A');
      final json = AnnotationCodec.encode(
        [slide],
        {
          slide.id: [streek('a'), streek('b', erased: true)],
        },
      )!;
      final terug = AnnotationCodec.decode(json, [slide])[slide.id]!;

      expect(terug.map((s) => s.id), ['a', 'b']);
      expect(terug.map((s) => s.erased), [false, true]);
    });

    test('een niet-gewiste streek schrijft geen erased-veld', () {
      // Ruis in een bestand dat mensen in een diff lezen. Het gewone geval is
      // een streek die er gewoon is.
      final ruw = jsonEncode(streek('a').toJson());
      expect(ruw, isNot(contains('erased')));
      expect(
        jsonEncode(streek('b', erased: true).toJson()),
        contains('erased'),
      );
    });
  });

  group('een sidecar van vóór de identiteit', () {
    test('krijgt alsnog een id, en blijft leesbaar', () {
      // Het leespad voor versie 1. Zonder id zou de streek niet te construeren
      // zijn en viel de hele tekening weg — en dat is precies wat deze
      // wijziging niet mag doen.
      final oud = InkStroke.fromJson({
        'tool': 'pen',
        'color': 0xFFEF4444,
        'width': 0.004,
        'points': [0.1, 0.1, 0.2, 0.2],
      });
      expect(oud.id, isNotEmpty);
      expect(oud.erased, isFalse);
      expect(oud.points, hasLength(2));
    });
  });

  group('de unie, waar dit formaat voor bestaat', () {
    // De driver komt in een volgende ronde; hier staat de eigenschap waar hij
    // op leunt, zodat het formaat niet stilletjes kan wegdrijven van wat de
    // merge nodig heeft.
    List<InkStroke> unie(List<InkStroke> a, List<InkStroke> b) {
      final byId = <String, InkStroke>{};
      for (final s in [...a, ...b]) {
        final gezien = byId[s.id];
        // Gewist wint: dat is de hele reden dat de grafsteen bestaat.
        byId[s.id] = gezien != null && gezien.erased ? gezien : s;
      }
      return byId.values.toList();
    }

    test('twee tekenaars houden allebei hun streken', () {
      final samen = unie([streek('a')], [streek('b')]);
      expect(samen.map((s) => s.id).toSet(), {'a', 'b'});
    });

    test('dezelfde streek van twee kanten blijft één streek', () {
      // Zonder identiteit zou dit een dubbel getrokken lijn opleveren.
      expect(unie([streek('a')], [streek('a')]), hasLength(1));
    });

    test('een gewiste streek komt niet terug', () {
      // De kern. De andere kant heeft hem nog ongewist; de grafsteen wint.
      final samen = unie([streek('a', erased: true)], [streek('a')]);
      expect(samen.single.erased, isTrue);
    });
  });
}
