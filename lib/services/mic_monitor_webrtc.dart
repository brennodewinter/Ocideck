// De enige echte binding achter [MicMonitor] (#2158), via `flutter_webrtc`
// (libwebrtc) — al een beproefde dependency (`lib/meetings/`, ketenkeuring
// `assurance/ketenkeuring-flutter-webrtc.md`).
//
// libwebrtc kent geen "render deze lokale track naar de speakers", dus dit
// bouwt een LOKALE loopback: twee peer connections in één proces — de mic-track
// wordt door de ene verstuurd en door de andere ontvangen, en libwebrtc's audio
// device module rendert inkomende remote-audio op de standaard-uitvoer. De
// offer/answer- en ICE-uitwisseling verlaat het proces nooit: met een lege
// `iceServers` levert de gathering alleen host-kandidaten (plus libwebrtc's
// `.local`-mDNS-obfuscatie op het LAN — dezelfde begrensde houding als de
// meetings-stack documenteert). Geen TURN, geen SFU, geen signalling-kanaal.
// ponytail: de loopback meent libwebrtc's jitter buffer — een paar tientallen
// ms vertraging. Voor stemversterking prima; wie echte low-latency monitoring
// wil, stapt over op een platformchannel (AVAudioEngine/WASAPI).
//
// Dit bestand kan niet in een headless test-VM draaien (het vereist een
// apparaat) en staat daarom in `uncoveredBaseline`; elke beslissing woont in
// `mic_monitor.dart` en de presenter-part en is dáár getest. Houd dit bestand
// tot directe calls beperkt — geen logica hierheen verhuizen.

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../utils/log.dart';
import 'mic_monitor.dart';

class WebrtcMicMonitor implements MicMonitor {
  MediaStream? _mic;
  RTCPeerConnection? _sendPc;
  RTCPeerConnection? _recvPc;
  bool _running = false;

  /// Heeft een lopende [start] af: [stop] verhoogt hem, en een start die zijn
  /// opbouw afrondt terwijl hij al gestopt is, ruimt zijn eigen spullen zelf op
  /// in plaats van een doodgezweerde mic achter te laten. Kan echt voorkomen:
  /// de macOS-machtigingsprompt kan seconden open staan terwijl de presentator
  /// al op Escape drukte.
  int _generation = 0;
  bool _starting = false;

  @override
  bool get running => _running;

  @override
  Future<void> start() async {
    if (_running || _starting) return;
    _starting = true;
    final generation = _generation;
    MediaStream? mic;
    RTCPeerConnection? send;
    RTCPeerConnection? recv;
    try {
      mic = await navigator.mediaDevices.getUserMedia({
        // Echo-onderdrukking is hier geen beleefdheid maar het punt: juist de
        // gemonitorde uitvoer zou via de zaalspeakers terug de mic in lopen.
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
      });
      send = await createPeerConnection(const {'iceServers': <Object>[]});
      recv = await createPeerConnection(const {'iceServers': <Object>[]});
      // Kandidaten die vóór de remote description binnenkomen moeten wachten —
      // addCandidate zonder remote description gooit op sommige platformen.
      var remoteReady = false;
      final pendingForSend = <RTCIceCandidate>[];
      final pendingForRecv = <RTCIceCandidate>[];
      send.onIceCandidate = (c) {
        if (remoteReady) {
          recv?.addCandidate(c);
        } else {
          pendingForRecv.add(c);
        }
      };
      recv.onIceCandidate = (c) {
        if (remoteReady) {
          send?.addCandidate(c);
        } else {
          pendingForSend.add(c);
        }
      };
      for (final track in mic.getAudioTracks()) {
        await send.addTrack(track, mic);
      }
      final offer = await send.createOffer();
      await send.setLocalDescription(offer);
      await recv.setRemoteDescription(offer);
      final answer = await recv.createAnswer();
      await recv.setLocalDescription(answer);
      await send.setRemoteDescription(answer);
      remoteReady = true;
      for (final c in pendingForRecv) {
        await recv.addCandidate(c);
      }
      for (final c in pendingForSend) {
        await send.addCandidate(c);
      }
    } catch (e) {
      await _teardown(mic, send, recv);
      _starting = false;
      throw MicMonitorException(e);
    }
    _starting = false;
    if (generation != _generation) {
      // Gestopt terwijl de start liep (zie [_generation]): de spullen horen bij
      // deze start en gaan hier mee weg — niet in de velden.
      await _teardown(mic, send, recv);
      return;
    }
    _mic = mic;
    _sendPc = send;
    _recvPc = recv;
    _running = true;
  }

  @override
  Future<void> stop() async {
    _generation++;
    _running = false;
    final mic = _mic;
    final send = _sendPc;
    final recv = _recvPc;
    _mic = null;
    _sendPc = null;
    _recvPc = null;
    await _teardown(mic, send, recv);
  }

  /// Ruimt een (deels) opgebouwde loopback op. Best-effort: een track die niet
  /// wil sluiten mag de rest van de opruiming niet tegenhouden — de mic-indicator
  /// van het OS moet hoe dan ook uit.
  static Future<void> _teardown(
    MediaStream? mic,
    RTCPeerConnection? send,
    RTCPeerConnection? recv,
  ) async {
    try {
      await send?.close();
    } catch (e) {
      logWarning('WebrtcMicMonitor: send-pc sluiten faalde', e);
    }
    try {
      await recv?.close();
    } catch (e) {
      logWarning('WebrtcMicMonitor: recv-pc sluiten faalde', e);
    }
    if (mic == null) return;
    for (final track in mic.getTracks()) {
      try {
        await track.stop();
      } catch (e) {
        logWarning('WebrtcMicMonitor: track stoppen faalde', e);
      }
    }
    try {
      await mic.dispose();
    } catch (e) {
      logWarning('WebrtcMicMonitor: stream opruimen faalde', e);
    }
  }
}
