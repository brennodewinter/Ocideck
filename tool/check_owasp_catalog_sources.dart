// Controleert de bronstructuur van de drie OWASP-catalogi, zowel voor de
// stabiele uitgave als voor de bewegende ontwikkelbranch.
//
// De gewone verouderingspoort vergelijkt versienummers. Dat bewijst niet dat
// de generator morgen nog iets kan lezen: WSTG verplaatste op `master` zijn
// checklist al van `checklist/` naar `checklists/`, zonder nieuwe release. Deze
// poort resolveert daarom iedere ref eerst naar een onveranderlijke commit-SHA
// en valideert daarna precies de paden en minimale schema-invarianten die onze
// generatoren gebruiken. Development wordt zichtbaar, maar nooit stil voor een
// officiële release aangezien.
//
// Gebruik:
//   dart run tool/check_owasp_catalog_sources.dart
//   dart run tool/check_owasp_catalog_sources.dart --advisory
import 'dart:convert';
import 'dart:io';

const owaspCatalogSources = <OwaspCatalogSource>[
  OwaspCatalogSource(
    id: 'wstg',
    name: 'OWASP WSTG',
    repository: 'OWASP/wstg',
    versionConstant: 'wstgVersion',
    versionFile: 'lib/services/wstg_catalog.dart',
    developmentRef: 'master',
    stableRoot: 'checklist',
    developmentRoot: 'checklists',
    licencePath: 'LICENSE',
    kind: OwaspCatalogKind.wstg,
  ),
  OwaspCatalogSource(
    id: 'mastg',
    name: 'OWASP MASTG',
    repository: 'OWASP/mastg',
    versionConstant: 'mastgVersion',
    versionFile: 'lib/services/mastg_catalog.dart',
    developmentRef: 'master',
    stableRoot: 'tests-beta',
    developmentRoot: 'tests-beta',
    licencePath: 'License.md',
    kind: OwaspCatalogKind.mastg,
  ),
  OwaspCatalogSource(
    id: 'maswe',
    name: 'OWASP MASWE',
    repository: 'OWASP/maswe',
    versionConstant: 'masweVersion',
    versionFile: 'lib/services/maswe_catalog.dart',
    developmentRef: 'main',
    stableRoot: 'weaknesses',
    developmentRoot: 'weaknesses',
    licencePath: 'License.md',
    kind: OwaspCatalogKind.maswe,
  ),
];

enum OwaspCatalogKind { wstg, mastg, maswe }

class OwaspCatalogSource {
  const OwaspCatalogSource({
    required this.id,
    required this.name,
    required this.repository,
    required this.versionConstant,
    required this.versionFile,
    required this.developmentRef,
    required this.stableRoot,
    required this.developmentRoot,
    required this.licencePath,
    required this.kind,
  });

  final String id;
  final String name;
  final String repository;
  final String versionConstant;
  final String versionFile;
  final String developmentRef;
  final String stableRoot;
  final String developmentRoot;
  final String licencePath;
  final OwaspCatalogKind kind;

  String get stableVersion {
    final source = File(versionFile).readAsStringSync();
    return RegExp(
          "^const $versionConstant = '([^']+)';",
          multiLine: true,
        ).firstMatch(source)?.group(1) ??
        '';
  }

  String get stableRef => 'v$stableVersion';
}

class OwaspSourceValidation {
  const OwaspSourceValidation({
    required this.source,
    required this.channel,
    required this.ref,
    required this.sha,
    required this.date,
    required this.itemCount,
    this.problems = const [],
    this.unknownReason = '',
  });

  final OwaspCatalogSource source;
  final String channel;
  final String ref;
  final String sha;
  final String date;
  final int itemCount;
  final List<String> problems;
  final String unknownReason;

  bool get isUnknown => unknownReason.isNotEmpty;
  bool get isValid => !isUnknown && problems.isEmpty;
}

