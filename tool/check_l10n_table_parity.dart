// Vergelijkt de 32 vertaaltabellen ONDERLING: elke sleutel die in één taal
// bestaat hoort in álle talen te bestaan.
//
// ── Het gat dat deze poort dicht ─────────────────────────────────────────────
//
// De bestaande dekkingstoets (`all literal Dutch source strings are translated
// in every language`, test/app_localizations_test.dart) scant lib/ op
// `d('…')`-literalen en eist alleen vóór díe sleutels een vertaling in elke
// taal. Haar spiegelbeeld, tool/check_l10n_orphans.dart, vraagt of een sleutel
// nog wordt opgehaald — en kijkt daarvoor in één tabel (en.dart).
//
// Allebei redeneren ze vanuit het GEBRUIK in lib/. Een sleutel die wél in de
// tabellen staat maar (even) nergens wordt opgevraagd valt door beide mazen:
// hij mag in de ene taal bestaan en in de andere ontbreken zonder dat iets
// klaagt. Bij #1520 bleek zo dat zes talen (de, es, fr, fy, it, pap) vier
// bronsleutels misten en dat 25 talen twee andere misten — dat stond er al
// een tijd en niemand zag het. Deze poort kijkt daarom niet naar gebruik maar
// naar de tabellen zelf.
//
// ── Twee sleutelfamilies, geen drie ──────────────────────────────────────────
//
// Per taal staan er drie top-level maps in lib/l10n/translations/<taal>.dart:
//
//   * `_strings<Taal>`        — de `t('sleutelnaam')`-tabel;
//   * `_dutchSource<Taal>`    — de `d('Nederlandse bronzin')`-tabel;
//   * `_dutchSourceAdd<Taal>` — dezelfde soort tabel, alleen jonger.
//
// De laatste twee zijn ÉÉN naamruimte. `make add-l10n` schrijft nieuwe
// bronstrings in de `Add`-tabel, en `AppLocalizations.d()` zoekt in allebei
// (eerst `Add`, dan de basis). Waar de knip tussen die twee ligt verschilt
// bovendien per taal, puur door de volgorde waarin ze ooit zijn aangelegd: de
// meeste talen staan op 1266/2014, de/es/fr/it op 501/2777, tr op 1949/1331.
// Per tabel vergelijken zou dus ruim duizend verschillen per taal melden die
// voor de app niets betekenen. Vandaar: de twee Nederlandse-brontabellen samen
// als één familie, `_strings*` apart.
//
// ── Waarom nl anders telt ────────────────────────────────────────────────────
//
// Nederlands is de brontaal. `d('Opslaan')` geeft voor nl meteen 'Opslaan'
// terug zonder ook maar één tabel te raadplegen, dus nl.dart HEEFT geen
// Nederlandse-brontabellen. Zonder uitzondering zou deze poort alle ~3280
// bronsleutels als "ontbreekt in nl" melden. nl doet daarom alleen mee in de
// `_strings*`-familie — daar heeft ook nl een echte tabel nodig, want `t()`
// heeft voor nl wél een waarde nodig.
//
// ── Waarom in `check` en niet in `check-full` ────────────────────────────────
//
// Zie het Makefile-doel `check-l10n-parity`. Kort: dit is een exacte
// verzamelingsvergelijking over 32 bestanden — geen tekstheuristiek, geen
// ratchet, geen basislijn, en klaar in een seconde. Hij kan dus strenger staan
// (nul tolerantie) en vroeger (bij elke `make check`) dan de wezenpoort, die
// op tekstbewijs leunt en daarom een basislijn draagt.
//
// Gebruik:
//   dart run tool/check_l10n_table_parity.dart          # de poort
//   dart run tool/check_l10n_table_parity.dart --list   # elk gat, per sleutel

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// De map met één Dart-bestand per taal.
const String translationsDir = 'lib/l10n/translations';

/// De brontaal: heeft geen Nederlandse-brontabellen en hoort die ook niet te
/// krijgen (zie de kop van dit bestand).
const String sourceLanguage = 'nl';

/// De `t()`-sleuteltabel. Elke taal, inclusief [sourceLanguage], draagt hem.
const String keyedFamily = 'strings';

/// De `d()`-brontabellen samen. Elke taal behalve [sourceLanguage].
const String dutchSourceFamily = 'dutchSource';

/// Een sleutel die in sommige taaltabellen staat en in andere niet.
class ParityGap {
  const ParityGap({
    required this.key,
    required this.family,
    required this.missingIn,
    required this.presentIn,
  });

  /// De sleutel: een `t()`-sleutelnaam of een Nederlandse bronstring.
  final String key;

  /// [keyedFamily] of [dutchSourceFamily] — zegt in welke tabel hij hoort.
  final String family;

  /// Talen die hem missen, alfabetisch.
  final List<String> missingIn;

  /// Talen die hem wél hebben, alfabetisch. Wie het gat dicht haalt hier zijn
  /// vertaling vandaan; staat er maar één taal in, dan is het meestal een
  /// restant dat weg moet in plaats van een gat dat gevuld moet worden.
  final List<String> presentIn;
}

/// De sleutels per taal en per familie, gelezen uit [root]/[translationsDir].
///
/// AST-gemeten, net als tool/check_l10n_orphans.dart: een reguliere expressie
/// struikelt over een sleutel die zelf een dubbele punt of een aanhalingsteken
/// draagt, en die staan er.
Map<String, Map<String, Set<String>>> translationTables(String root) {
  final directory = Directory('$root/$translationsDir');
  final tables = <String, Map<String, Set<String>>>{};
  if (!directory.existsSync()) return tables;

  final files = directory.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    if (!name.endsWith('.dart')) continue;
    final language = name.substring(0, name.length - '.dart'.length);
    tables[language] = _familiesIn(file);
  }
  return tables;
}

