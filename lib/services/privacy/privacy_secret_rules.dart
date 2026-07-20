// De secrets-familie: API-sleutels, tokens, private keys en wachtwoorden.
//
// Dit is de goedkoopste en hoogst renderende familie van de hele scanner.
// Leverancierstokens hebben een vaste prefix — `AKIA`, `ghp_`, `xoxb-`,
// `sk_live_` — en die prefix maakt de detectie vrijwel vals-positief-vrij. Waar
// de identificatoren checksums nodig hebben om ruis te onderdrukken, doet hier
// het formaat zelf het werk.
//
// Wat er wél mis kan gaan, gaat mis op twee plekken, en die dekken we allebei af:
//
//   * de gedocumenteerde voorbeeldsleutels van de leveranciers zelf (AWS' eigen
//     `AKIAIOSFODNN7EXAMPLE` staat in half hun documentatie);
//   * de placeholders in een handleiding: `<your-key>`, `YOUR_API_KEY`,
//     `changeme`, `xxx`. Een slide die uitlegt *hoe* je een sleutel invult, mag
//     geen alarm geven.

import 'dart:convert';
import 'dart:math';

import '../../models/privacy_finding.dart';

/// Eén detectieregel voor een geheim.
class SecretRule {
  final String id;
  final RegExp pattern;

  /// Extra controle bovenop de regex. Null = het formaat is bewijs genoeg.
  final bool Function(String match)? validate;

  /// Woorden die in de buurt moeten staan. Leeg = de vorm draagt het bewijs.
  ///
  /// Vrijwel elk geheim hier heeft een prefix die nergens anders voorkomt
  /// (`AKIA`, `glpat-`, `-----BEGIN`), en die heeft geen context nodig. De
  /// uitzondering is `secret.entropy`, dat op vorm-lóze willekeur afgaat en
  /// zonder poort elke base64-blob zou melden.
  final List<String> contextWords;

  /// Hoe zeker de treffer is. Vrijwel altijd `certain`: een AWS-sleutel is een
  /// AWS-sleutel. `secret.entropy` is de uitzondering en blijft `possible`.
  final PrivacyConfidence confidence;

  const SecretRule(
    this.id,
    this.pattern, {
    this.validate,
    this.contextWords = const [],
    this.confidence = PrivacyConfidence.certain,
  });
}

/// Waarden die eruitzien als een geheim maar er geen zijn.
///
/// Deels de officiële voorbeeldsleutels van de leveranciers, deels de klassieke
/// invulinstructies. Een slide die uitlegt hoe je een sleutel configureert, moet
/// stil blijven — anders leert de gebruiker dat hij deze meldingen kan negeren.
const Set<String> knownExampleSecrets = {
  'AKIAIOSFODNN7EXAMPLE',
  'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
  'AIzaSyD-EXAMPLE-KEY-1234567890abcdefghij',
};

/// Onmiskenbare invulplaatsen: hoofdletters, punthaken, herhaalde x'en.
final RegExp _placeholderValue = RegExp(
  r'^(?:'
  r'<[^>]*>'
  r'|\$\{[^}]*\}'
  r'|\{\{[^}]*\}\}'
  r'|%[A-Z_]+%'
  r'|\$[A-Z_]+'
  r'|x{3,}|X{3,}|\*{3,}|\.{3,}|-{3,}'
  r'|your[_-]?\w*'
  r'|my[_-]?\w*key'
  r'|changeme|change_me|placeholder|redacted|todo|tbd|secret|password|hunter2'
  r'|abc123|test|dummy|example|sample|insert[_-]?\w*'
  r')$',
  caseSensitive: false,
);

/// Waarden die in broncode staan waar een geheim zou kunnen staan, maar die
/// juist het *ontbreken* ervan uitdrukken.
///
/// Zonder deze lijst gaat `const token = null;` af — en een codeslide vol
/// `password = null` zou de scanner meteen ongeloofwaardig maken.
const Set<String> _codeLiterals = {
  'null',
  'nil',
  'none',
  'true',
  'false',
  'undefined',
  'empty',
  '{}',
  '[]',
  '""',
  "''",
};

