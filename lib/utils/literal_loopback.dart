// Lexicale hostclassificatie voor code die zonder `dart:io` moet draaien
// (web). `NetGuard` beantwoordt dezelfde vragen via `InternetAddress`, maar
// dat bestaat in een browser niet — `tryParse` gooit daar
// `Unsupported operation`. Dezelfde regels, puur op de tekst:
//
// * een loopback-uitzondering (platte `http`/`ws`) telt alleen een letterlijk
//   adres, nooit een naam — `localhost` gaat langs DNS en kan ergens anders
//   uitkomen;
// * een blokkade (cloud-ASR, het label "intern netwerk") dekt dezelfde
//   letterlijke ranges als `NetGuard.isBlockedHost`, plus `localhost`. Een
//   andere naam wordt niet opgelost: dat kan op web niet, en de browser is
//   daar de grens. Een onleesbaar IPv6-literal telt wél als intern — liever
//   een cloud-URL weigeren dan een vorm die we niet kunnen classificeren
//   als publiek doorlaten.

/// Of [host] een letterlijk loopback-adres is (`127.0.0.0/8` of `::1`).
bool isLiteralLoopbackHost(String host) {
  final bare = _stripBrackets(host);
  if (bare == '::1') return true;
  final octets = _canonicalIpv4(bare);
  return octets != null && octets[0] == 127;
}

/// Of een browser-`fetch` van [url] door de schemegrens mag.
///
/// `https` overal, `http` alleen naar een letterlijk loopback-adres. De
/// webhelft van de config.js-fetch kan de test-VM niet in (`package:web`);
/// deze functie ís die beslissing.
bool allowsWebConfigFetch(Uri url) {
  final scheme = url.scheme.toLowerCase();
  return scheme == 'https' ||
      (scheme == 'http' && isLiteralLoopbackHost(url.host));
}

/// Of een browser-WebSocket naar [url] door de schemegrens mag.
///
/// `wss` overal, `ws` alleen naar een letterlijk loopback-adres — het
/// SASL-wachtwoord gaat over deze stroom.
bool allowsWebXmppSocket(Uri url) {
  final scheme = url.scheme.toLowerCase();
  return scheme == 'wss' || (scheme == 'ws' && isLiteralLoopbackHost(url.host));
}

/// Of [host] een letterlijk intern adres is — loopback, privé, link-local,
/// CGNAT, multicast, of de naam `localhost`.
///
/// Spiegel van `NetGuard.isBlockedHost` voor wat die functie zónder DNS
/// beslist. Een voorloopnul in een vierdelig numeriek adres telt ook: de
/// browser kan `10.0.0.01` als `10.0.0.1` lezen, en een cloud-URL daarnaartoe
/// is geen cloud.
bool isLiteralInternalHost(String host) {
  final bare = _stripBrackets(host.trim().toLowerCase());
  if (bare.isEmpty || bare == 'localhost' || bare.endsWith('.localhost')) {
    return true;
  }
  if (bare.contains(':')) return _isInternalIpv6(bare);
  if (_suspiciousDottedQuad(bare)) return true;
  final octets = _canonicalIpv4(bare);
  if (octets == null) return false;
  return _isBlockedIpv4(octets[0], octets[1]);
}

String _stripBrackets(String host) => host.startsWith('[') && host.endsWith(']')
    ? host.substring(1, host.length - 1)
    : host;

/// Vier decimale octetten in canonieke vorm, of null.
List<int>? _canonicalIpv4(String bare) {
  final parts = bare.split('.');
  if (parts.length != 4) return null;
  final octets = <int>[];
  for (final part in parts) {
    final octet = int.tryParse(part);
    if (octet == null || octet < 0 || octet > 255 || part != '$octet') {
      return null;
    }
    octets.add(octet);
  }
  return octets;
}

/// `10.0.0.01` en `172.16.0.256`: het lijkt een adres, maar niet het
/// canonieke. Blokkeren, niet als publieke naam behandelen.
bool _suspiciousDottedQuad(String bare) {
  final parts = bare.split('.');
  if (parts.length != 4) return false;
  if (parts.any((part) => int.tryParse(part) == null)) return false;
  return _canonicalIpv4(bare) == null;
}

