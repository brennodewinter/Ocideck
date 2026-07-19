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
// Exit codes:  0 = alles actueel (of alleen onbekenden)
//              1 = ten minste één standaard is verouderd
//              2 = de controle kon niet draaien (geen netwerk)
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

class _Standard {
  final String id, name, version, probe, target;

  /// Mag een nieuwere upstreamversie de poort laten falen? Zie
  /// `ReferenceStandard.advisory`: detectielexicons melden zich wél maar
  /// blokkeren niet, want die brengen maandelijks uit en een poort die altijd
  /// rood staat wordt uitgezet.
  final bool advisory;
  _Standard(
    this.id,
    this.name,
    this.version,
    this.probe,
    this.target, {
    this.advisory = false,
  });
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

  final standards = _parseStandards(_sourceFile.readAsStringSync());
  if (standards.isEmpty) {
    stderr.writeln('check_reference_data: geen standaarden gevonden.');
    exit(2);
  }

  final rows = <List<String>>[];
  var outdated = 0;
  // Adviserende bronnen tellen apart: ze worden gemeld maar laten de poort niet
  // vallen. Zie ReferenceStandard.advisory voor waarom een detectielexicon daar
  // hoort en een catalogus niet.
  var outdatedAdvisory = 0;
  var unreachable = 0;

  final notes = <String>[];

