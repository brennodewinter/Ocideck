/// Reads and writes an OciDeck document's **style** — a `theme:` key in the
/// leading YAML front matter of a plain `.md` — always *byte-surgically*.
///
/// A document is its source verbatim (see [MarkdownDocument]); the style must
/// therefore live in the source itself, as ordinary YAML front matter that
/// Pandoc/Obsidian/GitHub recognise and hide. The red line is byte-faithfulness:
/// a document without a style carries **no** front matter, so opening and saving
/// it unchanged yields identical bytes. Only choosing a style writes a block;
/// choosing "none" removes it again, restoring the plain body.
///
/// Everything here is a pure string transform so it is exhaustively testable
/// apart from the editor. The functions never re-serialise the whole document —
/// they touch only the bytes of the `theme:` line and, when it is the last key,
/// the fences around it. Other front-matter keys a user wrote by hand are
/// preserved verbatim.
library;

import 'dart:collection';

const _fence = '---';

const int kMaxDocumentFields = 100;
const int kMaxDocumentFieldValueLength = 4096;

/// De front-matter-sleutels die het documentpad zelf schrijft.
///
/// Bewust een register en geen losse regexen: zodra er meer dan één sleutel is,
/// heeft het documentpad dezelfde discipline nodig als het deckpad
/// (`front_matter_merge.dart`). Zonder register is er geen pad om een sleutel
/// ooit nog uit bestaande bestanden te krijgen — die blijft er dan tot in
/// lengte van dagen in staan, en de uitgang hoort net zo makkelijk te zijn als
/// de ingang.
///
/// Elke sleutel hier is er een die andere gereedschappen al kennen en
/// uitvoeren: `theme:` (Pandoc, Obsidian, GitHub), `papersize:` en `geometry:`
/// (Pandoc), `reference-location:` (Pandoc/Quarto — waar de voetnoten
/// terechtkomen). OciDeck voegt geen eigen dialect toe — zie FILE_FORMAT.md
/// §14.1.
const Set<String> kDocumentOwnedKeys = {
  'theme',
  'tlp',
  'papersize',
  'geometry',
  'reference-location',
};

/// Sleutels die het documentpad ooit schreef en niet meer schrijft.
///
/// Ze worden bij het volgende bewuste schrijven verwijderd, zodat een
/// ingetrokken sleutel vanzelf uit bestaande bestanden verdwijnt in plaats van
/// er voor altijd in te blijven staan. Leeg zolang er niets is ingetrokken.
const Set<String> kDocumentRetiredKeys = {};

final _documentFieldKey = RegExp(r'^[a-z][a-z0-9_-]*$');
final _doubleQuotedDocumentScalar = RegExp(
  r'^("(?:\\.|[^"\\])*")((?:\s+#.*)?\s*)$',
);
final _singleQuotedDocumentScalar = RegExp(
  r"^('(?:''|[^'])*')((?:\s+#.*)?\s*)$",
);

/// Een eenmaal gelezen frontmatter-snapshot. [MarkdownDocument] bewaart deze
/// zolang alleen de body verandert, zodat typen niet telkens YAML scant.
class DocumentFrontMatterMetadata {
  DocumentFrontMatterMetadata._(this.frontMatter, this.fields, this._values);

  final String frontMatter;
  final DocumentFields fields;
  final Map<String, List<String>> _values;

  List<String> valuesFor(String key) => _values[key] ?? const [];
}

/// Vrije velden met behoud van informatie over dubbele bronregels.
class DocumentFields extends MapBase<String, String> {
  DocumentFields._(Map<String, String> values, this.duplicateValues)
    : _values = Map<String, String>.unmodifiable(values);

  final Map<String, String> _values;
  final Map<String, List<String>> duplicateValues;

  Set<String> get duplicateKeys => duplicateValues.keys.toSet();

  @override
  String? operator [](Object? key) => _values[key];

  @override
  void operator []=(String key, String value) =>
      throw UnsupportedError('documentvelden zijn onveranderlijk');

  @override
  void clear() => throw UnsupportedError('documentvelden zijn onveranderlijk');

  @override
  Iterable<String> get keys => _values.keys;

  @override
  String? remove(Object? key) =>
      throw UnsupportedError('documentvelden zijn onveranderlijk');
}

/// Of [key] de eenvoudige, uitwisselbare sleutelvorm voor documentvelden heeft.
bool isValidDocumentFieldKey(String key) => _documentFieldKey.hasMatch(key);

