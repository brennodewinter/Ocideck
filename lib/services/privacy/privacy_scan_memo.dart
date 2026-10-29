import 'package:flutter/foundation.dart';

import '../../models/deck.dart';
import '../../models/privacy_finding.dart';
import '../../models/slide.dart';
import 'privacy_scanner.dart';

/// Per-slide memoisatie van de privacyscan.
///
/// [PrivacyScanner.scanSlide] bestond hier al voor — het doc-commentaar noemt
/// letterlijk "voor de per-slide memoisatie in de provider" — maar werd nergens
/// aangeroepen. De provider draaide `scan(deck)`, dus élke aanslag scande het
/// hele deck opnieuw: gemeten ~1,07 ms per dia, en dus 208 ms bij 200 dia's en
/// 519 ms bij 500. Er verandert bij een aanslag precies één dia.
///
/// De sleutel is waterdicht doordat alles wat de uitkomst bepaalt erin zit:
///
///   * de **scanner** als object. Hij komt uit een provider die opnieuw wordt
///     gebouwd zodra een instelling wijzigt (uitgezette regels, eigen identiteit,
///     landpakketten), dus een andere configuratie is per definitie een ander
///     object en dus een misser. Dat is beter dan de velden los in de sleutel
///     leggen: vergeet je er later één, dan blijft er stilletjes een verouderde
///     bevinding hangen — en dát is bij een privacycontrole de verkeerde fout.
///   * de **dia** als object. `Slide` is onveranderlijk en elke bewerking levert
///     een nieuw exemplaar op, dus identiteit is hier een geldige
///     wijzigingsstempel.
///
/// De index zit er bewust niet in. Een globale LRU met de index in de sleutel
/// viel boven 512 dia's volledig weg: één invoeging bovenaan maakte elke
/// volgende dia een misser, en een sequentiële scan over meer dia's dan het
/// plafond verdrong elk item vlak voordat het weer nodig was (#2622). De scan
/// zelf hangt niet van de index af — die wordt alleen op de bevinding gezet —
/// dus we scannen zonder index en schrijven hem pas bij het samenvoegen, zoals
/// de kwaliteitscontrole dat met `reindexed` doet.
///
/// Het [Expando] is zwak: de memo verdwijnt met de dia, en groeit dus niet los
/// van het geheugen dat het deck zelf al houdt.
final Expando<_SlideScanMemo> _slideScanCache = Expando<_SlideScanMemo>(
  'privacySlideScan',
);

/// Generatie van [clearPrivacyScanMemo]. Een test die de memo leegt, maakt
/// bestaande dia's daarmee een misser zonder het Expando te hoeven aflopen.
int _scanEpoch = 0;

/// Hoe vaak een dia écht opnieuw gescand is sinds de laatste
/// [clearPrivacyScanMemo]. Tests gebruiken dit om te zien dat een verschoven
/// dia niet opnieuw gescand wordt.
@visibleForTesting
int privacyScanMemoMisses = 0;

class _SlideScanMemo {
  _SlideScanMemo(this.epoch, this.scanner, this.findings);

  final int epoch;
  final PrivacyScanner scanner;

  /// Bevindingen zoals [PrivacyScanner.scanSlide] ze op index 0 oplevert.
  final List<PrivacyFinding> findings;
}

/// De scan van één dia, uit de memo wanneer die er al is.
PrivacyScanResult memoizedSlideScan(
  PrivacyScanner scanner,
  Slide slide,
  int index,
) {
  final cached = _slideScanCache[slide];
  if (cached != null &&
      cached.epoch == _scanEpoch &&
      identical(cached.scanner, scanner)) {
    return _atIndex(cached.findings, index);
  }
  privacyScanMemoMisses++;
  final scanned = scanner.scanSlide(slide, 0);
  _slideScanCache[slide] = _SlideScanMemo(
    _scanEpoch,
    scanner,
    scanned.findings,
  );
  return _atIndex(scanned.findings, index);
}

PrivacyScanResult _atIndex(List<PrivacyFinding> findings, int index) {
  if (index == 0 || findings.isEmpty) return PrivacyScanResult(findings);
  return PrivacyScanResult([
    for (final finding in findings) _withIndex(finding, index),
  ]);
}

PrivacyFinding _withIndex(PrivacyFinding finding, int index) {
  if (finding.slideIndex == index) return finding;
  return PrivacyFinding(
    ruleId: finding.ruleId,
    family: finding.family,
    confidence: finding.confidence,
    slideIndex: index,
    field: finding.field,
    fragmentIndex: finding.fragmentIndex,
    start: finding.start,
    end: finding.end,
    maskedSample: finding.maskedSample,
    role: finding.role,
    personRole: finding.personRole,
  );
}

/// De scan van een heel deck, met de dia's uit de memo.
///
/// Levert exact hetzelfde op als [PrivacyScanner.scan]: de deckbrede velden
/// eerst, daarna de dia's op volgorde. `privacy_scan_memo_test.dart` vergelijkt
/// de twee op willekeurige decks, zodat de snelle weg niet stilletjes van de
/// trage kan gaan afwijken.
PrivacyScanResult memoizedDeckScan(PrivacyScanner scanner, Deck deck) {
  final findings = [
    ...scanner.scanDeckFields(deck).findings,
    for (var i = 0; i < deck.slides.length; i++)
      ...memoizedSlideScan(scanner, deck.slides[i], i).findings,
  ];
  return PrivacyScanResult(findings);
}

/// Leegt de memo. Alleen voor tests: in de app verdwijnt een entry met de dia.
void clearPrivacyScanMemo() {
  _scanEpoch++;
  privacyScanMemoMisses = 0;
}
