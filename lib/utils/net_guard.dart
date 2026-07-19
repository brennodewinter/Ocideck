import 'dart:io';

import 'log.dart';

/// Waarom een hostcontrole geen adressen opleverde.
///
/// Het onderscheid is het hele punt. Beide gevallen gaven hiervoor `null`, en
/// de aanroeper maakte er één melding van: "markeer een privé/LAN-server eerst
/// als vertrouwd". Bij een tikfout in de hostnaam is dat advies niet alleen
/// nutteloos maar schadelijk — de gebruiker zet een veiligheidsvink om, en het
/// werkt nog steeds niet. De guard wéét welk van de twee het is; hij hoort het
/// door te geven.
enum HostRefusal {
  /// De naam is niet op te lossen: hij bestaat niet, of DNS antwoordde niet.
  unknownHost,

  /// De naam lost wél op, maar (mede) naar een intern adres. Hier — en alleen
  /// hier — helpt "vertrouwd intern" wél.
  blocked,
}

/// De uitkomst van een hostcontrole: gevalideerde adressen, of de reden waarom
/// niet. Precies één van beide is gevuld.
class HostResolution {
  final List<InternetAddress>? addresses;
  final HostRefusal? refusal;

  const HostResolution._(this.addresses, this.refusal);
  const HostResolution.ok(List<InternetAddress> addresses)
    : this._(addresses, null);
  const HostResolution.refused(HostRefusal refusal) : this._(null, refusal);

  bool get isOk => addresses != null;
}

/// Shared SSRF guards for any code that turns a deck-supplied string into a
/// network request. Extracted from `FileService` so the URL-import path and the
/// live remote-media path apply exactly the same host/address rules.
///
/// Two layers:
///  * [isBlockedHost] / [isBlockedAddress] — cheap, synchronous, lexical. Use at
///    insert time to reject obviously-internal targets before anything touches
///    the network.
///  * [safeResolve] — resolves a hostname and rejects it when ANY address is
///    internal, returning the validated addresses so the caller can pin the
///    socket against a DNS rebind. Use right before an `HttpClient` connect.
///
/// Wie de *reden* van een weigering aan de gebruiker moet uitleggen — de
/// opslagverbindingen, want die host heeft hij zelf ingetypt — gebruikt
/// [resolveConfigured] in plaats van [safeResolveTrusted].
class NetGuard {
  NetGuard._();

  /// Hosts a request must never reach (loopback, private and link-local ranges)
  /// so a deck URL can't be used to probe the local machine or intranet (SSRF).
  static bool isBlockedHost(String host) {
    final h = host.toLowerCase();
    if (h.isEmpty || h == 'localhost' || h.endsWith('.localhost')) return true;
    final addr = InternetAddress.tryParse(host);
    if (addr == null) return false; // a hostname; resolved in [safeResolve]
    return isBlockedAddress(addr);
  }

  /// Classifies a resolved IP as loopback/private/link-local/etc.
  static bool isBlockedAddress(InternetAddress addr) {
    if (addr.isLoopback || addr.isLinkLocal || addr.isMulticast) return true;
    final raw = addr.rawAddress;
    if (addr.type == InternetAddressType.IPv4) {
      return _isBlockedIPv4(raw[0], raw[1]);
    }
    // IPv6. First unwrap the IPv4 that an IPv6 literal can embed — Dart reports
    // `::ffff:127.0.0.1` as an IPv6 address with `isLoopback == false`, so an
    // embedded internal IPv4 would otherwise sail past every check below and
    // let a deck URL like `http://[::ffff:169.254.169.254]/` reach the metadata
    // service. Re-classify the embedded IPv4 via the same v4 rules.
    final embeddedV4 = _embeddedIPv4(raw);
    if (embeddedV4 != null) {
      return _isBlockedIPv4(embeddedV4[0], embeddedV4[1]);
    }
    // `::` (unspecified) and `::1` (loopback, normally caught by isLoopback but
    // guarded here too) must never be dialled.
    if (raw.every((b) => b == 0)) return true; // ::
    if ((raw[0] & 0xfe) == 0xfc) return true; // fc00::/7 unique-local
    return false;
  }

