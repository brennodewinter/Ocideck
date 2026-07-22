import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_reference_data.dart';

/// De verouderingspoort voor de gebundelde referentiestandaarden, in **twee**
/// richtingen.
///
/// Dat "twee" is de hele reden dat dit bestand bestaat. De poort stond groen en
/// dat werd voor een uitspraak aangezien, terwijl hij voor MIAUW structureel
/// niet rood kón worden: de gebundelde "versie" was de dag waarop wij het
/// schema overnamen (2026-07-16) en de probe leverde de datum van de bron
/// (2024-12-06). Twee verschillende klokken, vergeleken met `>`. Een
/// overnamedatum ligt per definitie ná de bronwijziging, dus "is upstream
/// nieuwer?" was daar een vraag die nooit met ja beantwoord kon worden.
///
/// Een poort die alleen groen kan zijn is erger dan geen poort, want hij wordt
/// voor bewijs gehouden. Dus toetst dit bestand niet alleen dat de huidige
/// gegevens schoon zijn, maar ook dat een geplante verouderde bron er
/// daadwerkelijk doorheen komt als rood — inclusief precies de boekhouding die
/// hem jarenlang groen hield.
void main() {
  final registry = File(
    'lib/services/reference_standards.dart',
  ).readAsStringSync();
  final standards = parseStandards(registry);

  /// Een probe die elke bron precies teruggeeft wat wij bundelen: de wereld
  /// staat stil, niets is verouderd.
  Future<ProbeResult> echo(Standard s) async => ProbeResult(s.version);

  group('de vergelijking', () {
    test('gelijk is niet verouderd', () {
      expect(deviates('2024-12-06', '2024-12-06'), isFalse);
      expect(deviates('4.2', '4.2'), isFalse);
    });

    test('nieuwer is verouderd', () {
      expect(deviates('2024-12-06', '2025-01-01'), isTrue);
    });

    test('een upstreamwaarde die óuder lijkt is óók een afwijking', () {
      // Dit is de bug. Met `latest > bundled` was dit stil "actueel"; het
      // betekent in werkelijkheid dat onze boekhouding een andere grootheid
      // noteert dan de bron publiceert, en dat hoort een mens te zien.
      expect(deviates('2026-07-16', '2024-12-06'), isTrue);
      // MASTG hernummerde bij de herbouw van 1.x naar 2.0: groter-is-nieuwer
      // gaat bij deze bronnen sowieso niet op.
      expect(deviates('2.0.0', '1.9.0'), isTrue);
    });

    test('zonder oordeel is er geen afwijking', () {
      expect(deviates('4.2', null), isFalse, reason: 'bron onbereikbaar');
      expect(deviates('', '4.2'), isFalse, reason: 'wij bundelen geen versie');
    });
  });

  group('het register', () {
    test('elke standaard is uitgelezen', () {
      expect(standards, hasLength(greaterThanOrEqualTo(7)));
      expect(standards.map((s) => s.id), contains('miauw'));
    });

    test('MIAUW kijkt naar het werkboek zelf, met een datum als versie', () {
      final miauw = standards.firstWhere((s) => s.id == 'miauw');
      expect(miauw.probe, 'githubCommitDate');
      expect(
        miauw.path,
        isNotEmpty,
        reason:
            'zonder probePath kijkt de poort repobreed en wordt hij rood van '
            'een README-typefout',
      );
      expect(miauw.version, matches(r'^\d{4}-\d{2}-\d{2}$'));
    });

    test('een datumprobe hoort bij een datum als gebundelde versie', () {
      // Anders vergelijkt de poort een versienummer met een datum en is elke
      // uitkomst betekenisloos — in beide richtingen.
      for (final s in standards.where((s) => s.probe == 'githubCommitDate')) {
        expect(
          s.version,
          matches(r'^\d{4}-\d{2}-\d{2}$'),
          reason:
              '${s.id}: datumprobe, maar de gebundelde versie is geen datum',
        );
      }
    });
  });

  group('de poort, groen', () {
    test('bronnen die niet bewogen zijn laten hem door', () async {
      final outcome = await evaluate(standards, echo);
      expect(outcome.outdated, 0);
      expect(outcome.exitCode(advisory: false), 0);
      expect(outcome.rows.every((r) => r.last == 'actueel'), isTrue);
    });
  });

  group('de poort, rood', () {
    test('een geplante nieuwere bron laat hem vallen', () async {
      final outcome = await evaluate(
        standards,
        (s) async => s.id == 'miauw'
            ? ProbeResult(
                '2027-01-01',
                stale: deviates(s.version, '2027-01-01'),
              )
            : echo(s),
      );
      expect(outcome.outdated, 1);
      expect(outcome.exitCode(advisory: false), 1);
      expect(outcome.rows.any((r) => r.last == 'VEROUDERD'), isTrue);
    });

    test('de oude MIAUW-boekhouding wordt nu wél gezien', () async {
      // Letterlijk de situatie van vóór 22-07-2026: gebundeld 2026-07-16 (onze
      // overnamedag), bron 2024-12-06. Dit moet rood zijn. Wordt deze test ooit
      // groen, dan is de vergelijking teruggedraaid naar "alleen nieuwer telt"
      // en bewaakt de poort weer niets.
      final asItWas = [
        Standard(
          'miauw',
          'MIAUW',
          '2026-07-16',
          'githubCommitDate',
          'brennodewinter/Informatiebeveiligingsonderzoek',
          path: 'NL-Schema_Miauw_1_00.xlsx',
        ),
      ];
      final outcome = await evaluate(
        asItWas,
        (s) async =>
            ProbeResult('2024-12-06', stale: deviates(s.version, '2024-12-06')),
      );
      expect(outcome.exitCode(advisory: false), 1);
    });

    test('een integriteitsbevinding telt ook als rood', () async {
      // Het gebundelde bronbestand is hernoemd: de bron antwoordt, maar over
      // dat pad bestaat geen historie. Dat mag geen "onbekend" worden, want dan
      // glipt het stil door.
      final outcome = await evaluate(
        standards,
        (s) async => s.id == 'miauw'
            ? ProbeResult(s.version, integrityProblem: 'pad bestaat niet meer')
            : echo(s),
      );
      expect(outcome.outdated, 1);
      expect(outcome.notes, contains('pad bestaat niet meer'));
      expect(outcome.exitCode(advisory: false), 1);
    });
  });

  group('de drie uitkomsten blijven uit elkaar', () {
    test('adviserend meldt hetzelfde maar blokkeert niet', () async {
      final outcome = await evaluate(
        standards,
        (s) async =>
            s.id == 'miauw' ? ProbeResult('2027-01-01', stale: true) : echo(s),
      );
      expect(outcome.outdated, 1, reason: 'de melding blijft staan');
      expect(outcome.exitCode(advisory: true), 0);
    });

    test('een adviserende bron laat de poort niet vallen', () async {
      // Orphanet is een detectielexicon: het meldt zich, maar blokkeert niet.
      final outcome = await evaluate(
        standards,
        (s) async =>
            s.advisory ? ProbeResult('2099-01-01', stale: true) : echo(s),
      );
      expect(outcome.outdatedAdvisory, greaterThan(0));
      expect(outcome.outdated, 0);
      expect(outcome.exitCode(advisory: false), 0);
    });

    test('onbekend is geen synoniem voor actueel', () async {
      // Alles onbereikbaar: dat is code 2 ("ik heb niet kunnen kijken"), nooit
      // 0. Ook adviserend niet — dat verschil is het hele punt van de poort.
      final outcome = await evaluate(standards, (s) async => ProbeResult(null));
      expect(outcome.unreachable, standards.length);
      expect(outcome.exitCode(advisory: false), 2);
      expect(outcome.exitCode(advisory: true), 2);
      expect(outcome.rows.every((r) => r.last.startsWith('onbekend')), isTrue);
    });

    test('één onbereikbare bron breekt de controle niet af', () async {
      final outcome = await evaluate(
        standards,
        (s) async => s.id == 'cwe' ? ProbeResult(null) : echo(s),
      );
      expect(outcome.unreachable, 1);
      expect(outcome.exitCode(advisory: false), 0);
    });
  });
}
