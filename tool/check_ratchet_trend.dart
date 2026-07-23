// Meetinstrument voor de ratchets: bewegen ze de goede kant op?
//
//   dart run tool/check_ratchet_trend.dart              (of: make ratchets)
//   dart run tool/check_ratchet_trend.dart --sinds=180  (ander ijkpunt in dagen)
//   dart run tool/check_ratchet_trend.dart --strict     (eindigt op 1 bij stilstand)
//
// ── Waarom dit er is ───────────────────────────────────────────────────────
//
// De poorten meten of iets *werkt*. Ze meten niet of het beter wordt. Er staan
// inmiddels negen basislijnen in dit project, elk met dezelfde afspraak: hij
// mag krimpen en nooit groeien. Wat niemand ziet, is of er ooit iets gekrompen
// ís. Een ratchet die een jaar stilstaat, is geen bewaakte schuld maar een
// schuld die comfortabel is gemaakt — en dat is precies het verschil dat een
// groene poort niet laat zien.
//
// Hetzelfde geldt voor dekking. 82% over de hele boom zegt niets over de vraag
// of de gedekte regels de regels zijn die ertoe doen; één sterke map kan een
// zwakke verbergen. Daarom rapporteert dit gereedschap per map en niet in één
// getal.
//
// ── Adviserend, en dat is hier de standaard ────────────────────────────────
//
// Stilstand tot een rode bouw maken straft een rustige maand. Dit gereedschap
// eindigt daarom uit zichzelf op 0; wie het als poort wil, zet `--strict`.
// Dezelfde keuze en dezelfde redenering als in
// `tool/check_issue_turnaround.dart`.
//
// ── Hoe het meet ───────────────────────────────────────────────────────────
//
// De basislijnen staan als constante in het gereedschap dat ze bewaakt. Dit
// instrument leest die constanten uit de BRONTEKST — de huidige en die van het
// ijkpunt, opgehaald met `git show`. Bewust niet door de constanten te
// importeren: dan zou de historische waarde onbereikbaar zijn, en juist het
// verschil tussen toen en nu is wat hier gemeten wordt.
//
// Het ijkpunt is de laatste commit vóór N dagen geleden (standaard 90). Dagen
// en geen commits: "hoe lang staat dit al stil" is een vraag over tijd, en
// honderd commits kunnen een week of een jaar beslaan.
//
// ── Wat een signaal is ─────────────────────────────────────────────────────
//
// Een basislijn die niet nul is en over het hele venster geen millimeter
// bewoog. Nul is geen signaal: daar valt niets meer te winnen, en die staat op
// nul te blijven is precies de bedoeling. Groei is hier evenmin een signaal —
// niet omdat het onschuldig is, maar omdat de poort zelf dat al hard afvangt.
//
// Exit codes:  0 = gemeten (ook als er stilstand is — zie hierboven)
//              1 = alleen met --strict: ten minste één stilstaande basislijn
//              2 = de meting kon niet draaien (geen git, geen ijkpunt)
import 'dart:io';

// ── De basislijnen die dit instrument volgt ────────────────────────────────

/// Welke kant een basislijn op hoort te bewegen.
enum Richting {
  /// Lager is beter (bijna alles: minder uitzonderingen, minder schuld).
  omlaag,

  /// Hoger is beter (de dekkingsvloer, de per-bestandsvloer).
  omhoog,
}

/// Hoe één basislijn uit een bronbestand te lezen is.
class Ratchet {
  const Ratchet({
    required this.naam,
    required this.bestand,
    required this.soort,
    required this.richting,
    required this.wat,
  });

  /// De naam van de constante, zoals hij in de broncode staat.
  final String naam;

  /// Het bestand waar die constante in staat.
  final String bestand;

  final RatchetSoort soort;
  final Richting richting;

  /// Eén regel over wat het getal telt, voor de lezer die de constante niet
  /// kent.
  final String wat;
}

/// Hoe de waarde uit de brontekst komt.
enum RatchetSoort {
  /// `const int naam = 4;` — het getal zelf.
  getal,

