import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/menu.dart';
import 'package:ocideck/models/question.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/export_readiness.dart';
import 'package:ocideck/utils/document_front_matter.dart';

/// De documentatie schrijft een paar tellingen en opsommingen uit die nergens
/// uit de code worden afgeleid. Die verrotten stil: het actie-slidetype werd
/// geschrapt en `API_DOCUMENTATION.md` bleef 24 types claimen terwijl het er 23
/// waren, plus "de laatste vijf" terwijl het er zes waren geworden.
///
/// Een lezer die zoiets narekent verliest vertrouwen in de rest van het
/// document, en juist bij een enum-telling is nakijken goedkoop.
void main() {
  String read(String path) => File(path).readAsStringSync();

  group('API_DOCUMENTATION telt de enums goed', () {
    test('het aantal SlideType-waarden klopt', () {
      final doc = read('docs/API_DOCUMENTATION.md');
      final match = RegExp(r'`SlideType` \((\d+) values\)').firstMatch(doc);
      expect(match, isNotNull, reason: 'de SlideType-telling staat er niet');
      expect(
        int.parse(match!.group(1)!),
        SlideType.values.length,
        reason: 'werk de telling in API_DOCUMENTATION.md bij',
      );
    });

    test('elk SlideType wordt bij naam genoemd', () {
      final doc = read('docs/API_DOCUMENTATION.md');
      for (final type in SlideType.values) {
        expect(
          doc,
          contains(type.name),
          reason: '${type.name} ontbreekt in API_DOCUMENTATION.md',
        );
      }
    });

    // Dezelfde bewaking voor de vraag-enums. Ze zijn met twee soorten tegelijk
    // gegroeid; de telling in GLOSSARY liep om precies deze reden achter en
    // niets merkte het.
    test('de vraag-enums tellen en noemen kloppen', () {
      final doc = read('docs/API_DOCUMENTATION.md');
      void checkEnum(String label, List<Enum> values) {
        final match = RegExp('`$label` \\((\\d+) values\\)').firstMatch(doc);
        expect(match, isNotNull, reason: 'de $label-telling staat er niet');
        expect(
          int.parse(match!.group(1)!),
          values.length,
          reason: 'werk de $label-telling in API_DOCUMENTATION.md bij',
        );
        for (final value in values) {
          expect(
            doc,
            contains(value.name),
            reason: '$label.${value.name} ontbreekt in API_DOCUMENTATION.md',
          );
        }
      }

      checkEnum('QuestionKind', QuestionKind.values);
      checkEnum('QuestionOnWrong', QuestionOnWrong.values);
      checkEnum('QuestionResult', QuestionResult.values);
    });

    // De keuze-menu-indeling (#1162) schrijft zijn drie waarden ook uit. Zelfde
    // reden, zelfde vorm: een vierde indeling erbij maakt de zin stil onwaar.
    test('de keuzemenu-indeling telt en noemt klopt', () {
      final doc = read('docs/API_DOCUMENTATION.md');
      final match = RegExp(r'`MenuLayout` \((\d+) values\)').firstMatch(doc);
      expect(match, isNotNull, reason: 'de MenuLayout-telling staat er niet');
      expect(
        int.parse(match!.group(1)!),
        MenuLayout.values.length,
        reason: 'werk de MenuLayout-telling in API_DOCUMENTATION.md bij',
      );
      for (final layout in MenuLayout.values) {
        expect(
          doc,
          contains(layout.name),
          reason: 'MenuLayout.${layout.name} ontbreekt in API_DOCUMENTATION.md',
        );
      }
    });

    // Dezelfde vorm, dezelfde reden: de exportstatus kreeg er op 2026-07-22 een
    // waarde bij (`readyPrivacyUnchecked`), en zonder deze poort was de telling
    // in het document vanaf de eerstvolgende toevoeging weer stil onwaar.
    test('het aantal ExportReadinessStatus-waarden klopt', () {
      final doc = read('docs/API_DOCUMENTATION.md');
      final match = RegExp(
        r'`ExportReadinessStatus` \((\d+) values\)',
      ).firstMatch(doc);
      expect(match, isNotNull, reason: 'de statustelling staat er niet');
      expect(
        int.parse(match!.group(1)!),
        ExportReadinessStatus.values.length,
        reason: 'werk de telling in API_DOCUMENTATION.md bij',
      );
    });

    test('elke ExportReadinessStatus wordt bij naam genoemd', () {
      final doc = read('docs/API_DOCUMENTATION.md');
      for (final status in ExportReadinessStatus.values) {
        expect(
          doc,
          contains(status.name),
          reason: '${status.name} ontbreekt in API_DOCUMENTATION.md',
        );
      }
    });
  });

  group('GLOSSARY telt de slidetypes goed', () {
    // De woordenlijst schrijft dezelfde telling en opsomming uit als
    // API_DOCUMENTATION, maar werd door niets bewaakt. Ze bleef daardoor op 21
    // staan terwijl er 24 types waren — `scorecard`, `assets` en `discoveries`
    // ontbraken. Precies de stille verrotting waar dit bestand voor bestaat,
    // dus nu hangt de tweede plek aan dezelfde bron als de eerste.
    test('het aantal SlideType-waarden klopt', () {
      final doc = read('docs/GLOSSARY.md');
      final match = RegExp(r'`SlideType` \((\d+) values\)').firstMatch(doc);
      expect(match, isNotNull, reason: 'de SlideType-telling staat er niet');
      expect(
        int.parse(match!.group(1)!),
        SlideType.values.length,
        reason: 'werk de telling in GLOSSARY.md bij',
      );
    });

    test('elk SlideType wordt bij naam genoemd', () {
      final doc = read('docs/GLOSSARY.md');
      for (final type in SlideType.values) {
        expect(
          doc,
          contains('`${type.name}`'),
          reason: '${type.name} ontbreekt in GLOSSARY.md',
        );
      }
    });
  });

  test('FILE_FORMAT noemt het class-token van elk slidetype', () {
    final doc = read('docs/FILE_FORMAT.md');
    for (final entry in slideTypeMeta.entries) {
      final token = entry.value.marpClass;
      // Types zonder eigen token (bullets, afbeeldingen, vrije markdown) worden
      // op inhoud herkend en hebben niets te registreren.
      if (token.isEmpty) continue;
      expect(
        doc,
        contains('`$token`'),
        reason:
            'het token `$token` van ${entry.key.name} staat niet in '
            'FILE_FORMAT.md',
      );
    }
  });

  test('FILE_FORMAT noemt elk grafiektype', () {
    final doc = read('docs/FILE_FORMAT.md');
    for (final type in ChartType.values) {
      expect(
        doc,
        contains('`${type.name}`'),
        reason: 'grafiektype ${type.name} staat niet in FILE_FORMAT.md',
      );
    }
  });

  /// §3.2 belooft de velden van het stijlprofiel uit te schrijven, en §3.3 zegt
  /// dat een `.ocideckstyle` "exactly the §3.2 field set" draagt. Tien velden
  /// (de drie `checklist…`- en zeven `table…`-velden) stonden er jarenlang niet
  /// in: ze kwamen met een functie mee en niemand liep de tabel na. Een lezer
  /// die de tabel als volledig leest, mist dan precies wat er nieuw is.
  ///
  /// Dart kent geen reflectie, dus de velden komen uit de bron van het model.
  test('FILE_FORMAT noemt elk veld van het stijlprofiel', () {
    final source = read('lib/models/settings.dart');
    final start = source.indexOf('class ThemeProfile {');
    expect(start, greaterThan(-1), reason: 'ThemeProfile niet gevonden');
    final end = source.indexOf('const ThemeProfile(', start);
    expect(end, greaterThan(start), reason: 'constructor niet gevonden');
    final fields = RegExp(
      r'^\s*final\s+[\w<>?,\s]+?\s+(\w+);\s*$',
      multiLine: true,
    ).allMatches(source.substring(start, end)).map((m) => m.group(1)!).toList();
    expect(
      fields.length,
      greaterThan(30),
      reason: 'de velden zijn niet gelezen',
    );

    final doc = read('docs/FILE_FORMAT.md');
    for (final field in fields) {
      expect(
        doc,
        contains('`$field`'),
        reason: 'stijlprofiel-veld $field staat niet in FILE_FORMAT.md §3.2',
      );
    }
  });

  /// Het register van front-matter-sleutels die het documentpad zelf schrijft
  /// (§14.1 belooft: geen eigen dialect, elke sleutel voert een ander
  /// gereedschap uit). Een sleutel erbij zonder een woord in het
  /// bestandsformaat is precies hoe `reference-location:` er ongemerkt in
  /// kwam terwijl §14.5 nog "exactly three keys" beloofde.
  test('FILE_FORMAT noemt elke sleutel die het documentpad schrijft', () {
    final doc = read('docs/FILE_FORMAT.md');
    for (final key in kDocumentOwnedKeys) {
      expect(
        doc,
        contains('`$key'),
        reason: 'front-matter-sleutel $key staat niet in FILE_FORMAT.md §14',
      );
    }
  });

  /// §8 belooft een *overzicht* van de HTML-commentaren die OciDeck schrijft.
  /// Dat was het niet: elf markers stonden er niet in, waaronder
  /// `ocideck_media_redacted` en `ocideck_ms_review`. Ze verdwenen niet met een
  /// knal — ze kwamen met een functie mee en niemand liep de tabel na.
  ///
  /// De scan zoekt naar de letterlijke commentaarvorm in `lib/`, niet naar de
  /// naam: `ocideck_staging` en `ocideck_git_sandbox` zijn mapnamen en horen
  /// hier niet bij.
  test('FILE_FORMAT noemt elke ocideck_-marker die in een .md belandt', () {
    final marker = RegExp(r'<!--\\?s?\*?\s*(ocideck_[a-z_]+)');
    final found = <String>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final m in marker.allMatches(entity.readAsStringSync())) {
        found.add(m.group(1)!);
      }
    }
    expect(found.length, greaterThan(20), reason: 'de scan vond bijna niets');

    final doc = read('docs/FILE_FORMAT.md');
    for (final name in found) {
      expect(
        doc,
        contains(name),
        reason:
            'de marker $name wordt in een .md geschreven maar staat nergens in '
            'FILE_FORMAT.md (§8 is het overzicht)',
      );
    }
  });
}
