// Contract tests for MeetingLinkResolver (#2533) — the "no probing" rules
// from COLLABORATION.md §7.1.6 in executable form:
//   * trusted hosts recognise suffix-safe; look-alike hosts do not;
//   * a user-approved profile claims only its exact origin (+ prefixes);
//   * fragments (#config.* overrides), credential params and trackers are
//     stripped BEFORE the link reaches an adapter;
//   * unknown https links are "unrecognized + hint" — never auto-decided.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/meeting_link_resolver.dart';
import 'package:ocideck/meetings/meeting_provider_profile.dart';
import 'package:ocideck/meetings/providers/jitsi/jitsi_meeting_provider.dart';

MeetingProviderProfile _profile(
  String origin, {
  Set<String> prefixes = const {},
  bool trustedInternal = false,
  String providerId = 'jitsi',
}) => MeetingProviderProfile(
  id: 'p1',
  providerId: providerId,
  origin: Uri.parse(origin),
  allowedJoinPathPrefixes: prefixes,
  trustedInternal: trustedInternal,
);

MeetingLinkResolver _resolver({
  List<MeetingProviderProfile> profiles = const [],
}) => MeetingLinkResolver(
  providers: [JitsiMeetingProvider()],
  profiles: profiles,
);

void main() {
  group('recognition', () {
    test('meet.jit.si link is recognised as jitsi', () {
      final r = _resolver().resolve('https://meet.jit.si/SprintReview');
      expect(r.verdict, MeetingLinkVerdict.recognized);
      expect(r.match!.providerId, 'jitsi');
      expect(r.match!.invitation.path, '/SprintReview');
      expect(r.viaProfile, isNull);
    });

    test('schemaless input assumes https', () {
      final r = _resolver().resolve('meet.jit.si/room');
      expect(r.verdict, MeetingLinkVerdict.recognized);
      expect(r.match!.invitation.scheme, 'https');
    });

    test('subdomain of the trusted host is trusted (beta.meet.jit.si)', () {
      final r = _resolver().resolve('https://beta.meet.jit.si/room');
      expect(r.verdict, MeetingLinkVerdict.recognized);
    });

    test('root path is not a meeting', () {
      final r = _resolver().resolve('https://meet.jit.si/');
      expect(r.verdict, MeetingLinkVerdict.unrecognized);
    });

    test('look-alike hosts are not recognised', () {
      for (final host in [
        'xmeet.jit.si',
        'meet.jit.si.evil.example',
        'meetjit.si',
      ]) {
        final r = _resolver().resolve('https://$host/room');
        expect(r.verdict, MeetingLinkVerdict.unrecognized, reason: host);
      }
    });
  });

  group('normalisation', () {
    test('fragments are stripped — #config.* may not set join defaults', () {
      final r = _resolver().resolve(
        'https://meet.jit.si/room#config.startWithAudioMuted=false'
        '&config.prejoinConfig.enabled=false',
      );
      expect(r.verdict, MeetingLinkVerdict.recognized);
      expect(r.match!.invitation.hasFragment, isFalse);
    });

    test('jwt and tracking params are stripped, other params kept', () {
      final r = _resolver().resolve(
        'https://meet.jit.si/room?jwt=SECRET&utm_source=news&keep=1',
      );
      expect(r.verdict, MeetingLinkVerdict.recognized);
      expect(r.carriedCredential, isTrue);
      expect(r.match!.invitation.queryParameters.containsKey('jwt'), isFalse);
      expect(
        r.match!.invitation.queryParameters.containsKey('utm_source'),
        isFalse,
      );
      expect(r.match!.invitation.queryParameters['keep'], '1');
    });

    test('embedded credentials refuse the link outright', () {
      final r = _resolver().resolve('https://user:pass@meet.jit.si/room');
      expect(r.verdict, MeetingLinkVerdict.invalid);
      expect(r.invalidReason, MeetingLinkInvalidReason.containsCredentials);
    });

    test('non-http schemes are refused', () {
      for (final link in [
        'javascript:alert(1)',
        'file:///etc/passwd',
        'intent://meet.jit.si/room',
      ]) {
        expect(
          _resolver().resolve(link).verdict,
          MeetingLinkVerdict.invalid,
          reason: link,
        );
      }
    });

    test('unparseable input is invalid, not a crash', () {
      expect(_resolver().resolve('   ').verdict, MeetingLinkVerdict.invalid);
      expect(_resolver().resolve(':::').verdict, MeetingLinkVerdict.invalid);
    });

    test('trailing slashes and host case are normalised', () {
      final r = _resolver().resolve('https://MEET.Jit.SI/Room///');
      expect(r.match!.invitation.host, 'meet.jit.si');
      expect(r.match!.invitation.path, '/Room');
    });
  });

  group('unrecognised + hint', () {
    test('a plausible meeting URL is unrecognized with the hint set', () {
      final r = _resolver().resolve('https://video.example.org/standup');
      expect(r.verdict, MeetingLinkVerdict.unrecognized);
      expect(r.looksLikeMeeting, isTrue);
      expect(r.normalized!.host, 'video.example.org');
    });

    test('a root URL carries no meeting hint', () {
      final r = _resolver().resolve('https://example.org/');
      expect(r.verdict, MeetingLinkVerdict.unrecognized);
      expect(r.looksLikeMeeting, isFalse);
    });
  });

  group('profiles', () {
    test('approved origin matches, via the profile', () {
      final r = _resolver(
        profiles: [_profile('https://meet.internal.example')],
      ).resolve('https://meet.internal.example/teamroom');
      expect(r.verdict, MeetingLinkVerdict.recognized);
      expect(r.viaProfile, isNotNull);
      expect(r.match!.viaProfile!.trustedInternal, isFalse);
    });

    test('a profile never claims subdomains or sibling ports', () {
      final profiles = [_profile('https://meet.internal.example:8443')];
      for (final link in [
        'https://sub.meet.internal.example:8443/room',
        'https://meet.internal.example/room', // poort 443 ≠ 8443
      ]) {
        expect(
          _resolver(profiles: profiles).resolve(link).verdict,
          MeetingLinkVerdict.unrecognized,
          reason: link,
        );
      }
      expect(
        _resolver(
          profiles: profiles,
        ).resolve('https://meet.internal.example:8443/room').verdict,
        MeetingLinkVerdict.recognized,
      );
    });

    test('path prefixes bound what the profile claims', () {
      final profiles = [
        _profile('https://corp.example', prefixes: {'/meet/'}),
      ];
      expect(
        _resolver(
          profiles: profiles,
        ).resolve('https://corp.example/meet/standup').verdict,
        MeetingLinkVerdict.recognized,
      );
      for (final link in [
        'https://corp.example/other/standup',
        'https://corp.example/meeting/x', // '/meet' claimt niet '/meeting'
      ]) {
        expect(
          _resolver(profiles: profiles).resolve(link).verdict,
          MeetingLinkVerdict.unrecognized,
          reason: link,
        );
      }
    });

    test('a profile for an unregistered provider matches nothing', () {
      final r = _resolver(
        profiles: [_profile('https://x.example', providerId: 'matrixrtc')],
      ).resolve('https://x.example/room');
      expect(r.verdict, MeetingLinkVerdict.unrecognized);
    });
  });
}
