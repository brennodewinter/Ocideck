// Wijst vertaalsleutels aan die NERGENS meer worden opgehaald: wezen in de
// vertaaltabel. Elke sleutel kost 31 vertalingen en staat in 32 bestanden; een
// sleutel die niemand meer opvraagt is dus 32 regels onderhoud voor tekst die
// geen mens ooit ziet. De vertaalpoorten van deze repo kijken maar één kant op
// — `make l10n-check` en `test/app_localizations_test.dart` bewaken dat elke
// GEBRUIKTE sleutel in alle talen bestaat. De omgekeerde vraag ("bestaat er
// nog iemand die deze sleutel opvraagt?") werd door niets gesteld.
//
// ── Waarom dit lastiger is dan een grep ──────────────────────────────────────
//
// Een ruwe grep over `lib/l10n/translations/en.dart` gaf 249 kandidaten. Drie
// daarvan zijn met de hand bevestigd; de rest was voor een groot deel ruis,
// langs vier wegen die een grep niet ziet:
//
//   1. AANEENGESCHAKELDE literals. `'Een lange zin die '\n'over twee regels'`
//      is één string in Dart en één sleutel in de tabel, maar staat nergens als
//      één stuk tekst in het bestand. Ook escapes (`\'`, `\n`) verschillen
//      tussen de bron en de sleutelwaarde. Daarom leest deze poort de literals
//      via de AST (net als tool/check_hardcoded_text.dart) en niet met een
//      reguliere expressie.
//   2. De DERDE ophaalweg. Naast `l10n.d('…')` en `l10n.t('…')` bestaat
//      `AppLocalizations.sourceFor(lang, labelNl)` — de verbetermodule haalt
//      daar de labels van haar sjablonen doorheen (canvas_spec.dart,
//      matrix_spec.dart, tree_spec.dart, flow_spec.dart). Die labels komen uit
//      GEGEVENS: assets/improvement/templates/*.md en het gebakken
//      improvement_templates_floor.g.dart. "Bedreigingen" staat dus in geen
//      enkele Dart-literal en is toch in gebruik.
//   3. Doorgeefluiken. `EditorField(label: 'Titel (H1)')` belandt via
//      `l10n.d(widget.label)` in de tabel. Die literal staat wél in de bron, dus
//      de literalverzameling hieronder vangt hem; de datastroomanalyse van
//      check_hardcoded_text is er niet apart voor nodig.
//   4. Samengestelde sleutels. `l10n.t(labelKey!)` in
//      settings_dialog_search.dart krijgt zijn sleutel uit een register — maar
//      de registerregels (`labelKey: 'applicationLanguage'`) zijn literals en
//      staan dus gewoon in de verzameling.
//
// ── Wat als bewijs van gebruik telt ──────────────────────────────────────────
//
// Een sleutel is IN GEBRUIK zodra hij op één van twee manieren voorkomt:
//
//   * als Dart-stringliteral (AST-gemeten, inclusief aaneenschakeling en
//     interpolatiedelen) in lib/, test/ of tool/;
//   * als letterlijke TEKST ergens in de code- of gegevensboom: lib/, test/,
//     tool/, assets/ en web/. Dat vangt weg 2 (JSON in een `.g.dart`, labels in
//     een asset-sjabloon) en alles wat via een generator wordt samengesteld.
//
// Die tweede regel is bewust grof. Hij levert VALSE NEGATIEVEN op — een echte
// wees die toevallig als deeltekst van een andere string voorkomt ("treffer(s)"
// zit in "meer treffer(s)") wordt niet gemeld. Dat is de goede kant om te
// falen: deze poort mag zwijgen over een wees, maar mag nooit iemand op
// zoektocht sturen naar een sleutel die wél gebruikt wordt.
//
// ── Wat NIET als bewijs telt ─────────────────────────────────────────────────
//
//   * docs/, README, CHANGELOG en de rest van het proza. Documentatie
//     BESCHRIJFT de app; ze roept geen sleutel op. Een knoplabel dat in de
//     CHANGELOG geciteerd staat omdat het ooit is toegevoegd, zou anders precies
//     de wezen wegpoetsen die je zoekt — twee van de drie met de hand bevestigde
//     wezen staan in de CHANGELOG.
//   * tool/*_l10n_spec.json. Dat zijn de INVOERbestanden van `make add-l10n`:
//     ze hebben de sleutel gemáákt. Een achtergebleven spec is geen gebruiker.
//   * De vertaaltabellen zelf (lib/l10n/translations/). Dat een sleutel in 32
//     talen bestaat zegt niets over of iemand hem opvraagt.
//
// ── Waarom een ratchet, en waarom in check-full ──────────────────────────────
//
// Zie [orphanBaseline] voor de ratchet en Makefile-doel `check-l10n-orphans`
// voor de plek in de keten.
//
// Gebruik:
//   dart run tool/check_l10n_orphans.dart          # de poort (ratchet)
//   dart run tool/check_l10n_orphans.dart --list   # de volledige lijst

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Hoeveel wezen er nog in de tabel staan. RATCHET: mag dalen, nooit stijgen.
///
/// Niet nul, want dit is de eerste meting: de opruiming is bewust een aparte
/// stap (#1512). Wat de ratchet nú al doet is de aanwas stoppen — een sleutel
/// die je toevoegt en nooit aanroept laat het getal stijgen en faalt de poort.
const int orphanBaseline = 181;

