import 'dart:io';

import 'log.dart';

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
      final a = raw[0], b = raw[1];
      if (a == 0 || a == 10 || a == 127) {
        return true; // this-host/private/loopback
      }
      if (a == 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12
      if (a == 192 && b == 168) return true; // 192.168.0.0/16
      if (a == 169 && b == 254) return true; // 169.254.0.0/16 link-local
    } else if ((raw[0] & 0xfe) == 0xfc) {
      return true; // fc00::/7 unique-local
    }
    return false;
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
    if (!allowPrivate) return safeResolve(host);
    final literal = InternetAddress.tryParse(host);
    if (literal != null) return [literal];
    try {
      final addrs = await InternetAddress.lookup(host);
      return addrs.isEmpty ? null : addrs;
    } catch (e) {
      logWarning('NetGuard.safeResolveTrusted: DNS lookup failed', e);
      return null;
    }
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
