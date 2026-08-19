import '../models/deck.dart';
import '../models/slide.dart';
import 'markdown_table_codec.dart';
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
        final markedSource = rawLines.slice(i, j);
        // Ook een nog onbruikbare tijdlijn blijft één bronblok. De visuele
        // editor laat de gebruiker zo'n tabel herstellen; de bridge mag vóór
        // dat herstel de marker niet losmaken of de tabel normaliseren.
        slides.add(
          Slide.create(SlideType.freeMarkdown).copyWith(
            customMarkdown: markedSource,
            // Schaduwstructuur voor OciWacht: de uitvoer blijft de rauwe
            // customMarkdown, maar kolomkopcontext en bulkregels moeten ook
            // voor een nog onbruikbare tijdlijn beschikbaar blijven.
            tableRows: decodeMarkdownTableRows(lines.sublist(i + 1, j)),
          ),
        );
        i = j;
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
      if (isMarkdownTableLine(trimmed) &&
          i + 1 < lines.length &&
          isMarkdownTableDelimiterRow(lines[i + 1].trim())) {
        flushFlow();
        // Koprij + scheidingsrij + body: de codec leest de per-kolomuitlijning
        // uit de scheidingsrij (en laat die daarna weg), zodat een office-tabel
        // zijn uitlijning door de deconstructie én de round-trip behoudt.
        final tableLines = <String>[line, lines[i + 1]];
        var j = i + 2;
        while (j < lines.length && isMarkdownTableLine(lines[j].trim())) {
          tableLines.add(lines[j]);
          j++;
        }
        final decoded = decodeMarkdownTableWithAlignment(tableLines);
        slides.add(
          Slide.create(SlideType.table).copyWith(
            tableRows: decoded.rows,
            tableColumnAlignments: decoded.alignments,
          ),
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
      return '```chart\n${slide.customMarkdown}\n```';
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
bool _isFenceClose(String trimmed, String marker, int length) =>
    RegExp('^${RegExp.escape(marker)}{$length,}[ \\t]*\$').hasMatch(trimmed);
