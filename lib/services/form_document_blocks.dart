// Formulierblokken in een document: waar ze liggen, en hoe OciDeck's eigen
// oppervlakken ze behandelen (FORM_INTAKE.md §4.9).
//
// Een formulier is een gewoon document met HTML-commentaar-markers. Voor *andere*
// Markdown-lezers is dat onzichtbaar; voor OciDeck's lezer en visuele editor niet
// — een `<!-- field … -->`-regel zou als alinea verschijnen en de visuele editor
// uitzetten (`rawHtml`). Daarom reist een formulier door dezelfde keten als het
// pentestblok (PENTEST_DOCUMENT.md §5.4): de grens van een blok woont op één plek
// (`packages/ocideck_form_core`, `formBlockLength`), deze service legt hem naast
// een heel document, en de lezer, de Quill-codec, de visuele poort en de exports
// vragen het hier.
//
// **Alleen een geldig formulier telt.** De blokken worden afgeleid uit
// `parseForm`: een formulier waarvan de structuur niet klopt (een niet-gesloten
// veld, een dubbele id) levert géén atomaire bereiken op. Dat is bedoeld — een
// half gesloopt formulier hoort zichtbaar kapot te zijn: de visuele editor valt
// terug op brontekst en toont de ruwe markers, zodat de auteur ze kan herstellen.
// Stil iets verliezen zou erger zijn (PENTEST_DOCUMENT.md §5.5).
//
// Zuiver Dart, geen Flutter: testbaar zonder widgets.

import 'package:ocideck_form_core/ocideck_form_core.dart';

/// Eén atomair blok: het bereik `[start, end)` van 0-gebaseerde regelindices.
class FormDocBlock {
  const FormDocBlock(this.kind, this.start, this.end);

  final FormBlockKind kind;

  /// Eerste regel, inclusief.
  final int start;

  /// Eerste regel ná het blok.
  final int end;
}

/// De formulierblokken van één brontekst, in documentvolgorde.
class FormBlockScan {
  const FormBlockScan(this.blocks, this._markerLines, this._lineToBlock);

  /// Geen formulier: de uitkomst voor elk gewoon document.
  static const none = FormBlockScan([], <int>{}, <int, int>{});

  final List<FormDocBlock> blocks;
  final Set<int> _markerLines;
  final Map<int, int> _lineToBlock;

  bool get isEmpty => blocks.isEmpty;

  /// Of regel [line] (0-gebaseerd) bij een atomair blok hoort.
  bool isAtomicLine(int line) => _lineToBlock.containsKey(line);

  FormDocBlock? blockAt(int line) {
    final i = _lineToBlock[line];
    return i == null ? null : blocks[i];
  }

  /// De regels die alleen structuur zijn (de markers) en niet getoond worden.
  Set<int> get markerLines => _markerLines;
}

// Eén memo-slot op tekstidentiteit, zoals `scanPentestBlocks`: de visuele poort
// vraagt dit per toetsaanslag en de editor bouwt meerdere keren per frame.
String? _memoSource;
FormBlockScan? _memoScan;

final RegExp _mentionsForm = RegExp(r'<!--[ \t]*form\b');

/// Legt de formulierblokken van [source] vast. Een document zonder `form`-marker
/// kost één regex-pas; een geldig formulier één `parseForm`.
FormBlockScan scanFormBlocks(String source) {
  final memo = _memoScan;
  if (memo != null &&
      (identical(source, _memoSource) || source == _memoSource)) {
    return memo;
  }
  final scan = _scan(source);
  _memoSource = source;
  _memoScan = scan;
  return scan;
}

FormBlockScan _scan(String source) {
  if (!_mentionsForm.hasMatch(source)) return FormBlockScan.none;
  final parsed = parseForm(source);
  if (parsed is! ParsedForm) return FormBlockScan.none;

  final spec = parsed.spec;
  final blocks = <FormDocBlock>[];
  final markers = <int>{};

  void add(FormBlockKind kind, int firstLine, int lastLine) {
    blocks.add(FormDocBlock(kind, firstLine - 1, lastLine));
  }

  add(FormBlockKind.header, spec.formMarker.line, spec.formMarker.line);
  markers.add(spec.formMarker.line - 1);
  final notice = spec.notice;
  final fields = spec.fields;
  // Documentvolgorde: de notice kan voor, tussen of na de velden staan.
  final entries = <(int, void Function())>[
    if (notice != null)
      (
        notice.open.line,
        () {
          add(FormBlockKind.notice, notice.open.line, notice.close.line);
          markers
            ..add(notice.open.line - 1)
            ..add(notice.close.line - 1);
        },
      ),
    for (final f in fields)
      (
        f.open.line,
        () {
          add(FormBlockKind.field, f.open.line, f.close.line);
          markers
            ..add(f.open.line - 1)
            ..add(f.answer.line - 1)
            ..add(f.close.line - 1);
        },
      ),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  for (final entry in entries) {
    entry.$2();
  }
  // (De kop staat per definitie vooraan en de ingangen zijn gesorteerd, dus
  // `blocks` ligt al in documentvolgorde.)

  final lineToBlock = <int, int>{};
  for (var i = 0; i < blocks.length; i++) {
    for (var line = blocks[i].start; line < blocks[i].end; line++) {
      lineToBlock[line] = i;
    }
  }
  return FormBlockScan(blocks, markers, lineToBlock);
}

/// [source] zonder de markerregels van een geldig formulier: elke markerregel
/// wordt een lege regel, zodat het aantal regels — en dus elke index in de lezer
/// — gelijk blijft. Label, richtlijn en antwoord blijven gewone tekst.
///
/// Voor de weergave en voor de exports die een formulier als document tonen
/// (HTML, PDF, DOCX, …). De `.md`-export en de opslag raken dit nooit: de
/// markers zijn bronbezit.
String stripFormMarkers(String source) {
  final scan = scanFormBlocks(source);
  if (scan.isEmpty) return source;
  final lines = source.split('\n');
  for (final i in scan.markerLines) {
    if (i >= lines.length) continue;
    lines[i] = lines[i].endsWith('\r') ? '\r' : '';
  }
  return lines.join('\n');
}