/// Is dit een invulplaats in plaats van een echt geheim?
bool isPlaceholderSecret(String value) {
  final trimmed = value.trim().replaceAll(RegExp(r'''^["']|["'];?$'''), '');
  if (trimmed.isEmpty) return true;
  if (_codeLiterals.contains(trimmed.toLowerCase())) return true;
  if (knownExampleSecrets.contains(trimmed)) return true;
  if (_placeholderValue.hasMatch(trimmed)) return true;
  // Een waarde die alleen uit één herhaald teken bestaat, is geen sleutel.
  if (RegExp(r'^(.)\1*$').hasMatch(trimmed)) return true;
  // Te kort om een wachtwoord te zijn. Bewust laag: `hunter2` is zeven tekens,
  // en die willen we wél zien.
  if (trimmed.length < 6) return true;
  return false;
}

/// Een JWT herkennen we niet aan zijn vorm maar aan zijn inhoud.
///
/// `eyJ…` is base64url voor `{"`, dus elke JSON die met een accolade begint,
/// codeert daarnaar. Door de header écht te decoderen en op een `alg`-veld te
/// controleren, gaat de vals-positieve kans naar vrijwel nul — en dat is de moeite
/// waard, want een JWT is zelf een container vol persoonsgegevens (`sub`, `email`,
/// `name`).
bool isDecodableJwt(String token) {
  final parts = token.split('.');
  if (parts.length < 2) return false;
  try {
    final normalized = base64Url.normalize(parts.first);
    final header = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    return header is Map && header.containsKey('alg');
  } on FormatException {
    // Geen geldige base64url of geen geldige JSON: dan is het geen JWT.
    return false;
  }
}

/// De Shannon-entropie van een string, in bits per teken.
///
/// Een maat voor hoe onvoorspelbaar de tekens zijn. `aaaaaaaa` levert 0 op,
/// twintig verschillende tekens ruim vier. Willekeurig gegenereerde sleutels
/// zitten hoog; woorden, zinnen en versienummers laag, omdat letters zich daarin
/// herhalen.
double shannonEntropy(String value) {
  if (value.isEmpty) return 0;
  final counts = <int, int>{};
  for (final unit in value.codeUnits) {
    counts[unit] = (counts[unit] ?? 0) + 1;
  }
  var entropy = 0.0;
  for (final count in counts.values) {
    final p = count / value.length;
    entropy -= p * (log(p) / ln2);
  }
  return entropy;
}

/// Strings die hoog scoren op entropie maar geen geheim zijn.
///
/// Dit is de lijst die `secret.entropy` bruikbaar maakt in plaats van
/// ondraaglijk. Een git-SHA, een UUID en een base64-afbeelding halen de
/// entropiedrempel moeiteloos, en ze staan alle drie in gewone technische
/// slides. Zonder deze uitsluitingen zou de regel vooral commit-hashes melden.
bool isHighEntropyButHarmless(String value) {
  final v = value.trim();

  // Alleen hex: git-SHA's (7/8/40/64), MD5 (32), checksums, UUID's zonder
  // streepjes. Een echt geheim beperkt zich zelden tot zestien tekens.
  if (RegExp(r'^[0-9a-fA-F]+$').hasMatch(v)) return true;

  // UUID mét streepjes.
  if (RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(v)) {
    return true;
  }

  // Een base64-afbeelding of ander data-URI-blok. De regex hieronder kan er
  // middenin landen, dus dit vangt de staart en niet de kop — vandaar de
  // aparte controle op de omringende tekst in de scanner.
  if (v.length > 200) return true;

  return false;
}

/// Contextwoorden waaraan `secret.entropy` zijn bestaansrecht ontleent.
///
/// Meertalig, want de scanner draait in 31 talen en een codeslide is zelden
/// consequent. Data, geen UI: deze woorden worden nooit getoond.
const List<String> entropyContextWords = [
  'secret',
  'token',
  'key',
  'sleutel',
  'password',
  'passwd',
  'wachtwoord',
  'credential',
  'apikey',
  'api_key',
  'api-key',
  'auth',
  'bearer',
  'geheim',
  'schlüssel',
  'passwort',
  'clé',
  'mot de passe',
  'contraseña',
  'clave',
];

