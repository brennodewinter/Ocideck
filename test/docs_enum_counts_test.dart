import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/slide.dart';

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
}