Map<String, Set<String>> _familiesIn(File file) {
  final unit = parseString(
    content: file.readAsStringSync(),
    featureSet: FeatureSet.latestLanguageVersion(),
    throwIfDiagnostics: false,
  ).unit;

  final families = <String, Set<String>>{};
  for (final declaration in unit.declarations) {
    if (declaration is! TopLevelVariableDeclaration) continue;
    for (final variable in declaration.variables.variables) {
      final initializer = variable.initializer;
      if (initializer is! SetOrMapLiteral) continue;
      final family = _familyOf(variable.name.lexeme);
      if (family == null) continue;
      final keys = families.putIfAbsent(family, () => <String>{});
      for (final element in initializer.elements) {
        if (element is! MapLiteralEntry) continue;
        final key = element.key;
        if (key is! StringLiteral) continue;
        final value = key.stringValue;
        if (value != null) keys.add(value);
      }
    }
  }
  return families;
}

/// `_dutchSourceAddDe` en `_dutchSourceDe` vallen allebei in
/// [dutchSourceFamily]; `_stringsDe` in [keyedFamily]. De volgorde van de
/// vergelijking doet er niet toe zolang `_dutchSourceAdd…` niet als iets anders
/// dan `_dutchSource…` wordt gelezen — ze horen in dezelfde familie.
String? _familyOf(String variableName) {
  if (variableName.startsWith('_dutchSource')) return dutchSourceFamily;
  if (variableName.startsWith('_strings')) return keyedFamily;
  return null;
}

/// Welke talen in een familie meetellen.
///
/// Alleen [sourceLanguage] valt buiten [dutchSourceFamily]. Een andere taal die
/// haar brontabellen mist is geen uitzondering maar een fout: dan mist ze
/// simpelweg élke bronsleutel, en dat hoort deze poort te melden.
List<String> languagesInFamily(Iterable<String> languages, String family) {
  final selected = [
    for (final language in languages)
      if (family != dutchSourceFamily || language != sourceLanguage) language,
  ];
  return selected..sort();
}

/// Elke sleutel die niet in alle talen van zijn familie voorkomt.
///
/// [root] is de wortel van de boom die onderzocht wordt; dat de poort niet
/// hardcodeert waar ze kijkt is wat haar toetsbaar maakt (zie
/// test/l10n_table_parity_test.dart, dat een mini-repo bouwt).
List<ParityGap> findParityGaps(String root) {
  final tables = translationTables(root);
  if (tables.isEmpty) return const [];

  final gaps = <ParityGap>[];
  for (final family in const [keyedFamily, dutchSourceFamily]) {
    final languages = languagesInFamily(tables.keys, family);
    final keysPerLanguage = {
      for (final language in languages)
        language: tables[language]?[family] ?? const <String>{},
    };
    final universe = <String>{
      for (final keys in keysPerLanguage.values) ...keys,
    };

    for (final key in universe) {
      final missing = [
        for (final language in languages)
          if (!keysPerLanguage[language]!.contains(key)) language,
      ];
      if (missing.isEmpty) continue;
      gaps.add(
        ParityGap(
          key: key,
          family: family,
          missingIn: missing,
          presentIn: [
            for (final language in languages)
              if (keysPerLanguage[language]!.contains(key)) language,
          ],
        ),
      );
    }
  }

  gaps.sort((a, b) {
    final byFamily = a.family.compareTo(b.family);
    return byFamily != 0 ? byFamily : a.key.compareTo(b.key);
  });
  return gaps;
}

void main(List<String> args) {
  final gaps = findParityGaps('.');

  if (args.contains('--list')) {
    for (final gap in gaps) {
      stdout
        ..writeln('${gap.family}: "${gap.key}"')
        ..writeln(
          '  ontbreekt in (${gap.missingIn.length}): '
          '${gap.missingIn.join(", ")}',
        )
        ..writeln(
          '  staat in (${gap.presentIn.length}): '
          '${gap.presentIn.join(", ")}',
        );
    }
    exit(0);
  }

  if (gaps.isNotEmpty) {
    final holes = gaps.fold<int>(0, (sum, gap) => sum + gap.missingIn.length);
    stderr
      ..writeln('l10n table parity FAILED:')
      ..writeln(
        '  ${gaps.length} sleutel(s) staan niet in alle taaltabellen — samen '
        '$holes ontbrekende regel(s).',
      );
    for (final gap in gaps.take(10)) {
      stderr.writeln(
        '  ${gap.family}: "${gap.key}" ontbreekt in ${gap.missingIn.length} '
        'taal/talen (${gap.missingIn.take(6).join(", ")}'
        '${gap.missingIn.length > 6 ? ", …" : ""})',
      );
    }
    if (gaps.length > 10) {
      stderr.writeln('  … en ${gaps.length - 10} meer.');
    }
    stderr
      ..writeln(
        '  Vul het gat met de vertaling uit een taal die de sleutel wél heeft, '
        'of haal de sleutel overal weg als hij een restant is (staat hij nog '
        'maar in één taal, dan is dat het waarschijnlijkst).',
      )
      ..writeln(
        '  Volledige lijst: dart run tool/check_l10n_table_parity.dart --list',
      );
    exit(1);
  }

  stdout.writeln(
    'l10n table parity OK: alle taaltabellen dragen dezelfde sleutels.',
  );
  exit(0);
}
