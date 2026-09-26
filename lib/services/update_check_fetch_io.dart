import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../utils/log.dart';
import '../utils/net_guard.dart';
import '../utils/pinned_http_client.dart';

/// Hoe lang de check in totaal mag duren. De release-index is klein en snel;
/// een trage verbinding mag het opstarten nooit voelbaar ophouden.
const _timeout = Duration(seconds: 10);

/// De release-JSON is klein (tag, naam, releasetekst); een kap die de normale
/// body ruim overdekt voorkomt dat een misgaand antwoord eindeloos
/// binnenstroomt.
const _maxResponseBytes = 64 * 1024;

/// De desktop-ophaalstap van de versiecheck. Fail-closed op het adres: de
/// host gaat door [NetGuard.safeResolve] (een naam die naar een intern adres
/// resolveert wordt geweigerd), de socket wordt aan het goedgekeurde adres
/// gepind en redirects staan uit — een 3xx kan de hostcontrole niet omzeilen.
/// Elke fout is `null`: zie [UpdateCheckService].
Future<String?> pinnedUpdateCheckFetch(Uri uri) async {
  if (uri.scheme != 'https') return null;
  // `safeResolve`, niet `safeResolveTrusted`: dit is geen door de gebruiker
  // geconfigureerde host waar "vertrouwd intern" ooit voor zou mogen gelden.
  final addresses = await NetGuard.safeResolve(uri.host);
  if (addresses == null || addresses.isEmpty) return null;
  final client = buildPinnedClient(
    addresses.first,
    connectionTimeout: _timeout,
  );
  try {
    final request = await client.openUrl('GET', uri).timeout(_timeout);
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(_timeout);
    if (response.statusCode != HttpStatus.ok) return null;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(_timeout)) {
      builder.add(chunk);
      if (builder.length > _maxResponseBytes) return null;
    }
    return utf8.decode(builder.takeBytes(), allowMalformed: true);
  } catch (e) {
    // Geen host of status in de melding — die voegt niets toe aan een "de
    // check faalde"-regel in het log van iemands machine.
    logWarning('versiecheck: ophalen mislukt', e);
    return null;
  } finally {
    client.close(force: true);
  }
}
