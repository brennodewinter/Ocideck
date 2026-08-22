import 'dart:math' as math;

import '../models/deck.dart';
import '../models/slide.dart';
import '../utils/markdown_blocks.dart';
import 'markdown_table_codec.dart';
import 'pentest_blocks.dart';
import 'document_timeline.dart';

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
    TlpLevel tlp = TlpLevel.none,
    Map<String, String> fields = const {},
  }) {
    final lines = body.split('\n');
    final rawLines = _ExactLineRanges(body);
    // Eén pas voor het hele document; de grensregel woont in `pentest_blocks`
    // en niet hier (PENTEST_DOCUMENT.md §6.1).
    final pentest = scanPentestBlocks(body);

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

      // De tijdlijnmarker en zijn direct volgende GFM-tabel zijn één atomair
      // blok. `customMarkdown` bewaart de rauwe bron voor de documentrondgang;
      // `tableRows` houdt dezelfde inhoud beschikbaar voor tabelweergave en
      // OciWacht-kolomcontext. De marker los in flow zetten zou bij terugkeer
      // een lege regel invoegen en daarmee zijn betekenis verliezen.
      if (isDocumentTimelineEnvelope(
        line,
        i + 1 < lines.length ? lines[i + 1] : null,
        i + 2 < lines.length ? lines[i + 2] : null,
      )) {
        flushFlow();
        var j = i + 3;
        while (j < lines.length && isMarkdownTableLine(lines[j])) {
          j++;
        }
        slides.add(_markedTableSlide(rawLines, lines, i, j));
        i = j;
        continue;
      }

      // Een pentest-envelop is één atomair blok. Deze tak staat vóór de
      // kop-tak; zie [_pentestEnvelopeSlide] voor waarom die volgorde het punt
      // is.
      final block = pentest.blockAt(i);
      if (block != null && block.start == i) {
        flushFlow();
        slides.add(_pentestEnvelopeSlide(block, rawLines, lines));
        i = block.end;
        continue;
      }

      // Kop: nieuwe sectie. De kopregel blijft verbatim in het dia-lichaam, dus
      // hij wordt gescand en het niveau overleeft een rondgang.
      if (_isHeading(trimmed)) {
        flushFlow();
        flow.add(line);
        i++;
        continue;
      }

      // Fence: chart apart, elke andere taal verbatim mee in de flow.
      final fence = markdownFenceOpen(trimmed);
      if (fence != null) {
        final block = <String>[line];
        var j = i + 1;
        var closed = false;
        while (j < lines.length) {
          block.add(lines[j]);
          if (fence.closes(lines[j].trim())) {
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
      if (isMarkdownTableLine(trimmed) &&
          i + 1 < lines.length &&
          isMarkdownTableDelimiterRow(lines[i + 1].trim())) {
        flushFlow();
        var j = i + 2;
        while (j < lines.length && isMarkdownTableLine(lines[j].trim())) {
          j++;
        }
        slides.add(_plainTableSlide(lines.sublist(i, j)));
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
    return _documentDeck(
      slides,
      title: title,
      projectPath: projectPath,
      tlp: tlp,
      fields: fields,
    );
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
      // Een render-kopie heeft geen gedaante in het bestandsformaat: hij draagt
      // de héle body en verschilt alleen in [Slide.renderPage]. Dezelfde regel
      // die `MarkdownService` al opschrijft — `expandRichTextForRender` levert
      // een lijst om te *tekenen*, nooit om weg te schrijven — en dit is de
      // tweede schrijver. Het exportpad klapt sinds #1589 al niet meer uit
      // (`expandPages: false`); deze regel houdt de belofte overeind voor elke
      // andere aanroeper, zoals "omzetten naar document" op een deck dat wél
      // uitgeklapt is aangeleverd.
      if (slide.renderPage != 0) continue;
      final body = _slideBody(slide);
      if (body.trim().isNotEmpty) {
        final atomicTimeline = startsWithDocumentTimelineEnvelope(body);
        parts.add(atomicTimeline ? body : body.trim());
      }
    }
    return '${parts.join('\n\n')}\n';
  }
}

Deck _documentDeck(
  List<Slide> slides, {
  required String title,
  required String? projectPath,
  required TlpLevel tlp,
  required Map<String, String> fields,
}) => Deck(
  title: fields['title'] ?? title,
  author: fields['author'] ?? '',
  description: fields['subtitle'] ?? '',
  documentFields: fields,
  slides: slides,
  projectPath: projectPath,
  tlp: tlp,
);

/// Levert exacte bronregels inclusief hun interne LF/CRLF-scheidingen.
///
/// De offsetindex ontstaat lui: gewone documenten zonder tijdlijn betalen niet
/// voor een tweede lijst naast de reeds gesplitste parserregels.
class _ExactLineRanges {
  _ExactLineRanges(this.source);

  final String source;
  List<int>? _starts;

  String slice(int start, int end) {
    final starts = _starts ??= _index();
    var endOffset = end < starts.length ? starts[end] - 1 : source.length;
    // Bij CRLF hoort de CR bij dezelfde regelscheiding als de LF. Interne
    // scheidingen blijven staan; alleen die ná de laatste rij hoort niet bij
    // het atomaire blok.
    if (endOffset > starts[start] && source.codeUnitAt(endOffset - 1) == 13) {
      endOffset--;
    }
    return source.substring(starts[start], endOffset);
  }

  List<int> _index() {
    final result = <int>[0];
    for (var offset = 0; offset < source.length; offset++) {
      if (source.codeUnitAt(offset) == 10) result.add(offset + 1);
    }
    return result;
  }
}

/// Eén `table`-dia uit een kale GFM-tabel.
///
/// Koprij + scheidingsrij + body: de codec leest de per-kolomuitlijning uit de
/// scheidingsrij (en laat die daarna weg), zodat een office-tabel zijn
/// uitlijning door de deconstructie én de rondgang behoudt.
///
/// Top-level en geen methode: hij raakt geen enkel veld van
/// [DocumentDeckBridge], en `documentToDeck` zit tegen zijn lengteplafond.
Slide _plainTableSlide(List<String> tableLines) {
  final decoded = decodeMarkdownTableWithAlignment(tableLines);
  return Slide.create(SlideType.table).copyWith(
    tableRows: decoded.rows,
    tableColumnAlignments: decoded.alignments,
  );
}

/// Eén atomaire dia voor een gemarkeerde tabel: de rauwe bron met haar marker,
/// plus de rijen als schaduwstructuur.
///
/// De marker mag niet losgemaakt worden en de tabel niet genormaliseerd — ook
/// niet wanneer de tabel nog onbruikbaar is. De visuele editor laat de gebruiker
/// zo'n tabel herstellen; de brug hoort daar niet op vooruit te lopen. De
/// `tableRows` zijn er voor OciWacht: de uitvoer blijft de rauwe
/// `customMarkdown`, maar kolomkopcontext en bulkregels moeten beschikbaar
/// blijven.
///
/// Top-level en geen methode: hij raakt geen enkel veld van [DocumentDeckBridge],
/// en `documentToDeck` zit tegen zijn lengteplafond.
Slide _markedTableSlide(
  _ExactLineRanges rawLines,
  List<String> lines,
  int start,
  int end,
) => Slide.create(SlideType.freeMarkdown).copyWith(
  customMarkdown: rawLines.slice(start, end),
  tableRows: decodeMarkdownTableRows(lines.sublist(start + 1, end)),
);

/// Eén atomaire dia voor een pentest-envelop (PENTEST_DOCUMENT.md §6).
///
/// **Waarom de envelop-tak vóór de kopsplitsing staat.** Zonder hem knipt die
/// splitsing een bevinding op elke `#### Description` in stukken, en dan
/// verliest de scanner de samenhang tussen de kop van de bevinding — waar het
/// scope-object en de CVSS staan — en de tekst eronder.
///
/// **Waarom het een `freeMarkdown`-dia blijft en nog geen `SlideType.finding`.**
/// `_slideBody` schrijft voor een tabelgedragen type zowel de `customMarkdown`
/// als de her-gecodeerde tabel weg. Een getypeerd blok dat óók zijn rauwe bron
/// houdt, zou zijn tabel dus dubbel in het document zetten — dezelfde klasse
/// fout als #1589. Typeren hoort bij de fase die `_slideBody` de enveloppen
/// leert kennen; tot die tijd is de rauwe bron de waarheid, precies zoals bij
/// de tijdlijn.
///
/// De markerregel hoort bij het bereik: hij is bronbezit (D9).
Slide _pentestEnvelopeSlide(
  PentestBlock block,
  _ExactLineRanges rawLines,
  List<String> lines,
) => Slide.create(SlideType.freeMarkdown).copyWith(
  customMarkdown: rawLines.slice(block.start, block.end),
  tableRows: block.kind.headingBounded
      ? const []
      : decodeMarkdownTableRows(lines.sublist(block.start + 1, block.end)),
);

/// Het lichaam van één dia als platte Markdown voor [DocumentDeckBridge.deckToDocumentMarkdown].
String _slideBody(Slide slide) {
  // Elk tabelgedragen type, niet `table` bij naam (#1588). Negen andere types
  // dragen hun inhoud óók in `tableRows` — hun `customMarkdown` blijft per
  // ontwerp leeg — en vielen daardoor door naar de terugval "titel + bullets",
  // waarmee de hele tabel stil uit het document verdween. Op `backedByTable`
  // toetsen in plaats van op één type is dezelfde les die
  // `SlideType.usesScaffoldMarkdownBody` opschrijft: een nieuw tabelgedragen
  // moduletype is dan meteen goed ingedeeld in plaats van stil verkeerd.
  //
  // De kop reist mee. Een dia draagt hem naast zijn tabel, een document leest
  // op koppen, en zonder deze regel verloor ook een gewone `table`-dia zijn
  // titel. Een tabel zonder titel — wat `documentToDeck` maakt — levert geen
  // lege kopregel op, zodat de rondgang document → deck → document
  // byte-getrouw blijft.
  //
  // En de tabel is niet het enige dat zo'n dia draagt. De ontleder zet
  // `bullets` voor élk type, en `_parsedCustomMarkdown` levert een lichaam voor
  // elke richText-dia ongeacht type: een handgeschreven `_class: checklist` met
  // een opsomming én een tabel komt dus mét beide binnen. Alleen kop + tabel
  // teruggeven gooide die opsomming stil weg — dezelfde fout als hierboven, één
  // veld verderop. Alles wat de dia aan tekst draagt gaat mee.
  if (slide.type.backedByTable && slide.tableRows.isNotEmpty) {
    final table = encodeMarkdownTable(
      slide.tableRows,
      alignments: slide.tableColumnAlignments,
    );
    return [
      _titleAndBullets(slide),
      slide.customMarkdown.trim(),
      table,
    ].where((part) => part.isNotEmpty).join('\n\n');
  }
  switch (slide.type) {
    case SlideType.chart:
      return _serializeChartFence(slide.customMarkdown);
    default:
      if (slide.customMarkdown.trim().isNotEmpty) {
        return slide.customMarkdown;
      }
      // Leeg lichaam op een niet-freeMarkdown type: val terug op titel + bullets
      // zodat er geen inhoud verloren gaat.
      if (slide.type != SlideType.freeMarkdown) {
        return _titleAndBullets(slide);
      }
      return slide.customMarkdown;
  }
}

/// De titel als `##`-kop met de bullets eronder — de twee tekstdragers die elk
/// dia-type gemeen heeft, in de vorm waarin een document ze leest.
String _titleAndBullets(Slide slide) => [
  if (slide.title.trim().isNotEmpty) '## ${slide.title}',
  for (final b in slide.bullets)
    if (b.trim().isNotEmpty) '- $b',
].join('\n');

/// Een regel die na trimmen met 1–6 `#` en een spatie begint.
bool _isHeading(String trimmed) => RegExp(r'^#{1,6} ').hasMatch(trimmed);

/// Serialiseer een chart-blok met een fence langer dan de langste backtick-run
/// in de inhoud, zodat een regel met ``` binnen de spec het blok niet
/// voortijdig sluit (#1685).
String _serializeChartFence(String content) {
  final maxRun = _maxBacktickRun(content);
  final fenceLen = math.max(3, maxRun + 1);
  final fence = '`' * fenceLen;
  return '$fence' + 'chart\n$content\n$fence';
}

/// De langste reeks achterelkaar staande backticks in [text].
int _maxBacktickRun(String text) {
  var max = 0;
  var run = 0;
  for (final c in text.codeUnits) {
    if (c == 0x60) {
      run++;
      if (run > max) max = run;
    } else {
      run = 0;
    }
  }
  return max;
}
