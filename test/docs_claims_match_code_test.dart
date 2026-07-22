import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';

import '../tool/check_ratchet_trend.dart';

/// Bewaakt de mechanische helft van "documentatie die klopt": een bewering in
/// proza die een constante uit de code herhaalt, hoort afgeleid of vergeleken
/// te worden — niet overgetypt.
///
/// `docs_registration_test` bewaakt dát een document bereikbaar is. Dat is een
/// poort over leidingwerk: het zei niets over de vraag of er iets waars in
/// staat. Twee echte gevallen uit één sessie: `CHECKS.md` schreef
/// `serviceUiImportBaseline` op 8 terwijl de code 4 zei, en het PR-sjabloon
/// noemde 8 talen tegen een werkelijke 32. Allebei netjes geregistreerd,
/// allebei onwaar.
///
/// De menselijke helft — is het te volgen, klopt het verhaal — staat hier
/// bewust niet in. Die is niet te automatiseren, en een test die doet alsof
/// verplaatst het probleem alleen.
///
/// Werkende voorbeelden van dezelfde soort: `test/docs_enum_counts_test.dart`
/// (enum-tellingen) en `test/pr_template_consistency_test.dart` (de afwezigheid
/// van een uitgeschreven talenlijst).
void main() {
  String lees(String pad) => File(pad).readAsStringSync();

  /// Constanten die in proza genoemd mogen worden, met de plek waar hun waarde
  /// werkelijk staat. De basislijnen komen uit `check_ratchet_trend.dart`, zodat
  /// er maar één lijst is die bijgewerkt moet worden als er een ratchet bij
  /// komt; de plafonds staan hier omdat het geen basislijnen zijn.
  final vindplaatsen = <String, Ratchet>{
    for (final ratchet in ratchets) ratchet.naam: ratchet,
    'maxFileLines': const Ratchet(
      naam: 'maxFileLines',
      bestand: 'tool/check_conventions.dart',
      soort: RatchetSoort.getal,
      richting: Richting.omlaag,
      wat: 'het plafond per bestand in regels',
    ),
    'maxMethodLines': const Ratchet(
      naam: 'maxMethodLines',
      bestand: 'tool/check_method_length.dart',
      soort: RatchetSoort.getal,
      richting: Richting.omlaag,
      wat: 'het plafond per declaratie in regels',
    ),
  };

  int? waardeVan(String naam) {
    final ratchet = vindplaatsen[naam];
    if (ratchet == null) return null;
    final bestand = File(ratchet.bestand);
    if (!bestand.existsSync()) return null;
    return waardeUit(ratchet, bestand.readAsStringSync());
  }

  group('CHECKS.md herhaalt geen enkel getal op eigen gezag', () {
    // Elke bewering van de vorm "currently **N**" moet in dezelfde adem de
    // constante noemen waar dat getal vandaan komt. De vorm is de afspraak:
    // (`naam`, currently **N**) of `naam` (currently **N**). Zonder die naam
    // valt het getal niet na te rekenen en verrot het stil.
    final bewering = RegExp(r'currently \*\*(\d+)%?\*\*');
    final constante = RegExp(r'`(--?[a-z-]+|[A-Za-z_][A-Za-z0-9_]*)`');

    test('elke "currently"-bewering noemt haar constante', () {
      final doc = lees('docs/CHECKS.md');
      final naamloos = <String>[];
      for (final treffer in bewering.allMatches(doc)) {
        // Terugkijken tot het begin van de zin: de naam hoort in dezelfde adem
        // te staan, niet drie alinea's eerder.
        final begin = treffer.start - 160 < 0 ? 0 : treffer.start - 160;
        final aanloop = doc.substring(begin, treffer.start);
        final namen = constante.allMatches(aanloop).toList();
        final laatste = namen.isEmpty ? null : namen.last.group(1);
        if (laatste == null || !vindplaatsen.containsKey(laatste)) {
          naamloos.add('“…${aanloop.split('\n').last}${treffer.group(0)}”');
        }
      }
      expect(
        naamloos,
        isEmpty,
        reason:
            'deze getallen staan in CHECKS.md zonder de constante te noemen '
            'waar ze vandaan komen, en zijn dus niet na te rekenen:\n'
            '  ${naamloos.join('\n  ')}\n'
            'Schrijf ze als (`constanteNaam`, currently **N**).',
      );
    });

    test('elk genoemd getal is het getal dat in de code staat', () {
      final doc = lees('docs/CHECKS.md');
      final fout = <String>[];
      var gecontroleerd = 0;
      for (final treffer in bewering.allMatches(doc)) {
        final begin = treffer.start - 160 < 0 ? 0 : treffer.start - 160;
        final namen = constante
            .allMatches(doc.substring(begin, treffer.start))
            .toList();
        if (namen.isEmpty) continue;
        final naam = namen.last.group(1)!;
        final echt = waardeVan(naam);
        if (echt == null) continue;
        gecontroleerd++;
        final beweerd = int.parse(treffer.group(1)!);
        if (beweerd != echt) {
          fout.add('$naam: CHECKS.md zegt $beweerd, de code zegt $echt');
        }
      }
      expect(
        gecontroleerd,
        greaterThanOrEqualTo(5),
        reason:
            'er werd bijna niets gecontroleerd — waarschijnlijk is de vorm van '
            'de beweringen in CHECKS.md veranderd en kijkt deze test langs de '
            'getallen heen. Dat is erger dan een fout getal.',
      );
      expect(
        fout,
        isEmpty,
        reason:
            'CHECKS.md herhaalt getallen die niet meer kloppen:\n'
            '  ${fout.join('\n  ')}\n'
            'Werk het document bij — een lezer die één getal narekent en het '
            'fout vindt, gelooft de rest ook niet meer.',
      );
    });
  });

  group('de dekkingsvloeren in proza', () {
    test('elk percentage naast het woord "floor" is een echte vloer', () {
      final doc = lees('docs/CHECKS.md');
      final regelVloer = waardeVan('--min');
      final bestandsVloer = waardeVan('perFileFloorPercent');
      expect(regelVloer, isNotNull);
      expect(bestandsVloer, isNotNull);

      // Percentages die in de buurt van het woord "floor" staan gaan over een
      // van de twee vloeren. Een derde getal daar is een verouderde bewering —
      // zo stond er ooit 65 in terwijl de vloer al op 80 lag.
      final vreemd = <String>[];
      // De vooruitblik naar achteren houdt gemeten waarden als "82.5%" buiten
      // beeld: die zijn een uitkomst, geen bewering over de vloer. Zonder hem
      // leest deze test er "5%" in en meldt hij een fout die er niet is.
      for (final treffer in RegExp(r'(?<![\d.])(\d+)%').allMatches(doc)) {
        final van = treffer.start - 40 < 0 ? 0 : treffer.start - 40;
        final tot = treffer.end + 40 > doc.length
            ? doc.length
            : treffer.end + 40;
        final omgeving = doc.substring(van, tot);
        if (!omgeving.contains('floor')) continue;
        final getal = int.parse(treffer.group(1)!);
        if (getal == regelVloer || getal == bestandsVloer) continue;
        vreemd.add(
          '${treffer.group(0)} in “${omgeving.replaceAll('\n', ' ')}”',
        );
      }
      expect(
        vreemd,
        isEmpty,
        reason:
            'deze percentages staan naast het woord "floor" maar zijn geen van '
            'beide vloeren ($regelVloer% en $bestandsVloer%):\n'
            '  ${vreemd.join('\n  ')}',
      );
    });

    test('beide vloeren staan er ook echt in', () {
      // De omgekeerde richting: een test die alleen naar afwijkingen kijkt,
      // blijft groen als het hele onderwerp uit het document verdwijnt.
      final doc = lees('docs/CHECKS.md');
      expect(doc, contains('${waardeVan('--min')}%'));
      expect(doc, contains('${waardeVan('perFileFloorPercent')}%'));
    });
  });

  group('de taaltelling', () {
    // Het PR-sjabloon noemde acht talen tegen een werkelijke 32, en niets zag
    // het. Dat kan overal gebeuren waar een getal met "languages" of "talen"
    // ernaast is opgeschreven.
    final telling = RegExp(r'\b(\d+)\s+(languages|talen)\b');

    List<String> documenten() => [
      'README.md',
      for (final bestand in Directory('docs').listSync())
        if (bestand is File && bestand.path.endsWith('.md')) bestand.path,
    ];

    // Niet elke taaltelling gaat over de interface. Het geloofslexicon van de
    // privacycontrole telt 27 talen omdat EuroVoc er zoveel heeft, en dat getal
    // heeft niets met AppLocalizations te maken. Alleen tellingen die in
    // dezelfde adem over vertalen, lokalisatie of de interface gaan, worden
    // hiertegen gehouden — de rest is een ander onderwerp dat toevallig
    // hetzelfde woord gebruikt.
    const overDeInterface = [
      'interface',
      'translat',
      'localis',
      'localiz',
      'AppLocalizations',
      'l10n',
      "d('",
    ];

    test('elke taaltelling over de interface klopt met AppLocalizations', () {
      final echt = AppLocalizations.languageNames.length;
      final fout = <String>[];
      var gevonden = 0;
      for (final pad in documenten()) {
        final tekst = lees(pad);
        for (final treffer in telling.allMatches(tekst)) {
          final van = treffer.start - 160 < 0 ? 0 : treffer.start - 160;
          final tot = treffer.end + 60 > tekst.length
              ? tekst.length
              : treffer.end + 60;
          final omgeving = tekst.substring(van, tot);
          if (!overDeInterface.any(omgeving.contains)) continue;
          gevonden++;
          final beweerd = int.parse(treffer.group(1)!);
          if (beweerd != echt) fout.add('$pad: "${treffer.group(0)}"');
        }
      }
      expect(
        gevonden,
        greaterThanOrEqualTo(4),
        reason:
            'er werd bijna geen taaltelling gevonden — kijk of de bewoording in '
            'de documentatie veranderd is en deze test er nu langs kijkt',
      );
      expect(
        fout,
        isEmpty,
        reason:
            'deze tellingen wijken af van AppLocalizations.languageNames '
            '($echt talen):\n  ${fout.join('\n  ')}',
      );
    });
  });

  group('de tellingen in ARCHITECTURE en README over de vertaalbestanden', () {
    test('het aantal vertaalbestanden klopt met het aantal talen', () {
      // De bestanden onder lib/l10n/translations/ zijn er één per taal. Loopt
      // dat uiteen, dan is er een taal half toegevoegd — en dan klopt élke
      // telling in de documentatie niet meer, hoe vaak je hem ook narekent.
      final bestanden = Directory('lib/l10n/translations')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .length;
      expect(
        bestanden,
        AppLocalizations.languageNames.length,
        reason:
            'er zijn $bestanden vertaalbestanden en '
            '${AppLocalizations.languageNames.length} geregistreerde talen',
      );
    });
  });
}
