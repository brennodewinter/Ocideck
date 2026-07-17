import 'dart:math' as math;

/// Verdeelt een te volle bulletlijst over pagina's — de logica achter "Splits
/// slide". Pure functies over een lijst bullets en een paginagrootte.
///
/// Met opzet dom: [size] bullets per pagina, op volgorde, en wat overblijft
/// vormt de laatste, kortere pagina. Een eerdere versie balanceerde de pagina's
/// en mat hoeveel bullets er op ware grootte fysiek pasten — bij lange bullets
/// zakte dat naar twee of drie per pagina en viel één slide uiteen in een stapel
/// van vijf. Voorspelbaar wint hier van slim: de maker moet aan de knop kunnen
/// zien wat hij gaat krijgen.

/// [bullets] in opeenvolgende pagina's van hooguit [size], de rest als laatste.
/// Een lege lijst levert geen pagina's; een [size] onder één telt als één.
List<List<String>> chunkBullets(List<String> bullets, int size) {
  final n = size < 1 ? 1 : size;
  return [
    for (var i = 0; i < bullets.length; i += n)
      bullets.sublist(i, math.min(i + n, bullets.length)),
  ];
}

/// De pagina's waarin "Splits slide" [bullets] verdeelt: pagina's van [size] met
/// de rest achteraan.
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
  return chunkBullets(bullets, n);
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