  /// `const Map/Set … naam = { … };` — het AANTAL regels in de verzameling.
  omvang,

  /// Een getal dat als vlag in de Makefile staat (`--min=80`).
  vlag,
}

/// De basislijnen, in de volgorde waarin ze in het rapport verschijnen.
///
/// De acht uit `check_conventions.dart` plus de dekkingsvloer zijn de negen uit
/// issue #538. De drie die daarna volgen hebben dezelfde vorm en dezelfde
/// afspraak; ze weglaten zou ze onzichtbaar houden om geen andere reden dan dat
/// niemand ze toen opnoemde.
const List<Ratchet> ratchets = [
  Ratchet(
    naam: 'catchUnderscoreBaseline',
    bestand: 'tool/check_conventions.dart',
    soort: RatchetSoort.getal,
    richting: Richting.omlaag,
    wat: 'stil weggeslikte fouten: bare catch (_) in lib/',
  ),
  Ratchet(
    naam: 'rawColorBaseline',
    bestand: 'tool/check_conventions.dart',
    soort: RatchetSoort.getal,
    richting: Richting.omlaag,
    wat: 'letterlijke Color(0x…) buiten het thema',
  ),
  Ratchet(
    naam: 'debugPrintBaseline',
    bestand: 'tool/check_conventions.dart',
    soort: RatchetSoort.getal,
    richting: Richting.omlaag,
    wat: 'print()/debugPrint() buiten de logger',
  ),
  Ratchet(
    naam: 'controlByteBaseline',
    bestand: 'tool/check_conventions.dart',
    soort: RatchetSoort.getal,
    richting: Richting.omlaag,
    wat: 'rauwe stuurbytes in de broncode',
  ),
  Ratchet(
    naam: 'serviceUiImportBaseline',
    bestand: 'tool/check_conventions.dart',
    soort: RatchetSoort.getal,
    richting: Richting.omlaag,
    wat: 'UI-imports in lib/services (de kop-loze kern)',
  ),
  Ratchet(
    naam: 'fileSizeBaseline',
    bestand: 'tool/check_conventions.dart',
    soort: RatchetSoort.omvang,
    richting: Richting.omlaag,
    wat: 'bestanden met een eigen plafond boven de 1000 regels',
  ),
  Ratchet(
    naam: 'classSizeBaseline',
    bestand: 'tool/check_conventions.dart',
    soort: RatchetSoort.omvang,
    richting: Richting.omlaag,
    wat: 'klassen met een eigen plafond boven de 1000 regels',
  ),
  Ratchet(
    naam: 'filePickerPathBaseline',
    bestand: 'tool/check_conventions.dart',
    soort: RatchetSoort.omvang,
    richting: Richting.omlaag,
    wat: 'bestanden die hun platformpoort bij de aanroeper hebben',
  ),
  Ratchet(
    naam: 'nosemgrepBaseline',
    bestand: 'tool/check_conventions.dart',
    soort: RatchetSoort.getal,
    richting: Richting.omlaag,
    wat: 'onderdrukte SAST-bevindingen in lib/',
  ),
  Ratchet(
    naam: '--min',
    bestand: 'Makefile',
    soort: RatchetSoort.vlag,
    richting: Richting.omhoog,
    wat: 'de dekkingsvloer over lib/ (procent)',
  ),
  Ratchet(
    naam: 'modelUiImportBaseline',
    bestand: 'tool/check_conventions.dart',
    soort: RatchetSoort.getal,
    richting: Richting.omlaag,
    wat: 'UI-imports in lib/models (harde nul)',
  ),
  Ratchet(
    naam: 'methodLengthBaseline',
    bestand: 'tool/check_method_length.dart',
    soort: RatchetSoort.omvang,
    richting: Richting.omlaag,
    wat: 'methodes met een eigen plafond boven de 150 regels',
  ),
  Ratchet(
    naam: 'mixedCommentBaseline',
    bestand: 'tool/check_comment_language.dart',
    soort: RatchetSoort.getal,
    richting: Richting.omlaag,
    wat: 'commentaarblokken die halverwege van taal wisselen',
  ),
  Ratchet(
    naam: 'uncoveredBaseline',
    bestand: 'tool/coverage_summary.dart',
    soort: RatchetSoort.omvang,
    richting: Richting.omlaag,
    wat: 'lib/-bestanden die in geen enkele test voorkomen',
  ),
  Ratchet(
    naam: 'perFileFloorPercent',
    bestand: 'tool/coverage_summary.dart',
    soort: RatchetSoort.getal,
    richting: Richting.omhoog,
    wat: 'de vloer per bestand (procent uitgevoerde regels)',
  ),
];

