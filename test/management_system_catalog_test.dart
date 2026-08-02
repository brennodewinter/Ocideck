import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/management_system.dart';
import 'package:ocideck/services/management_system_catalog.dart';
import 'package:ocideck/services/reference_standards.dart';

void main() {
  final cat = ManagementSystemCatalog.instance;

  group('de gebundelde ISO-indexen', () {
    // De aantallen zijn het bewijs dat de index compleet is overgenomen, niet
    // half. Ze staan hier hard zodat een per ongeluk weggevallen regel de poort
    // laat vallen in plaats van stil door te glippen.
    test('ISO 27001: 93 controls over vier thema\'s', () {
      expect(cat.sectionsFor(ManagementSystemStandard.iso27001), hasLength(4));
      expect(cat.controlsFor(ManagementSystemStandard.iso27001), hasLength(93));
      expect(cat.controlsInSection(ManagementSystemStandard.iso27001, 'A.5'),
          hasLength(37));
      expect(cat.controlsInSection(ManagementSystemStandard.iso27001, 'A.6'),
          hasLength(8));
      expect(cat.controlsInSection(ManagementSystemStandard.iso27001, 'A.7'),
          hasLength(14));
      expect(cat.controlsInSection(ManagementSystemStandard.iso27001, 'A.8'),
          hasLength(34));
    });

    test('ISO 9001: clausule-index (7 clausules, 28 sub-clausules)', () {
      expect(cat.sectionsFor(ManagementSystemStandard.iso9001), hasLength(7));
      expect(cat.controlsFor(ManagementSystemStandard.iso9001), hasLength(28));
      // 9.3 Management review is de haak waar de 9.3-reviewdia op leunt.
      expect(cat.byId(ManagementSystemStandard.iso9001, '9.3')?.title,
          'Management review');
    });

    test('ISO 42001: 38 controls over negen doelstellingen', () {
      expect(cat.sectionsFor(ManagementSystemStandard.iso42001), hasLength(9));
      expect(cat.controlsFor(ManagementSystemStandard.iso42001), hasLength(38));
    });

    test('elke control wijst naar een bestaande sectie', () {
      for (final std in ManagementSystemStandard.values) {
        final sectionIds = cat.sectionsFor(std).map((s) => s.id).toSet();
        for (final c in cat.controlsFor(std)) {
          expect(sectionIds, contains(c.sectionId),
              reason: '${std.token} ${c.id} → onbekende sectie ${c.sectionId}');
        }
      }
    });

    test('control-ids zijn uniek binnen een norm', () {
      for (final std in ManagementSystemStandard.values) {
        final ids = cat.controlsFor(std).map((c) => c.id).toList();
        expect(ids.toSet(), hasLength(ids.length), reason: std.token);
      }
    });

    test('byId vindt een control en is null voor onbekend', () {
      expect(cat.byId(ManagementSystemStandard.iso27001, 'A.5.1')?.title,
          'Policies for information security');
      expect(cat.byId(ManagementSystemStandard.iso27001, 'A.99.99'), isNull);
    });
  });

  group('ManagementSystemStandard', () {
    test('fromToken rondtript en is null voor onbekend', () {
      for (final s in ManagementSystemStandard.values) {
        expect(ManagementSystemStandard.fromToken(s.token), s);
      }
      expect(ManagementSystemStandard.fromToken('ISO27001'),
          ManagementSystemStandard.iso27001,
          reason: 'hoofdletterongevoelig');
      expect(ManagementSystemStandard.fromToken('bestaat-niet'), isNull);
    });

    test('label draagt naam én editie', () {
      expect(ManagementSystemStandard.iso27001.label, 'ISO/IEC 27001:2022');
      expect(ManagementSystemStandard.iso9001.hasAnnexA, isFalse);
      expect(ManagementSystemStandard.iso27001.hasAnnexA, isTrue);
    });

    test('de editie loopt niet weg bij het register', () {
      // Twee waarheden mogen niet uiteenlopen: de editie op het enum en de
      // bundledVersion in reference_standards.dart (waar de freshness-poort en
      // LICENSE_COMPLIANCE.md uit lezen) horen gelijk te zijn.
      expect(ManagementSystemStandard.iso27001.edition, iso27001BundledEdition);
      expect(ManagementSystemStandard.iso9001.edition, iso9001BundledEdition);
      expect(ManagementSystemStandard.iso42001.edition, iso42001BundledEdition);
    });
  });
}
