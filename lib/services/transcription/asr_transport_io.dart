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
  const IoAsrTransport({this.maxResponseBytes = 16 * 1024 * 1024});

  /// Harde grens aan de responsebody; er wordt niet meer gebufferd.
  final int maxResponseBytes;

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
    var cancelRequested = false;
    HttpClientRequest? inFlight;

    () async {
      final pinned = await resolveAsrPinned(url.host, strategy);
      final client = buildPinnedClient(pinned);
      void abort() {
        completer.completeError(const AsrRequestException('afgebroken'));
      }

      try {
        final request = await client.openUrl(method, url);
        inFlight = request;
        if (cancelRequested) {
          request.abort();
          abort();
          return;
        }
        request.followRedirects =
            false; // een 3xx mag de hostcontrole niet omzeilen
        headers.forEach(request.headers.set);
        if (body != null) request.add(body);
        final response = await request.close().timeout(timeout);
        final builder = BytesBuilder(copy: false);
        await for (final chunk in response) {
          builder.add(chunk);
          if (builder.length > maxResponseBytes) {
            throw const AsrRequestException('respons groter dan het maximum');
          }
        }
        completer.complete(
          AsrResponse(
            response.statusCode,
            utf8.decode(builder.takeBytes(), allowMalformed: true),
          ),
        );
      } on AsrRequestException catch (e, s) {
        completer.completeError(e, s);
      } catch (e) {
        // Een gevraagde abort is geen netwerkfout: de engine vertaalt
        // 'afgebroken' naar Cancelled.
        if (cancelRequested) {
          abort();
        } else if (e is TimeoutException) {
          completer.completeError(
            const AsrRequestException('verbinding verliep'),
          );
        } else {
          // De host blijft bewust uit de foutmelding: hij is door de
          // gebruiker geconfigureerd maar kan gevoelig zijn.
          logError('IoAsrTransport.send: verzoek mislukt', e);
          completer.completeError(const AsrRequestException('netwerk'));
        }
      } finally {
        client.close(force: true);
      }
    }().catchError((Object e, StackTrace s) {
      // Fouten boven de request (resolve, openUrl) vallen hier.
      if (cancelRequested) {
        completer.completeError(const AsrRequestException('afgebroken'));
      } else {
        logError('IoAsrTransport.send: aanloop mislukt', e, s);
        completer.completeError(const AsrRequestException('netwerk'));
      }
    });

    return AsrSendHandle(
      done: completer.future,
      cancel: () {
        cancelRequested = true;
        inFlight?.abort();
      },
    );
  }
}

AsrTransport createAsrTransport() => const IoAsrTransport();
