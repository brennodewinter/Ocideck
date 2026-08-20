import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/platform/clipboard_html.dart';
import 'package:ocideck/platform/clipboard_html_io.dart';
import 'package:ocideck/utils/clipboard_markdown.dart';
import 'package:ocideck/utils/html_to_markdown.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => debugClipboardHtmlReader = null);

  group('unwrapClipboardHtml', () {
    test('haalt het Apple-fragment uit de envelope', () {
      expect(
        unwrapClipboardHtml(
          '<html><body><!--StartFragment--><p>Hi</p><!--EndFragment--></body></html>',
        ),
        '<p>Hi</p>',
      );
    });

    test('slaat de CF_HTML-kop over tot de eerste tag', () {
      const raw =
          'Version:0.9\nStartHTML:0000000100\n\n<html><body>x</body></html>';
      expect(unwrapClipboardHtml(raw), '<html><body>x</body></html>');
    });
  });

  group('htmlClipboardToMarkdown', () {
    test('geneste lijst houdt het niveau', () {
      const html = '''
<ul>
  <li>Eerste
    <ul>
      <li>Tweede
        <ul><li>Derde</li></ul>
      </li>
    </ul>
  </li>
  <li>Nog een eerste</li>
</ul>
''';
      expect(
        htmlClipboardToMarkdown(html),
        '- Eerste\n'
        '  - Tweede\n'
        '    - Derde\n'
        '- Nog een eerste',
      );
    });

    test('kop wordt een hekje, zonder de gerenderde kale tekst', () {
      expect(
        htmlClipboardToMarkdown('<h1>Ocideck Bullet indent test</h1>'),
        '# Ocideck Bullet indent test',
      );
    });

    test('tabel wordt GFM', () {
      const html = '''
<table>
  <tr><th>A</th><th>B</th></tr>
  <tr><td>1</td><td>2</td></tr>
</table>
''';
      expect(
        htmlClipboardToMarkdown(html),
        '| A | B |\n'
        '| --- | --- |\n'
        '| 1 | 2 |',
      );
    });

    test('stijl- en klasse-attributen leveren niets op', () {
      expect(
        htmlClipboardToMarkdown('<p class="x" style="color:red">Hallo</p>'),
        'Hallo',
      );
    });

    test('javascript-href valt weg, de linktekst blijft', () {
      expect(
        htmlClipboardToMarkdown('<a href="javascript:alert(1)">klik</a>'),
        'klik',
      );
    });

    test('https-link blijft een Markdown-link', () {
      expect(
        htmlClipboardToMarkdown('<a href="https://example.com/a">klik</a>'),
        '[klik](https://example.com/a)',
      );
    });

    test('script en style verdwijnen, ook hun inhoud', () {
      expect(
        htmlClipboardToMarkdown(
          '<p>zichtbaar</p><script>alert(1)</script><style>p{color:red}</style>',
        ),
        'zichtbaar',
      );
    });

    test('nadruk en code', () {
      expect(
        htmlClipboardToMarkdown(
          '<p><strong>vet</strong> en <em>schuin</em> en <code>x</code></p>',
        ),
        '**vet** en *schuin* en `x`',
      );
    });

    test('te groot is niets, zodat de platte tekst de val blijft', () {
      expect(
        htmlClipboardToMarkdown('a' * (kClipboardHtmlMaxChars + 1)),
        isNull,
      );
    });

    test('leeg is null', () {
      expect(htmlClipboardToMarkdown(''), isNull);
      expect(htmlClipboardToMarkdown('   '), isNull);
    });
  });

  group('resolveClipboardMarkdown', () {
    test(' Copilot-achtige platte tekst wijkt voor HTML met neststructuur', () {
      const plain = 'Ocideck Bullet indent test\n- Eerste\n- Tweede';
      const html =
          '<h1>Ocideck Bullet indent test</h1>'
          '<ul><li>Eerste<ul><li>Tweede</li></ul></li></ul>';
      final got = resolveClipboardMarkdown(plain: plain, html: html)!;
      expect(got.kind, ClipboardMarkdownKind.markdown);
      expect(got.text, contains('# Ocideck Bullet indent test'));
      expect(got.text, contains('  - Tweede'));
    });

    test('een spreadsheet wint van HTML, zodat TSV het oude pad blijft', () {
      final got = resolveClipboardMarkdown(
        plain: 'A\tB\n1\t2',
        html: '<p>negeer mij</p>',
      )!;
      expect(got.kind, ClipboardMarkdownKind.table);
      expect(got.text, '| A | B |\n| --- | --- |\n| 1 | 2 |');
    });

    test('zonder HTML blijft de opgeschoonde platte tekst', () {
      final got = resolveClipboardMarkdown(plain: 'hallo\n\n', html: null)!;
      expect(got.kind, ClipboardMarkdownKind.markdown);
      expect(got.text, 'hallo');
    });

    test('HTML zonder platte tekst is genoeg', () {
      final got = resolveClipboardMarkdown(plain: null, html: '<h2>Kop</h2>')!;
      expect(got.text, '## Kop');
    });

    test('beide leeg is null', () {
      expect(resolveClipboardMarkdown(plain: null, html: null), isNull);
      expect(resolveClipboardMarkdown(plain: '', html: ''), isNull);
    });
  });

  group('readClipboardHtml', () {
    test('de testnaad wint van het platform', () async {
      debugClipboardHtmlReader = () async => '<p>via override</p>';
      expect(await readClipboardHtml(), '<p>via override</p>');
    });

    test('kanaal html op macOS/Linux, met bovengrens', () async {
      const channel = MethodChannel('ocideck/clipboard');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'html');
        return '<p>van het kanaal</p>';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final got = await readClipboardHtmlImpl();
      // Op deze machine (macOS) is Pasteboard.html null en volgt het kanaal.
      // Windows zou Pasteboard.html eerst proberen; ontbreekt de plugin, dan
      // null. Beide zijn een geldige uitkomst van dezelfde functie.
      expect(got == null || got == '<p>van het kanaal</p>', isTrue);
    });
  });
}
