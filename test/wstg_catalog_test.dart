import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/wstg_catalog.dart';

/// The bundled OWASP WSTG v4.2 catalog is the offline standard test list for a
/// `checklist` slide. It must be complete, well-formed and stable so a report
/// cites a fixed, citeable standard version.
void main() {
  final catalog = WstgCatalog.instance;

  test('pins the stable released version', () {
    expect(catalog.version, '4.2');
    expect(catalog.standardLabel, 'OWASP WSTG v4.2');
  });

  test('holds the full v4.2 checklist (97 tests)', () {
    expect(catalog.tests, hasLength(97));
  });

  test('every id is well-formed and unique', () {
    final idPattern = RegExp(r'^WSTG-[A-Z]{4}-\d{2}$');
    final seen = <String>{};
    for (final t in catalog.tests) {
      expect(idPattern.hasMatch(t.id), isTrue, reason: 'bad id ${t.id}');
      expect(t.title.trim(), isNotEmpty, reason: '${t.id} has no title');
      expect(t.category.trim(), isNotEmpty, reason: '${t.id} has no category');
      expect(seen.add(t.id), isTrue, reason: 'duplicate id ${t.id}');
    }
  });

  test('covers all twelve WSTG categories', () {
    final codes = {for (final t in catalog.tests) t.id.split('-')[1]};
    expect(codes, {
      'INFO',
      'CONF',
      'IDNT',
      'ATHN',
      'ATHZ',
      'SESS',
      'INPV',
      'ERRH',
      'CRYP',
      'BUSL',
      'CLNT',
      'APIT',
    });
  });

  test('includes well-known anchor tests verbatim', () {
    String titleOf(String id) =>
        catalog.tests.firstWhere((t) => t.id == id).title;
    expect(titleOf('WSTG-INPV-05'), 'Testing for SQL Injection');
    expect(titleOf('WSTG-ATHN-07'), 'Testing for Weak Password Policy');
    // v4.2 anchor: INPV-13 is Format String Injection (not the deprecated
    // Buffer Overflow), and APIT has the single GraphQL test.
    expect(titleOf('WSTG-INPV-13'), 'Testing for Format String Injection');
    expect(titleOf('WSTG-APIT-01'), 'Testing GraphQL');
  });
}
