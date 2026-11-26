import 'dart:convert';
import 'package:test/test.dart';
import 'package:ociserve_file_contract/ociserve_file_contract.dart';

void main() {
  test(
    'expiry text rejects invalid dates and preserves explicit UTC offsets',
    () {
      expect(
        parseShareExpiryInput('2026-12-01T18:00:00+01:00').toUtc(),
        DateTime.utc(2026, 12, 1, 17),
      );
      for (final value in [
        '2026-02-30T12:00:00',
        '2026-12-01T25:00:00',
        '2026-12-01T12:60:00',
        '2026-12-01T12:00:00+01:99',
      ]) {
        expect(() => parseShareExpiryInput(value), throwsFormatException);
      }
    },
  );

  test(
    'public links separate origin, ID and secret without serializing credentials',
    () {
      final secret = base64Url.encode(List.filled(32, 42)).replaceAll('=', '');
      final link = FileShareLink.parse(
        'https://files.example$shareLandingPath#12345678-1234-4234-8234-123456789abc.$secret',
      );
      expect(link.origin.toString(), 'https://files.example');
      expect(link.toString(), isNot(contains(secret)));
      expect(
        () => FileShareLink.parse(
          'http://files.example$shareLandingPath#${link.id}.$secret',
        ),
        throwsFormatException,
      );
    },
  );
  test('folder pages reject malformed IDs and oversized server listings', () {
    final root = {'id': 'root', 'name': '', 'kind': 'directory', 'size': 0};
    final page = CatalogPage.fromJson({
      'folder': root,
      'items': [],
      'breadcrumbs': [
        {'id': 'root', 'name': ''},
      ],
    });
    expect(page.items, isEmpty);
    expect(page.folder.directory, true);
    expect(() => fileId('../another-tenant'), throwsFormatException);
    expect(
      () => CatalogPage.fromJson({
        'folder': root,
        'items': List.filled(101, root),
      }),
      throwsFormatException,
    );
  });
  test('expiry and password rules match the server limits', () {
    final now = DateTime.utc(2026);
    validateShareExpiry(now.add(const Duration(days: 90)), now);
    expect(() => validateShareExpiry(now, now), throwsFormatException);
    validateSharePassword('éééé');
    expect(() => validateSharePassword('x' * 257), throwsFormatException);
  });
}