/// De regeltabel. Data, geen code — zo blijft de scanner kort en is een regel
/// toevoegen één regel.
final List<SecretRule> secretRules = [
  // ── Leverancierstokens: prefix = bewijs ────────────────────────────────────
  SecretRule('secret.aws', RegExp(r'\b(?:AKIA|ASIA)[0-9A-Z]{16}\b')),
  SecretRule('secret.gcp', RegExp(r'\bAIza[0-9A-Za-z\-_]{35}\b')),
  SecretRule(
    'secret.github',
    RegExp(r'\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{60,})\b'),
  ),
  SecretRule('secret.gitlab', RegExp(r'\bglpat-[A-Za-z0-9\-_]{20,}\b')),
  SecretRule('secret.slack', RegExp(r'\bxox[baprs]-[A-Za-z0-9-]{10,}\b')),
  // Alleen LIVE-sleutels. `sk_test_` is per definitie waardeloos en zou een
  // demoslide onterecht laten afgaan.
  SecretRule('secret.stripe', RegExp(r'\b[sr]k_live_[A-Za-z0-9]{16,}\b')),
  SecretRule('secret.llm', RegExp(r'\bsk-(?:ant-)?[A-Za-z0-9\-_]{32,}\b')),
  SecretRule('secret.huggingface', RegExp(r'\bhf_[A-Za-z0-9]{30,}\b')),
  SecretRule(
    'secret.sendgrid',
    RegExp(r'\bSG\.[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{30,}\b'),
  ),
  SecretRule('secret.npm', RegExp(r'\bnpm_[A-Za-z0-9]{36}\b')),

  // ── Structureel onmiskenbaar ──────────────────────────────────────────────
  SecretRule(
    'secret.private_key',
    RegExp(
      r'-----BEGIN (?:RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY(?: BLOCK)?-----',
    ),
  ),
  SecretRule(
    'secret.jwt',
    RegExp(r'\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]*'),
    validate: isDecodableJwt,
  ),
  // Een wachtwoord ín een URL. Postgres, MySQL, Mongo, Redis, AMQP, of gewoon
  // basic-auth over https.
  SecretRule(
    'secret.connection_string',
    RegExp(
      r'\b(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?|redis|amqp|ftp|https?)'
      r'://[^\s:/@]+:[^\s@/]+@[^\s/]+',
    ),
    validate: connectionStringHasRealPassword,
  ),
  // Azure kent twee vormen die allebei volledige toegang geven. De
  // connection string draagt de sleutel zelf; het SAS-token draagt een
  // handtekening die net zo goed werkt, en staat vaak kaal in een URL op een
  // architectuurslide.
  SecretRule(
    'secret.azure',
    RegExp(
      r'(?:DefaultEndpointsProtocol=[^\s;]+;[^\s]*AccountKey=[A-Za-z0-9+/=]{20,}'
      r'|\bsv=\d{4}-\d{2}-\d{2}[^\s]*&sig=[A-Za-z0-9%+/=]{20,})',
      caseSensitive: false,
    ),
  ),

  // ── Wachtwoordhashes ──────────────────────────────────────────────────────
  //
  // Een hash is geen wachtwoord, en juist daarom melden mensen hem niet. Maar
  // een bcrypt- of NTLM-hash op een slide is een uitnodiging om te kraken, en
  // bij `/etc/shadow`-regels staat de gebruikersnaam er gratis bij. De
  // `$id$`-vorm is een standaard (crypt(3)) en komt nergens anders voor.
  SecretRule(
    'secret.hash',
    RegExp(
      r'\$(?:2[aby]|argon2(?:id|i|d)|6|5|1|y)\$[^\s:]{8,}'
      // NTLM/LM: 32 hex, maar alleen in de `gebruiker:id:lm:nt:::`-vorm van een
      // dump. Kaal is 32 hex een MD5 van iets onschuldigs, en dat mag niet
      // afgaan — zie `isHighEntropyButHarmless`.
      r'|\b[^\s:]+:\d+:[0-9a-fA-F]{32}:[0-9a-fA-F]{32}:::',
    ),
  ),

  // ── Tweede factor ─────────────────────────────────────────────────────────
  //
  // De TOTP-seed is het gedeelde geheim achter elke authenticator-app: wie hem
  // heeft, genereert dezelfde codes als de eigenaar en de tweede factor is weg.
  // Hij lekt bijna altijd via de QR-code — en de `otpauth://`-URI erachter komt
  // in screenshots en onboardingslides terecht.
  SecretRule(
    'secret.totp',
    RegExp(
      r'otpauth://[a-z]+/[^\s]*[?&]secret=[A-Z2-7]{16,}',
      caseSensitive: false,
    ),
  ),

  // ── Het vangnet ───────────────────────────────────────────────────────────
  //
  // Alles hierboven herkent een geheim aan zijn vórm. Deze regel bestaat voor de
  // geheimen zonder vorm: de interne token, de sleutel van een leverancier die
  // hier niet staat, het gegenereerde wachtwoord.
  //
  // Daarom is dit de enige regel met een contextpoort én de enige die niet boven
  // `possible` uitkomt. Willekeur is geen bewijs — een minified bundel, een
  // base64-blob en een commit-hash zijn ook willekeurig. Het contextwoord doet
  // hier het werk dat elders de prefix doet, en `possible` zorgt dat een misser
  // niemand onderbreekt en niets escaleert.
  SecretRule(
    'secret.entropy',
    RegExp(r'[A-Za-z0-9+/=_\-]{20,}'),
    validate: isPlausibleHighEntropySecret,
    contextWords: entropyContextWords,
    confidence: PrivacyConfidence.possible,
  ),
];