/// De bestanden waaruit de basislijnen komen, zonder dubbelen.
List<String> get ratchetBestanden =>
    {for (final r in ratchets) r.bestand}.toList()..sort();

// ── De brontekst uitlezen ──────────────────────────────────────────────────

/// Verwijdert regelcommentaar uit Dart-brontekst, zonder in een string te
/// snijden.
///
/// Nodig omdat de basislijnen vol commentaar staan — `uncoveredBaseline` legt
/// per regel uit waaróm een bestand er staat, en die uitleg zit vol komma's en
/// accolades. Wie die meetelt, telt een basislijn van 25 als 60.
String zonderRegelcommentaar(String bron) {
  final uit = StringBuffer();
  var inString = false;
  String? aanhaling;
  for (var i = 0; i < bron.length; i++) {
    final teken = bron[i];
    if (inString) {
      uit.write(teken);
      if (teken == r'\') {
        if (i + 1 < bron.length) {
          uit.write(bron[i + 1]);
          i++;
        }
      } else if (teken == aanhaling) {
        inString = false;
        aanhaling = null;
      }
      continue;
    }
    if (teken == "'" || teken == '"') {
      inString = true;
      aanhaling = teken;
      uit.write(teken);
      continue;
    }
    if (teken == '/' && i + 1 < bron.length && bron[i + 1] == '/') {
      while (i < bron.length && bron[i] != '\n') {
        i++;
      }
      uit.write('\n');
      continue;
    }
    uit.write(teken);
  }
  return uit.toString();
}

/// De waarde van `const int <naam> = <getal>;` in [bron], of null.
int? getalUit(String bron, String naam) {
  final schoon = zonderRegelcommentaar(bron);
  final treffer = RegExp(
    '\\b${RegExp.escape(naam)}\\s*=\\s*(-?\\d+)\\s*;',
  ).firstMatch(schoon);
  return treffer == null ? null : int.tryParse(treffer.group(1)!);
}

/// Het aantal regels in de verzameling `<naam> = { … }` in [bron], of null als
/// die verzameling er niet staat.
///
/// Geteld worden de komma's op het bovenste niveau; `dart format` schrijft een
/// afsluitende komma zodra de verzameling over meer dan één regel gaat, en een
/// verzameling op één regel zonder afsluitende komma wordt apart opgevangen.
int? omvangUit(String bron, String naam) {
  final schoon = zonderRegelcommentaar(bron);
  final start = RegExp(
    '\\b${RegExp.escape(naam)}\\s*=\\s*\\{',
  ).firstMatch(schoon);
  if (start == null) return null;

  var diepte = 0;
  var kommas = 0;
  var laatsteZichtbaar = '';
  var eindeInhoud = -1;
  for (var i = start.end - 1; i < schoon.length; i++) {
    final teken = schoon[i];
    if (teken == '{' || teken == '[' || teken == '(') diepte++;
    if (teken == '}' || teken == ']' || teken == ')') {
      diepte--;
      if (diepte == 0) {
        eindeInhoud = i;
        break;
      }
    }
    if (teken == ',' && diepte == 1) kommas++;
    if (teken.trim().isNotEmpty && diepte >= 1) laatsteZichtbaar = teken;
  }
  if (eindeInhoud < 0) return null;
  final inhoud = schoon.substring(start.end, eindeInhoud).trim();
  if (inhoud.isEmpty) return 0;
  // Zonder afsluitende komma is de laatste regel niet geteld.
  return laatsteZichtbaar == ',' ? kommas : kommas + 1;
}

