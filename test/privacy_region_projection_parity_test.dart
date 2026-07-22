// Wat de landenpakketten wél scannen, moet de redactie óók redigeren — en wat
// ze niet scannen, moet blijven staan.
//
// De waarschuwingskant geeft de ingestelde pakketten netjes door
// (`privacy_provider.dart` reikt `settings.privacyRegions` aan de scanner), maar
// `PrivacyProjection._project` bouwde zijn eigen scanner **zonder** `regions:`
// en viel dus terug op `defaultPrivacyRegions`. Gevolg: wie een landpakket
// uitzet, krijgt in de voorvertoning en de export zwarte blokken over waarden
// die OciWacht hem nooit heeft gemeld. Het kwaliteitspaneel en de export waren
// het oneens op precies het punt waar de gebruiker op het paneel afgaat om te
// beslissen wat hij deelt.
//
// Dit is dezelfde vorm als `privacy_scan_redact_parity_test`, één laag hoger:
// daar liepen de *velden* uiteen tussen scannen en redigeren, hier de *regels*.
//
// Alle waarden zijn nep; het BSN hieronder komt uit `privacy_regions_test`.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

/// Een geldig gevormd BSN: alleen de `nl.bsn`-regel vindt dit, en die hangt aan
/// het `nl`-pakket.
const String _bsn = '728398242';
const String _zin = 'Het burgerservicenummer is $_bsn';

/// Pakketten mét en zónder Nederland. `be`/`de` staan erin zodat de scanner niet
/// bij een lege verzameling een ander pad neemt.
const Set<String> _zonderNl = {'be', 'de'};
const Set<String> _metNl = {'be', 'de', 'nl'};

Deck _deck() => Deck(
  title: 'Rapport',
  slides: [Slide.create(SlideType.bullets).copyWith(title: _zin)],
  privacy: PrivacyDisposition.redact,
);

/// De titel van de eerste dia zoals de ontvanger hem krijgt.
String _geprojecteerdeTitel(Set<String> regions) =>
    PrivacyProjection.forAudience(_deck(), regions: regions).slides.first.title;

bool _scantBsn(Set<String> regions) => PrivacyScanner(
  regions: regions,
).scan(_deck()).findings.any((f) => f.ruleId == 'nl.bsn');

void main() {
  group('de redactie volgt de ingestelde landenpakketten', () {
    // De ijkpunten: zonder deze twee zegt de test hieronder niets, want dan kan
    // hij groen staan doordat de detectie zelf stuk is.
    test('de scanner meldt het BSN alleen met het nl-pakket aan', () {
      expect(_scantBsn(_metNl), isTrue);
      expect(_scantBsn(_zonderNl), isFalse);
    });

    test('met het pakket aan verdwijnt het nummer uit de projectie', () {
      expect(_geprojecteerdeTitel(_metNl), isNot(contains(_bsn)));
    });

    test('met het pakket uit blijft het nummer staan', () {
      // Dit is de bug. Zonder `regions:` in `_project` valt de projectie terug
      // op alle pakketten, redigeert het BSN alsnog, en krijgt de gebruiker een
      // zwart blok over iets wat hem nooit gemeld is.
      expect(
        _geprojecteerdeTitel(_zonderNl),
        contains(_bsn),
        reason:
            'een uitgezet landpakket meldt niets en moet dus ook niets '
            'weglakken — anders zijn het kwaliteitspaneel en de export het '
            'oneens over wat er in de export staat',
      );
    });

    test('de universele laag blijft redigeren, ook zonder één pakket', () {
      // De belangrijkste grens van deze wijziging: een regiokeuze mag nooit een
      // e-mailadres of IBAN laten passeren. Zou het doorgeven van `regions` dat
      // wél doen, dan is de reparatie een lek in plaats van een correctie.
      final deck = Deck(
        title: 'Rapport',
        slides: [
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Mail naar marieke@acme.example'),
        ],
        privacy: PrivacyDisposition.redact,
      );
      final projected = PrivacyProjection.forAudience(deck, regions: const {});
      expect(projected.slides.first.title, isNot(contains('marieke@acme')));
    });

    // Deze pin legt een besluit vast, geen implementatiedetail: de landkeuze
    // geldt niet voor de route naar buiten. Wie het `nl`-pakket uitzet doet een
    // uitspraak over zijn eigen paneel en zijn eigen export, niet over wat een
    // model van een derde partij mag zien. `forExternalProcessing` neemt daarom
    // bewust geen `regions`-parameter — komt die er ooit toch, dan hoort deze
    // test eerst een expliciete afweging af te dwingen.
    test('de route naar buiten trekt zich niets aan van de landkeuze', () {
      final projected = PrivacyProjection.forExternalProcessing(_deck());
      expect(
        projected.slides.first.title,
        isNot(contains(_bsn)),
        reason:
            'data die het apparaat verlaat is niet terug te halen; daar geldt '
            'de strengste stand, niet de voorkeur van de gebruiker',
      );
    });
  });
}
