// De stub-helft: geen io, geen browser — de liveroute kan hier niet,
// en dat is een eerlijk antwoord in plaats van een stille mislukking.
import 'dart:async';

import 'asr_live_transport.dart';

final class StubAsrLiveTransport implements AsrLiveTransport {
  const StubAsrLiveTransport();

  @override
  Future<AsrLiveSocket> connect({
    required Uri url,
    required AiResolveStrategy strategy,
    Map<String, String> headers = const {},
  }) {
    throw const AsrLiveException('geen live-transport op dit platform');
  }
}

AsrLiveTransport createAsrLiveTransport() => const StubAsrLiveTransport();