/// De waarde van een vlag als `--min=80` in [bron] (de Makefile), of null.
int? vlagUit(String bron, String naam) {
  final treffer = RegExp('${RegExp.escape(naam)}=(\\d+)').firstMatch(bron);
  return treffer == null ? null : int.tryParse(treffer.group(1)!);
}

/// Leest [ratchet] uit de brontekst van zijn bestand, of null als hij er niet
/// in staat (bijvoorbeeld omdat hij op het ijkpunt nog niet bestond).
int? waardeUit(Ratchet ratchet, String? bron) {
  if (bron == null) return null;
  switch (ratchet.soort) {
    case RatchetSoort.getal:
      return getalUit(bron, ratchet.naam);
    case RatchetSoort.omvang:
      return omvangUit(bron, ratchet.naam);
    case RatchetSoort.vlag:
      return vlagUit(bron, ratchet.naam);
  }
}

// ── De vergelijking ────────────────────────────────────────────────────────

/// Wat er van één basislijn te zeggen valt.
class RatchetStand {
  const RatchetStand({
    required this.ratchet,
    required this.nu,
    required this.toen,
  });

  final Ratchet ratchet;

  /// De waarde nu, of null als de constante niet gevonden werd — dat laatste is
  /// zelf een bevinding: dan is dit instrument achtergebleven bij de code.
  final int? nu;

  /// De waarde op het ijkpunt, of null als hij toen niet bestond.
  final int? toen;

  bool get onvindbaar => nu == null;

  bool get isNieuw => nu != null && toen == null;

  /// Bewoog er iets, en zo ja hoeveel (positief = gestegen)?
  int? get verschil => (nu == null || toen == null) ? null : nu! - toen!;

  /// Is dit de goede kant op bewogen?
  bool get verbeterd {
    final delta = verschil;
    if (delta == null || delta == 0) return false;
    return ratchet.richting == Richting.omlaag ? delta < 0 : delta > 0;
  }

  /// Staat deze basislijn stil terwijl er nog iets te winnen valt?
  ///
  /// Nul is geen stilstand maar de eindstand. Een dekkingsvloer die stilstaat
  /// telt wél mee: die is nooit af.
  bool get stilstand {
    if (verschil != 0) return false;
    if (ratchet.richting == Richting.omlaag) return nu != 0;
    return true;
  }
}

/// Vergelijkt alle basislijnen tussen twee momentopnames van de brontekst.
///
/// [nuBronnen] en [toenBronnen] zijn per bestandspad de volledige inhoud; een
/// ontbrekend bestand hoort als null in de kaart te staan. Bewust twee kaarten
/// en geen bestandssysteem: zo is deze vergelijking te toetsen met vaste tekst,
/// zonder git en zonder werkkopie.
List<RatchetStand> vergelijk(
  Map<String, String?> nuBronnen,
  Map<String, String?> toenBronnen,
) => [
  for (final ratchet in ratchets)
    RatchetStand(
      ratchet: ratchet,
      nu: waardeUit(ratchet, nuBronnen[ratchet.bestand]),
      toen: waardeUit(ratchet, toenBronnen[ratchet.bestand]),
    ),
];

// ── Dekking per map ────────────────────────────────────────────────────────

/// De dekking van één map.
class MapDekking {
  const MapDekking({
    required this.pad,
    required this.geraakt,
    required this.gevonden,
    required this.bestanden,
  });

  final String pad;
  final int geraakt;
  final int gevonden;
  final int bestanden;

  double get percentage => gevonden == 0 ? 0 : geraakt / gevonden * 100;
}

