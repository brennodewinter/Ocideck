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
import 'dart:convert';
import 'dart:io';

/// Uitgelezen uit lib/services/reference_standards.dart, zodat dit gereedschap
/// en de app niet uiteen kunnen lopen. Bewust een parse van de bron en geen
/// tweede lijst: een handmatig gekopieerde lijst is precies de fout die dit
/// gereedschap moet voorkomen.
final _sourceFile = File('lib/services/reference_standards.dart');

class _Standard {
  final String id, name, version, probe, target;
  _Standard(this.id, this.name, this.version, this.probe, this.target);
}

void main(List<String> args) async {
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
  var unreachable = 0;

  for (final s in standards) {
    final byDate = s.probe == 'githubReleaseDate';
    if (s.probe != 'githubReleases' && !byDate) {
      rows.add([s.name, s.version, '—', 'onbekend (niet te bevragen)']);
      continue;
    }
    final latest = await _latestGithubRelease(s.target, byDate: byDate);
    if (latest == null) {
      unreachable++;
      rows.add([s.name, s.version, '?', 'onbekend (bron onbereikbaar)']);
      continue;
    }
    // Op datum is "nieuwer" echt te bepalen; op een tag is elke afwijking reden
    // om een mens te laten kijken (OWASP hernummerde MASTG van 1.x naar 2.0,
    // dus groter-is-nieuwer gaat daar niet op).
    final stale = byDate
        ? latest.compareTo(s.version) > 0
        : latest != s.version;
    if (!stale) {
      rows.add([s.name, s.version, latest, 'actueel']);
    } else {
      outdated++;
      rows.add([s.name, s.version, latest, 'VEROUDERD']);
    }
  }

  _printTable(rows);

  if (unreachable == standards.length) {
    stderr.writeln(
      '\ncheck_reference_data: geen enkele bron bereikbaar — '
      'controle niet uitgevoerd (netwerk?).',
    );
    exit(2);
  }
  if (outdated > 0) {
    stderr.writeln(
      '\ncheck_reference_data: $outdated standaard(en) verouderd.\n'
      'Werk de catalogus bij, pas de versie aan in '
      '${_sourceFile.path} én docs/LICENSE_COMPLIANCE.md, en controleer of de '
      'licentie van de bron is gewijzigd.',
    );
    exit(1);
  }
  stdout.writeln('\nReference data OK.');
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
      ),
    );
  }
  return out;
}

/// `wstgVersion` woont in de catalogus zelf, niet in het register. Eén gerichte
/// uitzondering, want de catalogus is daar de bron van waarheid.
String _knownExternalConst(String name, String _) {
  const files = {'wstgVersion': 'lib/services/wstg_catalog.dart'};
  final path = files[name];
  if (path == null) return '';
  final f = File(path);
  if (!f.existsSync()) return '';
  return RegExp(
        "const $name = '([^']*)'",
      ).firstMatch(f.readAsStringSync())?.group(1) ??
      '';
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