/// Zuivere validatie van één Git-tree. De netwerkrand levert alleen paden en,
/// voor WSTG, het kleine machineleesbare checklistbestand aan.
List<String> validateOwaspTree(
  OwaspCatalogSource source, {
  required bool development,
  required List<String> paths,
  String wstgJson = '',
  String licenceText = '',
}) {
  final problems = <String>[];
  final root = development ? source.developmentRoot : source.stableRoot;
  if (!paths.contains(source.licencePath)) {
    problems.add('${source.licencePath} ontbreekt');
  }
  if (!_isCcBySa4(licenceText)) {
    problems.add('licentie is niet herkenbaar als CC-BY-SA-4.0');
  }

  switch (source.kind) {
    case OwaspCatalogKind.wstg:
      final checklist = '$root/checklist.json';
      if (!paths.contains(checklist)) {
        problems.add('$checklist ontbreekt');
        break;
      }
      problems.addAll(_validateWstgJson(wstgJson, development: development));
      break;
    case OwaspCatalogKind.mastg:
      final tests = paths.where(
        (p) =>
            p.startsWith('$root/') &&
            p.endsWith('.md') &&
            RegExp(r'/MASTG-TEST-\d+\.md$').hasMatch(p),
      );
      if (tests.isEmpty) {
        problems.add('$root/ bevat geen herkenbare MASTG-testbestanden');
      }
      break;
    case OwaspCatalogKind.maswe:
      final weaknesses = paths.where(
        (p) =>
            p.startsWith('$root/') && RegExp(r'/MASWE-\d{4}\.md$').hasMatch(p),
      );
      if (weaknesses.isEmpty) {
        problems.add('$root/ bevat geen herkenbare MASWE-bestanden');
      }
      break;
  }
  return problems;
}

int countOwaspItems(
  OwaspCatalogSource source, {
  required bool development,
  required List<String> paths,
  String wstgJson = '',
}) {
  final root = development ? source.developmentRoot : source.stableRoot;
  switch (source.kind) {
    case OwaspCatalogKind.wstg:
      try {
        final categories = (jsonDecode(wstgJson) as Map)['categories'] as Map;
        final ids = <String>{};
        for (final category in categories.values) {
          final tests = (category as Map)['tests'];
          if (tests is! List) continue;
          for (final test in tests) {
            final id = (test as Map)['id']?.toString() ?? '';
            if (id.isNotEmpty) ids.add(id);
          }
        }
        return ids.length;
      } on Object {
        return 0;
      }
    case OwaspCatalogKind.mastg:
      return paths
          .where(
            (p) =>
                p.startsWith('$root/') &&
                RegExp(r'/MASTG-TEST-\d+\.md$').hasMatch(p),
          )
          .length;
    case OwaspCatalogKind.maswe:
      return paths
          .where(
            (p) =>
                p.startsWith('$root/') &&
                RegExp(r'/MASWE-\d{4}\.md$').hasMatch(p),
          )
          .length;
  }
}

List<String> _validateWstgJson(String text, {required bool development}) {
  if (text.isEmpty) return ['checklist.json kon niet worden gelezen'];
  try {
    final root = jsonDecode(text);
    final categories = root is Map ? root['categories'] : null;
    if (categories is! Map || categories.isEmpty) {
      return ['checklist.json heeft geen niet-lege `categories`-tabel'];
    }
    final seen = <String>{};
    final duplicates = <String>{};
    var count = 0;
    for (final entry in categories.entries) {
      final category = entry.value;
      final tests = category is Map ? category['tests'] : null;
      if (tests is! List) continue;
      for (final value in tests) {
        if (value is! Map) continue;
        final id = value['id']?.toString() ?? '';
        final name = value['name']?.toString() ?? '';
        if (!RegExp(r'^WSTG-[A-Z]{4}-\d{2}$').hasMatch(id) || name.isEmpty) {
          return ['checklist.json bevat een test zonder geldig id of titel'];
        }
        count++;
        if (!seen.add(id)) duplicates.add(id);
      }
    }
    if (count == 0) return ['checklist.json bevat geen tests'];
    // v4.2 publiceert INPV-13 dubbel; de generator meldt dit en gebruikt de
    // laatste. De ontwikkelbron heeft die botsing opgelost en krijgt geen
    // historische uitzondering.
    final allowed = development ? <String>{} : {'WSTG-INPV-13'};
    final unexpected = duplicates.difference(allowed);
    if (unexpected.isNotEmpty) {
      return ['dubbele WSTG-id(s): ${unexpected.join(', ')}'];
    }
    return const [];
  } on Object {
    return ['checklist.json is geen geldig verwacht JSON-schema'];
  }
}

