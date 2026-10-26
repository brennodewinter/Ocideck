// De resolve-per-strategie voor de ASR-serverroutes (§4.3). Was privé
// in `asr_transport_io.dart`; de live-WebSocket uit #2525 pint zijn
// socket via precies dezelfde regels, dus het recept staat nu hier —
// één kopie SSRF-verdediging, niet twee die uit elkaar kunnen lopen.
import 'dart:io';

import 'package:network_guard/network_guard.dart' show AiResolveStrategy;

import '../../utils/net_guard.dart' show NetGuard;
import 'asr_transport.dart' show AsrRequestException;

/// Resolveert [host] tot het ene adres waarop de socket wordt gepind,
/// per netwerkregime van de gate-strategie. Gooit bij weigering.
Future<InternetAddress> resolveAsrPinned(
  String host,
  AiResolveStrategy strategy,
) async {
  switch (strategy) {
    case AiResolveStrategy.loopbackDirect:
      final addr = InternetAddress.tryParse(host);
      if (addr != null && addr.isLoopback) return addr;
      // `localhost` als naam: resolve zelf, loopback-eis controleert elke
      // treffer — DNS kan hier niet naar buiten wijzen zonder te falen.
      // Een naam kan naar meerdere families wijzen (::1 én 127.0.0.1);
      // whisper-server bindt standaard IPv4, dus die gaat voor.
      final hits = await InternetAddress.lookup(host);
      final loopbacks = hits.where((h) => h.isLoopback).toList();
      for (final hit in loopbacks) {
        if (hit.type == InternetAddressType.IPv4) return hit;
      }
      if (loopbacks.isNotEmpty) return loopbacks.first;
      throw const AsrRequestException('loopback resolveerde extern');
    case AiResolveStrategy.publicGuarded:
      final addrs = await NetGuard.safeResolve(host);
      if (addrs == null || addrs.isEmpty) {
        throw const AsrRequestException('host geweigerd');
      }
      return addrs.first;
    case AiResolveStrategy.trustedPrivate:
      final addrs = await NetGuard.safeResolveTrusted(host, allowPrivate: true);
      if (addrs == null || addrs.isEmpty) {
        throw const AsrRequestException('host geweigerd');
      }
      return addrs.first;
  }
}
