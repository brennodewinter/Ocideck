// Verouderingspoort voor de gebundelde referentiestandaarden (WSTG, CWE, MIAUW,
// CVSS — zie lib/services/reference_standards.dart).
//
//   dart run tool/check_reference_data.dart     (of: make deps-check)
//
// Deze catalogi zijn met de hand ingecheckt en vallen dus buiten
// `flutter pub outdated`, net als de gevendorde JavaScript waar
// tool/check_bundled_js.dart over gaat. Dit is hun tegenhanger. Het bestaat
// omdat het al een keer is misgegaan: MASTG werd op 30-06-2026 volledig
// herbouwd en niets in deze repo kon dat merken.
//
// Wat het doet: voor elke standaard met een machineleesbare bron de actuele
// versie ophalen en naast de gebundelde leggen.
//
// De regel die het bewaakt is niet "alles moet actueel zijn" — een standaard
// bijwerken is werk met inhoudelijke gevolgen, geen automatisme. De regel is
// dat een afwijking **zichtbaar** wordt in plaats van stil te blijven.
//
// Drie uitkomsten, en het onderscheid tussen de laatste twee is het hele punt:
//   actueel    — gebundelde versie == upstream
//   VEROUDERD  — upstream heeft iets anders; een mens moet kijken
//   onbekend   — niet automatisch vast te stellen (bron publiceert het niet)
//
// "Onbekend" wordt nooit als "actueel" geteld. Stilte mag hier niet als
// goedkeuring lezen; dat is precies hoe een catalogus jarenlang veroudert.
//
// ── Wat je vergelijkt, moet dezelfde grootheid zijn ─────────────────────────
//
// Een poort die alleen groen kan zijn is erger dan geen poort, want hij wordt
// voor bewijs gehouden. MIAUW was er zo een: de gebundelde "versie" was de dag
// waarop wij het schema overnamen en de probe leverde de datum van de bron. Een
// overnamedatum ligt per definitie ná de bronwijziging, dus de vergelijking
// "is upstream nieuwer?" kon daar nooit met ja worden beantwoord. De poort
// meldde jaren "actueel" zonder ooit iets te hebben kunnen zeggen.
//
// Twee dingen zijn daarop veranderd, en ze horen bij elkaar:
//   * de gebundelde versie is de waarde die de **bron** draagt, nooit de dag
//     van overname (zie `miauwBundledVersion`);
//   * de vergelijking is `!=` en niet `>` — elke afwijking alarmeert, ook een
//     upstreamwaarde die ouder lijkt, want dan klopt onze boekhouding niet.
//     Zie [deviates]; het is dezelfde regel als `StandardFreshness.isOutdated`.
//
// test/check_reference_data_tool_test.dart toetst beide richtingen: schoon op
// het echte register, en rood op een geplante verouderde bron — inclusief
// precies de boekhouding die hem groen hield.
//
// Exit codes:  0 = alles actueel (of alleen onbekenden)
//              1 = ten minste één standaard is verouderd
//              2 = de controle kon niet draaien (geen netwerk)
//
// Met `--json` komt dezelfde ronde machineleesbaar naar buiten (id, naam,
// gebundelde versie, laatste versie, status) en eindigt hij op 0 tenzij er
// niets bereikbaar was. Daar leest scripts/refresh_catalogs.sh uit wélke versie
// het moet ophalen, zodat de verversing en de poort niet over verschillende
// versies kunnen praten.
//
// Bij een verouderdmelding: werk de catalogus bij, zet de nieuwe versie in
// lib/services/reference_standards.dart én in docs/LICENSE_COMPLIANCE.md, en
// controleer of de licentievoorwaarden van de bron zijn veranderd.
//
// ── --advisory: dezelfde vraag, ander moment ────────────────────────────────
//
// Met `--advisory` rapporteert de controle hetzelfde maar eindigt ze altijd op
// 0. Dat is geen verzachte variant van de poort; het is een andere vraag op een
// ander moment.
//
// De poort in CI vraagt: *mag dit gemerged worden?* Daar is verouderd een
// blokkade, want anders sluipt het erin.
//
// De adviserende vraagt: *weet ik wat ik ga inpakken?* Die hoort vóór een
// release-build, en daar is falen juist verkeerd. Een nieuwe upstreamversie is
// geen defect in wat je bouwt — het is iets wat je wilt wéten voordat je een
// artefact met een jaar houdbaarheid de deur uit doet. Zou hij de build
// afbreken, dan wordt hij binnen twee releases overgeslagen met een vlag, en
// dan is de zichtbaarheid weg die het hele doel was.
//
// Dat onderscheid gaat er echt toe doen zodra er detectielexicons bij komen
// (OCIWACHT §13.3). Die brengen maandelijks een nieuwe upstreamversie uit, en
// "er zijn nieuwe termen" is daar geen fout maar een verversingsbeslissing —
// inclusief het hercontroleren van de vals-positievencorpus.
import 'dart:convert';
import 'dart:io';

