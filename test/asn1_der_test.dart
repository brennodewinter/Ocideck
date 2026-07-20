import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/asn1_der.dart';

void main() {
  group('derLength', () {
    test('short form below 128', () {
      expect(derLength(0), [0]);
      expect(derLength(127), [127]);
    });
    test('long form at and above 128', () {
      expect(derLength(128), [0x81, 128]);
      expect(derLength(300), [0x82, 0x01, 0x2c]);
    });
  });

  group('derInteger', () {
    test('encodes a small value', () {
      expect(derInteger(1), [0x02, 0x01, 0x01]);
    });
    test('prepends a zero byte when the high bit is set', () {
      expect(derInteger(0x80), [0x02, 0x02, 0x00, 0x80]);
    });
  });

  group('parseDer', () {
    test('round-trips a nested SEQUENCE', () {
      final encoded = Uint8List.fromList(
        derSequence([
          derInteger(1),
          derOctetString(const [1, 2, 3]),
          derBoolean(true),
        ]),
      );
      final node = parseDer(encoded)!;
      expect(node.tag, 0x30);
      expect(node.isConstructed, isTrue);
      expect(node.children, hasLength(3));
      expect(node.children[0].tag, 0x02);
      expect(node.children[0].content, [1]);
      expect(node.children[1].tag, 0x04);
      expect(node.children[1].content, [1, 2, 3]);
      expect(node.children[2].content, [0xff]);
    });

    test('handles long-form lengths', () {
      final big = List<int>.filled(200, 0x41);
      final encoded = Uint8List.fromList(derSequence([derOctetString(big)]));
      final node = parseDer(encoded)!;
      expect(node.children.single.content, hasLength(200));
    });

    test('descendantsAndSelf walks depth-first', () {
      final encoded = Uint8List.fromList(
        derSequence([
          derSequence([
            derOid(const [0x2a]),
          ]),
          derNull(),
        ]),
      );
      final tags = parseDer(encoded)!.descendantsAndSelf.map((n) => n.tag);
      expect(tags, [0x30, 0x30, 0x06, 0x05]);
    });

    test('returns null on malformed input', () {
      expect(parseDer(Uint8List.fromList([0x30, 0x05, 0x01])), isNull);
    });
  });

  group('vijandige invoer', () {
    Uint8List nested(int depth) {
      List<int> cur = [0x05, 0x00];
      for (var d = 0; d < depth; d++) {
        final n = cur.length;
        final List<int> len;
        if (n < 0x80) {
          len = [n];
        } else if (n < 0x100) {
          len = [0x81, n];
        } else if (n < 0x10000) {
          len = [0x82, (n >> 8) & 0xff, n & 0xff];
        } else {
          len = [0x83, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff];
        }
        cur = [0x30, ...len, ...cur];
      }
      return Uint8List.fromList(cur);
    }

    test('diep geneste DER geeft null in plaats van een stack overflow', () {
      // Het token staat in de front matter van het deck en wordt gelezen bij het
      // bouwen van het zegelvenster, dus dit liet de app omvallen op een bestand
      // dat iemand je stuurt. StackOverflowError is een Error, geen Exception:
      // de `on RangeError` ving hem niet en de aanroeper evenmin.
      expect(parseDer(nested(200)), isNull);
    });

    test('een normale nesting blijft gewoon werken', () {
      final node = parseDer(nested(8));
      expect(node, isNotNull);
      expect(node!.descendantsAndSelf.length, 9);
    });

    test('een onbepaalde lengte (BER) wordt geweigerd', () {
      // `30 80` is in DER ongeldig. Het werd als lengte nul gelezen, waarna de
      // inhoud buiten de boom viel en een niveau hoger opnieuw werd uitgelegd —
      // in een verificatiepad precies het soort verschil dat je niet wilt.
      expect(parseDer(Uint8List.fromList([0x30, 0x80, 0x05, 0x00])), isNull);
    });
  });
}
