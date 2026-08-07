// Bewaakt de toolchain waarop de poort draait: officieel stable kanaal, en
// exact de gepinde versie.
//
// #598 meldde dat de enige machine waarop `make check` ooit gedraaid heeft niet
// op de gepinde versie stond: `.tool-versions` zei één ding, de machine zei
// `3.44.2 • [user-branch] • unknown source`, en het pad noemde een derde
// nummer. Elke groene poort waar de publicatie op leunt — en COMPLIANCE.md
// QA.04, "repeatable test procedures" — was dus geproduceerd door een build die
// niemand anders kon reproduceren.
//
// Dat is één keer met de hand rechtgezet en daarna opnieuw uit elkaar gelopen.
// Niemand merkte het, want niets keek. Dát is het gebrek dat deze poort dicht:
// niet welk nummer er draait, maar dat het verschil onzichtbaar kon zijn.
//
// **Drie harde eisen**, elk afzonderlijk fataal:
//
//  1. kanaal `stable` — een build uit `[user-branch]` is per definitie niet
//     reproduceerbaar;
//  2. herkomst de officiële Flutter-repository — "unknown source" zegt niets
//     over wat er in die SDK zit;
//  3. de versie gelijk aan de pin in `.tool-versions` — anders bewijst een
//     groene `dart format` iets over een andere formatter dan CI draait.
//
// Een eerdere opzet eiste alleen dat de draaiende toolchain érgens in een tabel
// in docs/CHECKS.md stond, uit vrees de enige ontwikkelmachine te blokkeren.
// Die soepelheid was een concessie aan een kapotte toestand; zodra die verholpen
// is, wordt ze een achterdeur. Loopt de pin achter op de laatste stable, dan is
// het antwoord de SDK bijwerken en de pin optrekken — niet deze poort verruimen.
import 'dart:convert';
import 'dart:io';

/// De officiële herkomst. Alles daarbuiten is een fork of een onbekende bron.
const officialRepository = 'https://github.com/flutter/flutter.git';

/// Het enige kanaal waarop dit project bouwt.
const requiredChannel = 'stable';

/// De toolchain zoals `flutter --version --machine` hem beschrijft.
class Toolchain {
  final String version;
  final String channel;
  final String source;

  const Toolchain(this.version, this.channel, this.source);

  /// Eén regel, zoals de poort hem meldt en zoals hij in docs/CHECKS.md staat.
  String get line => '$version • $channel • $source';

  @override
  String toString() => line;
}

