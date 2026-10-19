import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/markdown_paste_cleanup.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/utils/source_patcher.dart';

String _roundTrip(String source) => MarkdownQuillCodec.markdownFromDocument(
  MarkdownQuillCodec.documentFromMarkdown(normalizeRichTextMarkdown(source)),
);

void main() {
  test('removing one paragraph stays removed when visual edits are saved', () {
    const blocks = [
      'Eerste regel.',
      'Herhaalde regel.',
      'Tweede regel.',
      'Herhaalde regel.',
      'Slotregel.',
    ];
    final original = '# Offerte\n\n${blocks.join('\n\n')}\n';
    final edited = '# Offerte\n\n${[...blocks]..removeAt(1)}';
    final result = patchVisualEdits(
      original: original,
      baseline: _roundTrip(original),
      current: _roundTrip('$edited\n'),
    );
    expect(result, '$edited\n');
  });

  test('removed content is never restored by the visual save patch', () {
    const marker = 'VERVALLENPASSAGE';
    const blocks = [
      'Een gewone VERVALLENPASSAGE in lopende tekst.',
      '**VERVALLENPASSAGE** met vet.',
      '1. VERVALLENPASSAGE in een lijst.',
      '> VERVALLENPASSAGE in een citaat.',
      '|Kolom|Waarde|\n|---|---|\n|VERVALLENPASSAGE|100|',
      'VERVALLENPASSAGE\n---',
      '```\nVERVALLENPASSAGE in code\n```',
    ];
    final failures = <String>[];
    for (final block in blocks) {
      final original = '# Offerte\n\nVooraf.\n\n$block\n\nAchteraf.\n';
      const edited = '# Offerte\n\nVooraf.\n\nAchteraf.\n';
      final result = patchVisualEdits(
        original: original,
        baseline: _roundTrip(original),
        current: _roundTrip(edited),
      );
      if (result.contains(marker)) failures.add(block);
    }
    expect(failures, isEmpty);
  });

  test('deleted prose from a soft-wrapped paragraph stays deleted', () {
    const original =
        '# Offerte\n\nDit is de aanhef\nVERVALLENPASSAGE die weg moet\n'
        'en hier loopt de tekst verder.\n';
    const edited =
        '# Offerte\n\nDit is de aanhef en hier loopt de tekst verder.\n';
    final result = patchVisualEdits(
      original: original,
      baseline: _roundTrip(original),
      current: _roundTrip(edited),
    );
    expect(result, isNot(contains('VERVALLENPASSAGE')));
    expect(_roundTrip(result), _roundTrip(edited));
  });
}
