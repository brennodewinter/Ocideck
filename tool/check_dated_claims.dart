// Verouderingspoort voor de **gemeten beweringen** in de documentatie.
//
//   dart run tool/check_dated_claims.dart                 (structuur)
//   dart run tool/check_dated_claims.dart --tegen-de-klok  (+ houdbaarheid)
//
// Waarom dit bestaat. `docs/CHECKS.md` beloofde op twee plekken dat een rode
// `main` zich "within ~half an hour" van de merge meldt. Op 2026-09-03 gemeten
// was dat mediaan 54 minuten, met 85 op het 90e percentiel. De claim was juist
// toen hij werd opgeschreven en stapte rond 2026-08-23 omhoog zonder dat de
// werkstroom veranderde: de suite groeit, de runner niet. Geen enkele poort zag
// het, en dat kón ook niet — er stond geen datum bij, dus er was niets om tegen
// te toetsen.
//
// Dat is een eigen klasse. De poorten op de code toetsen hard, maar een
// bewering over een *gemeten* grootheid verrot terwijl de boom stilstaat. Dit
// is de tegenhanger van tool/check_reference_data.dart (externe standaarden die
// verouderen) voor onze eigen metingen.
//
// ── Twee helften, en de tweede houdt de eerste eerlijk ──────────────────────
//
// 1. **Het register** ([gemetenBeweringen]) is de lijst van beweringen die
//    leven: waar ze staan, wat er gemeten is, wanneer, en waarmee je ze
//    opnieuw meet. Daarop toetst deze poort drie dingen — staat het anker er
//    nog, draagt het document dezelfde datum als het register, en is de meting
//    nog houdbaar.
//
// 2. **De basislijn** ([looptijdBasislijn]) telt élke looptijduitdrukking in de
//    bewaakte documenten. Zonder die tweede helft bewaakt het register alleen
//    wat iemand eraan heeft toegevoegd, en is de volgende ongedateerde claim
//    net zo onzichtbaar als de vorige. Komt er een uitdrukking bij, dan valt de
//    poort om met de vraag: registreer hem met een meetdatum, of zet hem in de
//    basislijn omdat het geschiedenis is.
//
// Die basislijn is dus geen dekking maar een teller. Wat er vandaag in staat is
// grotendeels verhaal ("#790 zette hem uit omdat hij 17,5 minuten kostte") en
// geen levende belofte; dat hoeft niet hermeten te worden. Wat het wél doet is
// voorkomen dat er ongemerkt een nieuwe belofte bij komt.
//
// ── Wat deze poort niet ziet ────────────────────────────────────────────────
//
// De basislijn is een multiset van uitdrukkingen, geen plaatsbepaling. Wie in
// hetzelfde bestand één "22 minutes" weghaalt en er elders één neerzet, komt er
// stil doorheen. Dat is de prijs van een teller die niet op regelnummers
// vastzit — die zou bij elke herwikkeling van een alinea omvallen. De grens
// staat hier opgeschreven omdat een poort waarvan niemand de blinde vlek kent
// voor meer bewijs wordt gehouden dan hij levert.
//
// Ook buiten beeld: beweringen zonder tijdseenheid. "87,1% dekking" of "11.078
// tests" verouderen net zo goed, maar die worden elders al tegen de code
// getoetst (test/docs_claims_match_code_test.dart). Deze poort gaat over de
// grootheid die géén constante in de code heeft: hoe lang iets duurt.
//
// ── Waarom twee momenten ────────────────────────────────────────────────────
//
// Zonder vlag toetst dit alleen wat van de boom af te lezen is: ankers en
// basislijn. Dat is deterministisch en hoort daarom in `make check` en in de
// statische poort per PR.
//
// Met `--tegen-de-klok` komt de houdbaarheid erbij. Die verandert van uitkomst
// zonder dat er een commit aan te pas komt, en hoort dus in
// `.forgejo/workflows/time-degrading-checks.yml` — dagelijks, tegen de klok.
// Zou de houdbaarheid in de PR-poort zitten, dan valt op een dag een
// willekeurige PR om op een bewering waar de indiener niets mee te maken heeft.
//
// Exit codes:  0 = alles in orde
//              1 = ten minste één bewering is zoek, wijkt af of is verouderd

