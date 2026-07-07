/// Lichtgewicht, dependency-vrije wachtwoordsterkte-schatting op basis van
/// *entropie*, niet op domme regels.
///
/// De bewust gekozen aanpak: sterkte ≈ lengte × log2(effectieve tekenset),
/// met correcties voor herhaling, opeenvolgende reeksen en een kleine lijst
/// veelgebruikte wachtwoorden. Zo scoort een lange wachtwoordzin ("correct
/// horse battery staple") hoog en scoort een kort "P@ss1!" laag — precies het
/// tegenovergestelde van een "verplichte !"-regel, die niets over echte
/// sterkte zegt. Het resultaat *waarschuwt* alleen; niets wordt geblokkeerd.
library;

import 'dart:math' as math;

/// Niet-letters, om de alfabetische kern van een wachtwoord te isoleren.
final _nonLetters = RegExp(r'[^a-z]');

/// Sterktecategorie, oplopend.
enum PasswordStrength { veryWeak, weak, fair, strong, veryStrong }

/// Uitkomst van [estimatePasswordStrength]: geschatte [bits] entropie plus de
/// afgeleide [category].
class PasswordStrengthResult {
  final double bits;
  final PasswordStrength category;

  const PasswordStrengthResult(this.bits, this.category);

  /// Onder ~40 bits beschouwen we een wachtwoord als zwak genoeg om te
  /// waarschuwen. Boven die grens is offline brute-force onpraktisch, zeker
  /// omdat het pakket met AES-256 wordt versleuteld.
  bool get isWeak =>
      category == PasswordStrength.veryWeak ||
      category == PasswordStrength.weak;

  /// Genormaliseerde waarde 0..1 voor een voortgangsbalk (128 bits = vol).
  double get fraction => (bits / 128).clamp(0.0, 1.0);
}

/// De grootste veelvoorkomende wachtwoorden en basiswoorden; een exacte match
/// (hoofdletterongevoelig) of een puur alfabetische kern hieruit drukt de score
/// hard omlaag, want zulke wachtwoorden staan in elke woordenlijst.
const _commonPasswords = <String>{
  'password',
  'wachtwoord',
  'geheim',
  'welkom',
  'welcome',
  'qwerty',
  'azerty',
  'admin',
  'letmein',
  'iloveyou',
  'monkey',
  'dragon',
  'sunshine',
  'princess',
  'football',
  'baseball',
  'superman',
  'batman',
  'trustno1',
  'starwars',
  '123456',
  '12345678',
  '123456789',
  '1234567890',
  '111111',
  '000000',
  'abc123',
  'password1',
  'qwerty123',
  'wachtwoord1',
};

/// Schat de sterkte van [password].
PasswordStrengthResult estimatePasswordStrength(String password) {
  if (password.isEmpty) {
    return const PasswordStrengthResult(0, PasswordStrength.veryWeak);
  }

  final bits = _estimateBits(password);
  return PasswordStrengthResult(bits, _categorize(bits));
}

double _estimateBits(String password) {
  final runes = password.runes.toList();
  final poolSize = _poolSize(runes);
  var bits = runes.length * (math.log(poolSize) / math.ln2);

  // Herhaling: weinig unieke tekens = minder effectieve entropie dan de lengte
  // suggereert ("aaaaaaaa" is niet 8× zo sterk als "a").
  final uniqueRatio = runes.toSet().length / runes.length;
  bits *= 0.3 + 0.7 * uniqueRatio;

  // Opeenvolgende reeksen (abc, 123, cba, zyx) zijn goedkoop te raden.
  bits -= _sequentialPenalty(runes);

  // Veelgebruikte wachtwoorden/woorden: capaciteit hard omlaag.
  final lower = password.toLowerCase();
  final alphaCore = lower.replaceAll(_nonLetters, '');
  if (_commonPasswords.contains(lower) ||
      (alphaCore.length >= 4 && _commonPasswords.contains(alphaCore))) {
    bits = math.min(bits, 12);
  }

  return bits < 0 ? 0 : bits;
}

/// Grootte van de tekenverzameling waaruit het wachtwoord lijkt te putten.
int _poolSize(List<int> runes) {
  var lower = false,
      upper = false,
      digit = false,
      symbol = false,
      other = false;
  for (final r in runes) {
    if (r >= 0x61 && r <= 0x7a) {
      lower = true;
    } else if (r >= 0x41 && r <= 0x5a) {
      upper = true;
    } else if (r >= 0x30 && r <= 0x39) {
      digit = true;
    } else if (r < 0x80) {
      symbol = true;
    } else {
      other = true;
    }
  }
  var pool = 0;
  if (lower) pool += 26;
  if (upper) pool += 26;
  if (digit) pool += 10;
  if (symbol) pool += 33;
  if (other) pool += 40; // ruwe schatting voor niet-ASCII (accenten, emoji, …)
  return pool < 2 ? 2 : pool;
}

/// Trek entropie af voor elke run van 3+ opeenvolgende tekens (op- of aflopend).
double _sequentialPenalty(List<int> runes) {
  var penalty = 0.0;
  var run = 1;
  for (var i = 1; i < runes.length; i++) {
    final diff = runes[i] - runes[i - 1];
    if (diff == 1 || diff == -1) {
      run++;
      if (run >= 3) penalty += 2.0;
    } else {
      run = 1;
    }
  }
  return penalty;
}

PasswordStrength _categorize(double bits) {
  if (bits < 28) return PasswordStrength.veryWeak;
  if (bits < 40) return PasswordStrength.weak;
  if (bits < 64) return PasswordStrength.fair;
  if (bits < 96) return PasswordStrength.strong;
  return PasswordStrength.veryStrong;
}
