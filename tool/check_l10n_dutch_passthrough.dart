// Wijst vertalingen aan die NIET vertaald zijn maar de NEDERLANDSE bron
// letterlijk hebben doorgelaten: `'Verbinding succesvol.': 'Verbinding
// succesvol.'` in het Klingon.
//
// ── Het gat dat deze poort dicht ─────────────────────────────────────────────
//
// Er stond al een wachter op onvertaalde tekst: test/l10n_untranslated_test.dart
// vergelijkt elke waarde met de ENGELSE vertaling van dezelfde sleutel en meldt
// wat daaraan gelijk is. Die kijkt dus maar één kant op. Een waarde die gelijk
// is aan de Nederlandse BRON glipt er ongemerkt langs, want de bron is geen
// vertaling waarmee zij vergelijkt.
//
// Bij #1524 bleek hoe groot dat gat is: lib/l10n/translations/tlh.dart droeg 44
// sleutels met de Nederlandse bron als waarde, waaronder een compleet
// LibrePlan-connectorblok van hele zinnen ("Kies welke slides u uit het
// LibrePlan-project wilt halen.", "Verbinding succesvol.", "Geen slides
// gevonden."). Het bleek allerminst tot die ene taal beperkt — datzelfde blok
// staat onvertaald in dertig talen.
//
// ── Wat er vergeleken wordt ──────────────────────────────────────────────────
//
// Per taal staan er drie top-level maps in lib/l10n/translations/<taal>.dart.
// De Nederlandse bron zit er op twee manieren in:
//
//   * `_dutchSource<Taal>` en `_dutchSourceAdd<Taal>` — de `d()`-tabellen. Daar
//     IS de sleutel de Nederlandse bronzin, dus de bron staat naast de waarde
//     en `sleutel == waarde` is de doorlaat.
//   * `_strings<Taal>` — de `t()`-tabel. Daar is de sleutel een naam
//     (`settingsLogo`) en zit de Nederlandse bron in `_stringsNl`. De doorlaat
//     is dus `waarde == _stringsNl[sleutel]`.
//
// Allebei tellen mee. In de huidige boom levert de tweede familie niets op,
// maar een `t()`-sleutel kan net zo goed onvertaald blijven en het kost geen
// extra werk om hem mee te nemen.
//
// ── Waarom pas vanaf drie woorden ────────────────────────────────────────────
//
// Precies dezelfde afweging als in test/l10n_untranslated_test.dart, en om
// dezelfde reden. Losse woorden zijn massaal identiek zonder dat er iets mis
// is: `Logo`, `Audio`, `Video`, `Status`, `Canvas`, `Mermaid`, `Gantt`, `OK`.
// Zonder drempel vindt deze poort er 1.800 en heeft ze in de meeste gevallen
// ongelijk — dat is geen poort maar ruis, en ruis wordt weggeklikt. Met de
// drempel blijven er 435 over, en na de uitzonderingen 394 — vrijwel allemaal
// echte gevallen.
//
// De prijs staat er eerlijk bij: een onvertaalde bron van één of twee woorden
// glipt hier doorheen. Dat is te betalen — de fout uit #1524 bestond uit hele
// zinnen.
//
// ── Waarom de uitzonderingen per SLEUTEL gaan ────────────────────────────────
//
// Zie [loanKeys]. Kort: een taal-uitzondering ("tlh mag dit") verbergt de
// volgende fout in diezelfde taal; een sleutel-uitzondering zegt iets over de
// bronzin zelf en blijft daarom houdbaar.
//
// ── Waarom een ratchet, en waarom in check-full ──────────────────────────────
//
// Zie [passthroughBaseline] en het Makefile-doel `check-l10n-passthrough`.
//
// Gebruik:
//   dart run tool/check_l10n_dutch_passthrough.dart           # de poort
//   dart run tool/check_l10n_dutch_passthrough.dart --list     # per sleutel
//   dart run tool/check_l10n_dutch_passthrough.dart --by-lang  # per taal

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// De map met één Dart-bestand per taal.
const String translationsDir = 'lib/l10n/translations';