/// Uitgelezen uit lib/services/reference_standards.dart, zodat dit gereedschap
/// en de app niet uiteen kunnen lopen. Bewust een parse van de bron en geen
/// tweede lijst: een handmatig gekopieerde lijst is precies de fout die dit
/// gereedschap moet voorkomen.
final _sourceFile = File('lib/services/reference_standards.dart');

class Standard {
  final String id, name, version, probe, target;

  /// Het pad binnen [target] waar de gebundelde inhoud vandaan komt, of leeg
  /// voor een bron waar de hele repo het signaal is. Zie
  /// `ReferenceStandard.probePath`.
  final String path;

  /// Mag een nieuwere upstreamversie de poort laten falen? Zie
  /// `ReferenceStandard.advisory`: detectielexicons melden zich wél maar
  /// blokkeren niet, want die brengen maandelijks uit en een poort die altijd
  /// rood staat wordt uitgezet.
  final bool advisory;
  Standard(
    this.id,
    this.name,
    this.version,
    this.probe,
    this.target, {
    this.path = '',
    this.advisory = false,
  });
}

/// Wat de poort van één ronde overhoudt: de tabel, de losse toelichtingen en de
/// tellingen waar de afloopcode uit volgt.
class GateOutcome {
  GateOutcome({
    required this.rows,
    required this.notes,
    required this.outdated,
    required this.outdatedAdvisory,
    required this.unreachable,
    required this.total,
  });

  final List<List<String>> rows;
  final List<String> notes;
  final int outdated, outdatedAdvisory, unreachable, total;

  /// De afloopcode: 2 = niet kunnen kijken, 1 = verouderd, 0 = in orde.
  /// Adviserend meldt hetzelfde maar eindigt nooit op 1 — zie de kop.
  int exitCode({required bool advisory}) {
    if (total > 0 && unreachable == total) return 2;
    if (outdated > 0 && !advisory) return 1;
    return 0;
  }
}

/// Hoe één standaard bij zijn bron wordt opgehaald. Injecteerbaar zodat de
/// poort zelf te toetsen is: zonder deze naad kun je alleen vaststellen dat de
/// poort *groen* is, en dat is precies de eigenschap die MIAUW jarenlang had
/// terwijl hij structureel niet rood kón worden.
typedef Prober = Future<ProbeResult> Function(Standard standard);

/// Weegt elke standaard en telt de uitkomsten op. Bevat geen netwerk en geen
/// exit(), zodat er in beide richtingen op te toetsen valt.
Future<GateOutcome> evaluate(List<Standard> standards, Prober prober) async {
  final rows = <List<String>>[];
  final notes = <String>[];
  var outdated = 0;
  // Adviserende bronnen tellen apart: ze worden gemeld maar laten de poort niet
  // vallen. Zie ReferenceStandard.advisory voor waarom een detectielexicon daar
  // hoort en een catalogus niet.
  var outdatedAdvisory = 0;
  var unreachable = 0;

  for (final s in standards) {
    final result = await prober(s);
    if (result.latest == null) {
      unreachable++;
      rows.add([s.name, s.version, '?', 'onbekend (bron onbereikbaar)']);
      continue;
    }
    if (result.note.isNotEmpty) notes.add(result.note);
    if (result.stale) {
      if (s.advisory) {
        outdatedAdvisory++;
        rows.add([s.name, s.version, result.latest!, 'nieuwer beschikbaar']);
      } else {
        outdated++;
        rows.add([s.name, s.version, result.latest!, 'VEROUDERD']);
      }
    } else {
      rows.add([s.name, s.version, result.latest!, 'actueel']);
    }
    if (result.integrityProblem.isNotEmpty) {
      outdated++;
      notes.add(result.integrityProblem);
    }
  }

  return GateOutcome(
    rows: rows,
    notes: notes,
    outdated: outdated,
    outdatedAdvisory: outdatedAdvisory,
    unreachable: unreachable,
    total: standards.length,
  );
}

