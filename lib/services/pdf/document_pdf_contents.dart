import 'document_pdf_blocks.dart';
import 'document_pdf_links.dart';

/// Isolates generated contents and structural indexes of forward heading links.
List<PdfBlock> paginatePdfContents(List<PdfBlock> blocks) {
  final headings = <String, int>{};
  final names = pdfHeadingLinks(
    blocks.whereType<PdfHeadingBlock>().map((b) => b.outlineText),
  );
  var heading = 0;
  for (var i = 0; i < blocks.length; i++) {
    if (blocks[i] is PdfHeadingBlock) {
      headings['ocideck-kop-${heading++}'] = i;
    }
  }
  final result = <PdfBlock>[];
  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i];
    if (block is PdfTocBlock && names.isNotEmpty) {
      // Een titel direct vóór de marker hoort bij de inhoudsopgave.
      if (result.lastOrNull is PdfHeadingBlock) {
        final title = result.removeLast();
        _break(result);
        result.add(title);
      } else {
        _break(result);
      }
      result.add(block);
      _break(result);
    } else if (block is PdfHeadingBlock &&
        i + 1 < blocks.length &&
        _isForwardIndex(blocks[i + 1], i + 1, names, headings)) {
      _break(result);
      result.addAll([block, blocks[++i]]);
      _break(result);
    } else if (block is PdfPageBreakBlock) {
      _break(result);
    } else {
      result.add(block);
    }
  }
  if (result.lastOrNull is PdfPageBreakBlock) result.removeLast();
  return result;
}

bool _isForwardIndex(
  PdfBlock block,
  int at,
  Map<String, String> names,
  Map<String, int> headings,
) {
  if (block is! PdfListBlock || block.items.length < 2) return false;
  var previous = at;
  for (final item in block.items) {
    if (item.blocks.length != 1 || item.blocks.single is! PdfParagraphBlock) {
      return false;
    }
    final spans = (item.blocks.single as PdfParagraphBlock).spans;
    final hrefs = spans
        .where((s) => s.text.trim().isNotEmpty)
        .map((s) => s.href)
        .toSet();
    if (hrefs.length != 1) return false;
    final href = hrefs.single;
    if (href == null || !href.startsWith('#')) return false;
    final target = headings[pdfFragmentDestination(href, names)];
    if (target == null || target <= previous) return false;
    previous = target;
  }
  return true;
}

void _break(List<PdfBlock> blocks) {
  if (blocks.isNotEmpty && blocks.last is! PdfPageBreakBlock) {
    blocks.add(const PdfPageBreakBlock());
  }
}
