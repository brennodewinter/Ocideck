import '../models/deck.dart';
import '../models/slide.dart';

/// Converteert tussen een plat Markdown-**document** en een getypeerd
/// [Deck]. Twee zuivere, headless functies — bewust hier en niet verspreid over
/// notifiers, omdat de conversie het rondgang- én het projectiecontract raakt
/// (DOCUMENT_MODE.md §7, §11.3).
///
/// De heenweg [documentToDeck] is de spil van het **zero-loss-contract**: élke
/// niet-lege bronregel moet in een getypeerd, gescand dia-veld belanden
/// (`customMarkdown` of `tableRows`), zodat de OciWacht-projectie later niets
/// mist. Daarom bouwt hij de dia's *rechtstreeks* en gebruikt hij bewust **niet**
/// de bestaande `_inferSlideType`, die een kop-geleide sectie stil naar een lege
/// `bullets`-dia laat vallen — precies de dominante documentvorm (§11.3, §11.5).
class DocumentDeckBridge {
  DocumentDeckBridge._();

  /// Deconstrueer een plat document naar getypeerde dia's.
  ///
  /// Per blok, regel voor regel over `body`:
  /// - een **kop** (`# `..`###### `) sluit de lopende flow af en begint een
  ///   nieuwe `freeMarkdown`-accumulator die met de kopregel begint — één dia
  ///   per kop-sectie, zodat de dia-brede escalatie sectie-lokaal blijft;
  /// - een ` ```chart `-fence wordt een aparte [SlideType.chart]-dia (de kale
  ///   binneninhoud, zonder de fence-regels), zodat grafiek-data-hydratatie
  ///   erop van toepassing is;
  /// - een andere fence (` ```mermaid `, ` ```dart `, …) gaat *verbatim*
  ///   (mét fence-regels) in de flow, en wordt zo als tekst gescand;
  /// - een **GFM-pijptabel** (koprij + scheidingsrij) wordt een aparte
  ///   [SlideType.table]-dia met gevulde `tableRows`, zodat de scanner de
  ///   kolomkoppen als context houdt;
  /// - al het overige (prosa, lege regels, een thematische `---`) hoopt op in de
  ///   flow.
  static Deck documentToDeck(
    String body, {
    String? projectPath,
    String title = '',
  }) {
    final lines = body.split('\n');
    final slides = <Slide>[];
    final flow = <String>[];

    void flushFlow() {
      var start = 0;
      var end = flow.length;
      while (start < end && flow[start].trim().isEmpty) {
        start++;
      }
      while (end > start && flow[end - 1].trim().isEmpty) {
        end--;
      }
      if (start < end) {
        slides.add(
          Slide.create(
            SlideType.freeMarkdown,
          ).copyWith(customMarkdown: flow.sublist(start, end).join('\n')),
        );
      }
      flow.clear();
    }

    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();

      // Kop: nieuwe sectie. De kopregel blijft verbatim in het dia-lichaam, dus
      // hij wordt gescand en het niveau overleeft een rondgang.
      if (_isHeading(trimmed)) {
        flushFlow();
        flow.add(line);
        i++;
        continue;
      }

      // Fence: chart apart, elke andere taal verbatim mee in de flow.
      final fence = _fenceOpen(trimmed);
      if (fence != null) {
        final block = <String>[line];
        var j = i + 1;
        var closed = false;
        while (j < lines.length) {
          block.add(lines[j]);
          if (_isFenceClose(lines[j].trim(), fence.marker, fence.length)) {
            closed = true;
            j++;
            break;
          }
          j++;
        }
        if (fence.language == 'chart') {
          flushFlow();
          final inner = block
              .sublist(1, closed ? block.length - 1 : block.length)
              .join('\n');
          slides.add(
            Slide.create(SlideType.chart).copyWith(customMarkdown: inner),
          );
        } else {
          flow.addAll(block);
        }
        i = j;
        continue;
      }

      // GFM-tabel: koprij gevolgd door een scheidingsrij.
      if (_looksLikeTableRow(trimmed) &&
          i + 1 < lines.length &&
          _isTableDelimiter(lines[i + 1].trim())) {
        flushFlow();
        final rawRows = <String>[line];
        var j = i + 2; // sla de koprij en de scheidingsrij over
        while (j < lines.length && _looksLikeTableRow(lines[j].trim())) {
          rawRows.add(lines[j]);
          j++;
        }
        slides.add(
          Slide.create(
            SlideType.table,
          ).copyWith(tableRows: _tableCells(rawRows)),
        );
        i = j;
        continue;
      }

      // Prosa, lege regel, thematische `---`.
      flow.add(line);
      i++;
    }

    flushFlow();
    if (slides.isEmpty) {
      slides.add(Slide.create(SlideType.freeMarkdown));
    }
    return Deck(title: title, slides: slides, projectPath: projectPath);
  }

  /// De omgekeerde weg: serialiseer de dia-lichamen tot één vloeiend document.
  ///
  /// Expliciet lossy op dia-*structuur* (§7): een tabel wordt weer een GFM-tabel,
  /// een chart weer een ` ```chart `-fence, en elk ander type levert zijn
  /// `customMarkdown` — of, als dat leeg is, een korte tekstuele terugval op
  /// titel en bullets, zodat er geen inhoud verdwijnt. Ook de projected-body-
  /// lezer voor het exportpad (§11.2 stap 4).
  static String deckToDocumentMarkdown(Deck deck) {
    final parts = <String>[];
    for (final slide in deck.slides) {
      final body = _slideBody(slide);
      if (body.trim().isNotEmpty) {
        parts.add(body.trim());
      }
    }
    return '${parts.join('\n\n')}\n';
  }
}