/// Dekking per map uit een lcov-verslag, zwakste map eerst.
///
/// [diepte] is het aantal padsegmenten waarop gegroepeerd wordt: 2 geeft
/// `lib/services`, 3 geeft `lib/services/git`. Eén getal over de hele boom
/// verbergt precies wat hier zichtbaar moet worden — een zwakke map die
/// wegvalt tegen een sterke.
List<MapDekking> dekkingPerMap(String lcov, {int diepte = 2}) {
  final geraakt = <String, int>{};
  final gevonden = <String, int>{};
  final bestanden = <String, int>{};

  String? map;
  for (final regel in lcov.split('\n')) {
    if (regel.startsWith('SF:')) {
      final pad = regel.substring(3).trim().replaceAll(r'\', '/');
      final delen = pad.split('/');
      map = delen.length <= diepte
          ? delen.take(delen.length - 1).join('/')
          : delen.take(diepte).join('/');
      bestanden[map] = (bestanden[map] ?? 0) + 1;
    } else if (regel.startsWith('LF:') && map != null) {
      gevonden[map] =
          (gevonden[map] ?? 0) + (int.tryParse(regel.substring(3)) ?? 0);
    } else if (regel.startsWith('LH:') && map != null) {
      geraakt[map] =
          (geraakt[map] ?? 0) + (int.tryParse(regel.substring(3)) ?? 0);
    }
  }

  final uitkomst =
      [
        for (final pad in gevonden.keys)
          MapDekking(
            pad: pad,
            geraakt: geraakt[pad] ?? 0,
            gevonden: gevonden[pad]!,
            bestanden: bestanden[pad] ?? 0,
          ),
      ]..sort((a, b) {
        final byPct = a.percentage.compareTo(b.percentage);
        return byPct != 0 ? byPct : a.pad.compareTo(b.pad);
      });
  return uitkomst;
}

// ── Het ijkpunt ────────────────────────────────────────────────────────────

/// De commit waartegen vergeleken wordt.
class Ijkpunt {
  const Ijkpunt({
    required this.commit,
    required this.datum,
    required this.dagenTerug,
    this.isBegin = false,
  });

  final String commit;
  final DateTime datum;

  /// Hoeveel dagen het ijkpunt werkelijk terug ligt — niet wat er gevraagd is.
  ///
  /// Die twee lopen uiteen zodra de geschiedenis korter is dan het gevraagde
  /// venster, en dan is het gevraagde getal het verkeerde om te tonen: het zou
  /// "negentig dagen stilstand" suggereren in een repository van vijftig dagen.
  final int dagenTerug;

  /// Is dit de eerste commit, omdat er geen oudere was?
  final bool isBegin;

  String get kort => commit.length <= 8 ? commit : commit.substring(0, 8);
}

// ── Het rapport ────────────────────────────────────────────────────────────

String _datum(DateTime moment) {
  final d = moment.toLocal();
  return '${d.day.toString().padLeft(2, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.year}';
}

String _beweging(RatchetStand stand) {
  if (stand.onvindbaar) {
    return 'NIET GEVONDEN — deze meting loopt achter op de code';
  }
  if (stand.isNieuw) return 'nieuw sinds het ijkpunt';
  final delta = stand.verschil!;
  if (delta == 0) {
    if (!stand.stilstand) return 'onveranderd (op de eindstand)';
    return 'STIL — geen millimeter';
  }
  final teken = delta > 0 ? '+$delta' : '$delta';
  return stand.verbeterd
      ? '$teken — de goede kant op'
      : '$teken — de verkeerde kant op';
}

List<String> _ratchetTabel(List<RatchetStand> standen) {
  final naamBreedte = standen
      .map((s) => s.ratchet.naam.length)
      .fold(0, (a, b) => a > b ? a : b);
  return [
    'Basislijnen:',
    '    ${'naam'.padRight(naamBreedte)}   nu  toen  beweging',
    for (final stand in standen)
      '    ${stand.ratchet.naam.padRight(naamBreedte)} '
          '${(stand.nu?.toString() ?? '?').padLeft(4)} '
          '${(stand.toen?.toString() ?? '—').padLeft(5)}  '
          '${_beweging(stand)}',
  ];
}

List<String> _watZeTellen(List<RatchetStand> standen) => [
  'Wat die getallen tellen:',
  for (final stand in standen)
    '    ${stand.ratchet.naam} — ${stand.ratchet.wat}',
];

List<String> _dekkingBlok(List<MapDekking> dekking, {int toon = 12}) {
  if (dekking.isEmpty) {
    return [
      'Dekking per map: geen coverage/lcov.info gevonden.',
      '',
      '    Draai eerst `flutter test --coverage` (of `make coverage`). Zonder',
      '    verslag is dit deel van de meting niet uitgevoerd — dat is iets',
      '    anders dan een goede uitslag.',
    ];
  }
  final tonen = dekking.take(toon).toList();
  return [
    'Dekking per map (zwakste eerst, ${tonen.length} van ${dekking.length}):',
    for (final map in tonen)
      '    ${map.percentage.toStringAsFixed(1).padLeft(5)}%  '
          '${'${map.geraakt}/${map.gevonden}'.padLeft(11)}  '
          '${map.bestanden.toString().padLeft(3)} bestand(en)  ${map.pad}',
    '',
    '    Eén getal over de hele boom verbergt de zwakste map achter de',
    '    sterkste. Dit is dezelfde dekking, alleen niet meer gemiddeld.',
  ];
}

/// Eén regel uit een basislijn met de datum waarop hij erin kwam.
class Basislijnregel {
  const Basislijnregel({
    required this.sleutel,
    required this.basislijn,
    required this.sinds,
  });

  final String sleutel;
  final String basislijn;

  /// Wanneer deze regel voor het eerst in de basislijn verscheen, of null als
  /// dat niet te achterhalen was.
  final DateTime? sinds;

  int? dagenOud(DateTime nu) =>
      sinds == null ? null : nu.toLocal().difference(sinds!).inDays;
}

List<String> _oudsteRegelsBlok(List<Basislijnregel> regels, DateTime nu) {
  if (regels.isEmpty) return const [];
  return [
    'Langst staande basislijnregels:',
    for (final regel in regels)
      '    ${(regel.dagenOud(nu)?.toString() ?? '?').padLeft(4)} dagen  '
          '${regel.sleutel}  (${regel.basislijn})',
    '',
    '    Een uitzondering die zo lang meegaat, is geen uitzondering meer maar',
    '    een gewoonte met een naam.',
  ];
}

/// De regels die dit gereedschap schrijft.
List<String> rapport({
  required List<RatchetStand> standen,
  required List<MapDekking> dekking,
  required List<Basislijnregel> oudsteRegels,
  required Ijkpunt? ijkpunt,
  required DateTime nu,
}) {
  final regels = <String>[
    '== OciDeck ratchets en dekking ==',
    'Peildatum: ${_datum(nu)}',
    if (ijkpunt != null)
      'IJkpunt: ${ijkpunt.kort} van ${_datum(ijkpunt.datum)} '
          '(${ijkpunt.dagenTerug} dagen terug)'
          '${ijkpunt.isBegin ? ' — de eerste commit; zo ver kijkt de '
                    'geschiedenis terug' : ''}'
    else
      'IJkpunt: geen — er is geen commit gevonden vóór het gevraagde moment. '
          'Alleen de huidige stand is gemeten.',
    '',
    ..._ratchetTabel(standen),
    '',
    ..._watZeTellen(standen),
    '',
    ..._dekkingBlok(dekking),
  ];
  final oudste = _oudsteRegelsBlok(oudsteRegels, nu);
  if (oudste.isNotEmpty) {
    regels
      ..add('')
      ..addAll(oudste);
  }
  return regels
    ..add('')
    ..add(_slotzin(standen, ijkpunt));
}

