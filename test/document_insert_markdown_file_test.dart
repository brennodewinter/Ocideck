import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/document_editor_screen.dart';

/// De invoeging "Markdown-bestand" (#2909) decodeert de gekozen bytes vóór ze
/// als blok op de cursor landen. Die stap — UTF-8, BOM eraf, regeleindes naar
/// `\n` — is puur in [decodeInsertableMarkdown] en wordt hier los getoetst.
void main() {
  group('decodeInsertableMarkdown', () {
    test('gewone UTF-8-tekst komt ongemoeid door', () {
      final bytes = Uint8List.fromList(utf8.encode('# Kop\n\nTekst.'));
      expect(decodeInsertableMarkdown(bytes), '# Kop\n\nTekst.');
    });

    test('een BOM aan het begin gaat eraf', () {
      final bytes = Uint8List.fromList([
        0xEF, 0xBB, 0xBF, // UTF-8 BOM
        ...utf8.encode('Tekst'),
      ]);
      expect(decodeInsertableMarkdown(bytes), 'Tekst');
    });

    test('CRLF- en kale CR-regeleindes worden LF', () {
      final bytes = Uint8List.fromList(utf8.encode('a\r\nb\rc'));
      expect(decodeInsertableMarkdown(bytes), 'a\nb\nc');
    });

    test('ongeldige UTF-8 levert null op, geen vervangende vraagtekens', () {
      // 0xFF is nooit een geldige UTF-8-byte: een binair bestand dat per
      // ongeluk als .md wordt gekozen, mag niet als mojibake in het document
      // landen.
      final bytes = Uint8List.fromList([0x41, 0xFF, 0xFE, 0x42]);
      expect(decodeInsertableMarkdown(bytes), isNull);
    });
  });
}
