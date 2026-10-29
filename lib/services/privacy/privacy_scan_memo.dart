import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/deck.dart';
import '../../models/privacy_finding.dart';
import '../../models/slide.dart';
import 'privacy_bulk_lexicon.dart';
import 'privacy_scanner.dart';

/// Per-slide memoisatie van de privacyscan op dia-identiteit.
///
/// `Slide` is onveranderlijk en elke bewerking levert een nieuw exemplaar op,
/// dus identiteit is een geldige wijzigingsstempel — een gewijzigde dia mist,
/// alle andere raken. De dia-**index** zit bewust níét in de sleutel: hij
/// staat alleen op elke bevinding gestempeld en wordt bij het samenvoegen
/// geschreven via [PrivacyFinding.reindexed]. Een dia die bovenaan wordt
/// ingevoegd ongeldigt daardoor geen enkele scan achter hem (#2622).
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

/// Meet de koude dia's van [slides] vooruit in een werk-isolate en legt de
/// uitslag in dezelfde memo's die [memoizedSlideScan] leest (#2634).
///
/// Bedoeld voor het openen: zonder deze pas scant de eerste provider-lezing
/// een groot deck synchroon op de UI-isolate — honderden milliseconden
/// stilte. De isolate krijgt een kopie van [scanner] en van de dia's; de
/// memo wordt hier met de UI-kant-instantie gevuld, want
/// [memoizedSlideScan] vergelijkt de scanner op identiteit. De uitkomst is
/// identiek: [PrivacyScanner.scanSlide] is een pure functie van dia plus
/// configuratie.
///
/// Het bulklexicon is een singleton **per isolate**: de werkkopie laadt hij
/// zelf via de root-token, en kon dat niet (geen binding, geen token), dan
/// valt deze pas terug op de synchrone scan — een memo die de bulktermen
/// mist is erger dan geen memo.
///
/// Op web bestaat geen isolate; daar loopt de scan zoals altijd synchroon.
Future<void> warmPrivacyScanMemo(
  PrivacyScanner scanner,
  List<Slide> slides,
) async {
  final cold = [
    for (final slide in slides)
      if (_slideScanCache[slide] == null ||
          _slideScanCache[slide]!.epoch != _scanEpoch ||
          !identical(_slideScanCache[slide]!.scanner, scanner))
        slide,
  ];
  if (cold.isEmpty) return;
  // Dezelfde index-0-meting als [memoizedSlideScan]: de echte dia-index
  // komt er pas bij het samenvoegen op via [_atIndex].
  List<PrivacyFinding> scanFindings(Slide slide) =>
      scanner.scanSlide(slide, 0).findings;
  List<List<PrivacyFinding>> scanSync() => [
    for (final slide in cold) scanFindings(slide),
  ];
  // `ServicesBinding.rootIsolateToken` is een nullable static — `null` zolang
  // er geen binding staat (headless test), en dan valt de pas op sync terug.
  final token = ServicesBinding.rootIsolateToken;
  final List<List<PrivacyFinding>> results;
  if (kIsWeb || token == null) {
    results = scanSync();
  } else {
    final scanned = await Isolate.run<(bool, List<List<PrivacyFinding>>)>(
      () async {
        BackgroundIsolateBinaryMessenger.ensureInitialized(token);
        await PrivacyBulkLexicon.instance.ensureLoaded();
        return (PrivacyBulkLexicon.instance.isLoaded, scanSync());
      },
    );
    // Kon het lexicon in de worker niet laden, dan missen diens uitslagen de
    // bulktermen — liever hier hermeten dan een incompleet warme memo.
    results = scanned.$1 ? scanned.$2 : scanSync();
  }
  for (var i = 0; i < cold.length; i++) {
    _slideScanCache[cold[i]] = _SlideScanMemo(_scanEpoch, scanner, results[i]);
  }
}