/// Of [key] door de documentstructuur of door OciDeck zelf wordt beheerd.
bool isReservedDocumentFieldKey(String key) =>
    kDocumentOwnedKeys.contains(key) ||
    kDocumentRetiredKeys.contains(key) ||
    key.startsWith('ocideck_');

/// A document split into its leading front-matter [block] (verbatim, including
/// the blank line(s) that separate it from the body — `''` when there is none)
/// and the [body] that follows. Always `block + body == source`.
typedef DocumentSplit = ({String block, String body});

/// Splits [source] at the end of a well-formed leading YAML front-matter block.
///
/// A block is recognised only when the source opens with a line that is exactly
/// `---` (a trailing `\r` is tolerated for CRLF files) and a later line closes
/// it with another `---`. A `---` with no closing fence is a horizontal rule,
/// not front matter, so the whole source is the body. Trailing blank lines after
/// the closing fence are folded into the block, so the body starts at real
/// content.
DocumentSplit splitDocumentFrontMatter(String source) {
  final firstBreak = source.indexOf('\n');
  if (firstBreak < 0) return (block: '', body: source);
  if (_stripCr(source.substring(0, firstBreak)) != _fence) {
    return (block: '', body: source);
  }
  var i = firstBreak + 1;
  while (i <= source.length) {
    final lineEnd = _lineEnd(source, i);
    final line = _stripCr(source.substring(i, lineEnd));
    final afterLine = lineEnd < source.length ? lineEnd + 1 : lineEnd;
    if (line == _fence) {
      // A closing fence alone isn't enough: `---\n# Kop\n---` (or a lone `---`
      // page break followed by a later `---`) is two horizontal rules, not front
      // matter. Only treat it as front matter when the block actually opens with a
      // YAML key — otherwise the whole source is body, so a `---` divider is safe.
      if (!_opensWithYamlKey(source.substring(firstBreak + 1, i))) {
        return (block: '', body: source);
      }
      var blockEnd = afterLine;
      // Fold any blank (whitespace-only) lines after the closing fence into the
      // block, so the body begins at the first content line.
      while (blockEnd < source.length) {
        final e = _lineEnd(source, blockEnd);
        if (source.substring(blockEnd, e).trim().isNotEmpty) break;
        blockEnd = e < source.length ? e + 1 : e;
      }
      return (
        block: source.substring(0, blockEnd),
        body: source.substring(blockEnd),
      );
    }
    if (lineEnd >= source.length) break; // last line, no closing fence
    i = afterLine;
  }
  return (block: '', body: source);
}

/// The document body — [source] with any leading front-matter block removed.
String documentBody(String source) => splitDocumentFrontMatter(source).body;

/// The style (`theme:` value) declared in the leading front matter, or `null`
/// when the document has no front matter or no `theme:` key. Quotes are removed.
String? documentStyleName(String source) {
  final value = documentFrontMatterValue(source, 'theme');
  return (value == null || value.isEmpty) ? null : value;
}

/// Returns [source] with its document style set to [name], or removed when
/// [name] is `null` or empty.
///
/// Byte-surgical: adding a style to a plain document prepends a minimal block;
/// removing the last key drops the whole block, restoring the exact plain body;
/// other front-matter keys and the body are never touched. A no-op change
/// returns the same bytes.
String withDocumentStyleName(String source, String? name) {
  final split = splitDocumentFrontMatter(source);
  final trimmed = name?.trim() ?? '';

  if (trimmed.isEmpty) {
    if (split.block.isEmpty) return source;
    final without = _removeKeysFromBlock(split.block, {'theme'});
    // `null`: er stond niets anders dan de stijl → het hele blok mag weg.
    return without == null ? split.body : without + split.body;
  }

  return withDocumentFrontMatterKey(source, 'theme', trimmed);
}

/// De waarde van [key] uit de frontmatter van [source], of `null` wanneer de
/// sleutel er niet staat. Alleen voor sleutels die OciDeck zelf schrijft.
String? documentFrontMatterValue(String source, String key) {
  final values = documentFrontMatterMetadata(source).valuesFor(key);
  return values.isEmpty ? null : values.first;
}