/// De brontaal. Voor nl IS de waarde de bron; die kan per definitie niet
/// "doorgelaten" zijn en doet dus niet mee.
const String sourceLanguage = 'nl';

/// De `d()`-brontabellen (`_dutchSource*` plus `_dutchSourceAdd*`) samen: één
/// naamruimte, precies zoals tool/check_l10n_table_parity.dart ze telt.
const String dutchSourceFamily = 'dutchSource';

/// De `t()`-sleuteltabel (`_strings*`).
const String keyedFamily = 'strings';

/// Vanaf hoeveel woorden een gelijke waarde als doorlaat telt.
///
/// Zie de kop van dit bestand voor de afweging. Drie, gelijk aan de drempel in
/// test/l10n_untranslated_test.dart — twee poorten die hetzelfde soort bewijs
/// wegen horen dezelfde grens te trekken.
const int minimumWords = 3;

/// Hoeveel doorgelaten bronzinnen er nog staan. RATCHET: mag dalen, nooit
/// stijgen.
///
/// Bij invoering gemeten op de boom van #1526. Nul is de bedoeling en de
/// opruimronde daarna brengt hem daarheen; tot die tijd houdt dit getal tegen
/// dat er nóg een taal of nóg een blok bijkomt. Zakt het getal, zet het dan
/// meteen omlaag — een basislijn die boven de werkelijkheid blijft hangen is
/// stille ruimte voor de volgende fout.
const int passthroughBaseline = 385;

/// Bronsleutels waarvoor een identieke waarde GOED is, niet fout.
///
/// **Het criterium, en het is streng:** de Nederlandse bronzin bevat geen enkel
/// vertaalbaar Nederlands woord. Wat erin staat is een eigennaam, een
/// vastgelegde vakterm, een opmaakplaatshouder, of een Engelse uitdrukking die
/// het Nederlands zélf onvertaald heeft geleend. Alleen dan is gelijkheid het
/// bewijs dat de vertaler de juiste term koos in plaats van het bewijs dat hij
/// niets deed.
///
/// **Waarom per sleutel en niet per taal.** Een uitzondering "tlh mag deze
/// waarde" zegt iets over de vertaler en dekt de volgende fout in diezelfde
/// taal toe. Een uitzondering per sleutel zegt iets over de BRONZIN — dat er
/// niets in zit om te vertalen — en die uitspraak blijft waar, ongeacht wie
/// hem opent.
///
/// **Wat dat kost, hardop.** Een sleutel die hier staat is voor álle talen
/// stil, ook voor een taal met een ander schrift die "Sprint review / demo"
/// wél zou translitereren. Dat is de prijs van een uitzondering die je kunt
/// verdedigen zonder de tabel per taal te laten uitdijen.
///
/// **Wat er bewust NIET in staat.** `Forgejo of Gitea`, `Nextcloud of
/// ownCloud`, `Smal (860 px)` en `ISO 27001 · Annex A — Organisatorisch (A.5)`
/// zijn voor de talen die ze nu raken (fy, pap, da, sv, de, gsw) waarschijnlijk
/// correct — maar ze dragen een woord dat elders wél vertaald moet worden (`of`,
/// `Smal`, `Organisatorisch`). Die blijven in de meting staan; de opruimronde
/// beslist per geval.
const Set<String> loanKeys = {
  // Alleen letters en plaatshouders — er staat geen woord in om te vertalen.
  'P {pitch}  B {bank}',
  // Veldnamen zoals ze letterlijk in de S3- en Forgejo-schermen staan. Wie ze
  // invult kijkt naar dat scherm; vertalen maakt ze onvindbaar.
  'Access key ID',
  'Secret access key',
  'Personal access token',
  // Gage R&R-terminologie (ANOVA). De Nederlandse bron is hier zelf Engels; er
  // is geen Nederlandse variant om vanaf te vertalen.
  'Part × Operator interaction pooled into repeatability',
  'Part × Operator interaction kept separate',
  // Engelse leenuitdrukkingen die het Nederlands onvertaald overnam; het
  // Nederlands zegt niet "spurtbeoordeling" of "nabespreking na de actie".
  'Accent / bullets',
  'Sprint review / demo',
  'CAB / release readiness',
  'Post-incident review / lessons learned',
  'Debriefing / after-action review',
  'Business continuity / DR-test',
  'DPIA / privacy impact assessment',
  'Training / workshop',
};

