import 'package:flutter_test/flutter_test.dart';
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
}