void main(List<String> args) async {
  final advisory = args.contains('--advisory');
  if (!_sourceFile.existsSync()) {
    stderr.writeln(
      'check_reference_data: ${_sourceFile.path} niet gevonden — '
      'draai dit vanuit de repo-root.',
    );
    exit(2);
  }

  final standards = parseStandards(_sourceFile.readAsStringSync());
  if (standards.isEmpty) {
    stderr.writeln('check_reference_data: geen standaarden gevonden.');
    exit(2);
  }

  final outcome = await evaluate(standards, probeUpstream);

  // --json: dezelfde ronde, machineleesbaar. Bestaat zodat scripts/refresh_catalogs.sh
  // niet zijn eigen probes hoeft te schrijven — twee implementaties van "wat is
  // upstream de laatste?" lopen uiteen, en dan haalt de verversing iets anders
  // op dan de poort verwacht. Precies die scheefstand hield de MASWE-datum in
  // de Makefile (2026-08-03) los van die in de catalogus (2026-08-04).
  //
  // Eindigt op 0 ook als er iets verouderd is: de aanroeper wil juist dán de
  // gegevens hebben. Alleen "ik heb niet kunnen kijken" (2) blijft een fout.
  if (args.contains('--json')) {
    stdout.writeln(jsonEncode(_asJson(standards, outcome)));
    exit(outcome.exitCode(advisory: true));
  }

  _printTable(outcome.rows);

  for (final n in outcome.notes) {
    stdout.writeln('\n$n');
  }

  // Eén afloopcode, uit één plek: main mag hier geen tweede regel naast
  // GateOutcome.exitCode zetten, want dan toetst de test iets anders dan er
  // draait.
  final code = outcome.exitCode(advisory: advisory);

  if (outcome.unreachable == standards.length) {
    stderr.writeln(
      '\ncheck_reference_data: geen enkele bron bereikbaar — '
      'controle niet uitgevoerd (netwerk?).',
    );
    // Ook adviserend blijft dit een 2: "ik heb niet kunnen kijken" is iets
    // anders dan "er is niets nieuws", en dat verschil mag nooit verdwijnen.
    exit(code);
  }
  // Adviserende bronnen melden zich altijd, in beide standen — alleen laten ze
  // de poort niet vallen.
  if (outcome.outdatedAdvisory > 0) {
    stdout.writeln(
      '\n${outcome.outdatedAdvisory} adviserende bron(nen) hebben een nieuwere '
      'uitgave.\n'
      'Dat is geen defect: bij een detectielexicon vuurt elke term, dus een '
      'verversing vraagt om de termdiff lezen en de vals-positievencorpus '
      'opnieuw wegen. Doe dat bewust, niet reflexmatig.',
    );
  }
  if (outcome.outdated > 0) {
    final where =
        'Werk de catalogus bij, pas de versie aan in '
        '${_sourceFile.path} én docs/LICENSE_COMPLIANCE.md, en controleer of de '
        'licentie van de bron is gewijzigd.';
    if (advisory) {
      stdout.writeln(
        '\ncheck_reference_data: ${outcome.outdated} standaard(en) hebben een '
        'nieuwere upstreamversie.\n$where\n'
        'Adviserend: dit breekt de build niet. Weeg zelf of deze release met de '
        'huidige bundel de deur uit mag.',
      );
    } else {
      stderr.writeln(
        '\ncheck_reference_data: ${outcome.outdated} standaard(en) verouderd.'
        '\n$where',
      );
    }
    exit(code);
  }
  stdout.writeln(
    outcome.outdatedAdvisory > 0
        ? '\nReference data OK (op de adviserende meldingen na).'
        : '\nReference data OK.',
  );
  exit(code);
}

