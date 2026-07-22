/// De snelste van [runs] doorlopen van [action].
///
/// **Waarom de snelste en niet het gemiddelde.** Een prestatietest meet hier de
/// code, niet de machine. Onder een volle suite draaien er tientallen isolates
/// naast elkaar; één uitschieter door een andere test die net het geheugen
/// aanspreekt, trekt een gemiddelde zo over de drempel. Het minimum is de enige
/// meting die dát wegfiltert: de snelste doorloop is de doorloop waarin de
/// machine niet in de weg zat.
///
/// De schade van een gemiddelde is niet dat de test soms rood is, maar wát dat
/// rood betekent. De eerste bijdrager die `make check` draait op een belaste
/// laptop krijgt een rode prestatietest voor een wijziging aan een dialoog — en
/// leert daarmee dat de poort ruis is (#638).
library;

Duration fastestOf(int runs, void Function() action) {
  var best = const Duration(days: 1);
  for (var r = 0; r < runs; r++) {
    final sw = Stopwatch()..start();
    action();
    sw.stop();
    if (sw.elapsed < best) best = sw.elapsed;
  }
  return best;
}
