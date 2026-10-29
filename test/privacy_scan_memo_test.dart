import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/privacy_finding.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_scan_memo.dart';
import 'package:ocideck/services/privacy/privacy_scanner.dart';

/// De gememoiseerde weg moet exact hetzelfde melden als de rechtstreekse.
///
/// Een memo die iets *anders* teruggeeft is bij een privacycontrole erger dan de
/// traagheid die hij oplost: een gemiste bevinding leest als "hier staat niets
/// gevoeligs". Vandaar dat deze suite steeds tegen `scanner.scan(deck)` afzet in
/// plaats van tegen een verwachte lijst.
///
/// Alle waarden hieronder zijn nep: 728398242 doorstaat de elfproef maar hoort
/// bij niemand, en de adressen wijzen naar `example`-domeinen.
void main() {
  setUp(clearPrivacyScanMemo);

  const scanner = PrivacyScanner();

  List<String> ids(Deck d, PrivacyScanResult r) => [
    for (final f in r.findings) '${f.slideIndex}:${f.ruleId}:${f.start}',
  ];

  Slide bullets(String text) =>
      Slide.create(SlideType.bullets).copyWith(bullets: [text]);

  Deck deckOf(List<Slide> slides, {String title = 'D'}) =>
      Deck(title: title, slides: slides);

  test('leeg deck: memo en directe scan zijn het eens', () {
    final deck = deckOf([bullets('niets bijzonders')]);
    expect(
      ids(deck, memoizedDeckScan(scanner, deck)),
      ids(deck, scanner.scan(deck)),
    );
  });

  test('bevindingen op meerdere dia\'s komen identiek terug', () {
    final deck = deckOf([
      bullets('BSN 728398242 van betrokkene'),
      bullets('niets aan de hand'),
      bullets('mail naar jan@voorbeeld-klant.example'),
    ]);

    final direct = scanner.scan(deck);
    expect(direct.findings, isNotEmpty, reason: 'anders test dit niets');
    expect(ids(deck, memoizedDeckScan(scanner, deck)), ids(deck, direct));
  });

  test('deckbrede velden reizen mee', () {
    final deck = deckOf([
      bullets('gewoon'),
    ], title: 'Briefing voor jan@voorbeeld-klant.example');

    final direct = scanner.scan(deck);
    expect(
      direct.findings.any((f) => f.isDeckWide),
      isTrue,
      reason: 'anders toetst dit de deckbrede tak niet',
    );
    expect(ids(deck, memoizedDeckScan(scanner, deck)), ids(deck, direct));
  });

  test('een bewerkte dia wordt opnieuw gescand, niet uit de memo geplukt', () {
    final schoon = bullets('niets bijzonders');
    final eerste = deckOf([schoon]);
    expect(memoizedDeckScan(scanner, eerste).findings, isEmpty);

    // Zelfde positie, nieuwe inhoud: `Slide` is onveranderlijk, dus dit is een
    // ander object en moet dus een misser zijn.
    final vies = deckOf([bullets('BSN 728398242 van betrokkene')]);
    final viaMemo = memoizedDeckScan(scanner, vies);

    expect(viaMemo.findings, isNotEmpty);
    expect(ids(vies, viaMemo), ids(vies, scanner.scan(vies)));
  });

  test('een verschoven dia krijgt de juiste index, niet de oude', () {
    final gevoelig = bullets('BSN 728398242 van betrokkene');
    final voor = deckOf([gevoelig, bullets('vulling')]);
    final na = deckOf([bullets('vulling'), gevoelig]);

    memoizedDeckScan(scanner, voor); // vult de memo op index 0

    final viaMemo = memoizedDeckScan(scanner, na);
    expect(ids(na, viaMemo), ids(na, scanner.scan(na)));
    expect(
      viaMemo.findings
          .where((f) => !f.isDeckWide)
          .every((f) => f.slideIndex == 1),
      isTrue,
      reason: 'de bevinding hoort nu bij dia 1, niet bij de onthouden 0',
    );
  });

  test('een andere scannerconfiguratie deelt de memo niet', () {
    final deck = deckOf([bullets('BSN 728398242 van betrokkene')]);
    expect(memoizedDeckScan(scanner, deck).findings, isNotEmpty);

    // Regel uit: dezelfde dia, ander resultaat. Zou de memo alleen op de dia
    // sleutelen, dan bleef de oude bevinding staan — een uitgezette regel die
    // toch blijft melden.
    const uit = PrivacyScanner(disabledRules: {'nl.bsn'});
    final viaMemo = memoizedDeckScan(uit, deck);

    expect(viaMemo.findings.any((f) => f.ruleId == 'nl.bsn'), isFalse);
    expect(ids(deck, viaMemo), ids(deck, uit.scan(deck)));
  });

  test('een deck van 1000 dia\'s blijft bij de tweede scan binnen 5 ms', () {
    final slides = [
      for (var i = 0; i < 1000; i++) bullets('dia $i zonder bijzonderheden'),
    ];
    final deck = deckOf(slides);
    memoizedDeckScan(scanner, deck);
    final missesAfterWarm = privacyScanMemoMisses;

    final watch = Stopwatch()..start();
    memoizedDeckScan(scanner, deck);
    watch.stop();

    expect(privacyScanMemoMisses, missesAfterWarm);
    expect(
      watch.elapsedMilliseconds,
      lessThan(5),
      reason: 'een warme scan van 1000 dia\'s duurde ${watch.elapsed}',
    );
  });

  test('een dia bovenaan invoegen scant alleen die nieuwe dia opnieuw', () {
    final slides = [
      for (var i = 0; i < 40; i++) bullets('dia $i zonder bijzonderheden'),
    ];
    final gevoelig = bullets('BSN 728398242 van betrokkene');
    slides.add(gevoelig);
    final voor = deckOf(slides);
    memoizedDeckScan(scanner, voor);
    final misses = privacyScanMemoMisses;

    final na = deckOf([bullets('nieuw bovenaan'), ...slides]);
    final viaMemo = memoizedDeckScan(scanner, na);

    expect(privacyScanMemoMisses - misses, 1);
    expect(ids(na, viaMemo), ids(na, scanner.scan(na)));
    expect(
      viaMemo.findings
          .where((f) => !f.isDeckWide)
          .every((f) => f.slideIndex == slides.length),
      isTrue,
      reason: 'de verschoven dia houdt zijn bevinding, op de nieuwe index',
    );
  });

  test('herhaalde scans van hetzelfde deck blijven gelijk', () {
    final deck = deckOf([
      bullets('BSN 728398242'),
      bullets('mail naar jan@voorbeeld-klant.example'),
    ]);
    final een = ids(deck, memoizedDeckScan(scanner, deck));
    final twee = ids(deck, memoizedDeckScan(scanner, deck));
    expect(twee, een);
    expect(twee, ids(deck, scanner.scan(deck)));
  });
}