/// Leest de drie velden die ertoe doen uit de JSON van `flutter --version
/// --machine`.
///
/// Alleen deze drie. De revisie verandert per hotfix zonder dat er iets aan de
/// reproduceerbaarheid verandert, en zou de poort elke week rood maken om niets.
Toolchain? parseToolchain(String machineJson) {
  final Object? decoded;
  try {
    decoded = jsonDecode(machineJson);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final version = decoded['frameworkVersion'];
  final channel = decoded['channel'];
  final source = decoded['repositoryUrl'];
  if (version is! String || channel is! String || source is! String) {
    return null;
  }
  return Toolchain(version, channel, source);
}

/// De versie die `.tool-versions` pint, of null als er geen flutter-regel staat.
///
/// Het formaat is `flutter 3.44.9-stable`; het achtervoegsel is het kanaal van
/// asdf en hoort niet bij het versienummer.
String? parsePin(String toolVersions) {
  for (final raw in const LineSplitter().convert(toolVersions)) {
    final line = raw.trim();
    if (!line.startsWith('flutter ')) continue;
    final value = line.substring('flutter '.length).trim();
    if (value.isEmpty) return null;
    return value.split('-').first;
  }
  return null;
}

/// Wat er mis is met [running] tegenover [pin] — leeg als er niets mis is.
///
/// Alle drie de eisen worden altijd nagelopen, ook als de eerste al valt: wie
/// een toolchain moet vervangen wil in één keer weten wat er allemaal aan
/// mankeert, niet drie runs lang één regel per keer.
List<String> toolchainProblems(Toolchain running, String? pin) => [
  if (running.channel != requiredChannel)
    'kanaal is `${running.channel}`, moet `$requiredChannel` zijn — een build '
        'buiten het stable-kanaal is niet reproduceerbaar',
  if (running.source != officialRepository)
    'herkomst is `${running.source}`, moet `$officialRepository` zijn',
  if (pin == null)
    '.tool-versions noemt geen flutter-versie, dus er valt niets tegen te '
        'toetsen'
  else if (running.version != pin)
    'versie is ${running.version}, `.tool-versions` pint $pin — `dart format` '
        'reflowt tussen releases, dus een groene opmaakpoort zegt hier iets '
        'over een andere formatter dan CI draait',
];

/// Of [doc] deze toolchain als bekende regel noemt.
///
/// Bewust de hele regel en niet de losse velden: zo kan een tabel niet per
/// ongeluk kloppen doordat het versienummer in de ene rij staat en het kanaal
/// in een andere.
bool documentsToolchain(String doc, Toolchain running) =>
    doc.contains(running.line);

/// Eén plek die een versie-eis uitspreekt.
class VersionClaim {
  final String file;
  final int line;
  final String version;
  final String context;

  const VersionClaim(this.file, this.line, this.version, this.context);
}

/// De bestanden die een versie-eis dragen, en de vorm waarin ze dat doen.
///
/// #721: dertien plekken noemen de Flutter-versie en niets bewaakte dat ze het
/// eens waren. Een pin verhogen en er één vergeten is een stille fout — de
/// documentatie belooft dan iets anders dan de machine doet, en dat is precies
/// waar #598 op stukliep.
///
/// De patronen herkennen een **eis**, geen getal. Dat onderscheid is nodig
/// omdat dezelfde documenten ook geschiedenis vertellen ("de machine draaide
/// 3.44.2 terwijl drie documenten 3.44.6 noemden"), en die zinnen horen niet
/// mee te veranderen als de pin opschuift — dan zouden ze onwaar worden.
///
/// De regel die dat scheidt is de opmaak, en hij is met opzet zo simpel: een
/// **vetgedrukte** versie is een eis, een `code-geciteerde` is een citaat. In
/// YAML is `flutter-version:` altijd een eis.
const versionClaimPatterns = <String, String>{
  '.tool-versions': r'^flutter (\d+\.\d+\.\d+)-stable',
  'README.md': r'Flutter \*\*(\d+\.\d+\.\d+)\*\*',
  'CONTRIBUTING.md': r'\*\*Flutter (\d+\.\d+\.\d+)\*\*',
  'docs/BUILD.md': r'\*\*Flutter (\d+\.\d+\.\d+)\*\*',
  'docs/CHECKS.md': r'\*\*Flutter (\d+\.\d+\.\d+)',
  'docs/CONTRIBUTING_GUIDELINES.md': r'\*\*Flutter (\d+\.\d+\.\d+)\*\*',
  'docs/TROUBLESHOOTING_GUIDE.md': r'\*\*Flutter (\d+\.\d+\.\d+)\*\*',
  // Twee vormen in één document: de eis in proza, en de bestandsnaam in het
  // uitpakcommando. Die tweede kan niet vetgedrukt — hij staat in een codeblok
  // — maar een archiefnaam is net zo goed een eis: wie hem overtypt haalt die
  // versie binnen. Zonder deze helft wijst de handleiding je naar de verkeerde
  // download terwijl de zin erboven klopt.
  'docs/DEVELOPMENT_SETUP_GUIDE.md':
      r'(?:\*\*Flutter |flutter_macos_)(\d+\.\d+\.\d+)',
  '.github/workflows/ci.yml': r'flutter-version: (\d+\.\d+\.\d+)',
  '.github/workflows/release.yml': r'flutter-version: (\d+\.\d+\.\d+)',
};

/// Alle versie-eisen in [content] volgens [pattern].
List<VersionClaim> findVersionClaims(
  String file,
  String content,
  String pattern,
) {
  final re = RegExp(pattern, multiLine: true);
  final lines = const LineSplitter().convert(content);
  return [
    for (var i = 0; i < lines.length; i++)
      for (final m in re.allMatches(lines[i]))
        VersionClaim(file, i + 1, m.group(1)!, lines[i].trim()),
  ];
}

/// De eisen die niet met [pin] overeenkomen.
List<VersionClaim> disagreeingClaims(List<VersionClaim> claims, String pin) => [
  for (final c in claims)
    if (c.version != pin) c,
];

void main(List<String> args) async {
  final checks = File('docs/CHECKS.md');
  final pins = File('.tool-versions');

  final ProcessResult probe;
  try {
    probe = await Process.run('flutter', ['--version', '--machine']);
  } on ProcessException catch (e) {
    stderr.writeln(
      'check-toolchain: `flutter` niet uit te voeren: ${e.message}',
    );
    exit(1);
  }
  if (probe.exitCode != 0) {
    stderr.writeln(
      'check-toolchain: `flutter --version --machine` gaf ${probe.exitCode}.',
    );
    exit(1);
  }

  final running = parseToolchain(probe.stdout as String);
  if (running == null) {
    stderr.writeln(
      'check-toolchain: de uitvoer van `flutter --version --machine` was niet '
      'te lezen. Verwacht JSON met frameworkVersion, channel en repositoryUrl.',
    );
    exit(1);
  }

  final pin = pins.existsSync() ? parsePin(pins.readAsStringSync()) : null;
  final problems = toolchainProblems(running, pin);
  if (problems.isNotEmpty) {
    stderr.writeln('check-toolchain FAILED:');
    stderr.writeln('  Deze machine draait: $running');
    for (final p in problems) {
      stderr.writeln('  - $p');
    }
    stderr.writeln('');
    stderr.writeln(
      '  Er hoort één Flutter op deze machine te staan: de laatste stable uit '
      'het officiële kanaal, in ~/flutter. Niet één versie per project — dat '
      'is geen beheer maar toeval.',
    );
    stderr.writeln('');
    stderr.writeln(
      '  Herstel: installeer de laatste stable (archief van '
      'storage.googleapis.com/flutter_infra_release, sha256 toetsen tegen '
      'releases_macos.json vóór uitpakken), en trek daarna élke pin mee: '
      '.tool-versions, README.md, docs/BUILD.md, CONTRIBUTING.md en beide '
      'workflows. Verruim deze poort niet.',
    );
    stderr.writeln(
      '  Staat ~/flutter er al en wint hij niet: kijk naar de PATH-volgorde in '
      '~/.zshrc — een regel vóór die van Homebrew verliest alsnog.',
    );
    exit(1);
  }

  // De pin klopt, dus de documentatie hoort dezelfde toolchain te noemen.
  // Zonder deze tweede toets zou docs/CHECKS.md ongemerkt achter kunnen lopen
  // op een pin-verhoging, en dat is precies de drift die #598 meldde.
  if (checks.existsSync() &&
      !documentsToolchain(checks.readAsStringSync(), running)) {
    stderr.writeln('check-toolchain FAILED:');
    stderr.writeln('  Deze machine draait: $running');
    stderr.writeln(
      '  Dat is de gepinde toolchain, maar docs/CHECKS.md noemt hem niet.',
    );
    stderr.writeln('');
    stderr.writeln(
      '  Herstel: werk de tabel onder "Toolchains of record" bij met de regel '
      'hierboven — letterlijk, inclusief de bolletjes. Een groene poort is een '
      'uitspraak over de toolchain die hem draaide; die hoort opgeschreven te '
      'staan.',
    );
    exit(1);
  }

  // Derde toets: de dertien plekken die de versie noemen moeten het eens zijn
  // (#721). Een pin verhogen en er één vergeten laat de documentatie iets
  // anders beloven dan de machine doet.
  final claims = <VersionClaim>[];
  for (final entry in versionClaimPatterns.entries) {
    final f = File(entry.key);
    if (!f.existsSync()) {
      stderr.writeln('check-toolchain FAILED:');
      stderr.writeln(
        '  ${entry.key} bestaat niet, maar staat wel in versionClaimPatterns.',
      );
      stderr.writeln(
        '  Is het bestand verplaatst, verplaats dan ook de regel — anders '
        'bewaakt de poort stilletjes niets meer.',
      );
      exit(1);
    }
    claims.addAll(
      findVersionClaims(entry.key, f.readAsStringSync(), entry.value),
    );
  }
  if (claims.length < versionClaimPatterns.length) {
    stderr.writeln('check-toolchain FAILED:');
    stderr.writeln(
      '  Slechts ${claims.length} versie-eis(en) gevonden in '
      '${versionClaimPatterns.length} bestanden — minstens één patroon vindt '
      'niets meer.',
    );
    stderr.writeln(
      '  Een poort die niets vindt is groen om de verkeerde reden. Kijk of de '
      'formulering in dat bestand veranderd is en pas het patroon aan.',
    );
    exit(1);
  }
  final disagree = disagreeingClaims(claims, running.version);
  if (disagree.isNotEmpty) {
    stderr.writeln('check-toolchain FAILED:');
    stderr.writeln(
      '  De gepinde versie is ${running.version}, maar '
      '${disagree.length} plek(ken) noemen iets anders:',
    );
    for (final c in disagree) {
      stderr.writeln(
        '  - ${c.file}:${c.line} zegt ${c.version} — ${c.context}',
      );
    }
    stderr.writeln('');
    stderr.writeln(
      '  Herstel: zet ze allemaal op ${running.version}. Een pin die op de ene '
      'plek opschuift en op de andere niet, laat de documentatie iets anders '
      'beloven dan de machine doet (#721).',
    );
    stderr.writeln(
      '  Let op: alleen een **vetgedrukte** versie is een eis. Een '
      '`code-geciteerde` versie in een historische zin hoort niet mee te '
      'veranderen — die zou er onwaar van worden.',
    );
    exit(1);
  }

  stdout.writeln(
    'Toolchain OK: $running — officieel stable, gelijk aan de pin, vastgelegd '
    'in docs/CHECKS.md, en ${claims.length} versie-eis(en) in '
    '${versionClaimPatterns.length} bestanden zijn het eens',
  );
}
