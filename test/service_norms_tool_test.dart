import 'package:flutter_test/flutter_test.dart';

import '../tool/check_service_norms.dart';

/// Het meetinstrument voor de servicenormen (`tool/check_service_norms.dart`).
///
/// Er is nog geen enkele echte melding — geen release, geen incident. Dat is
/// juist de reden dat dit met verzonnen invoer wordt getoetst: het instrument
/// moet aantoonbaar werken vóórdat de eerste melding binnenkomt, niet erna.
///
/// Alle datums zijn verzonnen en alle melders heten `melder` of `beheerder`.
/// Er staat geen persoonsgegeven en geen sleutel in dit bestand.
void main() {
  group('werkdagen', () {
    test('pasen valt waar de kerk hem legt', () {
      // Ankerjaren; het hele feestdagenrooster hangt hieraan.
      expect(paaszondag(2026), DateTime(2026, 4, 5));
      expect(paaszondag(2027), DateTime(2027, 3, 28));
      expect(paaszondag(2024), DateTime(2024, 3, 31));
    });

    test('een weekend telt niet mee', () {
      // Vrijdag 3 juli 2026 → maandag 6 juli 2026 is één werkdag.
      expect(werkdagenTussen(DateTime(2026, 7, 3), DateTime(2026, 7, 6)), 1);
      // Vrijdag → zaterdag is er geen.
      expect(werkdagenTussen(DateTime(2026, 7, 3), DateTime(2026, 7, 4)), 0);
      // Dezelfde dag ook niet.
      expect(werkdagenTussen(DateTime(2026, 7, 3), DateTime(2026, 7, 3)), 0);
    });

    test('een feestdag telt niet mee', () {
      // Tweede kerstdag 2025 valt op een vrijdag. Do 24 dec → ma 29 dec is dus
      // 1 werkdag (donderdag 25e en vrijdag 26e zijn kerst, weekend erna).
      expect(
        werkdagenTussen(DateTime(2025, 12, 24), DateTime(2025, 12, 29)),
        1,
      );
      expect(isWerkdag(DateTime(2026, 1, 1)), isFalse);
      // Tweede paasdag 2026: maandag 6 april.
      expect(isWerkdag(DateTime(2026, 4, 6)), isFalse);
      // De dinsdag erna is een gewone werkdag.
      expect(isWerkdag(DateTime(2026, 4, 7)), isTrue);
    });

    test('koningsdag wijkt voor de zondag', () {
      // 27 april 2025 is een zondag; dan is de 26e de vrije dag. Beide vallen
      // in het weekend, dus dit toetst vooral de verschuiving zelf.
      expect(feestdagen(2025), contains(DateTime(2025, 4, 26)));
      expect(feestdagen(2025), isNot(contains(DateTime(2025, 4, 27))));
      // 27 april 2026 is een maandag en dus een echte vrije werkdag.
      expect(isWerkdag(DateTime(2026, 4, 27)), isFalse);
    });

    test('een lange termijn telt alleen de werkdagen', () {
      // Wo 1 juli 2026 → wo 15 juli 2026: twee volle weken, 10 werkdagen.
      expect(werkdagenTussen(DateTime(2026, 7, 1), DateTime(2026, 7, 15)), 10);
    });

    test('kalenderdagen tellen wél gewoon door', () {
      expect(
        kalenderdagenTussen(DateTime(2026, 7, 1), DateTime(2026, 7, 15)),
        14,
      );
      // Terug in de tijd is geen negatieve afstand maar geen afstand.
      expect(
        kalenderdagenTussen(DateTime(2026, 7, 15), DateTime(2026, 7, 1)),
        0,
      );
    });
  });

  group('een melding langs de normen', () {
    // Woensdag 1 juli 2026. Alles hieronder rekent vanaf dat moment.
    final gemeld = DateTime(2026, 7, 1, 9);

    ServiceNorm normMet(String id) =>
        serviceNormen.firstWhere((n) => n.id == id);

    Meting meet(String id, Melding melding, DateTime nu) =>
        beoordeel(norm: normMet(id), melding: melding, nu: nu);

    test('op tijd beantwoord heet gehaald', () {
      final melding = Melding(
        nummer: 1,
        gemeld: gemeld,
        eersteReactie: DateTime(2026, 7, 3, 11),
      );
      final m = meet('eerste-reactie', melding, DateTime(2026, 7, 20));
      expect(m.stand, Stand.gehaald);
      expect(m.verstreken, 2);
    });

    test('te laat beantwoord blijft overschreden, ook al is het af', () {
      // 20 juli is elf werkdagen later; de norm is vijf.
      final melding = Melding(
        nummer: 2,
        gemeld: gemeld,
        eersteReactie: DateTime(2026, 7, 20, 9),
      );
      final m = meet('eerste-reactie', melding, DateTime(2026, 8, 1));
      expect(m.stand, Stand.overschreden);
      expect(m.afgerond, isTrue);
    });

    test('een lopende termijn dreigt vóór hij verloopt', () {
      final melding = Melding(nummer: 3, gemeld: gemeld);
      // Twee werkdagen later: nog niets aan de hand.
      expect(
        meet('eerste-reactie', melding, DateTime(2026, 7, 3)).stand,
        Stand.loopt,
      );
      // Vier werkdagen later: de waarschuwingsdrempel. Dit is het hele punt —
      // je hoort het vóór de vijfde dag, niet erna.
      expect(
        meet('eerste-reactie', melding, DateTime(2026, 7, 7)).stand,
        Stand.dreigt,
      );
      // Zes werkdagen later: eroverheen.
      expect(
        meet('eerste-reactie', melding, DateTime(2026, 7, 9)).stand,
        Stand.overschreden,
      );
    });

    test('sluiten stopt elke klok', () {
      // Zelf gemeld, zelf afgehandeld: er is nooit een ander bij geweest. Zonder
      // deze regel zou zo'n melding voor eeuwig als onbeantwoord staan.
      final melding = Melding(
        nummer: 4,
        gemeld: gemeld,
        gesloten: DateTime(2026, 7, 2, 16),
      );
      expect(
        meet('eerste-reactie', melding, DateTime(2027, 1, 1)).stand,
        Stand.gehaald,
      );
      expect(
        meet('oordeel', melding, DateTime(2027, 1, 1)).stand,
        Stand.gehaald,
      );
    });

    test('ruis valt buiten de oplossingsnorm', () {
      final melding = Melding(
        nummer: 5,
        gemeld: gemeld,
        eersteReactie: DateTime(2026, 7, 2),
        oordeelOp: DateTime(2026, 7, 6),
      );
      final m = meet('oplossing', melding, DateTime(2027, 6, 1));
      expect(m.stand, Stand.nietVanToepassing);
      expect(m.vraagtAandacht, isFalse);
    });

    test('een bevestigde melding loopt wél tegen de 90 dagen aan', () {
      final melding = Melding(
        nummer: 6,
        gemeld: gemeld,
        eersteReactie: DateTime(2026, 7, 2),
        oordeelOp: DateTime(2026, 7, 6),
        bevestigd: true,
      );
      // Dag 80: over de waarschuwingsdrempel van 75, nog binnen de norm.
      final dag80 = meet('oplossing', melding, gemeld.add(Duration(days: 80)));
      expect(dag80.stand, Stand.dreigt);
      expect(dag80.verstreken, 80);
      // Dag 91: eroverheen.
      expect(
        meet('oplossing', melding, gemeld.add(Duration(days: 91))).stand,
        Stand.overschreden,
      );
    });

    test('een eerder afgesproken datum wint van de norm', () {
      // "Binnen 90 dagen of eerder in overleg": de afspraak staat als due date
      // op de melding, dus daar meet het tegen.
      final melding = Melding(
        nummer: 7,
        gemeld: gemeld,
        eersteReactie: DateTime(2026, 7, 2),
        oordeelOp: DateTime(2026, 7, 6),
        bevestigd: true,
        afgesprokenUiterlijk: DateTime(2026, 7, 31),
      );
      final m = meet('oplossing', melding, gemeld.add(Duration(days: 45)));
      expect(m.limiet, 30);
      expect(m.stand, Stand.overschreden);
      // De waarschuwing schuift mee: op 25 van de 30, niet op 75.
      expect(waarschuwingsdrempel(normMet('oplossing'), 30), 25);
    });

    test('een latere afspraak rekt de norm niet op', () {
      final melding = Melding(
        nummer: 8,
        gemeld: gemeld,
        bevestigd: true,
        afgesprokenUiterlijk: gemeld.add(const Duration(days: 200)),
      );
      expect(
        meet('oplossing', melding, gemeld.add(Duration(days: 95))).limiet,
        90,
      );
    });

    test('elke melding levert een meting per norm op', () {
      final metingen = meetAlles([
        Melding(nummer: 9, gemeld: gemeld),
      ], DateTime(2026, 7, 2));
      expect(metingen, hasLength(serviceNormen.length));
    });
  });

  group('de forge uitlezen', () {
    test('het adres komt uit de remote, in welke vorm dan ook', () {
      // Verzonnen host; het gaat om de vorm, niet om de plek.
      const vormen = [
        'ssh://git@forge.voorbeeld.test:2222/Groep/Project.git',
        'git@forge.voorbeeld.test:Groep/Project.git',
        'https://forge.voorbeeld.test/Groep/Project.git',
        'https://forge.voorbeeld.test/Groep/Project',
      ];
      for (final vorm in vormen) {
        final adres = forgeUit(vorm);
        expect(adres, isNotNull, reason: vorm);
        expect(adres!.host, 'forge.voorbeeld.test', reason: vorm);
        expect(adres.eigenaar, 'Groep', reason: vorm);
        expect(adres.repo, 'Project', reason: vorm);
        // De git-poort mag niet meeliften naar de API, en de API gaat over
        // https ook al praat git over ssh.
        expect(
          adres.api.toString(),
          startsWith('https://forge.voorbeeld.test/'),
        );
        expect(adres.api.toString(), isNot(contains('2222')));
      }
    });

    test('een remote die nergens op lijkt geeft null', () {
      expect(forgeUit('dit is geen url'), isNull);
      expect(forgeUit(''), isNull);
    });

    test('de scp-vorm pakt geen ssh-url af', () {
      // Zonder vooruitblik leest die vorm de poort als eigenaar. Dat gaat nu
      // alleen goed door de volgorde van de patronen — een afhankelijkheid
      // die niemand ziet tot iemand de lijst herschikt.
      final adres = forgeUit(
        'ssh://git@forge.voorbeeld.test:2222/Groep/P.git',
      )!;
      expect(adres.eigenaar, 'Groep');
      expect(adres.eigenaar, isNot('2222'));
    });

    Map<String, Object?> issue({
      required int nummer,
      List<String> labels = const ['beveiliging'],
      String melder = 'melder',
      String gemeld = '2026-07-01T09:00:00Z',
      String? gesloten,
      String? uiterlijk,
    }) => {
      'number': nummer,
      'created_at': gemeld,
      'closed_at': gesloten,
      'due_date': uiterlijk,
      'user': {'login': melder},
      'labels': [
        for (final naam in labels) {'name': naam},
      ],
    };

    Map<String, Object?> gebeurtenis({
      required String type,
      required String wie,
      required String wanneer,
      String? label,
      String? inhoud,
    }) {
      final labelDeel = label == null ? null : <String, String>{'name': label};
      return {
        'type': type,
        'created_at': wanneer,
        'user': {'login': wie},
        'label': ?labelDeel,
        'content': ?inhoud,
      };
    }

    test('zonder beveiligingslabel is het geen melding', () {
      expect(meldingUit(issue(nummer: 1, labels: ['bug']), const []), isNull);
      expect(meldingUit(issue(nummer: 1, labels: []), const []), isNull);
      // Hoofdletters horen er niet toe te doen.
      expect(
        meldingUit(issue(nummer: 1, labels: ['Beveiliging']), const []),
        isNotNull,
      );
    });

    test('de eerste reactie is die van iemand anders dan de melder', () {
      final melding = meldingUit(issue(nummer: 12), [
        // De melder die zichzelf aanvult is geen reactie.
        gebeurtenis(
          type: 'comment',
          wie: 'melder',
          wanneer: '2026-07-01T10:00:00Z',
        ),
        gebeurtenis(
          type: 'comment',
          wie: 'beheerder',
          wanneer: '2026-07-02T11:00:00Z',
        ),
        gebeurtenis(
          type: 'comment',
          wie: 'beheerder',
          wanneer: '2026-07-03T11:00:00Z',
        ),
      ])!;
      expect(melding.nummer, 12);
      expect(melding.eersteReactie, DateTime.parse('2026-07-02T11:00:00Z'));
    });

    test('een automatische kruisverwijzing is geen reactie', () {
      // De forge maakt deze zelf aan zodra elders naar de melding verwezen
      // wordt. Zou die de klok stoppen, dan meet dit gereedschap zichzelf een
      // reactie aan die niemand gegeven heeft.
      final melding = meldingUit(issue(nummer: 13), [
        gebeurtenis(
          type: 'commit_ref',
          wie: 'iemand-anders',
          wanneer: '2026-07-01T10:00:00Z',
        ),
      ])!;
      expect(melding.eersteReactie, isNull);
    });

    test('het oordeel is het eerste oordeellabel, de uitkomst het huidige', () {
      final melding =
          meldingUit(issue(nummer: 14, labels: ['beveiliging', 'bevestigd']), [
            gebeurtenis(
              type: 'label',
              wie: 'beheerder',
              wanneer: '2026-07-06T09:00:00Z',
              label: 'ruis',
              inhoud: '1',
            ),
            gebeurtenis(
              type: 'label',
              wie: 'beheerder',
              wanneer: '2026-07-20T09:00:00Z',
              label: 'bevestigd',
              inhoud: '1',
            ),
          ])!;
      // Het oordeel is op de 6e geveld, ook al is het later herzien: de
      // oordeelnorm gaat over hoe snel er geoordeeld is.
      expect(melding.oordeelOp, DateTime.parse('2026-07-06T09:00:00Z'));
      // De uitkomst is wat er nú staat.
      expect(melding.bevestigd, isTrue);
    });

    test('een weggehaald label is geen oordeel', () {
      final melding = meldingUit(issue(nummer: 15), [
        gebeurtenis(
          type: 'label',
          wie: 'beheerder',
          wanneer: '2026-07-06T09:00:00Z',
          label: 'ruis',
          inhoud: '0',
        ),
      ])!;
      expect(melding.oordeelOp, isNull);
    });

    test('een leeg tijdstip is geen datum', () {
      // Forgejo schrijft een niet-gezette datum als het jaar 1.
      final melding = meldingUit(
        issue(nummer: 16, gesloten: '0001-01-01T00:00:00Z'),
        const [],
      )!;
      expect(melding.gesloten, isNull);
      expect(melding.afgesprokenUiterlijk, isNull);
    });
  });

  group('het rapport', () {
    const bron = 'https://forge.voorbeeld.test/Groep/Project';
    final nu = DateTime(2026, 7, 22);

    test('nul metingen zegt nadrukkelijk niet dat het goed gaat', () {
      final regels = rapport(meldingen: const [], nu: nu, bron: bron);
      final tekst = regels.join('\n');
      expect(tekst, contains('Er is niets gemeten'));
      expect(tekst, contains('geen bewijs dat de normen gehaald worden'));
      // De normen staan er wél, met het voorbehoud erbij.
      expect(tekst, contains('geen toezegging aan derden'));
      expect(exitCodeVoor(meetAlles(const [], nu)), 0);
    });

    test('een overschrijding kleurt de uitkomst rood', () {
      final metingen = meetAlles([
        Melding(nummer: 20, gemeld: DateTime(2026, 6, 1)),
      ], nu);
      expect(exitCodeVoor(metingen), 1);
      expect(
        rapport(
          meldingen: [Melding(nummer: 20, gemeld: DateTime(2026, 6, 1))],
          nu: nu,
          bron: bron,
        ).join('\n'),
        contains('OVERSCHREDEN'),
      );
    });

    test('een dreiging meldt zich maar laat de poort groen', () {
      // Vier werkdagen open: over de waarschuwingsdrempel, binnen de norm.
      final melding = Melding(nummer: 21, gemeld: DateTime(2026, 7, 16));
      final metingen = meetAlles([melding], nu);
      expect(exitCodeVoor(metingen), 0);
      expect(ietsTeMelden(metingen), isTrue);
      expect(
        rapport(meldingen: [melding], nu: nu, bron: bron).join('\n'),
        contains('DREIGT'),
      );
    });

    test('quiet zwijgt als er niets aan de hand is, en anders niet', () {
      // Vandaag gemeld: alles loopt nog.
      final rustig = Melding(nummer: 22, gemeld: nu);
      expect(
        rapport(meldingen: [rustig], nu: nu, bron: bron, quiet: true),
        isEmpty,
      );
      // Ook een lege verzameling hoort in cron niets te zeggen.
      expect(
        rapport(meldingen: const [], nu: nu, bron: bron, quiet: true),
        isEmpty,
      );
      // Maar een te oude melding wél.
      final oud = Melding(nummer: 23, gemeld: DateTime(2026, 6, 1));
      expect(
        rapport(
          meldingen: [rustig, oud],
          nu: nu,
          bron: bron,
          quiet: true,
        ).join('\n'),
        allOf(contains('#23'), isNot(contains('#22'))),
      );
    });

    test('het rapport draagt geen titel of melder mee', () {
      // Wat hier uit komt kan in een cron-mail belanden. De inhoud van een
      // openstaande kwetsbaarheidsmelding hoort daar niet in.
      final tekst = rapport(
        meldingen: [Melding(nummer: 24, gemeld: DateTime(2026, 6, 1))],
        nu: nu,
        bron: bron,
      ).join('\n');
      expect(tekst, contains('#24'));
      expect(tekst.toLowerCase(), isNot(contains('melder')));
    });
  });
}