import 'dart:io';

/// Een bewering over een gemeten grootheid die in de documentatie staat.
///
/// [anker] is de letterlijke tekst waaraan de bewering te herkennen is. Staat
/// hij er niet meer, dan is de bewering herschreven zonder dat dit register
/// meebewoog en bewaakt de regel hieronder niets meer — dat is een faal, geen
/// stilte. Zie de MIAUW-les in tool/check_reference_data.dart: een poort die
/// alleen groen kan zijn is erger dan geen poort.
class GemetenBewering {
  const GemetenBewering({
    required this.id,
    required this.bestand,
    required this.anker,
    required this.grootheid,
    required this.gemetenOp,
    required this.houdbaarDagen,
    required this.hermeetMet,
  });

  /// Korte sleutel voor de meldingen.
  final String id;

  /// Het document waarin de bewering staat, vanaf de wortel van de repo.
  final String bestand;

  /// Letterlijke tekst die het document moet dragen, inclusief de meetdatum.
  final String anker;

  /// Wat er gemeten is, in één zin — voor wie de melding leest.
  final String grootheid;

  /// De meetdatum, als `YYYY-MM-DD`.
  final String gemetenOp;

  /// Hoe lang deze meting mag blijven staan voordat iemand hem naloopt.
  final int houdbaarDagen;

  /// Hoe je hem opnieuw meet. Zonder dit is "verouderd" een melding waar de
  /// lezer niets mee kan.
  final String hermeetMet;
}

/// De beweringen die leven: iemand belooft er iets mee, en de grootheid
/// beweegt.
///
/// Historische getallen horen hier **niet** in. "De poort kostte in #790 17,5
/// minuten" is een gebeurtenis en verandert niet meer; die staat in
/// [looptijdBasislijn] en blijft daar staan.
const List<GemetenBewering> gemetenBeweringen = [
  GemetenBewering(
    id: 'linux-gate-oordeel',
    bestand: 'docs/CHECKS.md',
    anker: 'measured 2026-09-03',
    grootheid: 'de looptijd van een linux-gate-run, mediaan en 90e percentiel',
    gemetenOp: '2026-09-03',
    houdbaarDagen: 120,
    hermeetMet:
        'percentielen over (stopped-started) in action_run op de forge, '
        "gefilterd op workflow_id='linux-gate.yml'",
  ),
  GemetenBewering(
    id: 'make-check-looptijd',
    bestand: 'docs/CHECKS.md',
    anker: 'Measured 2026-09-01 on the machine',
    grootheid:
        'de looptijd van de volledige `make check` op de onderhouder-Mac',
    gemetenOp: '2026-09-01',
    houdbaarDagen: 120,
    hermeetMet:
        'time make check, op de machine die er in dezelfde alinea staat',
  ),
];

/// Elke looptijduitdrukking in de bewaakte documenten, met hoe vaak hij
/// voorkomt. RATCHET op de samenstelling: een uitdrukking erbij is een faal.
///
/// Dat het er zoveel zijn is geen probleem: verreweg de meeste zijn verhaal
/// ("kostte 17,5 minuten", "22 minutes per pull request") en geen belofte. Ze
/// staan hier zodat een *nieuwe* uitdrukking opvalt — want dat is de plek waar
/// de volgende ongedateerde belofte binnenkomt.
const Map<String, Map<String, int>> looptijdBasislijn = {
  'docs/CHECKS.md': {
    '13 minutes': 2,
    '17.5 minutes': 2,
    '19 seconds': 1,
    '2 seconds': 2,
    '2.5 minutes': 1,
    '21 min': 1,
    '22 minutes': 2,
    '29 minutes': 1,
    '33 min': 2,
    '46 minute': 3,
    '46 minutes': 1,
    '51 minutes': 2,
    '54 minutes': 1,
    // De dagkosten van de oude per-merge-cadence (7,6 merges maal 51 minuten),
    // het cijfer dat de wissel naar `schedule` droeg. Geschiedenis: het gaat
    // over een trigger die niet meer bestaat.
    '6.5 hours': 1,
    'half an hour': 1,
  },
  'CONTRIBUTING.md': {'2.5 minutes': 1, '22 minutes': 1},
  'docs/BUILD.md': {
    '17.5 minutes': 1,
    '2.5 minute': 1,
    '2.5 minutes': 1,
    '22 minutes': 1,
    '30 minutes': 2,
    '45 minute': 1,
    '75 min': 1,
    'a few minutes': 1,
    'half an hour': 1,
  },
};

