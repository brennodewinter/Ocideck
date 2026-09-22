import 'dart:math' as math;

/// Verdeelt een te volle bulletlijst over pagina's — de logica achter "Splits
/// slide". Twee vormen, beide voorspelbaar en op volgorde:
///
/// * [splitBulletsIntoPages] telt: [size] bullets per pagina, de rest achteraan.
///   Voor tweekoloms-slides, waar beide kolommen uitgelijnd moeten blijven en
///   een pagina dus geen eigen hoogte heeft.
/// * [packBulletsIntoPages] meet: elke pagina vult tot de eerstvolgende bullet
///   er op de doelschaal niet meer bij past, met een aantal-bovengrens. Voor
///   éénkoloms-slides, waar lange volzin-bullets een pagina vullen die een
///   puur aantal-verdeling halfleeg of overvol zou achterlaten.

/// Het kleinste aantal bullets dat een eigen pagina waard is. Eén of twee
/// bullets is geen slide, dus zo'n rest maken we niet.
const int kMinPageBullets = 3;

/// De schaal waarop [packBulletsIntoPages] zijn pagina's minstens wil laten
/// renderen: 80% van de basismaat, dezelfde grens die de finding-paginering
/// als leesbaar aanhoudt. Onder deze grens is een extra pagina eerlijker dan
/// nóg kleinere tekst; erboven zou het pakken bij lange bullets terugzakken
/// naar twee of drie per pagina en één slide in een stapel uiteenvallen.
const double kSplitPageTargetScale = 0.80;

/// [bullets] in opeenvolgende pagina's van hooguit [size], de rest als laatste.
/// Een lege lijst levert geen pagina's; een [size] onder één telt als één.
List<List<String>> chunkBullets(List<String> bullets, int size) {
  final n = size < 1 ? 1 : size;
  return [
    for (var i = 0; i < bullets.length; i += n)
      bullets.sublist(i, math.min(i + n, bullets.length)),
  ];
}

/// [bullets] over precies [pages] pagina's, zo gelijk mogelijk; wat niet
/// opgaat komt op de eerste pagina's terecht, zodat die nooit leger zijn dan de
/// laatste.
List<List<String>> _spreadEvenly(List<String> bullets, int pages) {
  final result = <List<String>>[];
  var start = 0;
  for (var p = pages; p > 0; p--) {
    final take = (bullets.length - start + p - 1) ~/ p; // naar boven afgerond
    result.add(bullets.sublist(start, start + take));
    start += take;
  }
  return result;
}

/// De pagina's waarin "Splits slide" [bullets] verdeelt: pagina's van [size] met
/// de rest achteraan.
///
/// Blijft er een rest van minder dan [kMinPageBullets] over, dan valt de lijst
/// in plaats daarvan gelijkmatig over hetzelfde aantal pagina's: negen bullets
/// worden 5/4 en niet 8/1, want die ene bullet is geen slide. Alleen die runt
/// wordt afgekocht — bij een rest die wél een pagina waard is blijft het gewoon
/// vullen (elf wordt 8/3).
///
/// Past de lijst al op één pagina, dan is er niets te chunken maar vroeg de
/// maker wél om een knip — dat is de menu-actie "In tweeën splitsen" op een
/// slide die niet overvol is. Dan valt hij in twee gelijke helften.
List<List<String>> splitBulletsIntoPages(List<String> bullets, int size) {
  if (bullets.isEmpty) return const [];
  final n = size < 1 ? 1 : size;
  if (bullets.length <= n) {
    final half = (bullets.length + 1) ~/ 2;
    return [bullets.sublist(0, half), bullets.sublist(half)];
  }
  final rest = bullets.length % n;
  if (rest != 0 && rest < kMinPageBullets) {
    return _spreadEvenly(bullets, (bullets.length + n - 1) ~/ n);
  }
  return chunkBullets(bullets, n);
}

/// Verdeelt [bullets] over pagina's die op de doelschaal nog passen: elke
/// pagina vult tot de eerstvolgende bullet er niet meer bij zou kunnen, met
/// [maxBullets] als harde aantal-bovengrens. Beide functies krijgen de
/// paginaindex mee omdat de eerste pagina een andere vorm kan hebben dan de
/// vervolgen — bij een split-slide staat daar nog de afbeelding naast.
///
/// Anders dan [splitBulletsIntoPages] telt dit geen bullets maar meet het de
/// paginahoogte via [fits]: een pagina vol lange volzinnen is net zo vol als
/// een pagina met het maximum aan korte. Zo vullen de pagina's de beschikbare
/// ruimte in plaats van dat een vaste verdeling de gedeelde run-schaal omlaag
/// drukt.
///
/// Blijft er een rest van minder dan [kMinPageBullets] over, dan wordt de
/// staart van de reeks herverdeeld zoals [splitBulletsIntoPages] dat ook deed:
/// de laatste twee pagina's vallen gelijkmatig uiteen (negen bullets worden
/// 5/4 en niet 8/1). Past zo'n gelijkere helft niet meer op de doelschaal, dan
/// trekt de laatste pagina desnoods bullets uit zijn voorganger naar voren —
/// en kan óók dat niet, dan blijft de runt staan: een korte laatste pagina is
/// leesbaarder dan een overvolle voorlaatste.
List<List<String>> packBulletsIntoPages(
  List<String> bullets, {
  required bool Function(int pageIndex, List<String> candidate) fits,
  required int Function(int pageIndex) maxBullets,
}) {
  final pages = <List<String>>[];
  var current = <String>[];
  for (final bullet in bullets) {
    if (current.isNotEmpty &&
        (current.length >= maxBullets(pages.length) ||
            !fits(pages.length, [...current, bullet]))) {
      pages.add(current);
      current = [];
    }
    current.add(bullet);
  }
  if (current.isNotEmpty) pages.add(current);

  if (pages.length > 1 && pages.last.length < kMinPageBullets) {
    final lastIndex = pages.length - 1;
    final combined = [...pages[lastIndex - 1], ...pages[lastIndex]];
    final spread = _spreadEvenly(combined, 2);
    if (spread.last.length <= maxBullets(lastIndex) &&
        fits(lastIndex - 1, spread.first) &&
        fits(lastIndex, spread.last)) {
      pages[lastIndex - 1] = spread.first;
      pages[lastIndex] = spread.last;
    } else {
      final last = pages[lastIndex];
      final prev = pages[lastIndex - 1];
      while (last.length < kMinPageBullets && prev.length > kMinPageBullets) {
        final moved = prev.removeLast();
        last.insert(0, moved);
        if (!fits(lastIndex, last)) {
          last.removeAt(0);
          prev.add(moved);
          break;
        }
      }
    }
  }
  return pages;
}

/// [left] en [right] over hetzelfde aantal pagina's, zodat een tweekoloms slide
/// in uitgelijnde helften valt. Elke kolom wordt apart verdeeld met
/// [splitBulletsIntoPages]; een kolom die eerder opraakt houdt lege pagina's
/// over.
List<(List<String>, List<String>)> splitTwoColumnsIntoPages(
  List<String> left,
  List<String> right,
  int size,
) {
  final lp = splitBulletsIntoPages(left, size);
  final rp = splitBulletsIntoPages(right, size);
  final pages = math.max(lp.length, rp.length);
  return [
    for (var i = 0; i < pages; i++)
      (
        i < lp.length ? lp[i] : const <String>[],
        i < rp.length ? rp[i] : const <String>[],
      ),
  ];
}