/// Ziet dit eruit als willekeur, en niet als iets onschuldigs dat toevallig
/// willekeurig oogt?
///
/// Drie eisen tegelijk, want elk afzonderlijk laat te veel door. Alleen entropie
/// meldt commit-hashes; alleen gemengde casing meldt elke CamelCase-klassenaam;
/// alleen lengte meldt elke URL.
bool isPlausibleHighEntropySecret(String value) {
  if (value.length < 20) return false;
  if (isHighEntropyButHarmless(value)) return false;
  if (shannonEntropy(value) < 4.0) return false;

  final hasLower = RegExp(r'[a-z]').hasMatch(value);
  final hasUpper = RegExp(r'[A-Z]').hasMatch(value);
  final hasDigit = RegExp(r'\d').hasMatch(value);
  return hasLower && hasUpper && hasDigit;
}

/// Het wachtwoorddeel van een connection string, niet de hele URL, door de
/// placeholder-poort halen.
///
/// Documentatie illustreert dit patroon nu eenmaal met `postgres://user:pass@…`.
/// Zou de hele match tellen, dan gaat elke handleiding af die uitlegt hóé een
/// connection string eruitziet — inclusief onze eigen ontwerpdocumenten. Dat is
/// geen theoretisch risico: dit is precies waar de corpustest ons op betrapte.
bool connectionStringHasRealPassword(String match) {
  final m = RegExp(r'://[^\s:/@]+:([^\s@/]+)@').firstMatch(match);
  if (m == null) return false;
  return !isPlaceholderSecret(m.group(1)!);
}

/// Een wachtwoord in klare taal: `wachtwoord: hunter2`.
///
/// Het contextwoord is meertalig, want de scanner draait in 31 talen en een
/// Duitse slide schrijft `Passwort`.
final RegExp secretAssignment = RegExp(
  r'\b(?:wachtwoord|password|passwort|passwd|pwd|mot de passe|contraseña'
  r'|senha|hasło|salasana|lösenord|adgangskode|heslo|jelszó'
  r'|pincode|api[_\s-]?key|apikey|secret|token|client[_\s-]?secret)'
  r'\s*[:=]\s*(\S+)',
  caseSensitive: false,
);