/// Het lichaam van één dia als platte Markdown voor [DocumentDeckBridge.deckToDocumentMarkdown].
String _slideBody(Slide slide) {
  switch (slide.type) {
    case SlideType.table:
      return _rowsToGfmTable(slide.tableRows);
    case SlideType.chart:
      return '```chart\n${slide.customMarkdown}\n```';
    default:
      if (slide.customMarkdown.trim().isNotEmpty) {
        return slide.customMarkdown;
      }
      // Leeg lichaam op een niet-freeMarkdown type: val terug op titel + bullets
      // zodat er geen inhoud verloren gaat.
      if (slide.type != SlideType.freeMarkdown) {
        final fallback = <String>[
          if (slide.title.trim().isNotEmpty) '## ${slide.title}',
          for (final b in slide.bullets)
            if (b.trim().isNotEmpty) '- $b',
        ];
        return fallback.join('\n');
      }
      return slide.customMarkdown;
  }
}

/// Serialiseer een celraster (eerste rij = koppen) naar een GFM-pijptabel: een
/// koprij, een scheidingsrij en de body. Een `|` in een cel wordt ontsnapt naar
/// `\|`; ragged rijen worden met lege cellen aangevuld tot de breedste.
///
/// Zuivere kopie van `rowsToGfmTable` uit het editor-scherm (een widget-bestand),
/// bewust hier herhaald: een service mag `lib/widgets/` niet importeren (de
/// laagpoort, `serviceUiImportBaseline`).
String _rowsToGfmTable(List<List<String>> rows) {
  if (rows.isEmpty) return '';
  final cols = rows.fold<int>(1, (m, r) => r.length > m ? r.length : m);
  String cell(List<String> r, int c) =>
      (c < r.length ? r[c] : '').replaceAll('|', r'\|');
  String line(List<String> r) =>
      '| ${List.generate(cols, (c) => cell(r, c)).join(' | ')} |';
  return [
    line(rows.first),
    '| ${List.filled(cols, '---').join(' | ')} |',
    for (final r in rows.skip(1)) line(r),
  ].join('\n');
}

/// De cellen van een GFM-tabelblok (koprij + body, zónder scheidingsrij),
/// ontdaan van pipe-ontsnapping. Zuivere kopie van
/// `DocumentMarkdownView.tableCells`, zodat wat de weergave toont en wat de
/// bridge deconstrueert gelijk zijn — herhaald in plaats van geïmporteerd omdat
/// een service `lib/widgets/` niet mag kennen.
List<List<String>> _tableCells(List<String> rawRows) => rawRows
    .map((r) => _splitTableRow(r).map((c) => c.replaceAll(r'\|', '|')).toList())
    .toList();

/// Splits een tabelrij op onontsnapte `|`, ontdaan van de buitenste pipes, elke
/// cel getrimd. Zuivere kopie van `DocumentMarkdownView._splitTableRow`.
List<String> _splitTableRow(String row) {
  var t = row.trim();
  if (t.startsWith('|')) t = t.substring(1);
  if (t.endsWith('|')) t = t.substring(0, t.length - 1);
  final cells = <String>[];
  final buf = StringBuffer();
  for (var i = 0; i < t.length; i++) {
    final c = t[i];
    if (c == r'\' && i + 1 < t.length) {
      buf.write(c);
      buf.write(t[i + 1]);
      i++;
      continue;
    }
    if (c == '|') {
      cells.add(buf.toString().trim());
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  cells.add(buf.toString().trim());
  return cells;
}

/// Een regel die na trimmen met 1–6 `#` en een spatie begint.
bool _isHeading(String trimmed) => RegExp(r'^#{1,6} ').hasMatch(trimmed);

/// Een regel die als GFM-pijptabelrij leest: bevat een `|` en begint ermee.
bool _looksLikeTableRow(String trimmed) =>
    trimmed.contains('|') && trimmed.startsWith('|');

/// De scheidingsrij onder een tabelkop, bijv. `| --- | :--: |`.
bool _isTableDelimiter(String trimmed) {
  if (!trimmed.contains('-') || !trimmed.contains('|')) return false;
  return RegExp(r'^\|?[\s:|-]+\|?$').hasMatch(trimmed);
}

/// Een geopende fence-regel, ontleed in het markeerteken, de lengte en de taal.
class _FenceInfo {
  final String marker; // '`' of '~'
  final int length;
  final String language;
  const _FenceInfo(this.marker, this.length, this.language);
}

/// Ontleedt een geopende fence (` ``` ` of `~~~`, minstens drie) uit een
/// getrimde regel, of null wanneer de regel geen fence opent.
_FenceInfo? _fenceOpen(String trimmed) {
  final m = RegExp(r'^(`{3,}|~{3,})[ \t]*(\S*)').firstMatch(trimmed);
  if (m == null) return null;
  final run = m.group(1)!;
  return _FenceInfo(run[0], run.length, m.group(2)!.toLowerCase());
}

/// Of een getrimde regel de fence sluit: hetzelfde teken, minstens even lang, en
/// zonder taal erachter.
bool _isFenceClose(String trimmed, String marker, int length) => RegExp(
  '^${RegExp.escape(marker)}{$length,}[ \\t]*\$',
).hasMatch(trimmed);