bool _isCcBySa4(String text) {
  final folded = text.toLowerCase();
  return folded.contains('attribution-sharealike 4.0 international') ||
      folded.contains('cc-by-sa-4.0') ||
      folded.contains('cc by-sa 4.0');
}

Future<void> main(List<String> args) async {
  final advisory = args.contains('--advisory');
  if (args.any((a) => a != '--advisory')) {
    stderr.writeln(
      'gebruik: dart run tool/check_owasp_catalog_sources.dart [--advisory]',
    );
    exitCode = 2;
    return;
  }

  final client = _GitHubClient();
  final results = <OwaspSourceValidation>[];
  for (final source in owaspCatalogSources) {
    if (source.stableVersion.isEmpty) {
      results.add(
        OwaspSourceValidation(
          source: source,
          channel: 'stabiel',
          ref: source.stableRef,
          sha: '',
          date: '',
          itemCount: 0,
          problems: ['${source.versionConstant} ontbreekt'],
        ),
      );
      continue;
    }
    results.add(await _inspect(client, source, development: false));
    results.add(await _inspect(client, source, development: true));
  }
  client.close();

  stdout.writeln(
    'Standaard   Kanaal        Ref             Commit        Datum      Bronnen Status',
  );
  stdout.writeln(
    '----------- ------------- --------------- ------------- ---------- ------ --------',
  );
  for (final result in results) {
    final status = result.isUnknown
        ? 'ONBEKEND'
        : result.isValid
        ? 'geldig'
        : 'ONGELDIG';
    stdout.writeln(
      '${result.source.name.padRight(11)} '
      '${result.channel.padRight(13)} '
      '${result.ref.padRight(15)} '
      '${_short(result.sha).padRight(13)} '
      '${result.date.padRight(10)} '
      '${result.itemCount.toString().padLeft(6)}  $status',
    );
    if (result.unknownReason.isNotEmpty) {
      stdout.writeln('  ${result.unknownReason}');
    }
    for (final problem in result.problems) {
      stdout.writeln('  ${result.source.name} ${result.channel}: $problem');
    }
  }

  final invalid = results.where((r) => !r.isValid).length;
  if (invalid == 0) {
    stdout.writeln(
      '\nOWASP-bronstructuur OK: stabiele uitgaven en ontwikkelbranches zijn '
      'op exacte commits valideerbaar.',
    );
    return;
  }
  stderr.writeln(
    '\ncheck_owasp_catalog_sources: $invalid bronkana(a)l(en) niet bewezen.',
  );
  if (!advisory) exitCode = 1;
}