/// Een getal met een tijdseenheid, plus de woordvormen die net zo goed een
/// belofte zijn.
///
/// Die woordvormen zijn geen bijvangst maar de aanleiding: de claim die dit
/// hele bestand veroorzaakte was "half an hour" en droeg geen cijfer. Een
/// patroon dat alleen op `\d+ minutes` let, had hem nooit gezien.
final RegExp looptijdPatroon = RegExp(
  r'\b\d+(?:[.,:]\d+)?\s*-?\s*'
  r'(?:minutes?|minuut|minuten|mins?|seconds?|seconden?|secs?|hours?|uur|uren)'
  r'\b|half an hour|a few minutes|an hour or so|about an hour',
  caseSensitive: false,
);

/// Wat er met één bewering aan de hand is.
enum Staat {
  /// Anker gevonden, datum klopt, meting nog houdbaar.
  vers,

  /// Het anker staat niet meer in het document: de bewering is herschreven en
  /// dit register bewaakt niets meer.
  zoek,

  /// De houdbaarheid is verstreken; een mens moet opnieuw meten.
  verouderd,
}

/// Beoordeelt één bewering tegen de inhoud van haar document.
///
/// [nu] wordt ingespoten in plaats van van de systeemklok gelezen, zodat de
/// test de houdbaarheid kan laten verlopen zonder te wachten.
Staat beoordeel(
  GemetenBewering bewering,
  String inhoud,
  DateTime nu, {
  required bool tegenDeKlok,
}) {
  if (!genormaliseerd(inhoud).contains(genormaliseerd(bewering.anker))) {
    return Staat.zoek;
  }
  if (!tegenDeKlok) return Staat.vers;
  final gemeten = DateTime.parse(bewering.gemetenOp);
  final dagen = nu.difference(gemeten).inDays;
  return dagen > bewering.houdbaarDagen ? Staat.verouderd : Staat.vers;
}

/// Plakt witruimte plat, zodat een anker dat over twee regels is afgebroken
/// nog steeds gevonden wordt. Zonder dit valt de poort om op een herwikkeling
/// die niets aan de betekenis verandert.
String genormaliseerd(String tekst) => tekst.replaceAll(RegExp(r'\s+'), ' ');

/// Haalt de tekst tussen backticks weg.
///
/// Een uitdrukking in code-opmaak is een *geciteerd* woord — de documentatie
/// van deze poort noemt `half an hour` als patroon, en dat is geen belofte over
/// hoe lang iets duurt. Zonder deze stap valt de poort om op zijn eigen
/// beschrijving, en dat is precies het soort ruis waardoor een poort wordt
/// uitgezet. Dezelfde afweging als in tool/check_comment_language.dart, dat om
/// dezelfde reden backticks laat vallen voordat het woorden telt.
String zonderCodeSpans(String tekst) =>
    tekst.replaceAll(RegExp('`[^`]*`'), ' ');

/// Telt de looptijduitdrukkingen in [inhoud], op dezelfde manier waarop
/// [looptijdBasislijn] is opgeschreven.
Map<String, int> looptijdenIn(String inhoud) {
  final telling = <String, int>{};
  final tekst = zonderCodeSpans(genormaliseerd(inhoud));
  for (final treffer in looptijdPatroon.allMatches(tekst)) {
    final sleutel = treffer
        .group(0)!
        .toLowerCase()
        .replaceAll(RegExp(r'\s*-\s*'), ' ');
    telling[sleutel] = (telling[sleutel] ?? 0) + 1;
  }
  return telling;
}

