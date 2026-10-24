// Desktop-implementatie van de config.js-fetch — hetzelfde recept als
// `media_fetch_io.dart`: NetGuard-resolutie, socket gepind op het
// goedgekeurde adres, `followRedirects = false` (een 3xx mag de
// hostcontrole niet omzeilen), en een body-cap zodat een vijandige of
// kapotte host geen onbegrensde respons in het geheugen duwt.
//
// De schemegrens spiegelt de XMPP-transportlaag bewust: `http` staat alleen
// toe voor een letterlijke loopback-host (de testomgeving); elke andere
// deployment moet TLS bieden. Cert-pinning gaat via
// [pinnedCertSha256] — dezelfde semantiek als XmppSettings.

import 'dart:convert';
import 'dart:typed_data';

import '../../../utils/net_guard.dart';
import '../../../utils/pinned_http_client.dart';
import 'jitsi_config.dart';

/// Haalt `config.js` op via een gepinde socket. Gooit
/// [JitsiConfigFetchException] bij elke weigering — de preflight beslist wat
/// dat betekent, deze laag levert alleen een eerlijke reden.
Future<String> fetchJitsiConfig(
  Uri configUrl, {
  required bool allowPrivate,
  String pinnedCertSha256 = '',
  Duration timeout = const Duration(seconds: 15),
  int maxBytes = 256 * 1024,
}) async {
  final scheme = configUrl.scheme.toLowerCase();
  if (scheme != 'https' &&
      !(scheme == 'http' && NetGuard.isLiteralLoopbackHost(configUrl.host))) {
    throw const JitsiConfigFetchException('alleen https (of http op loopback)');
  }
  final resolution = await NetGuard.resolveConfigured(
    configUrl.host,
    allowPrivate: allowPrivate,
  );
  if (!resolution.isOk || resolution.addresses!.isEmpty) {
    throw JitsiConfigFetchException(
      'host geweigerd (${resolution.refusal?.name ?? 'onbekend'})',
    );
  }

  final client = buildPinnedClient(
    resolution.addresses!.first,
    pinnedCertSha256: pinnedCertSha256.isEmpty ? null : pinnedCertSha256,
  );
  try {
    final request = await client.getUrl(configUrl).timeout(timeout);
    request.followRedirects = false;
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200) {
      throw JitsiConfigFetchException('HTTP ${response.statusCode}');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(timeout)) {
      bytes.add(chunk);
      if (bytes.length > maxBytes) {
        throw const JitsiConfigFetchException('config.js te groot');
      }
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  } finally {
    client.close(force: true);
  }
}
