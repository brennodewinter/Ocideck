/// Delta-bewerkingen om geplakte Markdown op de Quill-caret te zetten.
///
/// De codec sluit een document af met een kale regelafsluiter. Die is geen
/// inhoud: laat je hem staan, dan breekt de plak de regel onder de caret.
/// Een afsluiter die wél blokopmaak draagt — het vinkje, de streep, de kop —
/// blijft. Die weghalen zette het laatste lijstitem als platte tekst op de
/// regel eronder, of vouwde de lijst samen (#2398).
library;

import 'package:flutter_quill/quill_delta.dart';

import 'markdown_quill_codec.dart';

const _blockAttributeKeys = {'list', 'header', 'blockquote', 'code-block'};

/// De bewerkingen die een plak van [markdown] in de visuele editor invoegt.
List<Operation> operationsForVisualPaste(String markdown) {
  final ops = MarkdownQuillCodec.documentFromMarkdown(
    markdown,
  ).toDelta().toList();
  if (ops.isEmpty) return ops;
  final last = ops.last;
  if (!last.isInsert || last.data is! String) return ops;
  final data = last.data! as String;
  if (!data.endsWith('\n')) return ops;
  if (_carriesBlock(last.attributes)) return ops;
  final trimmed = data.substring(0, data.length - 1);
  if (trimmed.isEmpty) {
    ops.removeLast();
  } else {
    ops[ops.length - 1] = Operation.insert(trimmed, last.attributes);
  }
  return ops;
}

bool _carriesBlock(Map<String, dynamic>? attributes) =>
    attributes != null && attributes.keys.any(_blockAttributeKeys.contains);
