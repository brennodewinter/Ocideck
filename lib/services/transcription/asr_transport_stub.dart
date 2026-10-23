// De weigerende transporthelft voor platforms zonder `dart:io` en zonder
// `dart:js_interop`: de serverroute bestaat daar niet, dus elk verzoek
// eindigt in een getypeerde fout in plaats van iets voor te wenden.
import 'dart:async';
import 'dart:typed_data';

import 'asr_transport.dart';
import 'transcription_errors.dart';

final class StubAsrTransport implements AsrTransport {
  const StubAsrTransport();

  @override
  AsrSendHandle send({
    required String method,
    required Uri url,
    required AiResolveStrategy strategy,
    Uint8List? body,
    Map<String, String> headers = const {},
    Duration timeout = Duration.zero,
  }) {
    return AsrSendHandle(
      done: Future.error(
        const UnsupportedSource('geen ASR-serverroute op dit platform'),
      ),
      cancel: () {},
    );
  }
}

AsrTransport createAsrTransport() => const StubAsrTransport();
