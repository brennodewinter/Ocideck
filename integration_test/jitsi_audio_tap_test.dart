// Integratietest: de ECHTE call-audiotap op macOS (#2527).
//
// Draait — net als jitsi_real_media_test.dart — in een echte app-engine
// met echte libwebrtc, echte ICE/DTLS/SRTP naar de JVB van het gepinde
// testbed. De tegenpartij is probe/solo.js: een echte Chrome met een
// fake-device-toon, dus de remote audiotrack decodeert écht geluid.
//
// Wat dit bewijst en niets anders kan:
//   * `startCallAudioCapture` levert remote PCM na decodering — met
//     amplitude, want de fake-device-toon is geen stilte;
//   * de lokale uitgaande track levert aparte frames met eigen track-id
//     (real mic; TCC-toestemming is nodig — geef die als de dialoog
//     verschijnt);
//   * `setMicrophone(enabled: false)` stopt de lokale levering — het
//     post-mute-contract dat een MediaRecorder-mix nooit kan geven;
//   * tijdstempels zijn monotoon per bron en de bronnen zijn
//     onderscheidbaar (role + trackId).
//
// Draaien (testbed omhoog + browser-tegenpartij in dezelfde room):
//   cd testbed/jitsi-meet && ./run.sh up && ./run.sh users
//   set -a && . testbed/jitsi-meet/.env && set +a
//   ROOM=ocideck_tap_it node testbed/jitsi-meet/probe/solo.js &
//   OCIDECK_JITSI_MEDIA_ROOM=ocideck_tap_it \
//     flutter test integration_test/jitsi_audio_tap_test.dart -d macos

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ocideck/meetings/call_audio_source.dart';
import 'package:ocideck/meetings/meeting_event.dart';
import 'package:ocideck/meetings/meeting_media_core_webrtc.dart';
import 'package:ocideck/meetings/meeting_provider.dart';
import 'package:ocideck/meetings/meeting_provider_profile.dart';
import 'package:ocideck/meetings/providers/jitsi/jitsi_meeting_provider.dart';

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

