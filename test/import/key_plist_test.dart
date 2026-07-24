import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/importers/keynote/key_context.dart';
import 'package:ocideck/services/import/importers/keynote/key_plist.dart';

List<int> _b(String s) => Uint8List.fromList(utf8.encode(s));

KeyContext _ctx(Map<String, Object> parts) {
  final archive = Archive();
  parts.forEach((name, content) {
    final data = content is List<int>
        ? Uint8List.fromList(content)
        : Uint8List.fromList((content as String).codeUnits);
    archive.addFile(ArchiveFile(name, data.length, data));
  });
  return KeyContext(archive);
}

const _xmlPlist =
    '<?xml version="1.0"?>'
    '<plist version="1.0"><dict>'
    '<key>title</key><string>Q3 Roadmap</string>'
    '<key>authors</key><array><string>Jane Doe</string><string>Sam</string></array>'
    '<key>untouched</key><integer>7</integer>'
    '</dict></plist>';

void main() {
  test(
    'readXmlPlist maps string and first-array values, skips non-strings',
    () {
      final map = readXmlPlist(_xmlPlist);
      expect(map['title'], 'Q3 Roadmap');
      expect(map['authors'], 'Jane Doe');
      expect(map.containsKey('untouched'), isFalse);
    },
  );

  test('deckMetadataFromPlist returns title and author', () {
    final ctx = _ctx({'Metadata/Properties.plist': _b(_xmlPlist)});
    final meta = deckMetadataFromPlist(ctx);
    expect(meta.title, 'Q3 Roadmap');
    expect(meta.author, 'Jane Doe');
  });

  test('deckMetadataFromPlist is empty when the plist is missing', () {
    final ctx = _ctx({});
    final meta = deckMetadataFromPlist(ctx);
    expect(meta.title, '');
    expect(meta.author, '');
  });

  test('deckMetadataFromPlist is empty for a binary plist (bplist00)', () {
    final ctx = _ctx({'Metadata/Properties.plist': _b('bplist00binary-junk')});
    final meta = deckMetadataFromPlist(ctx);
    expect(meta.title, '');
    expect(meta.author, '');
  });
}
