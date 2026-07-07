/// Genereer een sterk, willekeurig wachtwoord met een cryptografisch veilige
/// bron ([Random.secure]).
///
/// Bedoeld om te kopiëren en door te geven (niet om te typen), dus de tekenset
/// is ruim. Ambigue tekens worden niet vermeden: bij kopiëren maakt "l vs 1"
/// niet uit, en een grotere set = meer entropie per teken.
library;

import 'dart:math';

/// Veilige, printbare ASCII-tekenset. Bewust géén aanhalingstekens/backslash/
/// spatie, zodat het wachtwoord probleemloos in commando's, JSON of URL's
/// geplakt kan worden zonder te ontsnappen.
const String passwordAlphabet =
    'abcdefghijklmnopqrstuvwxyz'
    'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    '0123456789'
    '!@#\$%^&*()-_=+[]{}:;,.?';

/// Voorgestelde lengtes voor de generatieknop: kort genoeg om te hanteren, of
/// extreem lang voor geautomatiseerde distributie.
const int shortPasswordLength = 32;
const int longPasswordLength = 256;

/// Genereer een willekeurig wachtwoord van [length] tekens uit
/// [passwordAlphabet]. [length] wordt begrensd tot minimaal 1.
String generatePassword(int length) {
  final n = length < 1 ? 1 : length;
  final rng = Random.secure();
  final buf = StringBuffer();
  for (var i = 0; i < n; i++) {
    buf.write(passwordAlphabet[rng.nextInt(passwordAlphabet.length)]);
  }
  return buf.toString();
}