/// Trekt de standaarden uit de Dart-bron. Bewust regel-voor-regel en niet met
/// één grote regexp over het hele bestand: zo is een gemiste standaard een
/// zichtbaar gat in de tabel in plaats van een stille nul.
List<Standard> parseStandards(String source) {
  final consts = <String, String>{};
  for (final m in RegExp(
    r"^const (\w+) = '([^']*)';",
    multiLine: true,
  ).allMatches(source)) {
    consts[m.group(1)!] = m.group(2)!;
  }

  final out = <Standard>[];
  for (final block in RegExp(
    r'ReferenceStandard\((.*?)\n  \),',
    dotAll: true,
  ).allMatches(source)) {
    final b = block.group(1)!;
    String field(String name) =>
        RegExp("$name: '([^']*)'").firstMatch(b)?.group(1) ?? '';

    final versionRef = RegExp(r'bundledVersion: (\w+)').firstMatch(b)?.group(1);
    final version = versionRef == null
        ? ''
        : consts[versionRef] ?? _knownExternalConst(versionRef, source);

    out.add(
      Standard(
        field('id'),
        field('name'),
        version,
        RegExp(r'probe: UpstreamProbe\.(\w+)').firstMatch(b)?.group(1) ?? '',
        field('probeTarget'),
        path: field('probePath'),
        advisory: RegExp(r'advisory: true').hasMatch(b),
      ),
    );
  }
  return out;
}

/// Sommige versies wonen in de catalogus zelf en niet in het register, omdat de
/// catalogus daar de bron van waarheid is. Deze lijst maakt ze vindbaar.
///
/// Een naam die hier ontbreekt levert een lege versie op, en dan meldt de poort
/// de standaard als verouderd. Dat is de goede kant om fout te gaan — bij het
/// toevoegen van MASTG gebeurde het meteen, en het viel op.
String _knownExternalConst(String name, String _) {
  const files = {
    'wstgVersion': 'lib/services/wstg_catalog.dart',
    'mastgVersion': 'lib/services/mastg_catalog.dart',
    'masweSnapshotDate': 'lib/services/maswe_catalog.dart',
  };
  final path = files[name];
  if (path == null) return '';
  final f = File(path);
  if (!f.existsSync()) return '';
  return RegExp(
        "const $name = '([^']*)'",
      ).firstMatch(f.readAsStringSync())?.group(1) ??
      '';
}

/// Wat één probe oplevert.
class ProbeResult {
  final String? latest;
  final bool stale;

  /// Een bevinding die géén veroudering is maar wel fout — nu: een bundel die
  /// niet zoveel items bevat als de bron zegt, of een gebundelde bron die niet
  /// meer op het opgegeven pad staat.
  final String integrityProblem;

  /// Vrije toelichting voor onder de tabel.
  final String note;

  ProbeResult(
    this.latest, {
    this.stale = false,
    this.integrityProblem = '',
    this.note = '',
  });
}

/// Wijkt de gebundelde versie af van wat de bron nu zegt?
///
/// **Elke** afwijking telt, ook een upstreamwaarde die *ouder* lijkt. Dat is
/// niet netjes-zijn maar de reparatie van een echte fout: de datumprobes
/// vergeleken met `>`, en MIAUW droeg als "versie" de dag waarop wij het schema
/// hadden overgenomen (2026-07-16) terwijl de bron 2024-12-06 meldde. Een
/// overnamedatum ligt per definitie ná de bronwijziging, dus `latest > bundled`
/// kon daar nooit waar worden: de poort stond structureel groen over een
/// vergelijking van twee verschillende klokken. Met `!=` was dat op dag één
/// rood geweest.
///
/// Dit is dezelfde regel als `StandardFreshness.isOutdated` in de app, en dat
/// is geen toeval: dat de poort en het instellingenoverzicht hetzelfde
/// antwoord geven hoort een eigenschap te zijn, geen toeval. Bij OWASP is
/// "nieuwer" bovendien niet uit de getallen af te leiden — MASTG hernummerde bij
/// de herbouw van 1.x naar 2.0.
bool deviates(String bundled, String? latest) =>
    latest != null && bundled.isNotEmpty && latest != bundled;

