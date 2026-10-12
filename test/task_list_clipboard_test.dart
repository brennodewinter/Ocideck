import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/clipboard_markdown.dart';
import 'package:ocideck/utils/html_to_markdown.dart';
import 'package:ocideck/utils/markdown_paste_cleanup.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/utils/source_patcher.dart';
import 'package:ocideck/utils/visual_paste_delta.dart';
import 'package:ocideck/utils/visual_selection_markdown.dart';

/// Regressie #2398: knippen en plakken van een taaklijst verloor de vinkjes,
/// en opslaan zette er soms een lege `- [ ]`-regel naast.
void main() {
  String roundTrip(String source) => MarkdownQuillCodec.markdownFromDocument(
    MarkdownQuillCodec.documentFromMarkdown(normalizeRichTextMarkdown(source)),
  );

  test('HTML-taaklijst houdt een regel en een vinkje per item', () {
    const html = '''
<ul>
<li><input type="checkbox"> een</li>
<li><input type="checkbox" checked> twee</li>
</ul>
''';
    expect(htmlClipboardToMarkdown(html), '- [ ] een\n- [x] twee');
  });

  test('een vinkje in een alinea van een los item blijft een vinkje', () {
    const html =
        '<ul><li><p><input type="checkbox" checked> klaar</p></li></ul>';
    expect(htmlClipboardToMarkdown(html), '- [x] klaar');
  });

  test(
    'platte taaklijst wint van HTML die de vinkjes en de regels verliest',
    () {
      const plain = '- [ ] een\n- [ ] twee';
      const html = '<p>een twee</p>';
      final got = resolveClipboardMarkdown(plain: plain, html: html)!;
      expect(got.text, '- [ ] een\n- [ ] twee');
    },
  );

  test('HTML met evenveel lijstregels blijft winnen van platte tekst', () {
    const plain = 'Ocideck Bullet indent test\n- Eerste\n- Tweede';
    const html =
        '<h1>Ocideck Bullet indent test</h1>'
        '<ul><li>Eerste<ul><li>Tweede</li></ul></li></ul>';
    final got = resolveClipboardMarkdown(plain: plain, html: html)!;
    expect(got.text, contains('  - Tweede'));
  });

  test('plak-delta houdt het vinkje van elk item', () {
    final ops = operationsForVisualPaste('- [ ] een\n- [ ] twee');
    final lists = [
      for (final op in ops)
        if (op.attributes?['list'] != null) op.attributes!['list'],
    ];
    expect(lists, ['unchecked', 'unchecked']);
  });

  test('selectie van een taaklijst kopieert de vinkjes per regel', () {
    final doc = MarkdownQuillCodec.documentFromMarkdown(
      '- [ ] een\n- [ ] twee\n',
    );
    // Platte tekst heeft de vinkjes niet — dat is precies het gat.
    expect(doc.getPlainText(0, doc.length), isNot(contains('[ ]')));

    final payload = visualClipboardPayload(doc, 0, doc.length)!;
    expect(payload.markdown, '- [ ] een\n- [ ] twee');
  });

  test('een deel van een woord krijgt geen vinkje', () {
    final doc = MarkdownQuillCodec.documentFromMarkdown('- [ ] een twee\n');
    // "een twee" — "wee" begint ná de regelstart.
    final payload = visualClipboardPayload(doc, 5, 8)!;
    expect(payload.markdown, 'wee');
    expect(payload.markdown, isNot(contains('[')));
  });

  test('knippen van een hele taakregel wist de regelafsluiter mee', () {
    final doc = MarkdownQuillCodec.documentFromMarkdown(
      '- [ ] een\n- [ ] twee\n',
    );
    // "een" zonder de regelafsluiter: die draagt het vinkje. Hem laten staan
    // maakt na het wissen een lege `- [ ]`.
    final payload = visualClipboardPayload(doc, 0, 3)!;
    expect(payload.markdown, '- [ ] een');
    expect(payload.end, 4);

    doc.delete(payload.start, payload.end - payload.start);
    final left = MarkdownQuillCodec.markdownFromDocument(doc);
    expect(left, isNot(contains('- [ ] \n')));
    expect('- [ ]'.allMatches(left).length, 1);
    expect(left, contains('- [ ] twee'));
  });

  test('opslaan naast een taaklijst voegt geen extra vinkje toe', () {
    const original = '# Notitie\n\n- bullet\n- [ ] taak\n\nTekst.\n';
    final baseline = roundTrip(original);
    expect('- [ ]'.allMatches(baseline).length, 1);
    final current = roundTrip(
      '# Notitie\n\n- bullet\n- [ ] taak\n\nGewijzigde tekst.\n',
    );
    final result = patchVisualEdits(
      original: original,
      baseline: baseline,
      current: current,
    );
    expect('- [ ]'.allMatches(result).length, 1);
    expect(result, contains('- bullet'));
    expect(result, contains('Gewijzigde tekst.'));
    expect(result, isNot(contains('\nTekst.')));
  });
}