  for (final s in standards) {
    final result = await _probe(s);
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

  _printTable(rows);

  for (final n in notes) {
    stdout.writeln('\n$n');
  }

  if (unreachable == standards.length) {
    stderr.writeln(
      '\ncheck_reference_data: geen enkele bron bereikbaar — '
      'controle niet uitgevoerd (netwerk?).',
    );
    // Ook adviserend blijft dit een 2: "ik heb niet kunnen kijken" is iets
    // anders dan "er is niets nieuws", en dat verschil mag nooit verdwijnen.
    exit(2);
  }
  // Adviserende bronnen melden zich altijd, in beide standen — alleen laten ze
  // de poort niet vallen.
  if (outdatedAdvisory > 0) {
    stdout.writeln(
      '\n$outdatedAdvisory adviserende bron(nen) hebben een nieuwere uitgave.\n'
      'Dat is geen defect: bij een detectielexicon vuurt elke term, dus een '
      'verversing vraagt om de termdiff lezen en de vals-positievencorpus '
      'opnieuw wegen. Doe dat bewust, niet reflexmatig.',
    );
  }
  if (outdated > 0) {
    final where =
        'Werk de catalogus bij, pas de versie aan in '
        '${_sourceFile.path} én docs/LICENSE_COMPLIANCE.md, en controleer of de '
        'licentie van de bron is gewijzigd.';
    if (advisory) {
      stdout.writeln(
        '\ncheck_reference_data: $outdated standaard(en) hebben een nieuwere '
        'upstreamversie.\n$where\n'
        'Adviserend: dit breekt de build niet. Weeg zelf of deze release met de '
        'huidige bundel de deur uit mag.',
      );
      exit(0);
    }
    stderr.writeln(
      '\ncheck_reference_data: $outdated standaard(en) verouderd.\n$where',
    );
    exit(1);
  }
  stdout.writeln(
    outdatedAdvisory > 0
        ? '\nReference data OK (op de adviserende meldingen na).'
        : '\nReference data OK.',
  );
}

/// Trekt de standaarden uit de Dart-bron. Bewust regel-voor-regel en niet met
/// één grote regexp over het hele bestand: zo is een gemiste standaard een
/// zichtbaar gat in de tabel in plaats van een stille nul.
List<_Standard> _parseStandards(String source) {
  final consts = <String, String>{};
  for (final m in RegExp(
    r"^const (\w+) = '([^']*)';",
    multiLine: true,
  ).allMatches(source)) {
    consts[m.group(1)!] = m.group(2)!;
  }

  final out = <_Standard>[];
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
      _Standard(
        field('id'),
        field('name'),
        version,
        RegExp(r'probe: UpstreamProbe\.(\w+)').firstMatch(b)?.group(1) ?? '',
        field('probeTarget'),
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
class _Result {
  final String? latest;
  final bool stale;

  /// Een bevinding die géén veroudering is maar wel fout — nu: een bundel die
  /// niet zoveel items bevat als de bron zegt.
  final String integrityProblem;

  /// Vrije toelichting voor onder de tabel.
  final String note;

  _Result(
    this.latest, {
    this.stale = false,
    this.integrityProblem = '',
    this.note = '',
  });
}

Future<_Result> _probe(_Standard s) async {
  switch (s.probe) {
    case 'githubReleases':
      final latest = await _latestGithubRelease(s.target);
      // Elke afwijking alarmeert: OWASP hernummerde MASTG van 1.x naar 2.0,
      // dus groter-is-nieuwer gaat hier niet op.
      return _Result(latest, stale: latest != null && latest != s.version);
    case 'githubCommitDate':
      final latest = await _latestCommitDate(s.target);
      return _Result(
        latest,
        stale: latest != null && latest.compareTo(s.version) > 0,
      );
    case 'githubReleaseDate':
      final latest = await _latestGithubRelease(s.target, byDate: true);
      return _Result(
        latest,
        stale: latest != null && latest.compareTo(s.version) > 0,
      );
    case 'orphanetDate':
      final latest = await _probeOrphanetDate(s.target);
      return _Result(
        latest,
        stale: latest != null && latest.compareTo(s.version) > 0,
      );
    case 'cweApi':
      return _probeCweApi(s);
    case 'successorDocument':
      return _probeSuccessor(s);
    default:
      return _Result(null);
  }
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

/// De datum van de laatste commit op de standaardbranch, als `JJJJ-MM-DD`.
Future<String?> _latestCommitDate(String repo) async {
  if (repo.isEmpty) return null;
  final body = await _get(
    Uri.parse('https://api.github.com/repos/$repo/commits?per_page=1'),
  );
  if (body == null) return null;
  try {
    final list = jsonDecode(body) as List;
    if (list.isEmpty) return null;
    final date = ((list.first as Map)['commit'] as Map)['committer'] as Map;
    final at = date['date'];
    if (at is! String || at.length < 10) return null;
    return at.substring(0, 10);
  } on Object {
    return null;
  }
}

/// MITRE's CWE-API: versie, inhoudsdatum én het aantal zwakheden.
Future<_Result> _probeCweApi(_Standard s) async {
  final body = await _get(Uri.parse(s.target));
  if (body == null) return _Result(null);
  final Map<String, dynamic> json;
  try {
    json = jsonDecode(body) as Map<String, dynamic>;
  } on Object {
    return _Result(null);
  }
  final version = json['ContentVersion']?.toString();
  if (version == null || version.isEmpty) return _Result(null);
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

  return _Result(
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
    return (jsonDecode(f.readAsStringSync()) as List).length;
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
Future<_Result> _probeSuccessor(_Standard s) async {
  final candidates = _successorVersions(s.version);
  if (candidates.isEmpty) return _Result(null);
  for (final candidate in candidates) {
    final url = Uri.parse(s.target.replaceAll('{version}', candidate));
    final exists = await _exists(url);
    if (exists == null) return _Result(null); // bron onbereikbaar
    if (exists) {
      return _Result(
        candidate,
        stale: true,
        note:
            '${s.name}: er bestaat een document voor v$candidate '
            '(${url.toString()}).',
      );
    }
  }
  return _Result(
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

/// De laatste release van een GitHub-repo: de tag (ontdaan van een `v`-prefix),
/// of met [byDate] de publicatiedatum als `JJJJ-MM-DD`.
Future<String?> _latestGithubRelease(String repo, {bool byDate = false}) async {
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
    if (byDate) {
      final at = json['published_at'];
      if (at is! String || at.length < 10) return null;
      return at.substring(0, 10);
    }
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
