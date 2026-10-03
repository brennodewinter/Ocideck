// The public age test vectors (C2SP CCTV, pinned: test/fixtures/age_testkit/PROVENANCE.md)
// run through `openAge`, the age layer of form_seal.dart (FORM_INTAKE.md §5.6, §17).
//
// The corpus README lets an implementation skip what it does not implement. This engine
// reads the binary format with native X25519 recipients only, so passphrase, armor, hybrid
// and tag vectors that must *succeed* are skipped — and counted, so the gate cannot go quiet
// by skipping more. What is never skipped is the other half: **a vector that must fail must
// not open**, whatever kind it is.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:test/test.dart';

const String _pinned = '1e3d2860d46e94e777e1b17c7a6f2436387e3ecc';

class _Vector {
  _Vector(this.name, this.headers, this.file);

  final String name;
  final Map<String, String> headers;
  final Uint8List file;

  String get expect => headers['expect'] ?? '';
  bool get armored => headers['armored'] == 'yes';
  bool get passphrase => headers.containsKey('passphrase');
  String? get identity => headers['identity'];

  /// A vector this engine can open: binary, an X25519 identity of the native kind.
  bool get native =>
      !armored &&
      !passphrase &&
      identity != null &&
      identity!.startsWith('AGE-SECRET-KEY-1');
}

_Vector _load(File source) {
  final bytes = source.readAsBytesSync();
  var separator = -1;
  for (var i = 0; i + 1 < bytes.length; i++) {
    if (bytes[i] == 0x0a && bytes[i + 1] == 0x0a) {
      separator = i;
      break;
    }
  }
  if (separator == -1) throw StateError('no header separator: ${source.path}');
  final headers = <String, String>{};
  for (final line in latin1.decode(bytes.sublist(0, separator)).split('\n')) {
    final colon = line.indexOf(': ');
    headers[line.substring(0, colon)] = line.substring(colon + 2);
  }
  var file = Uint8List.sublistView(bytes, separator + 2);
  if (headers['compressed'] == 'zlib') {
    file = Uint8List.fromList(zlib.decode(file));
  } else if (headers.containsKey('compressed')) {
    throw StateError('unknown compression: ${source.path}');
  }
  return _Vector(source.uri.pathSegments.last, headers, file);
}

/// What each failure kind of the corpus must come out as. A vector with a passphrase or a
/// non-native identity is not compared on kind — this engine cannot reach the place where
/// that kind of failure happens — only on being refused.
const Map<String, FormUnsealIssue> _kinds = {
  'no match': FormUnsealIssue.noIdentityMatched,
  'HMAC failure': FormUnsealIssue.tampered,
  'payload failure': FormUnsealIssue.tampered,
  'header failure': FormUnsealIssue.notAge,
  'armor failure': FormUnsealIssue.notAge,
};

/// Where this engine fails closed with another word than the corpus. Each is a vector the
/// corpus calls a *header failure* and this engine reports as `tampered`: the X25519 share
/// is the identity point (the shared secret would be the disallowed all-zero value, which
/// the library refuses where it unwraps), or the file ends inside the payload nonce. The
/// corpus README allows aliasing kinds an API does not tell apart; nothing here opens.
const Map<String, FormUnsealIssue> _aliased = {
  'x25519_identity': FormUnsealIssue.tampered,
  'x25519_low_order': FormUnsealIssue.tampered,
  'stream_no_nonce': FormUnsealIssue.tampered,
  'stream_short_nonce': FormUnsealIssue.tampered,
};

/// The files of the directory that are not vectors.
const Set<String> _notVectors = {'PROVENANCE.md', 'SHA256SUMS'};

void main() {
  final directory = Directory('test/fixtures/age_testkit');
  final vectors =
      directory
          .listSync()
          .whereType<File>()
          .where((f) => !_notVectors.contains(f.uri.pathSegments.last))
          .map(_load)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  test('every vector is byte for byte what the project published', () {
    // SHA256SUMS was made from the upstream checkout at the pinned commit. A vector that
    // git (a line-ending rule), an editor or a refresh changed would still "pass" below
    // while testing a file nobody published.
    final sums = {
      for (final line in File(
        '${directory.path}/SHA256SUMS',
      ).readAsLinesSync().where((l) => l.trim().isNotEmpty))
        line.substring(66): line.substring(0, 64),
    };
    expect(sums, hasLength(143));
    final here = directory.listSync().whereType<File>().where(
      (f) => !_notVectors.contains(f.uri.pathSegments.last),
    );
    expect(here.map((f) => f.uri.pathSegments.last).toSet(), sums.keys.toSet());
    for (final file in here) {
      final name = file.uri.pathSegments.last;
      expect(
        crypto.sha256.convert(file.readAsBytesSync()).toString(),
        sums[name],
        reason: name,
      );
    }
  });

  test('the whole corpus at the pinned commit is here', () {
    expect(_pinned, hasLength(40));
    expect(
      File('${directory.path}/PROVENANCE.md').readAsStringSync(),
      contains(_pinned),
    );
    expect(vectors, hasLength(143));
    expect(
      vectors.map((v) => v.name),
      containsAll(['x25519', 'stream_two_chunks']),
    );
  });

  test('every alias names a vector that exists', () {
    expect(
      _aliased.keys.toSet().difference(vectors.map((v) => v.name).toSet()),
      isEmpty,
    );
  });

  test('the kinds of expectation are the ones this test knows', () {
    final kinds = vectors.map((v) => v.expect).toSet();
    expect(kinds, {'success', ..._kinds.keys});
  });

  group('a vector that must fail does not open', () {
    for (final v in vectors.where((v) => v.expect != 'success')) {
      test('${v.name} (${v.expect})', () async {
        final identity = v.identity != null && v.native
            ? v.identity!
            : generateAgeIdentity();
        final result = await openAge(v.file, [identity]);
        expect(result, isA<FormAgeRefused>());
        if (v.native || v.identity == null && !v.passphrase) {
          expect(
            (result as FormAgeRefused).issue,
            _aliased[v.name] ?? _kinds[v.expect],
          );
        }
      });
    }
  });

  group('a vector that must succeed opens, with the payload it names', () {
    for (final v in vectors.where((v) => v.expect == 'success' && v.native)) {
      test(v.name, () async {
        final result = await openAge(v.file, [v.identity!]);
        expect(result, isA<FormAgeOpened>());
        final digest = crypto.sha256.convert(
          (result as FormAgeOpened).plaintext,
        );
        expect(digest.toString(), v.headers['payload']);
      });
    }
  });

  test('how much was skipped, so it cannot grow unseen', () {
    final success = vectors.where((v) => v.expect == 'success').toList();
    final skipped = success.where((v) => !v.native).toList();
    // Everything skipped is a feature this engine deliberately does not have.
    for (final v in skipped) {
      expect(
        v.armored ||
            v.passphrase ||
            !(v.identity ?? '').startsWith('AGE-SECRET-KEY-1'),
        isTrue,
        reason: v.name,
      );
    }
    // The counts at the pinned commit. A change here is a change of coverage; say so in
    // the commit that makes it.
    expect(success.length - skipped.length, 14, reason: 'opened');
    expect(
      skipped.length,
      12,
      reason: 'skipped: armor, passphrase, hybrid, tag',
    );
    expect(vectors.length - success.length, 117, reason: 'must fail');
  });
}
