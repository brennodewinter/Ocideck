import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/pdf/document_pdf_blocks.dart';

void main() {
  test('PDF-tussenmodel houdt waarde, diagnose en beide beeldvormen vast', () {
    const plain = PdfSpan('tekst');
    final marked = plain.copyWith(
      bold: true,
      italic: true,
      strikeThrough: true,
      code: true,
      href: 'https://example.test',
      superscript: true,
      math: true,
    );
    expect(marked, equals(marked.copyWith()));
    expect(marked.hashCode, marked.copyWith().hashCode);
    expect(marked, isNot(plain));
    expect(marked.toString(), contains('href=https://example.test'));

    final blocks = <PdfBlock>[
      const PdfHeadingBlock(2, [plain], 'Kop'),
      const PdfParagraphBlock([plain]),
      const PdfListBlock([PdfListItem([])], ordered: true, startNumber: 3),
      const PdfTimelineBlock(
        ['Tijd', 'Gebeurtenis'],
        [
          PdfTimelineEvent([plain], [plain], metadata: [plain]),
        ],
      ),
      const PdfQuoteBlock([]),
      const PdfCodeBlock('code', language: 'dart'),
      const PdfTableBlock([], hasHeader: true),
      const PdfImageBlock('beeld.png', alt: 'beeld'),
      const PdfPageBreakBlock(),
      const PdfTocBlock(),
      const PdfVerbatimBlock('x', kind: PdfVerbatimKind.math),
    ];
    for (final block in blocks) {
      expect(block.toString(), isNotEmpty);
    }

    const svg = PdfRenderedGraphic.svg(
      '<svg/>',
      naturalWidth: 12,
      naturalHeight: 8,
    );
    final image = PdfRenderedGraphic.image(
      Uint8List.fromList([1, 2, 3]),
      naturalWidth: 12,
      naturalHeight: 8,
    );
    expect(svg.toString(), contains('svg'));
    expect(image.toString(), contains('image'));
  });
}
