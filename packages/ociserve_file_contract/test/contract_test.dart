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
  test('public capability round-trips preserve the explicit HTTPS origin', () {
    const id = '12345678-1234-4234-8234-123456789abc';
    final secret = base64Url
        .encode(List.generate(32, (i) => i))
        .replaceAll('=', '');
    final uri = Uri.https(
      'files.example:8443',
      shareLandingPath,
    ).replace(fragment: '$id.$secret');
    final link = FileShareLink.parse(uri.toString());
    expect(link.browserUri, uri);
    expect(FileShareLink.resembles(uri), isTrue);
    expect(
      FileShareLink.resembles(Uri.https('files.example', '/ordinary.md')),
      isFalse,
    );
    for (final invalid in [
      uri.replace(query: 'password=canary'),
      uri.replace(userInfo: 'canary-userinfo'),
      uri.replace(path: '/ordinary.md'),
      uri.replace(fragment: '$id.${secret.substring(0, 42)}B'),
      uri.replace(fragment: 'root.$secret'),
    ]) {
      expect(
        () => FileShareLink.parse(invalid.toString()),
        throwsFormatException,
      );
    }
    expect(() => fileId('root'), throwsFormatException);
    expect(fileId('root', root: true), 'root');
  });

  test(
    'public folder pages retain supported files, immutable metadata and cursors',
    () {
      const id = '12345678-1234-4234-8234-123456789abc';
      final page = CatalogPage.fromJson({
        'node': {'id': id, 'name': 'Snapshot', 'kind': 'directory', 'size': 0},
        'items': [
          {
            'id': id,
            'name': 'DECK.MD',
            'kind': 'file',
            'size': 12,
            'content_type': 'text/markdown',
            'etag': 'pinned-version',
          },
        ],
        'next_cursor': 'opaque-next-page',
      }, public: true);
      expect(page.breadcrumbs, isEmpty);
      expect(page.nextCursor, 'opaque-next-page');
      expect(page.folder.supported, isFalse);
      final file = page.items.single;
      expect(file.supported, isTrue);
      expect(file.contentType, 'text/markdown');
      expect(file.etag, 'pinned-version');
      expect(file.size, 12);
      expect(
        const CatalogEntry(
          id: id,
          name: 'deck.ocideck',
          directory: false,
        ).supported,
        isTrue,
      );
      expect(
        const CatalogEntry(
          id: id,
          name: 'notes.pdf',
          directory: false,
        ).supported,
        isFalse,
      );
      for (final invalid in [
        {'id': id, 'name': 'bad', 'kind': 'symlink', 'size': 0},
        {'id': id, 'name': 'bad', 'kind': 'file', 'size': -1},
        {'id': id, 'name': 'bad', 'kind': 'file', 'size': '12'},
      ]) {
        expect(() => CatalogEntry.fromJson(invalid), throwsFormatException);
      }
    },
  );

  test(
    'managed shares preserve UTC expiry, snapshot identity and one-time link redaction',
    () {
      const id = '12345678-1234-4234-8234-123456789abc';
      const root = '22345678-1234-4234-8234-123456789abc';
      const oneTime = 'one-time-link-canary';
      final data = <String, Object?>{
        'id': id,
        'root_id': root,
        'expires_at': '2026-12-01T18:00:00+01:00',
        'status': 'active',
        'password_protected': true,
        'revision': 3,
        'link': oneTime,
        'target_name': 'Course',
        'target_kind': 'directory',
        'snapshot_items': 2,
        'snapshot_bytes': 12,
      };
      final share = ManagedFileShare.fromJson(data);
      expect(share.id, id);
      expect(share.rootId, root);
      expect(share.expiresAt, DateTime.utc(2026, 12, 1, 17));
      expect(share.passwordProtected, isTrue);
      expect(share.etag, '"3"');
      expect(share.link, oneTime);
      expect(share.toString(), isNot(contains(oneTime)));
      expect(share.targetName, 'Course');
      expect(share.targetKind, 'directory');
      expect(share.snapshotItems, 2);
      expect(share.snapshotBytes, 12);
      final legacy = <String, Object?>{
        'id': id,
        'root_id': root,
        'expires_at': '2026-12-01T17:00:00Z',
        'status': 'revoked',
        'password_protected': false,
        'revision': 4,
      };
      final page = ManagedSharePage.fromJson({
        'items': [legacy],
        'next_cursor': 'next',
      });
      expect(page.nextCursor, 'next');
      final listed = page.items.single;
      expect(listed.status, 'revoked');
      expect(listed.link, isNull);
      expect(listed.targetName, isEmpty);
      expect(listed.targetKind, isEmpty);
      expect(listed.snapshotItems, 0);
      expect(listed.snapshotBytes, 0);
      expect(listed.passwordProtected, isFalse);
      expect(listed.etag, '"4"');
      expect(
        () => ManagedFileShare.fromJson({...legacy, 'root_id': 'root'}),
        throwsFormatException,
      );
    },
  );

  test(
    'expiry and password boundaries retain defaults and byte-based limits',
    () {
      final now = DateTime.utc(2026, 11, 26);
      validateShareExpiry(null, now);
      expect(
        () => validateShareExpiry(
          now.add(const Duration(days: 90, microseconds: 1)),
          now,
        ),
        throwsFormatException,
      );
      validateSharePassword('');
      validateSharePassword('é' * 128);
      expect(() => validateSharePassword('short'), throwsFormatException);
      expect(() => validateSharePassword('é' * 129), throwsFormatException);
      expect(
        parseShareExpiryInput('2026-12-01T18:00:00Z'),
        DateTime.utc(2026, 12, 1, 18),
      );
      expect(
        parseShareExpiryInput('2026-12-01T18:00:00.123456'),
        DateTime(2026, 12, 1, 18, 0, 0, 123, 456),
      );
      expect(
        () => parseShareExpiryInput('01/12/2026 18:00'),
        throwsFormatException,
      );
      expect(
        () => parseShareExpiryInput('2026-12-01T18:00:00+24:00'),
        throwsFormatException,
      );
    },
  );
}