/// De uitkomst als JSON: per standaard id, naam, gebundelde versie, wat upstream
/// meldt en de status. De volgorde van [GateOutcome.rows] loopt één-op-één met
/// [standards] — [evaluate] voegt per standaard precies één rij toe — dus de
/// twee zijn hier te ritsen zonder een tweede ronde probes.
List<Map<String, Object?>> _asJson(
  List<Standard> standards,
  GateOutcome outcome,
) => [
  for (var i = 0; i < standards.length; i++)
    {
      'id': standards[i].id,
      'naam': standards[i].name,
      'gebundeld': standards[i].version,
      // De probe kon niets ophalen → geen laatste versie, en dat is iets anders
      // dan "gelijk aan wat wij hebben". Null zegt dat eerlijk; een script dat
      // hierop verversten wil, hoort dan niets te doen.
      'laatste': outcome.rows[i][2] == '?' ? null : outcome.rows[i][2],
      'status': switch (outcome.rows[i][3]) {
        'actueel' => 'actueel',
        'VEROUDERD' || 'nieuwer beschikbaar' => 'verouderd',
        _ => 'onbekend',
      },
      'adviserend': standards[i].advisory,
    },
];

/// De echte, netwerkgebonden probe. Zie [Prober] voor waarom dit een los
/// aanwijsbare functie is en geen vaste tak in [evaluate].
Future<ProbeResult> probeUpstream(Standard s) async {
  switch (s.probe) {
    case 'githubReleases':
      final latest = await _latestGithubRelease(s.target);
      return ProbeResult(latest, stale: deviates(s.version, latest));
    case 'githubCommitDate':
      return _probeCommitDate(s);
    case 'orphanetDate':
      final latest = await _probeOrphanetDate(s.target);
      return ProbeResult(latest, stale: deviates(s.version, latest));
    case 'cweApi':
      return _probeCweApi(s);
    case 'successorDocument':
      return _probeSuccessor(s);
    case 'isoEdition':
      return _probeIsoEdition(s);
    default:
      return ProbeResult(null);
  }
}

/// De gepubliceerde editie van een ISO-norm, gelezen van ISO's publieke
/// popular-standards-pagina (die de drie normen mét editie noemt, bv.
/// "ISO/IEC 27001:2022"). Het normnummer komt uit de naam ("ISO/IEC 27001" →
/// `27001`), en op de pagina zoeken we `27001:JJJJ`.
///
/// ISO verkoopt de norm en blokkeert bovendien vaak geautomatiseerd ophalen; dan
/// levert dit **onbekend** — een eerlijke uitkomst, geen valse "actueel". De
/// toelichting zegt dan dat een mens de editie op iso.org moet nakijken. Zie
/// UpstreamProbe.isoEdition.
Future<ProbeResult> _probeIsoEdition(Standard s) async {
  final number = RegExp(r'(\d{4,5})$').firstMatch(s.name.trim())?.group(1);
  if (number == null) return ProbeResult(null);
  final body = await _get(Uri.parse(s.target));
  if (body == null) {
    return ProbeResult(
      null,
      note:
          '${s.name}: ISO publiceert de editie op ${s.target}, maar blokkeert '
          'geautomatiseerd ophalen — controleer de editie met de hand.',
    );
  }
  final latest = RegExp('$number:(\\d{4})').firstMatch(body)?.group(1);
  return ProbeResult(latest, stale: deviates(s.version, latest));
}