int _maxAmp(CallAudioChunk c) {
  final bd = ByteData.sublistView(c.pcm);
  var max = 0;
  for (var i = 0; i + 1 < c.pcm.lengthInBytes; i += 2) {
    final v = bd.getInt16(i, Endian.little).abs();
    if (v > max) max = v;
  }
  return max;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final room = Platform.environment['OCIDECK_JITSI_MEDIA_ROOM'];

  testWidgets('echte tap: remote + lokaal PCM, post-mute stopt lokaal', (
    tester,
  ) async {
    if (room == null || room.isEmpty) {
      fail(
        'zet OCIDECK_JITSI_MEDIA_ROOM op de room waar probe/solo.js als '
        'host zit (zie header)',
      );
    }
    final core = WebrtcMediaCore();
    expect(await core.selfTest(), isTrue, reason: 'libwebrtc ontbreekt');

    // Mic aan bij join: de lokale uitgaande tap moet echt frames leveren.
    final session = await JitsiMeetingProvider(mediaCoreFactory: () => core)
        .join(
          MeetingJoinRequest(
            link: _match(room),
            displayName: 'ocideck-tap-proef',
            startMuted: false,
            startCameraOff: true,
          ),
        );
    addTearDown(() => session.leave());
    expect(session.connectionState, MeetingConnectionState.connected);
    expect(
      session.capabilities.callAudio.wholeCall,
      isTrue,
      reason: 'macOS-adapter claimt geen whole-call tap',
    );

    final chunks = <CallAudioChunk>[];
    final sub = session.startCallAudioCapture().listen(
      chunks.add,
      onError: (Object e) =>
          // ignore: avoid_print
          print('DIAG tap-fout: $e'),
    );
    addTearDown(() => sub.cancel());

    // De browser-tegenpartij verschijnt met een audiotrack.
    try {
      await _until(
        () => session.participants.any((p) => !p.isLocal && p.audio != null),
        what: 'remote participant met audiotrack',
      );
    } catch (_) {
      // ignore: avoid_print
      print(
        'DIAG deelnemers: ${session.participants.map((p) => '${p.id}'
            ' audio=${p.audio?.id} video=${p.video?.id}').join(' | ')}\n'
        'DIAG chunks zover: ${chunks.map((c) => '${c.role.name}:${c.trackId}').join(',')}',
      );
      rethrow;
    }

    // Wacht tot remote PCM écht binnenkomt (decode-pad bewijs).
    await _until(
      () => chunks.where((c) => c.role == CallAudioRole.remote).length >= 5,
      timeout: const Duration(seconds: 30),
      what: 'remote PCM-frames',
    );
    // Lokaal mag even op zich wachten (mic-pad opent pas na ICE+track).
    await _until(
      () =>
          chunks.where((c) => c.role == CallAudioRole.localOutbound).isNotEmpty,
      timeout: const Duration(seconds: 30),
      what: 'lokale PCM-frames',
    );

    // De remote fake-device-toon decodeert als échte amplitude.
    final remoteChunks = chunks
        .where((c) => c.role == CallAudioRole.remote)
        .toList();
    final remoteMax = remoteChunks
        .map(_maxAmp)
        .fold<int>(0, (a, b) => a > b ? a : b);
    expect(remoteMax, greaterThan(0), reason: 'remote PCM is stilte');

    // Per-bron scheiding: rollen en track-ids verschillen.
    final localChunks = chunks
        .where((c) => c.role == CallAudioRole.localOutbound)
        .toList();
    expect(localChunks.first.trackId, isNot(remoteChunks.first.trackId));

    // Participant-stempeling: remote chunks dragen een roster-id, geen
    // track-id — de eigenaar komt uit de signalering.
    final remoteIds = session.participants
        .where((p) => !p.isLocal)
        .map((p) => p.id)
        .toSet();
    expect(remoteChunks.first.participantId, isIn(remoteIds));

    // Monotonie per bron.
    for (final role in [CallAudioRole.remote, CallAudioRole.localOutbound]) {
      final ts = chunks.where((c) => c.role == role).map((c) => c.at).toList();
      for (var i = 1; i < ts.length; i++) {
        expect(
          ts[i].isAfter(ts[i - 1]),
          isTrue,
          reason: 'niet-monotone timestamp in $role',
        );
      }
    }

    // Post-mute-contract: mic uit → geen lokale frames meer in de tap.
    await session.setMicrophone(enabled: false);
    await tester.pump(const Duration(seconds: 2));
    final localBeforeMute = localChunks.length;
    final mutedChunks = <CallAudioChunk>[];
    final mutedSub = session.startCallAudioCapture().listen(mutedChunks.add);
    await tester.pump(const Duration(seconds: 5));
    await mutedSub.cancel();
    // De tweede capture-stroom is een nieuwe tap — `localChunks` kan nog
    // groeien via de oude sub; daarom kijken we naar de verse stroom.
    expect(
      mutedChunks.where((c) => c.role == CallAudioRole.localOutbound),
      isEmpty,
      reason: 'lokale frames na mute — post-mute-contract gebroken',
    );
    // Remote blijft wél lopen — de tap zelf is niet dood.
    expect(
      mutedChunks.where((c) => c.role == CallAudioRole.remote),
      isNotEmpty,
      reason: 'remote tap stopte mee met mute',
    );
    expect(localBeforeMute, greaterThan(0));

    // Mic weer aan → lokale frames hervatten.
    await session.setMicrophone(enabled: true);
    final resumeChunks = <CallAudioChunk>[];
    final resumeSub = session.startCallAudioCapture().listen(resumeChunks.add);
    await tester.pump(const Duration(seconds: 4));
    await resumeSub.cancel();
    expect(
      resumeChunks.where((c) => c.role == CallAudioRole.localOutbound),
      isNotEmpty,
      reason: 'lokale tap hervatte niet na unmute',
    );

    // ignore: avoid_print
    print(
      'TAP-PROEF macOS: remote=${remoteChunks.length} '
      'local=$localBeforeMute remoteMaxAmp=$remoteMax '
      'mutedLocal=0 unmuteLocal='
      '${resumeChunks.where((c) => c.role == CallAudioRole.localOutbound).length}',
    );
  });
}