/// Het bestand dat de sleutelvoorraad definieert.
///
/// Eén taal volstaat: `make add-l10n` schrijft een nieuwe sleutel in alle 32
/// tabellen tegelijk, en `test/app_localizations_test.dart` bewaakt dat ze
/// gelijk lopen. Engels is de tabel die ook de `t()`-sleutels draagt.
const String keyTablePath = 'lib/l10n/translations/en.dart';

/// Mappen waarin GEBRUIK kan staan: code en gegevens die de app inleest.
const List<String> useRoots = ['lib', 'test', 'tool', 'assets', 'web'];

/// Deze poort en haar test noemen sleutels bij naam — in commentaar en in een
/// verwachting. Zonder deze uitzondering wast de poort haar eigen bevindingen
/// weg: de drie met de hand bevestigde wezen verdwenen uit de lijst op het
/// moment dat dit bestand ze in een voorbeeldzin opschreef.
const Set<String> selfReferences = {
  'tool/check_l10n_orphans.dart',
  'test/l10n_orphan_check_test.dart',
};

/// Bestanden binnen [useRoots] die geen bewijs van gebruik zijn.
bool isNotEvidence(String path) =>
    path.contains('lib/l10n/translations/') ||
    path.endsWith('_l10n_spec.json') ||
    selfReferences.any(path.endsWith);

/// Extensies die als tekst worden doorzocht. Beeld en lettertypen slaan we over
/// — die kosten alleen tijd.
const Set<String> textExtensions = {
  '.dart',
  '.md',
  '.json',
  '.yaml',
  '.yml',
  '.txt',
  '.html',
  '.css',
  '.js',
  '.csv',
  '.po',
  '.arb',
  '.xml',
  '.sh',
};

/// Een sleutel uit de vertaaltabel die nergens meer wordt opgehaald.
class OrphanKey {
  const OrphanKey({required this.key, required this.table, required this.line});

  /// De sleutel zoals hij in de tabel staat: een `t()`-sleutel
  /// (`settingsLogo`) of een Nederlandse bronstring.
  final String key;

  /// De tabel waarin hij staat (`_stringsEn`, `_dutchSourceEn`, …). Zegt welk
  /// soort sleutel het is en dus hoe je hem opruimt.
  final String table;

  /// Regelnummer in [keyTablePath], zodat je hem meteen kunt vinden.
  final int line;
}

/// Elke sleutel in [keyTablePath], met tabel en regelnummer.
///
/// AST-gemeten: de sleutels van de drie top-level maps. Een reguliere expressie
/// zou over een sleutel struikelen die zelf een dubbele punt of een
/// aangehaald teken draagt.
List<OrphanKey> translationKeysIn(String root) {
  final file = File('$root/$keyTablePath');
  final parsed = parseString(
    content: file.readAsStringSync(),
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  );
  final keys = <OrphanKey>[];
  for (final declaration in parsed.unit.declarations) {
    if (declaration is! TopLevelVariableDeclaration) continue;
    for (final variable in declaration.variables.variables) {
      final initializer = variable.initializer;
      if (initializer is! SetOrMapLiteral) continue;
      for (final element in initializer.elements) {
        if (element is! MapLiteralEntry) continue;
        final key = element.key;
        if (key is! StringLiteral) continue;
        final value = key.stringValue;
        if (value == null) continue;
        keys.add(
          OrphanKey(
            key: value,
            table: variable.name.lexeme,
            line: parsed.lineInfo.getLocation(key.offset).lineNumber,
          ),
        );
      }
    }
  }
  return keys;
}