Future<OwaspSourceValidation> _inspect(
  _GitHubClient client,
  OwaspCatalogSource source, {
  required bool development,
}) async {
  final channel = development ? 'ontwikkeling' : 'stabiel';
  final ref = development ? source.developmentRef : source.stableRef;
  final commit = await client.commit(source.repository, ref);
  if (commit == null) {
    return OwaspSourceValidation(
      source: source,
      channel: channel,
      ref: ref,
      sha: '',
      date: '',
      itemCount: 0,
      unknownReason: '${source.repository}@$ref kon niet worden opgelost',
    );
  }
  final paths = await client.tree(source.repository, commit.sha);
  if (paths == null) {
    return OwaspSourceValidation(
      source: source,
      channel: channel,
      ref: ref,
      sha: commit.sha,
      date: commit.date,
      itemCount: 0,
      unknownReason:
          'de Git-tree van ${source.repository}@${commit.sha} ontbreekt',
    );
  }
  final licence = await client.raw(
    source.repository,
    commit.sha,
    source.licencePath,
  );
  final root = development ? source.developmentRoot : source.stableRoot;
  final wstgJson = source.kind == OwaspCatalogKind.wstg
      ? await client.raw(
              source.repository,
              commit.sha,
              '$root/checklist.json',
            ) ??
            ''
      : '';
  final problems = validateOwaspTree(
    source,
    development: development,
    paths: paths,
    wstgJson: wstgJson,
    licenceText: licence ?? '',
  );
  return OwaspSourceValidation(
    source: source,
    channel: channel,
    ref: ref,
    sha: commit.sha,
    date: commit.date,
    itemCount: countOwaspItems(
      source,
      development: development,
      paths: paths,
      wstgJson: wstgJson,
    ),
    problems: problems,
  );
}

String _short(String sha) => sha.length <= 12 ? sha : sha.substring(0, 12);

class _Commit {
  const _Commit(this.sha, this.date);
  final String sha;
  final String date;
}

class _GitHubClient {
  final Map<String, Directory> _repositories = {};

  Future<_Commit?> commit(String repository, String ref) async {
    final repo = await _repository(repository);
    if (repo == null) return null;
    final fetched = await _git(repo, [
      'fetch',
      '--quiet',
      '--depth=1',
      '--filter=blob:none',
      'origin',
      ref,
    ]);
    if (fetched == null) return null;
    final sha = await _git(repo, ['rev-parse', r'FETCH_HEAD^{commit}']);
    if (sha == null || sha.isEmpty) return null;
    final timestamp = await _git(repo, ['show', '-s', '--format=%cI', sha]);
    return _Commit(
      sha,
      timestamp != null && timestamp.length >= 10
          ? timestamp.substring(0, 10)
          : '?',
    );
  }

  Future<List<String>?> tree(String repository, String sha) async {
    final repo = _repositories[repository];
    if (repo == null) return null;
    final output = await _git(repo, ['ls-tree', '-r', '--name-only', sha]);
    if (output == null) return null;
    return output.split('\n').where((line) => line.isNotEmpty).toList();
  }

  Future<String?> raw(String repository, String sha, String path) async {
    final repo = _repositories[repository];
    if (repo == null) return null;
    return _git(repo, ['show', '$sha:$path']);
  }

  Future<Directory?> _repository(String repository) async {
    final existing = _repositories[repository];
    if (existing != null) return existing;
    final dir = Directory.systemTemp.createTempSync('ocideck-owasp-source-');
    final init = await _git(dir, ['init', '--quiet', '--bare']);
    if (init == null) {
      dir.deleteSync(recursive: true);
      return null;
    }
    final remote = await _git(dir, [
      'remote',
      'add',
      'origin',
      'https://github.com/$repository.git',
    ]);
    if (remote == null) {
      dir.deleteSync(recursive: true);
      return null;
    }
    _repositories[repository] = dir;
    return dir;
  }

  Future<String?> _git(Directory directory, List<String> args) async {
    try {
      final result = await Process.run(
        'git',
        args,
        workingDirectory: directory.path,
        environment: const {'GIT_TERMINAL_PROMPT': '0'},
      );
      if (result.exitCode != 0) return null;
      return (result.stdout as String).trim();
    } on Object {
      return null;
    }
  }

  void close() {
    for (final repo in _repositories.values) {
      if (repo.existsSync()) repo.deleteSync(recursive: true);
    }
  }
}