bool _isBlockedIpv4(int a, int b) {
  if (a == 0 || a == 10 || a == 127) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  if (a == 192 && b == 168) return true;
  if (a == 169 && b == 254) return true;
  if (a == 100 && b >= 64 && b <= 127) return true;
  if (a >= 224 && a <= 239) return true;
  return false;
}

bool _isInternalIpv6(String bare) {
  final raw = _ipv6Bytes(bare);
  // Onleesbaar literal: liever blokkeren dan als publiek doorlaten.
  if (raw == null) return true;
  if (raw.every((b) => b == 0)) return true;
  if (raw.sublist(0, 15).every((b) => b == 0) && raw[15] == 1) return true;
  final embedded = _embeddedIpv4(raw);
  if (embedded != null) return _isBlockedIpv4(embedded[0], embedded[1]);
  if ((raw[0] & 0xfe) == 0xfc) return true;
  if (raw[0] == 0xfe && (raw[1] & 0xc0) == 0x80) return true;
  if (raw[0] == 0xff) return true;
  return false;
}

/// Zestien bytes, of null als [bare] geen IPv6-literal is. Zelfde vormen als
/// `NetGuard`: een punt-staart (`::ffff:127.0.0.1`) telt als twee groepen.
List<int>? _ipv6Bytes(String bare) {
  var text = bare.toLowerCase();
  List<int>? v4;
  final colon = text.lastIndexOf(':');
  if (colon >= 0 && text.substring(colon + 1).contains('.')) {
    v4 = _canonicalIpv4(text.substring(colon + 1));
    if (v4 == null) return null;
    // `64:ff9b::1.2.3.4` — de laatste `:` hoort bij `::`. Die moet blijven,
    // anders verdwijnt de compressie en blijft een lege groep over.
    final compressed = colon > 0 && text[colon - 1] == ':';
    text = text.substring(0, colon);
    if (compressed && !text.endsWith('::')) text = '$text:';
  }
  final sides = text.split('::');
  if (sides.length > 2) return null;
  final left = _hextets(sides[0]);
  if (left == null) return null;
  final right = sides.length == 2 ? _hextets(sides[1]) : <int>[];
  if (right == null) return null;
  final v4groups = v4 == null
      ? const <int>[]
      : [(v4[0] << 8) | v4[1], (v4[2] << 8) | v4[3]];
  final explicit = left.length + right.length + v4groups.length;
  final List<int> groups;
  if (sides.length == 1) {
    if (explicit != 8) return null;
    groups = [...left, ...v4groups];
  } else {
    if (explicit > 7) return null;
    groups = [
      ...left,
      ...List<int>.filled(8 - explicit, 0),
      ...right,
      ...v4groups,
    ];
  }
  final bytes = <int>[];
  for (final group in groups) {
    bytes
      ..add(group >> 8)
      ..add(group & 0xff);
  }
  return bytes;
}

List<int>? _hextets(String side) {
  if (side.isEmpty) return [];
  final out = <int>[];
  for (final group in side.split(':')) {
    if (group.isEmpty || group.length > 4) return null;
    final value = int.tryParse(group, radix: 16);
    if (value == null) return null;
    out.add(value);
  }
  return out;
}

/// IPv4 die een IPv6-literal kan verbergen: mapped (`::ffff:0:0/96`),
/// compatible (`::/96`) of NAT64 (`64:ff9b::/96`). Zelfde drie als NetGuard.
List<int>? _embeddedIpv4(List<int> raw) {
  const nat64 = [0x00, 0x64, 0xff, 0x9b, 0, 0, 0, 0, 0, 0, 0, 0];
  var isNat64 = true;
  for (var i = 0; i < 12; i++) {
    if (raw[i] != nat64[i]) {
      isNat64 = false;
      break;
    }
  }
  if (isNat64) return [raw[12], raw[13], raw[14], raw[15]];
  for (var i = 0; i < 10; i++) {
    if (raw[i] != 0) return null;
  }
  final mapped = raw[10] == 0xff && raw[11] == 0xff;
  final compatible =
      raw[10] == 0 && raw[11] == 0 && raw.sublist(12).any((b) => b != 0);
  if (!mapped && !compatible) return null;
  return [raw[12], raw[13], raw[14], raw[15]];
}