/// De laatste-commitdatum, eventueel versmald tot het bestand waar de gebundelde
/// inhoud werkelijk uit komt ([Standard.path]).
///
/// Die versmalling is het punt: MIAUW's schema komt uit één werkboek in de
/// methodologie-repo, en die repo krijgt ook commits die het schema niet raken.
/// Een repobrede datum zou dan rood worden om een README-typefout, en een
/// releasedatum zou groen blijven bij een werkboekwijziging zonder release.
/// Beide leren mensen wegkijken.
Future<ProbeResult> _probeCommitDate(Standard s) async {
  final commits = await _commits(s.target, path: s.path);
  if (commits == null) return ProbeResult(null);
  if (commits.isEmpty) {
    // De repo antwoordde wél, maar over dit pad bestaat geen historie: het
    // bestand is hernoemd of verplaatst. Dat is geen "onbereikbaar" — dan zou
    // het stil doorglippen — maar een bevinding met een naam.
    return ProbeResult(
      s.version,
      integrityProblem:
          '${s.name}: ${s.target} kent geen commits voor "${s.path}". Het '
          'gebundelde bronbestand is hernoemd of verplaatst — zoek het nieuwe '
          'pad op en werk probePath bij, anders bewaakt deze poort niets meer.',
    );
  }
  final latest = _committerDate(commits.first);
  return ProbeResult(latest, stale: deviates(s.version, latest));
}

/// De uitgavedatum uit de kop van een Orphanet-productbestand.
///
/// Die bestanden zijn ruim 50 MB per taal, en de datum staat in de eerste regel.
/// Vandaar een range-verzoek van twee kilobyte: de hele lijst binnenhalen om één
/// datum te lezen zou de poort traag én duur maken, en dan wordt hij overgeslagen.
Future<String?> _probeOrphanetDate(String url) async {
  if (url.isEmpty) return null;
  try {
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-2047');
    final res = await req.close();
    final head = await res
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    client.close(force: true);
    return RegExp(
      r'<JDBOR date="(\d{4}-\d{2}-\d{2})',
    ).firstMatch(head)?.group(1);
  } catch (_) {
    return null;
  }
}

/// De nieuwste commit(s) op de standaardbranch, eventueel alleen die welke
/// [path] raken. Null wanneer de bron niet te bevragen was; een lege lijst is
/// een antwoord — zie [_probeCommitDate].
Future<List<dynamic>?> _commits(String repo, {String path = ''}) async {
  if (repo.isEmpty) return null;
  final query = {'per_page': '1', if (path.isNotEmpty) 'path': path};
  final body = await _get(
    Uri.https('api.github.com', '/repos/$repo/commits', query),
  );
  if (body == null) return null;
  try {
    return jsonDecode(body) as List;
  } on Object {
    return null;
  }
}

/// De committerdatum van één commit uit de GitHub-API, als `JJJJ-MM-DD`.
String? _committerDate(dynamic commit) {
  try {
    final at = ((commit as Map)['commit'] as Map)['committer']['date'];
    if (at is! String || at.length < 10) return null;
    return at.substring(0, 10);
  } on Object {
    return null;
  }
}

/// MITRE's CWE-API: versie, inhoudsdatum én het aantal zwakheden.
Future<ProbeResult> _probeCweApi(Standard s) async {
  final body = await _get(Uri.parse(s.target));
  if (body == null) return ProbeResult(null);
  final Map<String, dynamic> json;
  try {
    json = jsonDecode(body) as Map<String, dynamic>;
  } on Object {
    return ProbeResult(null);
  }
  final version = json['ContentVersion']?.toString();
  if (version == null || version.isEmpty) return ProbeResult(null);
  final date = json['ContentDate']?.toString() ?? '';

  // Het aantal is een gratis integriteitscontrole: onze bundel hoort er even
  // veel te bevatten. Wijkt dat af, dan is hij afgekapt of half geregenereerd —
  // een ander soort fout dan veroudering, en stiller.
  var integrity = '';
  final total = json['TotalWeaknesses'];
  final bundled = _bundledCweCount();
  if (total is int && bundled != null && total != bundled) {
    integrity =
        'CWE: de bundel bevat $bundled zwakheden, de bron meldt er $total. '
        'De bundel is onvolledig of half geregenereerd — regenereer hem met '
        'tool/build_cwe_catalog.dart.';
  }

  return ProbeResult(
    version,
    stale: version != s.version,
    integrityProblem: integrity,
    note: date.isEmpty ? '' : 'CWE-inhoudsdatum bij de bron: $date.',
  );
}