String _slotzin(List<RatchetStand> standen, Ijkpunt? ijkpunt) {
  final onvindbaar = standen.where((s) => s.onvindbaar).toList();
  if (onvindbaar.isNotEmpty) {
    return '${onvindbaar.length} basislijn(en) waren niet te vinden in de '
        'brontekst. Dat is geen goede uitslag maar een kapotte meting — werk '
        'de lijst in tool/check_ratchet_trend.dart bij.';
  }
  final stil = standen.where((s) => s.stilstand).toList();
  final beter = standen.where((s) => s.verbeterd).toList();
  if (stil.isEmpty) {
    return '${beter.length} basislijn(en) bewogen de goede kant op en geen '
        'enkele stond stil. Dit is een meting, geen goedkeuring.';
  }
  final venster = ijkpunt == null
      ? 'het gemeten venster'
      : '${ijkpunt.dagenTerug} dagen';
  return '${stil.length} basislijn(en) stonden $venster stil, '
      '${beter.length} bewogen de goede kant op. Stilstand is geen fout — het '
      'is schuld die comfortabel is geworden, en dat is de reden dat dit getal '
      'zichtbaar is in plaats van rood.';
}

/// 1 zodra er stilstand is. Alleen gebruikt onder `--strict`.
int exitCodeVoor(List<RatchetStand> standen) =>
    standen.any((s) => s.stilstand || s.onvindbaar) ? 1 : 0;

