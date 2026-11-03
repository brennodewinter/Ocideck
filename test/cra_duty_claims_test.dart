import 'package:flutter_test/flutter_test.dart';

import '../tool/check_conventions.dart';

/// Het meetinstrument achter de CRA-plichtregel in
/// `tool/check_conventions.dart` (`craDutyClaimsIn`, #2717).
///
/// Het positiebesluit (#532) schrijft "as described in" voor en nooit
/// "required by": een "vereist"-zin wordt elders als fabrikantenplicht
/// teruggeciteerd. De wet zelf citeren mag — zo'n zin noemt haar
/// plichtsdrager ("manufacturer") — en CHANGELOG.md is historie.
void main() {
  Map<String, List<int>> meet(Map<String, String> sources) =>
      craDutyClaimsIn(sources);

  test('een plichtzin over de eigen artefacten wordt gevonden', () {
    // De echte zin uit CHECKS.md vóór #2717.
    expect(
      meet({
        'docs/X.md':
            '- **Covers:** the Software Bill of Materials the EU Cyber '
            'Resilience Act (Reg. (EU) 2024/2847, Annex I Part II §1) '
            'requires.\n',
      })['docs/X.md'],
      [1],
    );
    expect(
      meet({
        'docs/X.md': 'the artefact required by the EU Cyber Resilience Act\n',
      })['docs/X.md'],
      [1],
    );
  });

  test('"as described in" valt buiten de regel', () {
    expect(
      meet({
        'docs/X.md':
            'the Software Bill of Materials as described in the EU Cyber '
            'Resilience Act (Reg. (EU) 2024/2847).\n',
      }),
      isEmpty,
    );
  });

  test('een citaat van de wet noemt haar plichtsdrager en mag', () {
    // De citaatalinea uit docs/SBOM.md.
    expect(
      meet({
        'docs/X.md':
            '**Annex I, Part II, §1** of the EU Cyber Resilience Act requires '
            'manufacturers of products with digital elements to:\n',
      }),
      isEmpty,
    );
  });

  test('CHANGELOG.md is historie en wordt niet herschreven', () {
    expect(
      meet({
        'CHANGELOG.md':
            'the artefact required by the **EU Cyber Resilience Act**\n',
      }),
      isEmpty,
    );
  });
}