/// Eén vertaalregel die de Nederlandse bron letterlijk doorliet.
class DutchPassthrough {
  const DutchPassthrough({
    required this.language,
    required this.key,
    required this.value,
    required this.family,
  });

  /// De taal waarin het staat (`tlh`, `da`, …).
  final String language;

  /// De sleutel: een Nederlandse bronzin ([dutchSourceFamily]) of een
  /// sleutelnaam ([keyedFamily]).
  final String key;

  /// De doorgelaten waarde. Voor [dutchSourceFamily] gelijk aan [key]; voor
  /// [keyedFamily] gelijk aan de Nederlandse waarde bij dezelfde sleutel.
  final String value;

  /// [dutchSourceFamily] of [keyedFamily].
  final String family;
}

/// Sleutel → waarde per taal en per familie, gelezen uit [root].
///
/// AST-gemeten, net als tool/check_l10n_orphans.dart: een reguliere expressie
/// struikelt over een sleutel of waarde die zelf een dubbele punt of een
/// aangehaald teken draagt, en die staan er.
Map<String, Map<String, Map<String, String>>> translationEntries(String root) {
  final directory = Directory('$root/$translationsDir');
  final tables = <String, Map<String, Map<String, String>>>{};
  if (!directory.existsSync()) return tables;

  final files = directory.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    if (!name.endsWith('.dart')) continue;
    tables[name.substring(0, name.length - '.dart'.length)] = _familiesIn(file);
  }
  return tables;
}

Map<String, Map<String, String>> _familiesIn(File file) {
  final unit = parseString(
    content: file.readAsStringSync(),
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  ).unit;

  final families = <String, Map<String, String>>{};
  for (final declaration in unit.declarations) {
    if (declaration is! TopLevelVariableDeclaration) continue;
    for (final variable in declaration.variables.variables) {
      final initializer = variable.initializer;
      if (initializer is! SetOrMapLiteral) continue;
      final family = _familyOf(variable.name.lexeme);
      if (family == null) continue;
      final entries = families.putIfAbsent(family, () => <String, String>{});
      for (final element in initializer.elements) {
        if (element is! MapLiteralEntry) continue;
        final key = element.key;
        final value = element.value;
        if (key is! StringLiteral || value is! StringLiteral) continue;
        final keyText = key.stringValue;
        final valueText = value.stringValue;
        if (keyText == null || valueText == null) continue;
        entries[keyText] = valueText;
      }
    }
  }
  return families;
}

String? _familyOf(String variableName) {
  if (variableName.startsWith('_dutchSource')) return dutchSourceFamily;
  if (variableName.startsWith('_strings')) return keyedFamily;
  return null;
}

/// Het aantal woorden in [text]: losse stukken tussen witruimte.
int wordCount(String text) =>
    text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

/// Of een gelijke waarde als doorlaat meetelt.
///
/// Twee zeven: lang genoeg om geen toeval te zijn ([minimumWords]) en niet in
/// [loanKeys].
bool countsAsPassthrough(String key, String value) =>
    !loanKeys.contains(key) && wordCount(value) >= minimumWords;