// ── Git ────────────────────────────────────────────────────────────────────

/// De inhoud van [pad] op [commit], of null als het bestand er toen niet was.
String? bronOp(String commit, String pad) {
  final uitslag = Process.runSync('git', ['show', '$commit:$pad']);
  return uitslag.exitCode == 0 ? uitslag.stdout as String : null;
}

/// De laatste commit vóór [dagen] dagen geleden, of null.
Ijkpunt? zoekIjkpunt(int dagen) {
  final grens = DateTime.now().subtract(Duration(days: dagen));
  final uitslag = Process.runSync('git', [
    'rev-list',
    '-1',
    '--before=${grens.toIso8601String()}',
    'HEAD',
  ]);
  if (uitslag.exitCode != 0) return null;
  var commit = (uitslag.stdout as String).trim();
  var isBegin = false;
  if (commit.isEmpty) {
    // Het venster reikt verder terug dan de geschiedenis. Terugvallen op de
    // eerste commit en niet opgeven: "zo ver kijkt de geschiedenis niet terug"
    // is een bruikbaar antwoord, "geen ijkpunt" laat de hele vergelijking leeg
    // terwijl er wél iets te vergelijken viel.
    final begin = Process.runSync('git', [
      'rev-list',
      '--max-parents=0',
      'HEAD',
    ]);
    if (begin.exitCode != 0) return null;
    final wortels = (begin.stdout as String)
        .split('\n')
        .map((r) => r.trim())
        .where((r) => r.isNotEmpty)
        .toList();
    if (wortels.isEmpty) return null;
    commit = wortels.last;
    isBegin = true;
  }
  final datum = Process.runSync('git', ['show', '-s', '--format=%aI', commit]);
  final gelezen = DateTime.tryParse((datum.stdout as String).trim());
  final werkelijk = gelezen ?? grens;
  return Ijkpunt(
    commit: commit,
    datum: werkelijk,
    dagenTerug: DateTime.now().difference(werkelijk).inDays,
    isBegin: isBegin,
  );
}

/// Wanneer [sleutel] voor het eerst in [bestand] verscheen, of null.
///
/// `git log -S` zoekt de commits waarin het aantal voorkomens van de tekst
/// veranderde; de laatste daarvan (chronologisch de eerste) is de invoering.
DateTime? sindsWanneer(String sleutel, String bestand) {
  final uitslag = Process.runSync('git', [
    'log',
    '--format=%aI',
    '-S',
    sleutel,
    '--',
    bestand,
  ]);
  if (uitslag.exitCode != 0) return null;
  final regels = (uitslag.stdout as String)
      .split('\n')
      .map((r) => r.trim())
      .where((r) => r.isNotEmpty)
      .toList();
  return regels.isEmpty ? null : DateTime.tryParse(regels.last);
}