/// De wezen: sleutels waarvoor geen enkel bewijs van gebruik te vinden is.
///
/// [root] is de wortel van de boom die onderzocht wordt. Dat de poort niet
/// hardcodeert waar ze kijkt, is wat haar toetsbaar maakt: de test bouwt een
/// mini-repo met één gebruikte en één ongebruikte sleutel en controleert
/// allebei de richtingen (test/l10n_orphan_check_test.dart).
List<OrphanKey> findOrphanKeys(String root) {
  final keys = translationKeysIn(root);
  final files = _evidenceFiles(root).toList();

  // Stap 1 — goedkoop en exact: elke Dart-stringliteral, via de AST. Vangt de
  // aaneengeschakelde en ge-escapete vormen die tekstueel zoeken mist.
  final literals = <String>{};
  for (final file in files) {
    if (!file.path.endsWith('.dart')) continue;
    parseString(
      content: file.readAsStringSync(),
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    ).unit.accept(_LiteralCollector(literals));
  }

  final candidates = [
    for (final key in keys)
      if (!literals.contains(key.key)) key,
  ];
  if (candidates.isEmpty) return const [];

  // Stap 2 — duur, dus alleen over wat stap 1 overhoudt: komt de sleutel als
  // tekst voor in de code- of gegevensboom? Dat vangt de sleutels die via
  // `sourceFor()` uit een asset of een gebakken JSON-blok komen.
  final unresolved = {for (final key in candidates) key.key};
  for (final file in files) {
    if (unresolved.isEmpty) break;
    final content = file.readAsStringSync();
    unresolved.removeWhere(content.contains);
  }

  return [
    for (final key in candidates)
      if (unresolved.contains(key.key)) key,
  ]..sort((a, b) => a.line.compareTo(b.line));
}

Iterable<File> _evidenceFiles(String root) sync* {
  for (final name in useRoots) {
    final directory = Directory('$root/$name');
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (!textExtensions.any(path.endsWith)) continue;
      if (isNotEvidence(path)) continue;
      yield entity;
    }
  }
}

class _LiteralCollector extends RecursiveAstVisitor<void> {
  _LiteralCollector(this.literals);

  final Set<String> literals;

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    literals.add(node.value);
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    final value = node.stringValue;
    if (value != null) literals.add(value);
    super.visitAdjacentStrings(node);
  }

  /// Een sleutel die in een interpolatie zit (`'$count treffers gevonden'`)
  /// bestaat nooit als hele literal. De losse tekstdelen tellen daarom mee:
  /// zo blijft een sleutel die met een variabele wordt samengesteld buiten de
  /// melding.
  @override
  void visitStringInterpolation(StringInterpolation node) {
    for (final element in node.elements) {
      if (element is InterpolationString) literals.add(element.value);
    }
    super.visitStringInterpolation(node);
  }
}

void main(List<String> args) {
  final orphans = findOrphanKeys('.');

  if (args.contains('--list')) {
    final byTable = <String, List<OrphanKey>>{};
    for (final orphan in orphans) {
      byTable.putIfAbsent(orphan.table, () => []).add(orphan);
    }
    for (final entry in byTable.entries) {
      stdout.writeln('${entry.key} (${entry.value.length})');
      for (final orphan in entry.value) {
        stdout.writeln('  $keyTablePath:${orphan.line}  "${orphan.key}"');
      }
    }
    exit(0);
  }

  if (orphans.length > orphanBaseline) {
    stderr
      ..writeln('l10n orphan check FAILED:')
      ..writeln(
        '  ${orphans.length} ongebruikte vertaalsleutel(s), meer dan de '
        'basislijn $orphanBaseline. Een sleutel die nergens wordt opgehaald '
        'kost 31 vertalingen in 32 bestanden voor tekst die niemand ziet.',
      )
      ..writeln(
        '  Roep de sleutel aan, of haal hem uit alle taaltabellen. Is hij wél '
        'in gebruik langs een weg die deze poort niet ziet, zet die weg dan in '
        'useRoots/textExtensions in tool/check_l10n_orphans.dart — niet de '
        'basislijn omhoog.',
      )
      ..writeln(
        '  Volledige lijst: dart run tool/check_l10n_orphans.dart --list',
      );
    exit(1);
  }

  stdout.writeln(
    'l10n orphans OK: ${orphans.length} ongebruikte sleutel(s), basislijn '
    '$orphanBaseline.',
  );
  if (orphans.length < orphanBaseline) {
    stdout.writeln(
      '  Er zijn er minder dan de basislijn — zet orphanBaseline in '
      'tool/check_l10n_orphans.dart op ${orphans.length}.',
    );
  }
  exit(0);
}