  /// RFC1918/loopback/link-local/CGNAT classification for an IPv4 given its
  /// first two octets. Shared by the native-IPv4 and IPv4-in-IPv6 paths.
  static bool _isBlockedIPv4(int a, int b) {
    if (a == 0 || a == 10 || a == 127) {
      return true; // this-host/private/loopback
    }
    if (a == 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12
    if (a == 192 && b == 168) return true; // 192.168.0.0/16
    if (a == 169 && b == 254) return true; // 169.254.0.0/16 link-local
    if (a == 100 && b >= 64 && b <= 127) return true; // 100.64.0.0/10 CGNAT
    return false;
  }

  /// Returns the four embedded IPv4 octets when [raw] (a 16-byte IPv6 address)
  /// is an IPv4-mapped (`::ffff:0:0/96`), IPv4-compatible (`::/96`, non-zero
  /// tail) or NAT64 well-known-prefix (`64:ff9b::/96`) address; otherwise null.
  static List<int>? _embeddedIPv4(List<int> raw) {
    if (raw.length != 16) return null;
    // NAT64 well-known prefix 64:ff9b::/96.
    const nat64 = [0x00, 0x64, 0xff, 0x9b, 0, 0, 0, 0, 0, 0, 0, 0];
    var isNat64 = true;
    for (var i = 0; i < 12; i++) {
      if (raw[i] != nat64[i]) {
        isNat64 = false;
        break;
      }
    }
    if (isNat64) return [raw[12], raw[13], raw[14], raw[15]];
    // First 10 bytes zero → ::ffff:x.x.x.x (mapped) or ::x.x.x.x (compatible).
    for (var i = 0; i < 10; i++) {
      if (raw[i] != 0) return null;
    }
    final isMapped = raw[10] == 0xff && raw[11] == 0xff;
    final isCompatible = raw[10] == 0 && raw[11] == 0;
    if (!isMapped && !isCompatible) return null;
    return [raw[12], raw[13], raw[14], raw[15]];
  }

  /// Resolves [host] to validated addresses, or null when the host (or ANY of
  /// its addresses) is internal or it can't be resolved — closes the SSRF hole
  /// where `attacker.com` resolves to 127.0.0.1 / 169.254.169.254 / an RFC1918
  /// host. The caller pins the connection to the returned address so a DNS
  /// rebind between this check and connect can't redirect the socket internally.
  static Future<List<InternetAddress>?> safeResolve(String host) async {
    final literal = InternetAddress.tryParse(host);
    if (literal != null) {
      return isBlockedAddress(literal) ? null : [literal];
    }
    try {
      final addrs = await InternetAddress.lookup(host);
      if (addrs.isEmpty || addrs.any(isBlockedAddress)) return null;
      return addrs;
    } catch (e) {
      // Host omitted from the log: it is deck-supplied and may be sensitive.
      logWarning('NetGuard.safeResolve: DNS lookup failed', e);
      return null; // can't resolve safely → refuse
    }
  }

  /// Variant of [safeResolve] for a host the user has *explicitly* configured
  /// (the WebDAV/Nextcloud server), not one supplied by a deck. When
  /// [allowPrivate] is true the private/loopback/link-local block is skipped so
  /// a self-hosted LAN server can be reached — the user opted in by ticking
  /// "trusted internal server". The host is still resolved and the returned
  /// address is still meant to be pinned by the caller, so TLS validates the
  /// real hostname and a DNS rebind can't move the socket after this check.
  ///
  /// With [allowPrivate] false this is exactly [safeResolve]: deck-supplied
  /// URLs never reach here, and even a configured public server stays guarded.
  static Future<List<InternetAddress>?> safeResolveTrusted(
    String host, {
    required bool allowPrivate,
  }) async {
    final result = await resolveConfigured(host, allowPrivate: allowPrivate);
    return result.addresses;
  }

  /// Als [safeResolveTrusted], maar geeft bij een weigering de *reden* terug.
  ///
  /// Voor een host die de gebruiker zelf heeft ingevuld. De naam mag hier wél
  /// in het log: anders dan bij een deck-URL is dit zijn eigen server, en juist
  /// die naam is het enige dat de twee weigeringsredenen uit elkaar houdt
  /// wanneer je achteraf een logboek zit te lezen.
  static Future<HostResolution> resolveConfigured(
    String host, {
    required bool allowPrivate,
  }) async {
    final literal = InternetAddress.tryParse(host);
    if (literal != null) {
      if (!allowPrivate && isBlockedAddress(literal)) {
        return const HostResolution.refused(HostRefusal.blocked);
      }
      return HostResolution.ok([literal]);
    }
    final List<InternetAddress> addrs;
    try {
      addrs = await InternetAddress.lookup(host);
    } catch (e) {
      logWarning('NetGuard.resolveConfigured: DNS lookup failed for $host', e);
      return const HostResolution.refused(HostRefusal.unknownHost);
    }
    // Een lege uitslag is geen blokkade maar een naam zonder adres: dezelfde
    // uitkomst als een mislukte lookup, en hetzelfde advies.
    if (addrs.isEmpty) {
      return const HostResolution.refused(HostRefusal.unknownHost);
    }
    if (!allowPrivate && addrs.any(isBlockedAddress)) {
      return const HostResolution.refused(HostRefusal.blocked);
    }
    return HostResolution.ok(addrs);
  }

  /// Lexical, synchronous check for whether [url] is a usable `http(s)` media
  /// URL that is not aimed at an obviously-internal host. Returns false for
  /// non-web schemes and blocked hosts. A `true` result does NOT guarantee the
  /// host resolves externally (a hostname is only fully checked by [safeResolve]
  /// at connect time) — it is the insert-time gate, not the connect-time gate.
  static bool isAllowedMediaUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return false;
    return !isBlockedHost(uri.host);
  }

  /// Per-host memo of the resolved media gate. Positive results stay cached for
  /// the session (a legitimate CDN host resolves once); a negative is dropped so
  /// a transient DNS blip can be retried and an internal host is re-checked
  /// rather than wrongly cached as reachable.
  static final Map<String, Future<bool>> _mediaHostResolveCache = {};

  /// Connect-time SSRF gate for a deck-supplied media URL. Layers a DNS
  /// resolution on top of the lexical [isAllowedMediaUrl]: a hostname that
  /// resolves to a loopback/private/link-local address — or a non-dotted
  /// encoding like `http://2130706433/` that the lexical check waves through —
  /// is rejected here. Call this before handing the URL to `NetworkImage` /
  /// `VideoPlayerController`, which otherwise resolve and connect with no host
  /// check of their own.
  ///
  /// NOTE: those higher-level APIs re-resolve the host at fetch time, so this
  /// does not pin the socket; a DNS rebind in the window between this check and
  /// the fetch stays possible. It closes the static-internal and
  /// resolves-to-internal cases, which are the realistic deck-driven attacks.
  static Future<bool> isAllowedMediaUrlResolved(String url) {
    if (!isAllowedMediaUrl(url)) return Future.value(false);
    final host = Uri.parse(url.trim()).host;
    final cached = _mediaHostResolveCache[host];
    if (cached != null) return cached;
    final future = safeResolve(host).then((addrs) => addrs != null);
    _mediaHostResolveCache[host] = future;
    future.then((allowed) {
      if (!allowed) _mediaHostResolveCache.remove(host);
    });
    return future;
  }
}