/// Telt de items in de gebundelde CWE-lijst, of null als die er niet is.
int? _bundledCweCount() {
  final f = File('assets/cwe/cwe_full.json');
  if (!f.existsSync()) return null;
  try {
    final decoded = jsonDecode(f.readAsStringSync());
    // The asset carries a MITRE attribution header around the rows; the older
    // bare-array shape is still counted so this never reports a false zero.
    final rows = decoded is Map<String, dynamic>
        ? decoded['weaknesses'] as List
        : decoded as List;
    return rows.length;
  } on Object {
    return null;
  }
}

/// Bronnen die geen "laatste versie" publiceren maar wel per versie een
/// document op een vaste URL: bestaat de opvolger al?
///
/// Geeft geen versienummer terug maar wel het antwoord dat telt. Zolang geen
/// enkele opvolger bestaat, is wat we bundelen de nieuwste — en dát is een
/// bevestiging, geen stilte.
Future<ProbeResult> _probeSuccessor(Standard s) async {
  final candidates = _successorVersions(s.version);
  if (candidates.isEmpty) return ProbeResult(null);
  for (final candidate in candidates) {
    final url = Uri.parse(s.target.replaceAll('{version}', candidate));
    final exists = await _exists(url);
    if (exists == null) return ProbeResult(null); // bron onbereikbaar
    if (exists) {
      return ProbeResult(
        candidate,
        stale: true,
        note:
            '${s.name}: er bestaat een document voor v$candidate '
            '(${url.toString()}).',
      );
    }
  }
  return ProbeResult(
    s.version,
    note:
        '${s.name}: geen opvolger gevonden (geprobeerd: '
        '${candidates.map((c) => 'v$c').join(', ')}).',
  );
}

/// De eerstvolgende minor en major na [version]. `4.0` → `4.1`, `5.0`.
List<String> _successorVersions(String version) {
  final parts = version.split('.');
  if (parts.length != 2) return const [];
  final major = int.tryParse(parts[0]);
  final minor = int.tryParse(parts[1]);
  if (major == null || minor == null) return const [];
  return ['$major.${minor + 1}', '${major + 1}.0'];
}

/// De laatste release van een GitHub-repo: de tag, ontdaan van een `v`-prefix.
Future<String?> _latestGithubRelease(String repo) async {
  if (repo.isEmpty) return null;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(
      Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
    );
    request.headers.set('Accept', 'application/vnd.github+json');
    request.headers.set('User-Agent', 'OciDeck-reference-data-check');
    final response = await request.close();
    if (response.statusCode != 200) return null;
    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final tag = json['tag_name'];
    if (tag is! String || tag.isEmpty) return null;
    return tag.startsWith('v') ? tag.substring(1) : tag;
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Haalt een URL op, of null bij welke fout dan ook.
Future<String?> _get(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(uri);
    request.headers.set('User-Agent', 'OciDeck-reference-data-check');
    final response = await request.close();
    if (response.statusCode != 200) return null;
    return await response.transform(utf8.decoder).join();
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Bestaat er iets op [uri]? null wanneer dat niet vast te stellen was —
/// bewust onderscheiden van `false`, want "niet gevonden" en "niet gekeken"
/// zijn hier verschillende antwoorden.
Future<bool?> _exists(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.headUrl(uri);
    request.headers.set('User-Agent', 'OciDeck-reference-data-check');
    final response = await request.close();
    await response.drain<void>();
    if (response.statusCode == 200) return true;
    if (response.statusCode == 404) return false;
    return null;
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}

void _printTable(List<List<String>> rows) {
  const headers = ['Standaard', 'Gebruikte versie', 'Laatste versie', 'Status'];
  final all = [headers, ...rows];
  final widths = List.generate(
    headers.length,
    (i) => all.map((r) => r[i].length).reduce((a, b) => a > b ? a : b),
  );
  String line(List<String> r) => [
    for (var i = 0; i < r.length; i++) r[i].padRight(widths[i]),
  ].join('  ').trimRight();

  stdout.writeln(line(headers));
  stdout.writeln(widths.map((w) => '-' * w).join('  '));
  for (final r in rows) {
    stdout.writeln(line(r));
  }
}
