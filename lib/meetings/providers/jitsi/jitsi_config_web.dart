// Web-implementatie van de config.js-fetch. De browser is hier de
// netwerkgrens, hetzelfde recept als `asr_transport_web` en
// `media_fetch_web`: `fetch` met `mode: 'cors'` beslist wat het netwerk op
// mag, de pagina-CSP begrenst met `connect-src` waar de app heen kan, en
// pinnen kan een browser niet — [pinnedCertSha256] en [allowPrivate] gelden
// hier bewust niet (het profiel rapporteert dat al als "desktop only").
//
// Wel blijven twee delen van het io-recept overeind: de schemegrens
// (`https`, of `http` naar een letterlijke loopback voor de lokale testbed)
// en de body-cap — een vijandige of kapotte host mag de tab niet vullen.
//
// Eerlijke beperking van deze route: cross-origin vraagt dat de deployment
// CORS op `config.js` toestaat, of dat OciDeck-web op dezelfde origin staat.
// Een "werkt maar ongelezen"-halte (no-cors) is geen optie — de body is dan
// opaak en de preflight zou niets bewijzen.

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../../../utils/literal_loopback.dart';
import '../../../utils/log.dart';
import 'jitsi_config.dart';

/// Haalt `config.js` op via de browser-`fetch`. Gooit
/// [JitsiConfigFetchException] bij elke weigering — de preflight beslist wat
/// dat betekent, deze laag levert alleen een eerlijke reden.
Future<String> fetchJitsiConfig(
  Uri configUrl, {
  required bool allowPrivate,
  String pinnedCertSha256 = '',
  Duration timeout = const Duration(seconds: 15),
  int maxBytes = 256 * 1024,
}) async {
  if (!allowsWebConfigFetch(configUrl)) {
    throw const JitsiConfigFetchException('alleen https (of http op loopback)');
  }
  final controller = web.AbortController();
  final timer = Timer(timeout, () => controller.abort());
  try {
    final response = await web.window
        .fetch(
          configUrl.toString().toJS,
          web.RequestInit(
            signal: controller.signal,
            mode: 'cors',
            credentials: 'omit',
          ),
        )
        .toDart;
    if (response.status != 200) {
      throw JitsiConfigFetchException('HTTP ${response.status}');
    }
    final buf = (await response.arrayBuffer().toDart).toDart;
    if (buf.lengthInBytes > maxBytes) {
      throw const JitsiConfigFetchException('config.js te groot');
    }
    return web.TextDecoder().decode(buf.asUint8List().toJS);
  } on JitsiConfigFetchException {
    rethrow;
  } catch (e) {
    // De browser rapporteert CORS-, DNS- en verbindingsweigeringen bewust
    // éénvormig; onze eigen abort is de enige uitzondering die we kennen.
    final aborted = controller.signal.aborted;
    logWarning('jitsi.config.fetch', aborted ? 'timeout' : e);
    throw JitsiConfigFetchException(aborted ? 'timeout' : 'onbereikbaar');
  } finally {
    timer.cancel();
  }
}