DocumentFrontMatterMetadata documentFrontMatterMetadata(String source) {
  final frontMatter = splitDocumentFrontMatter(source).block;
  final values = <String, List<String>>{};
  final fields = <String, String>{};
  final duplicates = <String, List<String>>{};
  if (frontMatter.isNotEmpty) {
    for (final raw in frontMatter.split('\n')) {
      final entry = _topLevelScalarLine(_stripCr(raw));
      if (entry == null) continue;
      values.putIfAbsent(entry.key, () => []).add(entry.value);
      if (!isValidDocumentFieldKey(entry.key) ||
          isReservedDocumentFieldKey(entry.key)) {
        continue;
      }
      final previous = fields[entry.key];
      if (previous == null) {
        fields[entry.key] = entry.value;
      } else {
        duplicates.putIfAbsent(entry.key, () => [previous]).add(entry.value);
      }
    }
  }
  return DocumentFrontMatterMetadata._(
    frontMatter,
    DocumentFields._(
      fields,
      Map.unmodifiable({
        for (final entry in duplicates.entries)
          entry.key: List<String>.unmodifiable(entry.value),
      }),
    ),
    Map<String, List<String>>.unmodifiable({
      for (final entry in values.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    }),
  );
}

/// Alle vrije, platte scalaire documentvelden in volgorde van voorkomen.
///
/// Bij een dubbele sleutel wint de eerste waarde. De dubbeling blijft apart
/// zichtbaar via [documentFieldDuplicateKeys], zodat een aanroeper haar niet
/// stil hoeft te verbergen.
Map<String, String> documentFields(String source) =>
    documentFrontMatterMetadata(source).fields;

/// Vrije scalaire documentveldsleutels die meer dan één keer voorkomen.
Set<String> documentFieldDuplicateKeys(String source) {
  return documentFrontMatterMetadata(source).fields.duplicateKeys;
}

/// Vervangt de volledige verzameling vrije documentvelden byte-chirurgisch.
///
/// Bestaande velden behouden hun plek en spelling wanneer hun waarde niet
/// verandert. Ontbrekende velden worden verwijderd en nieuwe velden komen in
/// de volgorde van [fields] vlak voor de sluitende fence. Structurele,
/// gereserveerde, samengestelde en onbekende regels blijven verbatim staan.
String withDocumentFields(String source, Map<String, String> fields) {
  if (fields.length > kMaxDocumentFields) {
    throw ArgumentError.value(
      fields.length,
      'fields',
      'te veel documentvelden',
    );
  }
  for (final entry in fields.entries) {
    if (!isValidDocumentFieldKey(entry.key) ||
        isReservedDocumentFieldKey(entry.key)) {
      throw ArgumentError.value(entry.key, 'fields', 'ongeldige veldsleutel');
    }
    if (entry.value.contains('\n') || entry.value.contains('\r')) {
      throw ArgumentError.value(
        entry.value,
        entry.key,
        'een documentveld moet één regel blijven',
      );
    }
    if (entry.value.length > kMaxDocumentFieldValueLength) {
      throw ArgumentError.value(
        entry.value.length,
        entry.key,
        'documentveld is te lang',
      );
    }
  }

  final split = splitDocumentFrontMatter(source);
  final eol = _detectEol(source);
  if (split.block.isEmpty) {
    if (fields.isEmpty) return source;
    final lines = [
      _fence,
      for (final entry in fields.entries)
        '${entry.key}: ${_yamlScalar(entry.value)}',
      _fence,
      '',
      '',
    ];
    return lines.join(eol) + split.body;
  }

  final remaining = Map<String, String>.of(fields);
  final written = <String>{};
  final lines = split.block.split('\n');
  final nextLines = <String>[];
  for (final line in lines) {
    final parsed = _documentFieldLine(_stripCr(line));
    if (parsed == null) {
      nextLines.add(line);
      continue;
    }
    final desired = remaining[parsed.key];
    if (desired == null || written.contains(parsed.key)) {
      continue;
    }
    written.add(parsed.key);
    remaining.remove(parsed.key);
    nextLines.add(
      parsed.value == desired
          ? line
          : '${parsed.key}: ${_yamlScalar(desired)}${parsed.commentSuffix}'
                '${_trailingCr(line)}',
    );
  }

  if (remaining.isNotEmpty) {
    final closing = nextLines.lastIndexWhere(
      (line) => _stripCr(line) == _fence,
    );
    final cr = closing >= 0 ? _trailingCr(nextLines[closing]) : '';
    nextLines.insertAll(closing, [
      for (final entry in fields.entries)
        if (remaining.containsKey(entry.key))
          '${entry.key}: ${_yamlScalar(entry.value)}$cr',
    ]);
  }

  final hasContent = nextLines.any((line) {
    final value = _stripCr(line).trim();
    return value.isNotEmpty && value != _fence;
  });
  return hasContent ? nextLines.join('\n') + split.body : split.body;
}

/// Zet [key] op [value], of haalt hem weg bij `null`/leeg.
///
/// Byte-chirurgisch, met dezelfde regels als de stijl: een plat document krijgt
/// een minimaal blok, en valt de laatste eigen sleutel weg dan verdwijnt het
/// hele blok en staat de kale body er weer. Handgeschreven sleutels blijven
/// verbatim staan.
String withDocumentFrontMatterKey(String source, String key, String? value) {
  assert(
    kDocumentOwnedKeys.contains(key),
    'alleen sleutels uit kDocumentOwnedKeys mogen geschreven worden',
  );
  final split = splitDocumentFrontMatter(source);
  final eol = _detectEol(source);
  final trimmed = value?.trim() ?? '';

  if (trimmed.isEmpty) {
    if (split.block.isEmpty) return source;
    final without = _removeKeysFromBlock(split.block, {
      key,
      ...kDocumentRetiredKeys,
    });
    return without == null ? split.body : without + split.body;
  }

  final scalar = _yamlScalar(trimmed);
  if (split.block.isEmpty) {
    return '$_fence$eol$key: $scalar$eol$_fence$eol$eol${split.body}';
  }
  // Een ingetrokken sleutel verdwijnt bij het eerstvolgende bewuste schrijven.
  // Dat is de terugtrekroute die het register belooft: zonder deze regel zou
  // een sleutel die we niet meer schrijven tot in lengte van dagen in bestaande
  // bestanden blijven staan.
  final block = kDocumentRetiredKeys.isEmpty
      ? split.block
      : (_removeKeysFromBlock(split.block, kDocumentRetiredKeys) ??
            split.block);
  return _setKeyInBlock(block, key, scalar) + split.body;
}

// --- block editors -----------------------------------------------------------

/// Replaces the `theme:` line in [block] with `theme: <value>`, or inserts one
/// before the closing fence when absent. Preserves every other line verbatim.
String _setKeyInBlock(String block, String key, String value) {
  final lines = block.split('\n');
  final matcher = _keyLine(key);
  var first = -1;
  for (var i = 0; i < lines.length; i++) {
    if (matcher.hasMatch(_stripCr(lines[i]))) {
      if (first < 0) {
        first = i;
        lines[i] = '$key: $value${_trailingCr(lines[i])}';
      }
    }
  }
  if (first >= 0) {
    for (var i = lines.length - 1; i > first; i--) {
      if (matcher.hasMatch(_stripCr(lines[i]))) lines.removeAt(i);
    }
    return lines.join('\n');
  }
  // Nog geen sleutel: invoegen vóór de sluitende fence (de laatste `---`).
  for (var i = lines.length - 1; i >= 0; i--) {
    if (_stripCr(lines[i]) == _fence) {
      lines.insert(i, '$key: $value${i == 0 ? '' : _trailingCr(lines[i])}');
      return lines.join('\n');
    }
  }
  return block; // defensief: splitDocumentFrontMatter garandeert een fence
}

/// Removes the `theme:` line from [block]. Returns `null` when nothing but the
/// fences (and blank lines) remains, signalling the whole block should be
/// dropped; otherwise the block without its theme line.
String? _removeKeysFromBlock(String block, Set<String> keys) {
  final lines = block.split('\n');
  final matchers = [for (final k in keys) _keyLine(k)];
  lines.removeWhere((l) => matchers.any((m) => m.hasMatch(_stripCr(l))));
  final hasOtherKeys = lines.any((l) {
    final s = _stripCr(l).trim();
    return s.isNotEmpty && s != _fence;
  });
  return hasOtherKeys ? lines.join('\n') : null;
}

// --- small helpers -----------------------------------------------------------

/// Een regel die [key] zet, met de waarde als groep 1.
RegExp _keyLine(String key) => RegExp('^${RegExp.escape(key)}\\s*:\\s*(.*)\$');

/// A YAML mapping key: a name starting with a letter or underscore, then a colon.
/// Deliberately excludes a leading digit (so a stray `12:30` line is not read as
/// a key) and a Markdown heading (`# …`) or bullet.
final _yamlKeyLine = RegExp(r'^\s*[A-Za-z_][\w.\-]*\s*:(\s|$)');

/// Whether [inner] (the lines between the fences) opens like YAML front matter:
/// its first non-blank line is a mapping key. A block whose first real line is a
/// heading, prose or anything else is not front matter — it is `---`-delimited
/// content (e.g. a page break), and must stay in the body verbatim.
bool _opensWithYamlKey(String inner) {
  for (final raw in inner.split('\n')) {
    final line = _stripCr(raw);
    if (line.trim().isEmpty) continue;
    return _yamlKeyLine.hasMatch(line);
  }
  return false;
}

int _lineEnd(String s, int from) {
  final nl = s.indexOf('\n', from);
  return nl < 0 ? s.length : nl;
}

String _stripCr(String line) =>
    line.endsWith('\r') ? line.substring(0, line.length - 1) : line;

String _trailingCr(String line) => line.endsWith('\r') ? '\r' : '';

String _detectEol(String source) => source.contains('\r\n') ? '\r\n' : '\n';

/// A YAML scalar for [s]: bare when safe, else double-quoted with escapes. Keeps
/// plain names (`LibreKAT`) unquoted while making an odd custom name (a colon, a
/// leading dash, surrounding spaces) safe to round-trip.
String _yamlScalar(String s) {
  final needsQuote =
      s.isEmpty ||
      s != s.trim() ||
      // Geen komma in deze lijst: in blokcontext is die in YAML gewoon onderdeel
      // van een platte scalar. Hem toch aanhalen maakte `geometry:
      // top=25mm,bottom=25mm,…` onnodig een string-met-quotes, en dat leest
      // slechter in een bestand dat mensen openslaan.
      RegExp('''[:#\\n"'\\[\\]{}&*!|>%@`]''').hasMatch(s) ||
      RegExp(r'^[-?]').hasMatch(s) ||
      RegExp(
        r'^(?:~|null|true|false|yes|no|on|off|[-+]?(?:0o[0-7_]+|0x[0-9a-f_]+|(?:\d[\d_]*(?:\.[\d_]*)?|\.[\d_]+)(?:e[-+]?\d+)?|\.inf|\.nan)|\d{4}-\d{1,2}-\d{1,2})$',
        caseSensitive: false,
      ).hasMatch(s);
  if (!needsQuote) return s;
  return '"${s.replaceAll('\\', r'\\').replaceAll('"', r'\"')}"';
}

String _unquote(String v) {
  if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
    return v
        .substring(1, v.length - 1)
        .replaceAll(r'\"', '"')
        .replaceAll(r'\\', '\\');
  }
  if (v.length >= 2 && v.startsWith("'") && v.endsWith("'")) {
    return v.substring(1, v.length - 1).replaceAll("''", "'");
  }
  return v;
}

