import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/info_safety/info_safety_reference_inventory.dart';

/// "Gegevens lokaal beschikbaar" zei niet wélke, en niet hoeveel. De inventaris
/// telt wat de app daadwerkelijk bedient — niet wat een pakket bewéért te
/// bevatten. Een catalogus die leeg is moet dus ook als leeg te zien zijn.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the snapshot names every reference catalog', () {
    final names = InfoSafetyReferenceInventory.snapshot()
        .map((c) => c.name)
        .toList();

    expect(names, contains('Zwakheden (CWE)'));
    expect(names, contains('Testgevallen (WSTG)'));
    expect(names, contains('MIAUW-eisen'));
    expect(names, contains('CVSS-scoretabel'));
    expect(names, contains('Bevindingsjablonen'));
  });

  test('every catalog reports a real, non-zero count and a source', () {
    for (final c in InfoSafetyReferenceInventory.snapshot()) {
      expect(
        c.count,
        greaterThan(0),
        reason: '${c.name} telt 0 — dan is "beschikbaar" een loze mededeling',
      );
      expect(c.source, isNotEmpty, reason: '${c.name} heeft geen herkomst');
    }
  });

  test(
    'load() merges the full CWE asset, so the count beats the floor',
    () async {
      final floor = InfoSafetyReferenceInventory.snapshot()
          .firstWhere((c) => c.name == 'Zwakheden (CWE)')
          .count;

      final loaded = (await InfoSafetyReferenceInventory.load())
          .firstWhere((c) => c.name == 'Zwakheden (CWE)')
          .count;

      // De curated bodem is een handvol; de volledige MITRE-lijst is honderden.
      expect(loaded, greaterThan(floor));
      expect(loaded, greaterThan(100));
    },
  );
}
