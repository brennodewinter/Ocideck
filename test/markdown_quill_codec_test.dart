import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_quill/markdown_quill.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';

void main() {
  test('markdown round-trips through quill for basic formatting', () {
    const source = '''## Kop

Dit is **vet** en *cursief* met `code`.

- item een
- item twee
''';

    final document = MarkdownQuillCodec.documentFromMarkdown(source);
    final restored = MarkdownQuillCodec.markdownFromDocument(document);

    expect(restored, contains('## Kop'));
    expect(restored, contains('**vet**'));
    expect(restored, contains('*cursief*'));
    expect(restored, contains('`code`'));
    expect(restored, contains('- item een'));
  });

  test('een GFM-tabel wordt een embed en round-trip\'t byte-getrouw', () {
    const source = '''# Rapport

Inleiding.

| Team | Omzet | Groei |
| --- | ---: | ---: |
| Ontwerp | 120 | 12% |
| Bouw | 340 | 8% |

Afsluiting.''';

    final document = MarkdownQuillCodec.documentFromMarkdown(source);

    // De tabel landt als één blok-embed (x-embed-table), niet als losse woorden.
    final embeds = document
        .toDelta()
        .toList()
        .where((op) => op.data is Map)
        .map((op) => (op.data as Map).keys.first)
        .toList();
    expect(
      embeds,
      contains(EmbeddableTable.tableType),
      reason: 'de tabel moet als embed in het document staan',
    );

    final restored = MarkdownQuillCodec.markdownFromDocument(document);

    // Kop, prosa én de tabel mét kolomuitlijning overleven de reis.
    expect(restored, contains('# Rapport'));
    expect(restored, contains('| Team | Omzet | Groei |'));
    expect(restored, contains('| --- | ---: | ---: |'));
    expect(restored, contains('| Ontwerp | 120 | 12% |'));
    expect(restored, contains('| Bouw | 340 | 8% |'));
    expect(restored, contains('Afsluiting.'));
  });
}