typedef _DocumentFieldEntry = ({
  String key,
  String value,
  String commentSuffix,
});

typedef _DocumentScalar = ({String value, String commentSuffix});

_DocumentFieldEntry? _documentFieldLine(String line) {
  final entry = _topLevelScalarLine(line);
  if (entry == null ||
      !isValidDocumentFieldKey(entry.key) ||
      isReservedDocumentFieldKey(entry.key)) {
    return null;
  }
  return entry;
}

_DocumentFieldEntry? _topLevelScalarLine(String line) {
  if (line.isEmpty || line.startsWith(' ') || line.startsWith('\t')) {
    return null;
  }
  final separator = line.indexOf(':');
  if (separator <= 0) return null;
  final key = line.substring(0, separator);
  final scalar = _plainScalarValue(line.substring(separator + 1));
  return scalar == null
      ? null
      : (key: key, value: scalar.value, commentSuffix: scalar.commentSuffix);
}

_DocumentScalar? _plainScalarValue(String raw) {
  final value = raw.trimLeft();
  if (value.isEmpty ||
      value.startsWith('#') ||
      value.startsWith('|') ||
      value.startsWith('>') ||
      value.startsWith('[') ||
      value.startsWith('{') ||
      value.startsWith('&') ||
      value.startsWith('*') ||
      value.startsWith('!')) {
    return null;
  }
  if (value.startsWith('"') || value.startsWith("'")) {
    final match =
        (value.startsWith('"')
                ? _doubleQuotedDocumentScalar
                : _singleQuotedDocumentScalar)
            .firstMatch(value);
    if (match == null) return null;
    final suffix = match.group(2)!;
    return (
      value: _unquote(match.group(1)!),
      commentSuffix: suffix.trim().isEmpty ? '' : suffix,
    );
  }
  final comment = RegExp(r'\s+#').firstMatch(value);
  return (
    value: _unquote(
      (comment == null ? value : value.substring(0, comment.start)).trim(),
    ),
    commentSuffix: comment == null ? '' : value.substring(comment.start),
  );
}
