// Vouchercodes voor zelfinschrijving (issue #2125). Dezelfde vorm als de
// OciServe setupcode: voorvoegsel OCVO, Crockford Base32 in groepen van vier
// en een checksum van twee tekens — de eerste byte van SHA-256 over de tien
// bytes entropie, in hetzelfde alfabet. De lokale controle vangt een typefout
// zonder de server te bevragen; de code zelf wordt nooit bewaard of gelogd.

import 'package:crypto/crypto.dart';

/// Crockford Base32 — hetzelfde alfabet als `collab_recovery_key.dart`.
const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Het voorvoegsel dat een OciServe-vouchercode merkt.
const String voucherCodePrefix = 'OCVO';

/// Tien bytes entropie per code — overgenomen van de server.
const int _entropyBytes = 10;

/// Normaliseert een ingevoerde code zoals de server dat doet: hoofdletters,
/// streepjes en spaties eruit, het OCVO-voorvoegsel eraf en de
/// Crockford-transcriptiefixes (o/O→0, i/I/l/L→1) alleen op de payload — het
/// voorvoegsel zelf bevat letters die anders verminkt zouden worden.
/// Geeft `null` als het voorvoegsel ontbreekt.
String? normalizeVoucherCode(String raw) {
  final compact = StringBuffer();
  for (final ch in raw.trim().toUpperCase().split('')) {
    if (ch == '-' || ch == ' ') continue;
    compact.write(ch);
  }
  final joined = compact.toString();
  if (!joined.startsWith(voucherCodePrefix)) return null;
  final payload = StringBuffer();
  for (final ch in joined.substring(voucherCodePrefix.length).split('')) {
    switch (ch) {
      case 'O':
        payload.write('0');
      case 'I' || 'L':
        payload.write('1');
      default:
        payload.write(ch);
    }
  }
  return payload.toString();
}

/// Decodeert Crockford Base32 naar bytes; `null` bij een vreemd teken.
/// De buffer wordt na elke emissie afgekapt — zonder masker loopt een
/// 16-teken payload over de 64 bits van een Dart-int heen.
List<int>? _decode(String chars) {
  final out = <int>[];
  var buffer = 0;
  var bits = 0;
  for (final ch in chars.split('')) {
    final value = _alphabet.indexOf(ch);
    if (value < 0) return null;
    buffer = ((buffer << 5) | value) & 0x1ffffffff;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.add((buffer >> bits) & 0xff);
      buffer &= (1 << bits) - 1;
    }
  }
  return out;
}

String _encode(List<int> bytes) {
  final out = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final b in bytes) {
    buffer = ((buffer << 8) | (b & 0xff)) & 0x1ffffffff;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out.write(_alphabet[(buffer >> bits) & 0x1f]);
      buffer &= (1 << bits) - 1;
    }
  }
  if (bits > 0) out.write(_alphabet[(buffer << (5 - bits)) & 0x1f]);
  return out.toString();
}

/// De canonieke, leesbare vorm van een geldig genormaliseerde code:
/// `OCVO-XXXX-XXXX-XXXX-XXXX-CC`. `null` als er geen voorvoegsel of payload
/// is — geldigheid van de checksum controleert
/// [hasValidVoucherChecksum].
String? formatVoucherCode(String raw) {
  final compact = normalizeVoucherCode(raw);
  if (compact == null || compact.length < 3) return null;
  final out = StringBuffer(voucherCodePrefix);
  for (var i = 0; i < compact.length; i++) {
    if (i % 4 == 0) out.write('-');
    out.write(compact[i]);
  }
  return out.toString();
}

/// Controleert vorm én checksum van een vouchercode, identiek aan
/// `hashVoucherCode` op de server: de laatste twee tekens zijn de eerste
/// SHA-256-byte van de gedecodeerde entropie in Crockford Base32. Alleen de
/// vorm wordt beoordeeld — of de code bekend, actueel of van deze uitvoering
/// is, weet alleen de server.
bool hasValidVoucherChecksum(String raw) {
  final compact = normalizeVoucherCode(raw);
  if (compact == null || compact.length < 4) return false;
  final payload = compact.substring(0, compact.length - 2);
  final check = compact.substring(compact.length - 2);
  final entropy = _decode(payload);
  if (entropy == null || entropy.length != _entropyBytes) return false;
  return _encode(sha256.convert(entropy).bytes.sublist(0, 1)) == check;
}
