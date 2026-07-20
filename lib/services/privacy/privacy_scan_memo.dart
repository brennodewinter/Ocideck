import '../../models/deck.dart';
import '../../models/privacy_finding.dart';
import '../../models/slide.dart';
import '../../utils/lru_cache.dart';
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
///     wijzigingsstempel (dezelfde redenering als bij `memoizedRenderLayout` en
///     bij de opslagrace in `deck_provider.dart`).
///   * de **index**, want die reist mee in elke bevinding. Een dia die van plek
///     verschuift krijgt daardoor een verse scan in plaats van bevindingen die
///     naar de oude positie wijzen.
///
/// LRU en niet onbegrensd: een lange sessie met veel bewerkingen zou anders elk
/// tussenresultaat vasthouden. 512 is ruim genoeg voor het werkende venster van
/// een groot deck, en volgt de maat die de layoutmemo al hanteert.
final LruCache<(PrivacyScanner, Slide, int), PrivacyScanResult>
_slideScanCache = LruCache(512);

/// De scan van één dia, uit de memo wanneer die er al is.
PrivacyScanResult memoizedSlideScan(
  PrivacyScanner scanner,
  Slide slide,
  int index,
) {
  final key = (scanner, slide, index);
  final cached = _slideScanCache[key];
  if (cached != null) return cached;
  final value = scanner.scanSlide(slide, index);
  _slideScanCache[key] = value;
  return value;
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

/// Leegt de memo. Alleen voor tests: in de app zorgt de LRU voor de begrenzing.
void clearPrivacyScanMemo() => _slideScanCache.clear();
