import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_toolchain.dart' show parsePin;
import '../tool/check_upstream_workarounds.dart';

Map<String, dynamic> fixture({String state = 'open'}) => {
  'schema_version': 1,
  'workarounds': [
    {
      'id': 'example',
      'issue': 3219,
      'observed_flutter': '3.47.2',
      'reviewed_flutter': '3.50.0',
      'reviewed_at': '2026-11-26',
      'upstream': [
        {'number': 191775, 'state': state},
      ],
      'pins': ['tool/check_linux_impeller.dart'],
      'verification': 'Run the native reproduction without the workaround.',
      'decision': 'Keep until the stable SDK contains the fix.',
    },
  ],
};

void main() {
  test(
    'recorded closure requests verification even without a network',
    () async {
      final messages = <String>[];
      final valid = await reviewWorkarounds(
        parseWorkarounds(jsonEncode(fixture(state: 'closed'))),
        '3.50.0',
        report: messages.add,
      );
      expect(valid, isTrue);
      expect(messages.single, contains('UPSTREAM CLOSED example'));
      expect(messages.single, contains('recorded; live status unavailable'));
      expect(
        messages.single,
        contains('Verify before removal: Run the native'),
      );
      expect(messages.single, contains('Keep until the stable SDK'));
    },
  );

  test('live closure since review is explicitly reported', () async {
    final messages = <String>[];
    await reviewWorkarounds(
      parseWorkarounds(jsonEncode(fixture())),
      '3.50.0',
      fetchState: (_) async => 'closed',
      report: messages.add,
    );
    expect(messages.single, contains('closed since recorded review'));
    expect(messages.single, contains('https://github.com/flutter/flutter/'));
  });

  test('open/reopened issues do not masquerade as a closure', () async {
    for (final state in ['open', 'closed']) {
      final messages = <String>[];
      await reviewWorkarounds(
        parseWorkarounds(jsonEncode(fixture(state: state))),
        '3.50.0',
        fetchState: (_) async => 'open',
        report: messages.add,
      );
      expect(messages, isEmpty);
    }
  });

  test('unknown live state preserves the known closure warning', () async {
    for (final error in [
      TimeoutException('deadline'),
      const HttpException('GitHub HTTP 403'),
      const FormatException('bad JSON'),
    ]) {
      final messages = <String>[];
      final valid = await reviewWorkarounds(
        parseWorkarounds(jsonEncode(fixture(state: 'closed'))),
        '3.50.0',
        fetchState: (_) async => throw error,
        report: messages.add,
      );
      expect(valid, isTrue);
      expect(messages.first, startsWith('UPSTREAM UNKNOWN #191775'));
      expect(messages.last, startsWith('UPSTREAM CLOSED'));
    }
  });

  test('a malformed live state is unknown, never silently open', () async {
    final messages = <String>[];
    await reviewWorkarounds(
      parseWorkarounds(jsonEncode(fixture(state: 'closed'))),
      '3.50.0',
      fetchState: (_) async => 'invalid',
      report: messages.add,
    );
    expect(messages.first, contains('UPSTREAM UNKNOWN'));
    expect(messages.last, contains('UPSTREAM CLOSED'));
  });

  test(
    'a Flutter bump requires a new review even when issues stay open',
    () async {
      final messages = <String>[];
      final valid = await reviewWorkarounds(
        parseWorkarounds(jsonEncode(fixture())),
        '3.50.1',
        report: messages.add,
      );
      expect(valid, isFalse);
      expect(messages.single, contains('UPSTREAM REVIEW REQUIRED example'));
      expect(messages.single, contains('3.50.0, pin is 3.50.1'));
      expect(messages.single, contains('native reproduction'));
    },
  );

  test('invalid or incomplete register cannot produce a green review', () {
    for (final value in [
      '{}',
      '[]',
      '{"schema_version": 1, "workarounds": []}',
      '{"schema_version": 1, "workarounds": [null]}',
      jsonEncode(fixture(state: 'unknown')),
    ]) {
      expect(() => parseWorkarounds(value), throwsFormatException);
    }
    for (final field in [
      'id',
      'issue',
      'observed_flutter',
      'reviewed_flutter',
      'reviewed_at',
      'upstream',
      'pins',
      'verification',
      'decision',
    ]) {
      final data = fixture();
      (data['workarounds'] as List).first.remove(field);
      expect(
        () => parseWorkarounds(jsonEncode(data)),
        throwsFormatException,
        reason: field,
      );
    }
    final data = fixture();
    (data['workarounds'] as List).add((data['workarounds'] as List).first);
    expect(() => parseWorkarounds(jsonEncode(data)), throwsFormatException);
  });

  test('register accounts for all four workarounds and current pin', () {
    final rows = parseWorkarounds(File(workaroundRegister).readAsStringSync());
    expect(rows.map((w) => w.id).toSet(), {
      'linux-impeller',
      'linux-wayland-scale',
      'macos-impeller',
      'macos-semantics',
    });
    final pin = parsePin(File('.tool-versions').readAsStringSync());
    for (final w in rows) {
      expect(w.reviewedFlutter, pin, reason: w.id);
      for (final p in w.pins) {
        expect(File(p).existsSync(), isTrue, reason: '${w.id}: $p');
      }
    }
    expect(rows.expand((w) => w.upstream).map((i) => i.number).toSet(), {
      191775,
      196476,
      185394,
      196872,
      193372,
    });
  });
}
