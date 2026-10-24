// Contract tests for MeetingProviderProfile + MeetingProfilesStore (#2533):
// exact-origin semantics (scheme, host, effective port, optional path
// prefixes), JSON round-trip, refuse-on-malformed, and the prefs store.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/meeting_provider_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

MeetingProviderProfile _p(String origin, {Set<String> prefixes = const {}}) =>
    MeetingProviderProfile(
      id: 'x',
      providerId: 'jitsi',
      origin: Uri.parse(origin),
      allowedJoinPathPrefixes: prefixes,
    );

void main() {
  group('allows', () {
    test('matches its own origin with a non-root path', () {
      expect(
        _p('https://meet.example').allows(Uri.parse('https://meet.example/r')),
        isTrue,
      );
    });

    test('rejects root path, other scheme, other host, other port', () {
      final p = _p('https://meet.example:8443');
      expect(p.allows(Uri.parse('https://meet.example:8443/')), isFalse);
      expect(p.allows(Uri.parse('http://meet.example:8443/r')), isFalse);
      expect(p.allows(Uri.parse('https://other.example:8443/r')), isFalse);
      expect(p.allows(Uri.parse('https://meet.example/r')), isFalse);
    });

    test('implicit default port equals the written one', () {
      expect(
        _p(
          'https://meet.example',
        ).allows(Uri.parse('https://meet.example:443/r')),
        isTrue,
      );
    });

    test('prefixes bind segment-safe', () {
      final p = _p('https://corp.example', prefixes: {'/meet/'});
      expect(p.allows(Uri.parse('https://corp.example/meet/a')), isTrue);
      expect(p.allows(Uri.parse('https://corp.example/meeting/b')), isFalse);
      expect(p.allows(Uri.parse('https://corp.example/x/meet/a')), isFalse);
    });
  });

  group('json', () {
    test('round-trips all fields', () {
      final p = MeetingProviderProfile(
        id: 'abc',
        providerId: 'jitsi',
        origin: Uri.parse('https://meet.example:8443'),
        allowedJoinPathPrefixes: {'/meet/'},
        trustedInternal: true,
        pinnedCertSha256: 'a' * 64,
      );
      final back = MeetingProviderProfile.fromJson(p.toJson());
      expect(back, p);
    });

    test('refuses malformed trust decisions', () {
      for (final json in <Map<String, Object?>>[
        {'id': '', 'providerId': 'jitsi', 'origin': 'https://x'},
        {'id': 'x', 'providerId': 'jitsi', 'origin': 'ftp://x'},
        {'id': 'x', 'providerId': 'jitsi', 'origin': 'https://x/path'},
        {'id': 'x', 'providerId': 'jitsi', 'origin': 'https://x?q=1'},
        {
          'id': 'x',
          'providerId': 'jitsi',
          'origin': 'https://x',
          'pinnedCertSha256': 'nothex',
        },
      ]) {
        expect(MeetingProviderProfile.fromJson(json), isNull, reason: '$json');
      }
    });
  });

  group('store', () {
    test('saves and loads via prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = MeetingProfilesStore(prefs: prefs);
      expect(await store.load(), isEmpty);
      await store.save([_p('https://meet.example')]);
      final loaded = await store.load();
      expect(loaded.single.origin, Uri.parse('https://meet.example'));
    });

    test('a corrupted value reads as empty, not a crash', () async {
      SharedPreferences.setMockInitialValues({
        'meetingProviderProfiles': '{broken',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(await MeetingProfilesStore(prefs: prefs).load(), isEmpty);
    });
  });
}