/// Het verschil tussen de basislijn en wat er nu staat, als leesbare regels.
/// Leeg betekent gelijk.
List<String> afwijkingen(Map<String, int> basislijn, Map<String, int> nu) {
  final regels = <String>[];
  for (final sleutel in {...basislijn.keys, ...nu.keys}.toList()..sort()) {
    final was = basislijn[sleutel] ?? 0;
    final is_ = nu[sleutel] ?? 0;
    if (was != is_) regels.add('  "$sleutel": basislijn $was, nu $is_');
  }
  return regels;
}

void main(List<String> args) {
  final tegenDeKlok = args.contains('--tegen-de-klok');
  final nu = DateTime.now();
  var fout = false;

  stdout.writeln('== OciDeck: gedateerde beweringen ==');

  for (final bewering in gemetenBeweringen) {
    final bestand = File(bewering.bestand);
    if (!bestand.existsSync()) {
      stdout.writeln(
        'ZOEK      ${bewering.id}: ${bewering.bestand} bestaat niet',
      );
      fout = true;
      continue;
    }
    final staat = beoordeel(
      bewering,
      bestand.readAsStringSync(),
      nu,
      tegenDeKlok: tegenDeKlok,
    );
    fout = _meld(bewering, staat, nu) || fout;
  }

  fout = _meldBasislijn() || fout;

  if (!tegenDeKlok) {
    stdout.writeln(
      'Houdbaarheid niet getoetst — draai met --tegen-de-klok voor die vraag.',
    );
  }
  exitCode = fout ? 1 : 0;
}

/// Schrijft de uitkomst van één bewering weg. Geeft terug of dit een faal is.
bool _meld(GemetenBewering bewering, Staat staat, DateTime nu) {
  switch (staat) {
    case Staat.vers:
      stdout.writeln('vers      ${bewering.id} (${bewering.gemetenOp})');
      return false;
    case Staat.zoek:
      stdout.writeln(
        'ZOEK      ${bewering.id}: het anker "${bewering.anker}" staat niet '
        'meer in ${bewering.bestand}.\n'
        '          De bewering is herschreven zonder dat het register '
        'meebewoog; werk gemetenBeweringen bij.',
      );
      return true;
    case Staat.verouderd:
      final dagen = nu.difference(DateTime.parse(bewering.gemetenOp)).inDays;
      stdout.writeln(
        'VEROUDERD ${bewering.id}: ${bewering.grootheid}\n'
        '          gemeten ${bewering.gemetenOp}, $dagen dagen geleden '
        '(houdbaar ${bewering.houdbaarDagen}).\n'
        '          Hermeet: ${bewering.hermeetMet}',
      );
      return true;
  }
}

/// Toetst de bewaakte documenten tegen [looptijdBasislijn]. Geeft terug of er
/// iets afwijkt.
bool _meldBasislijn() {
  var fout = false;
  for (final pad in looptijdBasislijn.keys) {
    final bestand = File(pad);
    if (!bestand.existsSync()) {
      stdout.writeln('ZOEK      $pad bestaat niet');
      fout = true;
      continue;
    }
    final regels = afwijkingen(
      looptijdBasislijn[pad]!,
      looptijdenIn(bestand.readAsStringSync()),
    );
    if (regels.isEmpty) {
      stdout.writeln('gelijk    $pad');
      continue;
    }
    stdout.writeln(
      'AFWIJKING $pad draagt andere looptijduitdrukkingen dan de basislijn:\n'
      '${regels.join('\n')}\n'
      '          Nieuw en een levende belofte? Meet hem, zet de datum erbij en '
      'registreer hem in gemetenBeweringen.\n'
      '          Nieuw maar geschiedenis (een getal uit een verhaal)? Werk '
      'looptijdBasislijn bij.',
    );
    fout = true;
  }
  return fout;
}
