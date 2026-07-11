import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/eis_entry.dart';
import 'package:ocideck/services/miauw_eis_catalog.dart';

void main() {
  final catalog = MiauwEisCatalog.instance;

  group('MiauwEisCatalog data integrity', () {
    test('every entry is well-formed', () {
      expect(catalog.entries, isNotEmpty);
      for (final e in catalog.entries) {
        expect(e.id.trim(), isNotEmpty);
        expect(e.title.trim(), isNotEmpty, reason: e.id);
      }
    });

    test('ids are unique', () {
      final ids = catalog.entries.map((e) => e.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'duplicate EIS id');
    });

    test('automatic EIS carry a check, manual ones do not', () {
      for (final e in catalog.entries) {
        if (e.derivation == EisDerivation.automatic) {
          expect(e.check, isNotNull, reason: '${e.id} automatic without check');
        } else {
          expect(e.check, isNull, reason: '${e.id} manual with a check');
        }
      }
    });

    test('covers all four MIAUW parts', () {
      for (final part in EisPart.values) {
        expect(catalog.forPart(part), isNotEmpty, reason: part.name);
      }
    });
  });

  group('MiauwEisCatalog lookup', () {
    test('byId returns the matching entry', () {
      final signOff = catalog.byId('1.6');
      expect(signOff, isNotNull);
      expect(signOff!.check, EisCheck.signOff);
      expect(signOff.part, EisPart.algemeen);
    });

    test('byId returns null for an id outside the subset', () {
      expect(catalog.byId('9.9'), isNull);
    });

    test('forPart keeps schema order', () {
      final ids = catalog.forPart(EisPart.algemeen).map((e) => e.id).toList();
      expect(ids.first, '1.1');
      expect(ids, contains('1.6'));
    });
  });
}
