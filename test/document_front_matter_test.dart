import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/document_front_matter.dart';

void main() {
  group('splitDocumentFrontMatter', () {
    test('plain body → no block', () {
      const src = '# Titel\n\nTekst.';
      final s = splitDocumentFrontMatter(src);
      expect(s.block, '');
      expect(s.body, src);
    });

    test(
      'leading --- without a closing fence is a horizontal rule, not fm',
      () {
        const src = '---\n\nEen scheidingslijn, geen front matter.';
        final s = splitDocumentFrontMatter(src);
        expect(s.block, '');
        expect(s.body, src);
      },
    );

    test(
      'valid block splits off, trailing blank line folded into the block',
      () {
        const src = '---\ntheme: Europa\n---\n\n# Titel\n\nTekst.';
        final s = splitDocumentFrontMatter(src);
        expect(s.block, '---\ntheme: Europa\n---\n\n');
        expect(s.body, '# Titel\n\nTekst.');
        expect(s.block + s.body, src);
      },
    );

    test('CRLF block splits and reassembles byte-exact', () {
      const src = '---\r\ntheme: Europa\r\n---\r\n\r\n# Titel\r\n';
      final s = splitDocumentFrontMatter(src);
      expect(s.block + s.body, src);
      expect(s.body, '# Titel\r\n');
    });
  });

  group('documentStyleName', () {
    test('null without front matter', () {
      expect(documentStyleName('# Titel\n'), isNull);
    });
    test('null when front matter has no theme', () {
      expect(documentStyleName('---\ntitle: Memo\n---\n\nx'), isNull);
    });
    test('reads a bare value', () {
      expect(documentStyleName('---\ntheme: LibreKAT\n---\n\nx'), 'LibreKAT');
    });
    test('reads a quoted value among other keys', () {
      const src = '---\ntitle: Memo\ntheme: "Mijn stijl"\n---\n\nx';
      expect(documentStyleName(src), 'Mijn stijl');
    });
  });

  group('withDocumentStyleName', () {
    const plain = '# Titel\n\nTekst.';

    test('adds a block to a plain document', () {
      final out = withDocumentStyleName(plain, 'LibreKAT');
      expect(out, '---\ntheme: LibreKAT\n---\n\n# Titel\n\nTekst.');
      expect(documentStyleName(out), 'LibreKAT');
    });

    test('set then clear restores the exact plain bytes (byte-faithful)', () {
      final set = withDocumentStyleName(plain, 'Security');
      final cleared = withDocumentStyleName(set, null);
      expect(cleared, plain);
    });

    test('clearing on a plain document is a no-op', () {
      expect(withDocumentStyleName(plain, null), plain);
      expect(withDocumentStyleName(plain, ''), plain);
    });

    test('replaces an existing theme value, preserving other keys', () {
      const src = '---\ntitle: Memo\ntheme: Europa\n---\n\nx';
      final out = withDocumentStyleName(src, 'Security');
      expect(out, '---\ntitle: Memo\ntheme: Security\n---\n\nx');
    });

    test('inserts a theme into a block that had none, keeping other keys', () {
      const src = '---\ntitle: Memo\n---\n\nx';
      final out = withDocumentStyleName(src, 'Europa');
      expect(documentStyleName(out), 'Europa');
      expect(out.contains('title: Memo'), isTrue);
      expect(out.endsWith('\n\nx'), isTrue);
    });

    test('removing theme keeps a block that has other keys', () {
      const src = '---\ntitle: Memo\ntheme: Europa\n---\n\nx';
      final out = withDocumentStyleName(src, null);
      expect(out, '---\ntitle: Memo\n---\n\nx');
      expect(documentStyleName(out), isNull);
    });

    test('a name needing quotes round-trips through set→read', () {
      const tricky = 'Blauw: donker #1';
      final out = withDocumentStyleName(plain, tricky);
      expect(out.contains('theme: "Blauw: donker #1"'), isTrue);
      expect(documentStyleName(out), tricky);
    });

    test('CRLF document gets a CRLF block', () {
      const src = '# Titel\r\n\r\nTekst.\r\n';
      final out = withDocumentStyleName(src, 'Europa');
      expect(out.startsWith('---\r\ntheme: Europa\r\n---\r\n\r\n'), isTrue);
      expect(withDocumentStyleName(out, null), src);
    });

    test('documentBody drops the block', () {
      final set = withDocumentStyleName(plain, 'LibreKAT');
      expect(documentBody(set), plain);
    });
  });
}