/// Elke vertaalregel in [root] die de Nederlandse bron letterlijk doorliet.
///
/// [root] is de wortel van de boom die onderzocht wordt; dat de poort niet
/// hardcodeert waar ze kijkt is wat haar toetsbaar maakt (zie
/// test/l10n_dutch_passthrough_test.dart, dat een mini-repo bouwt).
List<DutchPassthrough> findDutchPassthroughs(String root) {
  final tables = translationEntries(root);
  final dutchKeyed = tables[sourceLanguage]?[keyedFamily] ?? const {};

  final found = <DutchPassthrough>[];
  final languages = tables.keys.toList()..sort();
  for (final language in languages) {
    if (language == sourceLanguage) continue;

    (tables[language]?[dutchSourceFamily] ?? const <String, String>{}).forEach((
      key,
      value,
    ) {
      if (key != value) return;
      if (!countsAsPassthrough(key, value)) return;
      found.add(
        DutchPassthrough(
          language: language,
          key: key,
          value: value,
          family: dutchSourceFamily,
        ),
      );
    });

    (tables[language]?[keyedFamily] ?? const <String, String>{}).forEach((
      key,
      value,
    ) {
      if (dutchKeyed[key] != value) return;
      if (!countsAsPassthrough(key, value)) return;
      found.add(
        DutchPassthrough(
          language: language,
          key: key,
          value: value,
          family: keyedFamily,
        ),
      );
    });
  }

  found.sort((a, b) {
    final byKey = a.key.compareTo(b.key);
    return byKey != 0 ? byKey : a.language.compareTo(b.language);
  });
  return found;
}

void main(List<String> args) {
  final found = findDutchPassthroughs('.');

  if (args.contains('--list')) {
    final byKey = <String, List<DutchPassthrough>>{};
    for (final hit in found) {
      byKey.putIfAbsent('${hit.family}|${hit.key}', () => []).add(hit);
    }
    final ordered = byKey.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    for (final entry in ordered) {
      final hits = entry.value;
      stdout
        ..writeln('${hits.first.family}: "${hits.first.key}"')
        ..writeln(
          '  ${hits.length} taal/talen: '
          '${hits.map((h) => h.language).join(", ")}',
        );
    }
    exit(0);
  }

  if (args.contains('--by-lang')) {
    final byLanguage = <String, int>{};
    for (final hit in found) {
      byLanguage[hit.language] = (byLanguage[hit.language] ?? 0) + 1;
    }
    final ordered = byLanguage.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in ordered) {
      stdout.writeln('${entry.key}: ${entry.value}');
    }
    exit(0);
  }

  if (found.length > passthroughBaseline) {
    final languages = {for (final hit in found) hit.language}.length;
    stderr
      ..writeln('l10n Dutch-passthrough check FAILED:')
      ..writeln(
        '  ${found.length} vertaalregel(s) in $languages taal/talen dragen de '
        'Nederlandse bron letterlijk als vertaling, meer dan de basislijn '
        '$passthroughBaseline.',
      );
    for (final hit in found.take(10)) {
      stderr.writeln('  ${hit.language}: "${hit.key}"');
    }
    if (found.length > 10) {
      stderr.writeln('  … en ${found.length - 10} meer.');
    }
    stderr
      ..writeln(
        '  Vertaal ze. Is de bronzin een eigennaam, vakterm of leenuitdrukking '
        'waar niets aan te vertalen valt, zet de SLEUTEL dan in loanKeys in '
        'tool/check_l10n_dutch_passthrough.dart mét de reden — niet de '
        'basislijn omhoog.',
      )
      ..writeln(
        '  Volledige lijst: dart run tool/check_l10n_dutch_passthrough.dart '
        '--list (of --by-lang)',
      );
    exit(1);
  }

  stdout.writeln(
    'l10n Dutch-passthrough OK: ${found.length} doorgelaten bronzin(nen), '
    'basislijn $passthroughBaseline.',
  );
  if (found.length < passthroughBaseline) {
    stdout.writeln(
      '  Er zijn er minder dan de basislijn — zet passthroughBaseline in '
      'tool/check_l10n_dutch_passthrough.dart op ${found.length}.',
    );
  }
  exit(0);
}
