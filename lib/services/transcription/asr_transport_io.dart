// De desktop-transport voor de ASR-serverroute (#2524). Zelfde model als
// `PinnedAiHttpTransport` uit `network_guard` — resolve volgens de
// gate-strategie, socket pinnen op het gevalideerde adres, omleidingen
// weigeren, respons begrenzen — maar dan voor byte-bodies en met een
// werkende afbreekknop.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../utils/log.dart';
import '../../utils/pinned_http_client.dart';
import 'asr_resolve_io.dart';
import 'asr_transport.dart';

/// De enige HTTP-uitgang van de serverroute op desktop. `cancel()` breekt
/// de in-flight request af via `HttpClientRequest.abort`.
final class IoAsrTransport implements AsrTransport {
  const IoAsrTransport({
    this.maxResponseBytes = 16 * 1024 * 1024,
    this.resolve = resolveAsrPinned,
  });

  /// Harde grens aan de responsebody; er wordt niet meer gebufferd.
  final int maxResponseBytes;

  /// Productie gebruikt uitsluitend de gevalideerde, gepinde resolver.
  /// Injecteerbaar om late DNS-resultaten zonder netwerk te toetsen.
  final Future<InternetAddress> Function(String, AiResolveStrategy) resolve;

  @override
  AsrSendHandle send({
    required String method,
    required Uri url,
    required AiResolveStrategy strategy,
    Uint8List? body,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(minutes: 15),
  }) {
    final completer = Completer<AsrResponse>();
    HttpClient? client;
    HttpClientRequest? inFlight;
    StreamSubscription<List<int>>? subscription;
    Timer? deadline;

    void cleanup() {
      deadline?.cancel();
      inFlight?.abort();
      client?.close(force: true);
      final sub = subscription;
      if (sub != null) unawaited(sub.cancel());
    }

    void fail(AsrRequestException error, [StackTrace? stack]) {
      if (completer.isCompleted) return;
      completer.completeError(error, stack);
      cleanup();
    }

    void networkFailure(Object error, StackTrace stack) {
      if (completer.isCompleted) return;
      if (error is AsrRequestException) {
        fail(error, stack);
      } else {
        logError('IoAsrTransport.send: verzoek mislukt', error, stack);
        fail(const AsrRequestException('netwerk'), stack);
      }
    }

    // Eén deadline voor DNS, verbinden, upload én de volledige body.
    deadline = Timer(
      timeout,
      () => fail(const AsrRequestException('verbinding verliep')),
    );
    unawaited(() async {
      try {
        final pinned = await resolve(url.host, strategy);
        if (completer.isCompleted) return;
        final activeClient = buildPinnedClient(pinned);
        client = activeClient;
        final request = await activeClient.openUrl(method, url);
        if (completer.isCompleted) {
          request.abort();
          return;
        }
        inFlight = request;
        request.followRedirects = false;
        headers.forEach(request.headers.set);
        if (body != null) request.add(body);
        final response = await request.close();
        if (completer.isCompleted) return;
        final builder = BytesBuilder(copy: false);
        subscription = response.listen(
          (chunk) {
            if (completer.isCompleted) return;
            if (chunk.length > maxResponseBytes - builder.length) {
              fail(const AsrRequestException('respons groter dan het maximum'));
              return;
            }
            builder.add(chunk);
          },
          onError: networkFailure,
          onDone: () {
            if (completer.isCompleted) return;
            completer.complete(
              AsrResponse(
                response.statusCode,
                utf8.decode(builder.takeBytes(), allowMalformed: true),
              ),
            );
            cleanup();
          },
        );
      } catch (error, stack) {
        networkFailure(error, stack);
      }
    }());

    return AsrSendHandle(
      done: completer.future,
      cancel: () => fail(const AsrRequestException('afgebroken')),
    );
  }
}

AsrTransport createAsrTransport() => const IoAsrTransport();
