import 'dart:isolate';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../../models/deck.dart';
import '../../models/privacy_finding.dart';
import '../../models/slide.dart';
import 'privacy_bulk_lexicon.dart';
import 'privacy_scanner.dart';

/// Stempel voor bevindingen die pas bij het uitlezen hun echte dia-index
/// krijgen. Bewust géén [kDeckWidePrivacyIndex] — die waarde betekent
/// "deckbreed" en mag op een slidebevinding nooit naar buiten lekken.
const int _unindexedSlide = -2;

class _SlideScanMemo {
  /// De scanner die deze uitkomst maakte — op identiteit. Hij komt uit een
  /// provider die opnieuw wordt gebouwd zodra een instelling wijzigt
  /// (uitgezette regels, eigen identiteit, landpakketten), dus een andere
  /// configuratie is per definitie een ander object en dus een misser. Dat is
  /// beter dan de velden los in de sleutel leggen: vergeet je er later één,
  /// dan blijft er stilletjes een verouderde bevinding hangen — en dát is bij
  /// een privacycontrole de verkeerde fout.
  final PrivacyScanner scanner;

  /// Bevindingen gestempeld op [_unindexedSlide]; de echte dia-index wordt er
  /// bij het samenvoegen van de deckscan op geschreven.
  final PrivacyScanResult result;

  const _SlideScanMemo(this.scanner, this.result);
}

/// Per-slide memoisatie van de privacyscan op dia-identiteit.
///
/// `Slide` is onveranderlijk en elke bewerking levert een nieuw exemplaar op,
/// dus identiteit is een geldige wijzigingsstempel — een gewijzigde dia mist,
/// alle andere raken. De dia-**index** zit bewust níét in de sleutel: hij
/// staat alleen op elke bevinding gestempeld en wordt bij het samenvoegen
/// geschreven via [PrivacyFinding.reindexed]. Een dia die bovenaan wordt
/// ingevoegd ongeldigt daardoor geen enkele scan achter hem (#2622).
///
/// Een `Expando` en geen LRU: de memo leeft precies zo lang als de dia zelf
/// en kent geen capaciteitsklif — een sequentiële scan over meer dia's dan de
/// oude 512-cap verdreef elke waarde vlak voordat die weer nodig was.
Expando<_SlideScanMemo> _slideScanCache = Expando<_SlideScanMemo>(
  'privacyScan',
);

/// De scan van één dia, uit de memo wanneer die er al is.
PrivacyScanResult memoizedSlideScan(
  PrivacyScanner scanner,
  Slide slide,
  int index,
) {
  var memo = _slideScanCache[slide];
  if (memo == null || !identical(memo.scanner, scanner)) {
    memo = _SlideScanMemo(scanner, scanner.scanSlide(slide, _unindexedSlide));
    _slideScanCache[slide] = memo;
  }
  return PrivacyScanResult([
    for (final f in memo.result.findings) f.reindexed(index),
  ]);
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

/// Vergeet alle memo's. Alleen voor tests: in de app ruimt de `Expando` mee
/// op met de dia's zelf.
void clearPrivacyScanMemo() =>
    _slideScanCache = Expando<_SlideScanMemo>('privacyScan');

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
          !identical(_slideScanCache[slide]!.scanner, scanner))
        slide,
  ];
  if (cold.isEmpty) return;
  List<PrivacyScanResult> scanSync() => [
    for (final slide in cold) scanner.scanSlide(slide, _unindexedSlide),
  ];
  // `ServicesBinding.rootIsolateToken` is een nullable static — `null` zolang
  // er geen binding staat (headless test), en dan valt de pas op sync terug.
  final token = ServicesBinding.rootIsolateToken;
  final List<PrivacyScanResult> results;
  if (kIsWeb || token == null) {
    results = scanSync();
  } else {
    final scanned = await Isolate.run<(bool, List<PrivacyScanResult>)>(
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
    _slideScanCache[cold[i]] = _SlideScanMemo(scanner, results[i]);
  }
}
