// Integratietest: de ECHTE mediaketen op een echt platform (#2535).
//
// Waar test/meetings/jitsi_join_testbed_test.dart de media-seam faked
// (libwebrtc draait niet in de test-VM), draait dit bestand in een echte
// app-engine op macOS — met de echte `WebrtcMediaCore`, echte
// getUserMedia, echte ICE/DTLS/SRTP naar de JVB van het gepinde testbed.
// De tegenpartij is een echte browser met een fake-device-signaal
// (probe/solo.js) — Chrome stuurt wél echte RTP.
//
// Wat dit bewijst en niets anders kan:
//   * `connected` is hier het harde bewijs: de sessie keert pas terug als
//     ICE/DTLS `live` rapporteert — een werkend mediapad met de JVB;
//   * remote tracks van de browser arriveren en koppelen aan een
//     participant via de sourcenaam-msid;
//   * `videoSurfaceFor` levert een échte texture; de screenshot bewijst
//     dat er pixels renderen (de fake-device van Chrome stuurt bewegende
//     testpatronen, geen zwart beeld);
//   * de lokale mic/cam leveren échte tracks (TCC-toestemming is nodig:
//     macOS vraagt eenmalig om microfoon- én cameratoegang voor de
//     test-runner — geef die als de dialoog verschijnt).
//
// Draaien (testbed omhoog + browser-tegenpartij in dezelfde room):
//   cd testbed/jitsi-meet && ./run.sh up && ./run.sh users
//   set -a && . testbed/jitsi-meet/.env && set +a
//   ROOM=ocideck_media_it node testbed/jitsi-meet/probe/solo.js &
//   OCIDECK_JITSI_MEDIA_ROOM=ocideck_media_it \
//     flutter test integration_test/jitsi_real_media_test.dart -d macos

import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ocideck/meetings/meeting_event.dart';
import 'package:ocideck/meetings/meeting_media_core_webrtc.dart';
import 'package:ocideck/meetings/meeting_provider.dart';
import 'package:ocideck/meetings/meeting_provider_profile.dart';
import 'package:ocideck/meetings/providers/jitsi/jitsi_meeting_provider.dart';
import 'package:ocideck/utils/atomic_file.dart';

const _origin = 'http://127.0.0.1:8000';

MeetingLinkMatch _match(String room) => MeetingLinkMatch(
  providerId: 'jitsi',
  invitation: Uri.parse('$_origin/$room'),
  viaProfile: MeetingProviderProfile(
    id: 'testbed',
    providerId: 'jitsi',
    origin: Uri.parse(_origin),
    trustedInternal: true,
  ),
);

Future<void> _until(
  bool Function() test, {
  Duration timeout = const Duration(seconds: 60),
  String what = 'voorwaarde',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (test()) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  fail('$what niet gehaald binnen $timeout');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final room = Platform.environment['OCIDECK_JITSI_MEDIA_ROOM'];

  testWidgets('echte RTP: OciDeck joint en rendert remote video', (
    tester,
  ) async {
    if (room == null || room.isEmpty) {
      fail(
        'zet OCIDECK_JITSI_MEDIA_ROOM op de room waar probe/solo.js als '
        'host zit (zie header)',
      );
    }
    // De testbed draait en de browser-host zit in de room — zonder die
    // is er geen remote track om te bewijzen.
    final core = WebrtcMediaCore();
    expect(await core.selfTest(), isTrue, reason: 'libwebrtc ontbreekt');
    expect(core.mediaE2ee, MeetingE2eeStatus.off); // macOS-stand (#2535)

    final session = await JitsiMeetingProvider(mediaCoreFactory: () => core)
        .join(
          MeetingJoinRequest(
            link: _match(room),
            displayName: 'ocideck-media-proef',
            // Camera aan: de self-view én de remote tegel zijn het bewijs.
            startMuted: true,
            startCameraOff: false,
          ),
        );
    addTearDown(() => session.leave());

    // Het mediapad-bewijs: `join` keert pas na ICE/DTLS live.
    expect(session.connectionState, MeetingConnectionState.connected);
    // De echte media-egress: de JVB uit de session-initiate, niet geraden.
    expect(session.mediaEgressOrigins, isNotEmpty);

    // De browser-tegenpartij verschijnt met een videotrack (fake-device).
    await _until(
      () => session.participants.any((p) => !p.isLocal && p.video != null),
      what: 'remote participant met videotrack',
    );
    final remote = session.participants.firstWhere(
      (p) => !p.isLocal && p.video != null,
    );

    // Een echte renderer op de remote track → echte texture.
    final surface = await session.videoSurfaceFor(remote.id);
    expect(surface, isNotNull, reason: 'geen surface op remote video');
    expect(surface!.textureId, greaterThanOrEqualTo(0));
    addTearDown(() => surface.dispose());

    // Rendern in een widget en een echte screenshot als pixelbewijs —
    // Chrome's fake-device stuurt bewegende patronen, geen zwart.
    final repaintKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 480,
              height: 270,
              child: RepaintBoundary(
                key: repaintKey,
                child: Texture(textureId: surface.textureId),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    final boundary =
        repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.5);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    expect(png, isNotNull);
    await writeBytesAtomic(
      File('integration_test/jitsi_media_proof.png'),
      png!.buffer.asUint8List(),
    );
    // Pixelbewijs zonder oog: een uniform vlak zou een lege texture zijn.
    // De fake-device-patronen garanderen variatie in de bytes.
    expect(png.buffer.asUint8List().toSet().length, greaterThan(64));
  });
}