/// De sleutels van een verzameling-basislijn, in bronvolgorde.
///
/// Alleen de letterlijke strings op het bovenste niveau; dat zijn bij elke
/// basislijn hier de paden of declaraties waar de uitzondering over gaat.
List<String> sleutelsUit(String bron, String naam) {
  final schoon = zonderRegelcommentaar(bron);
  final start = RegExp(
    '\\b${RegExp.escape(naam)}\\s*=\\s*\\{',
  ).firstMatch(schoon);
  if (start == null) return const [];
  var diepte = 0;
  var einde = -1;
  for (var i = start.end - 1; i < schoon.length; i++) {
    final teken = schoon[i];
    if (teken == '{') diepte++;
    if (teken == '}') {
      diepte--;
      if (diepte == 0) {
        einde = i;
        break;
      }
    }
  }
  if (einde < 0) return const [];
  return [
    for (final m in RegExp(
      "'([^']+)'",
    ).allMatches(schoon.substring(start.end, einde)))
      m.group(1)!,
  ];
}

/// De langst staande regels over alle verzameling-basislijnen heen.
List<Basislijnregel> oudsteRegels(
  Map<String, String?> bronnen, {
  int hoeveel = 8,
}) {
  final gevonden = <Basislijnregel>[];
  for (final ratchet in ratchets) {
    if (ratchet.soort != RatchetSoort.omvang) continue;
    final bron = bronnen[ratchet.bestand];
    if (bron == null) continue;
    for (final sleutel in sleutelsUit(bron, ratchet.naam)) {
      gevonden.add(
        Basislijnregel(
          sleutel: sleutel,
          basislijn: ratchet.naam,
          sinds: sindsWanneer(sleutel, ratchet.bestand),
        ),
      );
    }
  }
  gevonden.sort((a, b) {
    if (a.sinds == null) return 1;
    if (b.sinds == null) return -1;
    return a.sinds!.compareTo(b.sinds!);
  });
  return gevonden.take(hoeveel).toList();
}

const _gebruik = '''
Gebruik: dart run tool/check_ratchet_trend.dart [--sinds=<dagen>] [--strict]

  --sinds=<dagen>  Vergelijk met de laatste commit vóór zoveel dagen geleden
                   (standaard 90).
  --strict         Eindig op 1 bij een stilstaande basislijn. Standaard is dit
                   adviserend: stilstand tot een rode bouw maken straft een
                   rustige maand.
  --help           Deze tekst.

Draai `make coverage` (of `flutter test --coverage`) eerst als je de dekking
per map wilt zien; zonder coverage/lcov.info blijft dat blok leeg.''';

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_gebruik);
    return;
  }
  var dagen = 90;
  var strict = false;
  for (final arg in args) {
    if (arg == '--strict') {
      strict = true;
    } else if (arg.startsWith('--sinds=')) {
      final gelezen = int.tryParse(arg.substring('--sinds='.length));
      if (gelezen == null || gelezen <= 0) {
        stderr.writeln('--sinds verwacht een positief aantal dagen.');
        exit(2);
      }
      dagen = gelezen;
    } else {
      stderr.writeln('Onbekende vlag: $arg\n\n$_gebruik');
      exit(2);
    }
  }

  final nuBronnen = <String, String?>{
    for (final pad in ratchetBestanden)
      pad: File(pad).existsSync() ? File(pad).readAsStringSync() : null,
  };
  if (nuBronnen.values.every((b) => b == null)) {
    stderr.writeln(
      'check_ratchet_trend: geen van de bronbestanden gevonden — draai dit '
      'vanuit de wortel van de werkkopie.',
    );
    exit(2);
  }

  final ijkpunt = zoekIjkpunt(dagen);
  final toenBronnen = <String, String?>{
    for (final pad in ratchetBestanden)
      pad: ijkpunt == null ? null : bronOp(ijkpunt.commit, pad),
  };

  final lcov = File('coverage/lcov.info');
  for (final regel in rapport(
    standen: vergelijk(nuBronnen, toenBronnen),
    dekking: lcov.existsSync()
        ? dekkingPerMap(lcov.readAsStringSync())
        : const [],
    oudsteRegels: oudsteRegels(nuBronnen),
    ijkpunt: ijkpunt,
    nu: DateTime.now(),
  )) {
    stdout.writeln(regel);
  }
  exit(strict ? exitCodeVoor(vergelijk(nuBronnen, toenBronnen)) : 0);
}
