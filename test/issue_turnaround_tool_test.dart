import 'package:flutter_test/flutter_test.dart';

import '../tool/check_issue_turnaround.dart';

/// Het meetinstrument voor de doorlooptijd van gewone issues
/// (`tool/check_issue_turnaround.dart`).
///
/// Alle invoer hieronder is verzonnen: verzonnen nummers, verzonnen datums,
/// indieners die `indiener` en `beheerder` heten. Er staat geen sleutel in dit
/// bestand en er gaat geen enkele netwerkvraag uit — de ophaallaag van het
/// gereedschap is een aparte laag (`ForgeGegevens`) juist zodat het rekenwerk
/// zonder forge te toetsen is.
///
/// Elke meting wordt in twee richtingen getoetst: schoon op een tracker waar
/// niets aan de hand is, en sprekend op een geplante afwijking. Een meting die
/// alleen bij problemen is beproefd, kan een vals alarm zijn dat niemand ooit
/// zag.
void main() {
  // Woensdag 22 juli 2026 is overal het peilmoment.
  final nu = DateTime(2026, 7, 22, 12);

  DateTime dagenGeleden(int dagen) => nu.subtract(Duration(days: dagen));

  TrackerIssue issue({
    required int nummer,
    required int openSinds,
    int? reactieNa,
    int? geslotenNa,
    Set<String> labels = const {},
  }) => TrackerIssue(
    nummer: nummer,
    geopend: dagenGeleden(openSinds),
    eersteReactie: reactieNa == null
        ? null
        : dagenGeleden(openSinds - reactieNa),
    gesloten: geslotenNa == null ? null : dagenGeleden(openSinds - geslotenNa),
    labels: labels,
  );

  group('leeftijd en reactietijd', () {
    test('een open issue telt door tot het peilmoment', () {
      expect(issue(nummer: 1, openSinds: 12).leeftijd(nu), 12);
    });

    test('een gesloten issue stopt bij de sluiting', () {
      // Veertig dagen geleden geopend, drie dagen later gesloten.
      final gesloten = issue(nummer: 2, openSinds: 40, geslotenNa: 3);
      expect(gesloten.leeftijd(nu), 3);
      expect(gesloten.isOpen, isFalse);
    });

    test('sluiten zonder een woord telt niet als reactie', () {
      // Dit is het randgeval dat het hele instrument bestaansrecht geeft: een
      // issue dat stilzwijgend werd gesloten ziet er in elke telling af uit,
      // terwijl de indiener nooit antwoord kreeg.
      final zwijgend = issue(nummer: 3, openSinds: 20, geslotenNa: 1);
      expect(zwijgend.dagenTotReactie(), isNull);
    });

    test('een reactie levert een afstand in hele dagen', () {
      expect(
        issue(nummer: 4, openSinds: 10, reactieNa: 2).dagenTotReactie(),
        2,
      );
    });
  });

  group('de mediaan', () {
    test('een lege lijst heeft er geen', () {
      expect(mediaan(const []), isNull);
    });

    test('oneven aantal: het middelste getal', () {
      expect(mediaan([9, 1, 5]), 5);
    });

    test('even aantal: de bovenste van de twee middelste', () {
      // Bewust naar boven: dit getal moet traagheid laten zien, niet verbergen.
      expect(mediaan([1, 2, 3, 4]), 3);
    });

    test('één uitschieter verplaatst de mediaan niet', () {
      // Het gemiddelde van deze reeks is 205; de mediaan blijft 2. Dat is de
      // hele reden dat hier geen gemiddelde staat.
      expect(mediaan([1, 2, 2, 3, 1000]), 2);
    });
  });

  group('het beeld op een rustige tracker', () {
    // Twee open issues, beide binnen een dag beantwoord, en een gesloten issue.
    final rustig = [
      issue(nummer: 10, openSinds: 30, reactieNa: 1, geslotenNa: 4),
      issue(nummer: 11, openSinds: 6, reactieNa: 1),
      issue(nummer: 12, openSinds: 2, reactieNa: 0),
    ];

    test('er is geen signaal', () {
      final beeld = meet(rustig, nu);
      expect(beeld.vraagtAandacht, isFalse);
      expect(beeld.zonderReactie, isEmpty);
      expect(beeld.triageStilstand, isEmpty);
      expect(exitCodeVoor(beeld), 0);
    });

    test('de tellingen kloppen', () {
      final beeld = meet(rustig, nu);
      expect(beeld.open.length, 2);
      expect(beeld.gesloten, 1);
      expect(beeld.oudste!.nummer, 11);
      expect(beeld.medianeReactietijd, 1);
      expect(beeld.beantwoord, 3);
    });

    test('onder --quiet zegt het niets', () {
      expect(
        rapport(issues: rustig, nu: nu, bron: 'forge', quiet: true),
        isEmpty,
      );
    });

    test('zonder --quiet zegt het wél iets, maar geen goedkeuring', () {
      final tekst = rapport(issues: rustig, nu: nu, bron: 'forge').join('\n');
      expect(tekst, contains('Geen signaal'));
      expect(tekst, contains('geen goedkeuring'));
    });

    test('het slot beweert niet dat alles beantwoord is', () {
      // Een open issue van drie dagen zonder reactie geeft geen signaal — het
      // is te jong voor de drempel. Het slot mocht daar ooit "elk open issue is
      // beantwoord" van maken; dat was aantoonbaar onwaar en precies de
      // geruststelling die dit instrument moet vermijden.
      final jong = [issue(nummer: 13, openSinds: 3)];
      final beeld = meet(jong, nu);
      expect(beeld.vraagtAandacht, isFalse);
      final tekst = rapport(issues: jong, nu: nu, bron: 'forge').join('\n');
      expect(tekst, contains('Geen signaal'));
      expect(tekst, isNot(contains('elk open issue is beantwoord')));
      expect(tekst, contains('Zonder enige reactie: 1 van 1'));
    });
  });

  group('het beeld op een geplante afwijking', () {
    // Eén issue van 100 dagen dat nooit antwoord kreeg, en één dat al 60 dagen
    // op triage staat.
    final scheef = [
      issue(nummer: 20, openSinds: 100),
      issue(nummer: 21, openSinds: 60, reactieNa: 1, labels: {'triage'}),
      issue(nummer: 22, openSinds: 3, reactieNa: 1),
    ];

    test('het onbeantwoorde issue komt bovenaan te staan', () {
      final beeld = meet(scheef, nu);
      expect(beeld.zonderReactie.map((i) => i.nummer), [20]);
      expect(beeld.langZonderReactie.map((i) => i.nummer), [20]);
      expect(beeld.oudste!.nummer, 20);
      expect(beeld.vraagtAandacht, isTrue);
      expect(exitCodeVoor(beeld), 1);
    });

    test('het vastgelopen triage-issue wordt apart genoemd', () {
      final beeld = meet(scheef, nu);
      expect(beeld.triageStilstand.map((i) => i.nummer), [21]);
    });

    test('onder --quiet zwijgt het niet meer', () {
      final tekst = rapport(
        issues: scheef,
        nu: nu,
        bron: 'forge',
        quiet: true,
      ).join('\n');
      expect(tekst, contains('#20'));
      expect(tekst, contains('100 dagen'));
      expect(tekst, contains('zwaarst telt'));
      expect(tekst, contains('#21'));
    });

    test('de uitvoer draagt geen titel en geen indiener', () {
      // Dit rapport kan in een cron-mail belanden. Nummers en datums mogen
      // daar staan; de inhoud van andermans issue niet.
      final tekst = rapport(issues: scheef, nu: nu, bron: 'forge').join('\n');
      expect(tekst, isNot(contains('indiener')));
      expect(tekst, isNot(contains('@')));
    });
  });

  group('de drempels zitten waar ze zeggen te zitten', () {
    test('één dag onder de drempel is nog geen signaal', () {
      final net = [issue(nummer: 30, openSinds: geenReactieSignaalDagen - 1)];
      final beeld = meet(net, nu);
      expect(beeld.zonderReactie, hasLength(1));
      expect(beeld.langZonderReactie, isEmpty);
      expect(beeld.vraagtAandacht, isFalse);
    });

    test('precies op de drempel is het dat wel', () {
      final net = [issue(nummer: 31, openSinds: geenReactieSignaalDagen)];
      expect(meet(net, nu).langZonderReactie, hasLength(1));
    });

    test('triage telt pas na de stilstandsdrempel', () {
      final vlak = [
        issue(
          nummer: 32,
          openSinds: triageStilstandDagen - 1,
          reactieNa: 0,
          labels: {'triage'},
        ),
      ];
      expect(meet(vlak, nu).triageStilstand, isEmpty);
      final over = [
        issue(
          nummer: 33,
          openSinds: triageStilstandDagen,
          reactieNa: 0,
          labels: {'triage'},
        ),
      ];
      expect(meet(over, nu).triageStilstand, hasLength(1));
    });

    test('een gesloten triage-issue telt niet als stilstand', () {
      final af = [
        issue(
          nummer: 34,
          openSinds: 200,
          reactieNa: 0,
          geslotenNa: 2,
          labels: {'triage'},
        ),
      ];
      expect(meet(af, nu).triageStilstand, isEmpty);
    });
  });

  group('de lege tracker', () {
    test('nul metingen is geen goed nieuws', () {
      final tekst = rapport(issues: const [], nu: nu, bron: 'forge').join('\n');
      expect(tekst, contains('niets gemeten'));
      expect(tekst, contains('geen bewijs dat het goed gaat'));
    });

    test(
      'geen open issues, wel gesloten: dan valt er geen leeftijd te meten',
      () {
        final alles = [
          issue(nummer: 40, openSinds: 9, reactieNa: 1, geslotenNa: 2),
        ];
        final tekst = rapport(issues: alles, nu: nu, bron: 'forge').join('\n');
        expect(tekst, contains('Geen open issues'));
      },
    );
  });

  group('de forge-JSON ontleden', () {
    // Vaste gegevens in de vorm die Forgejo teruggeeft. Verzonnen, en met de
    // velden die dit gereedschap werkelijk leest.
    Map<String, Object?> ruwIssue({
      required int nummer,
      required String geopend,
      String? gesloten,
      List<String> labels = const [],
      String indiener = 'indiener',
      bool isPull = false,
    }) => {
      'number': nummer,
      'created_at': geopend,
      'closed_at': gesloten ?? '0001-01-01T00:00:00Z',
      'labels': [
        for (final naam in labels) {'name': naam},
      ],
      'user': {'login': indiener},
      if (isPull) 'pull_request': {'merged': false},
    };

    Map<String, Object?> ruweReactie({
      required int nummer,
      required String wanneer,
      String door = 'beheerder',
      bool alsPull = false,
    }) => {
      'created_at': wanneer,
      'user': {'login': door},
      'issue_url': alsPull
          ? ''
          : 'https://forge/api/v1/repos/x/y/issues/$nummer',
      'html_url': alsPull
          ? 'https://forge/x/y/pulls/$nummer#issuecomment-1'
          : 'https://forge/x/y/issues/$nummer#issuecomment-1',
    };

    test('een gewoon issue met een reactie komt er compleet uit', () {
      final issues = issuesUit(
        [ruwIssue(nummer: 100, geopend: '2026-07-01T09:00:00Z')],
        [ruweReactie(nummer: 100, wanneer: '2026-07-03T09:00:00Z')],
      );
      expect(issues, hasLength(1));
      expect(issues.single.nummer, 100);
      expect(issues.single.dagenTotReactie(), 2);
      expect(issues.single.isOpen, isTrue);
    });

    test('een reactie van de indiener zelf is geen antwoord', () {
      // Iemand die zijn eigen issue aanvult, heeft nog steeds geen antwoord.
      final issues = issuesUit(
        [ruwIssue(nummer: 101, geopend: '2026-07-01T09:00:00Z')],
        [
          ruweReactie(
            nummer: 101,
            wanneer: '2026-07-02T09:00:00Z',
            door: 'indiener',
          ),
        ],
      );
      expect(issues.single.eersteReactie, isNull);
    });

    test('de vroegste reactie wint, ongeacht de volgorde in de lijst', () {
      final issues = issuesUit(
        [ruwIssue(nummer: 102, geopend: '2026-07-01T09:00:00Z')],
        [
          ruweReactie(nummer: 102, wanneer: '2026-07-09T09:00:00Z'),
          ruweReactie(nummer: 102, wanneer: '2026-07-02T09:00:00Z'),
        ],
      );
      expect(issues.single.dagenTotReactie(), 1);
    });

    test('een pull request telt niet mee', () {
      final issues = issuesUit([
        ruwIssue(nummer: 103, geopend: '2026-07-01T09:00:00Z', isPull: true),
        ruwIssue(nummer: 104, geopend: '2026-07-01T09:00:00Z'),
      ], const []);
      expect(issues.map((i) => i.nummer), [104]);
    });

    test('een reactie op een pull request hoort bij geen issue', () {
      // Forgejo laat `issue_url` leeg bij een PR-reactie; de html_url wijst dan
      // naar /pulls/. Zonder dit onderscheid zou PR #105 als antwoord op issue
      // #105 gelden.
      expect(
        issuenummerVanReactie(
          ruweReactie(nummer: 105, wanneer: 'x', alsPull: true),
        ),
        isNull,
      );
      expect(
        issuenummerVanReactie(ruweReactie(nummer: 105, wanneer: 'x')),
        105,
      );
    });

    test('een beveiligingsmelding valt af — die heeft haar eigen meting', () {
      final issues = issuesUit([
        ruwIssue(
          nummer: 106,
          geopend: '2026-07-01T09:00:00Z',
          labels: ['Security'],
        ),
        ruwIssue(nummer: 107, geopend: '2026-07-01T09:00:00Z'),
      ], const []);
      expect(issues.map((i) => i.nummer), [107]);
    });

    test('het lege jaar-1-tijdstip van Forgejo is geen sluiting', () {
      final issues = issuesUit([
        ruwIssue(nummer: 108, geopend: '2026-07-01T09:00:00Z'),
      ], const []);
      expect(issues.single.gesloten, isNull);
      expect(issues.single.isOpen, isTrue);
    });

    test('een gesloten issue draagt zijn sluitingsdatum', () {
      final issues = issuesUit([
        ruwIssue(
          nummer: 109,
          geopend: '2026-07-01T09:00:00Z',
          gesloten: '2026-07-05T09:00:00Z',
        ),
      ], const []);
      expect(issues.single.isOpen, isFalse);
      expect(issues.single.leeftijd(nu), 4);
    });

    test('labels komen in kleine letters binnen', () {
      final issues = issuesUit([
        ruwIssue(
          nummer: 110,
          geopend: '2026-07-01T09:00:00Z',
          labels: ['Triage'],
        ),
      ], const []);
      expect(issues.single.labels, contains('triage'));
      expect(issues.single.wachtOpWeging, isTrue);
    });
  });

  group('het forge-adres uit een remote', () {
    test('ssh, scp en https leiden naar dezelfde plek', () {
      for (final remote in [
        'ssh://git@forge.example/Groep/Project.git',
        'git@forge.example:Groep/Project.git',
        'https://forge.example/Groep/Project.git',
      ]) {
        final adres = forgeUit(remote);
        expect(adres, isNotNull, reason: remote);
        expect(adres!.host, 'forge.example');
        expect(adres.eigenaar, 'Groep');
        expect(adres.repo, 'Project');
        expect(adres.api.scheme, 'https');
      }
    });

    test('onzin levert niets op in plaats van een verkeerde meting', () {
      expect(forgeUit('dit is geen url'), isNull);
    });
  });
}
