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

  /// Een library mét zijn `part`-bestanden, als één tekst.
  ///
  /// Een meting die op één bestand grept, meet stilzwijgend niets meer zodra
  /// dat bestand langs het regelplafond wordt gesplitst: de constante staat er
  /// dan nog, maar in een part ernaast. Dat overkwam
  /// `defaultCveApiBaseUrl` toen `AppSettings` naar
  /// `models/parts/app_settings.dart` verhuisde.
  String leesLibrary(String pad) {
    final bron = lees(pad);
    final map = File(pad).parent.path;
    final parts = RegExp(
      r"^part\s+'([^']+)';",
      multiLine: true,
    ).allMatches(bron).map((m) => m.group(1)!);
    return [bron, for (final p in parts) lees('$map/$p')].join('\n');
  }

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

  group('de server die de uitgever zelf draait', () {
    // #579: `PRIVACY.md` opende met "no OciDeck server" en `COMPLIANCE.md` zei
    // dat de stichting niets als dienst host — terwijl `cveapi.librekat.nl` in
    // de code als standaard staat. Beide zinnen waren precies de zin die een
    // kritische lezer als eerste natrekt.
    //
    // Wat hier bewaakt wordt is de kóppeling, niet de formulering: zolang de
    // code een host van de uitgever als standaard declareert, moeten de twee
    // documenten die host noemen én mag de absolute claim er niet staan. Zet
    // iemand de standaard om naar een host die niet van de uitgever is, dan
    // vervalt de eis vanzelf — dan is er ook niets meer te melden.
    final settings = leesLibrary('lib/models/settings.dart');
    final standaard = RegExp(
      r"defaultCveApiBaseUrl\s*=\s*'([^']+)'",
    ).firstMatch(settings)?.group(1);

    test('de standaard-mirror staat nog in de code', () {
      // Zonder deze meting meet de rest niets: een hernoemde constante zou de
      // hele groep stilzwijgend groen maken.
      expect(
        standaard,
        isNotNull,
        reason: 'defaultCveApiBaseUrl niet gevonden in de settings-library',
      );
    });

    /// De hostnaam zonder schema, zoals proza hem schrijft.
    final host = standaard == null ? '' : Uri.parse(standaard).host;
    final vanDeUitgever = host.endsWith('librekat.nl');

    test('PRIVACY.md noemt hem bij naam', () {
      if (!vanDeUitgever) return;
      expect(
        lees('docs/PRIVACY.md'),
        contains(host),
        reason:
            'De standaard-CVE-mirror is van de uitgever; PRIVACY.md hoort te '
            'zeggen dat hij bestaat en wat de app ernaartoe stuurt.',
      );
    });

    test('COMPLIANCE.md noemt hem ook', () {
      if (!vanDeUitgever) return;
      expect(
        lees('COMPLIANCE.md'),
        contains(host),
        reason:
            'COMPLIANCE.md zegt wat de stichting wél en niet doet; één '
            'draaiende dienst hoort daarbij.',
      );
    });

    /// De tekst zónder de cursieve correctienotities.
    ///
    /// Deze repo citeert in zo'n notitie bewust de oude, onware zin — dat is
    /// hoe je later terugvindt wat er stond en waarom het veranderde. Een poort
    /// die op de kale zin zoekt zou dus precies de correctie bestraffen die hij
    /// wilde afdwingen. Beweringen tellen; geschiedenis niet.
    String zonderCorrecties(String tekst) =>
        tekst.replaceAll(RegExp(r'\*\(?Corrected.*?\)?\*', dotAll: true), '');

    test('en de absolute claim staat er niet meer', () {
      if (!vanDeUitgever) return;
      // Precies de zin die onwaar werd. Niet op "server" in het algemeen — dat
      // woord komt terecht tientallen keren voor over servers van de gebruiker.
      expect(
        zonderCorrecties(lees('docs/PRIVACY.md')),
        isNot(contains('no OciDeck server')),
        reason:
            'Er draait er wél één. Schrijf op wat waar is ("no server that '
            'holds your decks"), niet wat prettig klinkt.',
      );
      expect(
        zonderCorrecties(lees('COMPLIANCE.md')),
        isNot(contains('host it as a service')),
        reason:
            'Die zin las als "de stichting draait geen servers". Ze draait er '
            'één, en dat hoort in dezelfde alinea te staan.',
      );
    });

    test('PRIVACY.md wijst de verantwoordelijke aan', () {
      if (!vanDeUitgever) return;
      final privacy = lees('docs/PRIVACY.md');
      // Een dienst zonder aanwijsbare verwerkingsverantwoordelijke is precies
      // het gat waar dit issue over ging: niet de gebruiker, en niet "niemand".
      expect(privacy, contains('controller'));
      expect(privacy, contains('Stichting LibreKAT'));
    });
  });

  group('de webdemo die de uitgever zelf draait', () {
    // #589: de README kreeg een link naar `ocideck.librekat.nl`, een gratis
    // publieke kopie van de webbouw op een oorsprong van de stichting. Dat is
    // hosten, en `COMPLIANCE.md` zei op dat moment nog dat de stichting
    // OciDeck niet als dienst host en precies één server draait — de tweede
    // absolute claim die bleef staan nadat #579 de eerste had opgeruimd.
    //
    // Wat hier bewaakt wordt is de kóppeling, en de README is de bron: zodra
    // een document van de uitgever een host op `librekat.nl` naar buiten toe
    // aanprijst, moeten de twee documenten die zeggen wat de stichting draait
    // die host ook noemen. Haal de link weg en de eis vervalt vanzelf — dan is
    // er ook niets meer aan te prijzen.
    /// Hosts op `librekat.nl` die een tekst als adres noemt.
    ///
    /// Alleen echte hostnamen: een e-mailadres als `security@librekat.nl`
    /// noemt geen server, en het `@` ervoor is precies wat dat onderscheidt.
    Set<String> hostenIn(String tekst) => RegExp(
      r'(?<![\w@.])([a-z0-9-]+\.librekat\.nl)',
    ).allMatches(tekst).map((m) => m.group(1)!).toSet();

    final hosts = hostenIn(lees('README.md'));

    test('de meting onderscheidt een host van een e-mailadres', () {
      // Zonder deze toets meet de rest niets: een regex die niets meer vangt
      // zou de hele groep stilzwijgend groen maken. Bewust op een vaste zin en
      // niet op de README zelf — verdwijnt de demolink ooit, dan hóórt de eis
      // te vervallen en niet de poort om te vallen.
      expect(
        hostenIn('zie <https://demo.librekat.nl/> of mail a@librekat.nl'),
        {'demo.librekat.nl'},
      );
    });

    for (final bestand in const ['COMPLIANCE.md', 'docs/PRIVACY.md']) {
      test('$bestand noemt elke aangeprezen host', () {
        for (final host in hosts) {
          expect(
            lees(bestand),
            contains(host),
            reason:
                'De README stuurt lezers naar $host. $bestand zegt wat de '
                'stichting draait en waarvoor zij verwerkingsverantwoordelijke '
                'is; een host die de README aanprijst en dit document niet '
                'kent is de eerste zin die een kritische lezer natrekt.',
          );
        }
      });
    }

    test('COMPLIANCE.md beweert niet meer dat de stichting niets host', () {
      // Precies de zin die onwaar werd, buiten de correctienotities om — die
      // citeren hem bewust.
      final tekst = lees(
        'COMPLIANCE.md',
      ).replaceAll(RegExp(r'\*\(?Corrected.*?\)?\*', dotAll: true), '');

      expect(
        tekst,
        isNot(contains('does not host OciDeck itself as a service')),
      );
      expect(tekst, isNot(contains('It does run **one** service')));
    });
  });
}
