// Integration test for the Jitsi preflight against the pinned local testbed
// (`testbed/jitsi-meet/`, #2540). This is the acceptance check that unit
// tests cannot be: a REAL fetch of config.js through a NetGuard-pinned
// socket, a REAL anonymous XMPP session, and a REAL XEP-0030 discovery that
// must come back with `muc.meet.jitsi` — the component name only the server
// knows, not the `conference.<domain>` convention.
//
// Gated behind OCIDECK_JITSI_INTEGRATION=1; the stack must be running
// (`testbed/jitsi-meet/run.sh up`). Run:
//   OCIDECK_JITSI_INTEGRATION=1 make test-jitsi-integration
//
// The testbed is loopback-only by design, so the match goes through a
// MeetingProviderProfile carrying trustedInternal — exactly the path a
// self-hosted deployment on a LAN takes.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/meeting_provider.dart';
import 'package:ocideck/meetings/meeting_provider_profile.dart';
import 'package:ocideck/meetings/providers/jitsi/jitsi_meeting_provider.dart';

// Letterlijk loopback — NetGuard honoureert ws/http op loopback alleen voor
// letterlijke adressen ('localhost' is een naam en gaat langs DNS).
const _origin = 'http://127.0.0.1:8000';

bool get _enabled => Platform.environment['OCIDECK_JITSI_INTEGRATION'] == '1';

void main() {
  if (!_enabled) {
    test(
      'Jitsi preflight integration (skipped — set OCIDECK_JITSI_INTEGRATION=1)',
      () {},
      tags: ['integration'],
    );
    return;
  }

  test(
    'preflight against the pinned testbed discovers the real MUC component',
    () async {
      final match = MeetingLinkMatch(
        providerId: 'jitsi',
        invitation: Uri.parse('$_origin/ocideck-preflight-test'),
        viaProfile: MeetingProviderProfile(
          id: 'testbed',
          providerId: 'jitsi',
          origin: Uri.parse(_origin),
          trustedInternal: true,
        ),
      );
      final pre = await JitsiMeetingProvider()
          .preflight(match)
          .timeout(const Duration(seconds: 60));

      expect(
        pre.canJoin,
        isTrue,
        reason:
            'preflight should succeed: ${pre.failureReason} '
            '(${pre.diagnosticsDetail})',
      );
      // The discovery proof: the component came from XEP-0030, and on this
      // deployment that is `muc.meet.jitsi` — not the `conference.`
      // convention a hardcoded assumption would have produced.
      expect(pre.egressOrigins, contains('xmpp:muc.meet.jitsi'));
      expect(pre.e2ee, MeetingE2eeStatus.off);
      expect(pre.identityLabel, startsWith('ocideck-'));
    },
    timeout: const Timeout(Duration(minutes: 1)),
    tags: ['integration'],
  );
}
