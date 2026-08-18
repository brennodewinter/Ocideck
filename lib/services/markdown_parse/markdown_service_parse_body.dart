// Part of the markdown_service library — see ../markdown_service.dart.
// Split out for navigability (het doorlopen van de body-regels van één blok en
// het afleiden van het diatype daaruit); all imports live in the main library
// file. Verhuisd uit `markdown_service_parse.dart` toen dat bestand tegen het
// bestandsplafond van 1000 regels liep — dezelfde library, dezelfde leden,
// geen gedragswijziging.
part of '../markdown_service.dart';

extension _MarkdownParseBody on MarkdownService {
  /// Walk the (non-fenced) body lines, accumulating headings, bullets, images,
  /// captions, video/audio, quote and table content. [bullets] is appended in
  /// place; [listStyle] may be refined (checklist/numbered) and is returned.
  ({
    String h1,
    String h2,
    String paragraph,
    String imagePath,
    String imagePath2,
    String imageCaption,
    String imageCaption2,
    int imageSize,
    bool sawBgLeft,
    bool sawBgRight,
    int bgLeftWidth,
    int bgRightWidth,
    String videoPath,
    bool videoAutoplay,
    int videoStartMs,
    int videoEndMs,
    String audioPath,
    bool audioAutoplay,
    String quote,
    String quoteAuthor,
    List<String> tableLines,
    List<String> richTextLines,
    ListStyle listStyle,
  })
  _parseBodyLines(
    List<String> lines,
    String cssClass,
    ListStyle listStyle,
    List<String> bullets, {
    required bool skipContentLines,
  }) {
    final b = _BodyParse(listStyle);
    final classTokens = cssClass.split(_reWhitespace);
    b.isSplit = classTokens.contains('split');

    for (final line in lines) {
      if (b.listStyle == ListStyle.richText) {
        _consumeRichTextLine(line, b);
        continue;
      }
      final t = line.trim();
      if (skipContentLines) {
        if (t.startsWith('# ')) {
          b.h1 = t.substring(2);
        } else if (t.startsWith('## ')) {
          b.h2 = t.substring(3);
        }
        continue;
      }
      _consumeContentLine(line, t, bullets, b);
    }

    // De zichtbare opmaak mag de stijl ook terugzetten. Stond er `checklist` of
    // `numbered` in de richtlijn maar draagt geen enkel item nog een vinkje of
    // een nummer, dan heeft iemand ze weggehaald en is dit een gewone
    // opsomming. Alleen omhoog kunnen betekende dat je een checklist nooit meer
    // kwijtraakte door de tekst te bewerken.
    if (b.sawPlainItem &&
        !b.sawMarkedItem &&
        (b.listStyle == ListStyle.checklist ||
            b.listStyle == ListStyle.numbered)) {
      b.listStyle = ListStyle.bullets;
    }

    return (
      h1: b.h1,
      h2: b.h2,
      paragraph: b.paragraph,
      imagePath: b.imagePath,
      imagePath2: b.imagePath2,
      imageCaption: b.imageCaption,
      imageCaption2: b.imageCaption2,
      imageSize: b.imageSize,
      sawBgLeft: b.sawBgLeft,
      sawBgRight: b.sawBgRight,
      bgLeftWidth: b.bgLeftWidth,
      bgRightWidth: b.bgRightWidth,
      videoPath: b.videoPath,
      videoAutoplay: b.videoAutoplay,
      videoStartMs: b.videoStartMs,
      videoEndMs: b.videoEndMs,
      audioPath: b.audioPath,
      audioAutoplay: b.audioAutoplay,
      quote: b.quote,
      quoteAuthor: b.quoteAuthor,
      tableLines: b.tableLines,
      richTextLines: b.richTextLines,
      listStyle: b.listStyle,
    );
  }

  void _consumeRichTextLine(String line, _BodyParse b) {
    final t = line.trim();
    // De split-stellage bijhouden vóór al het andere. De kopfase hieronder slikt
    // elke `<div`-regel en keert meteen terug, en bij een dia met een lége body
    // is die fase nog actief wanneer `<div class="split-image">` langskomt: de
    // vlag ging dan nooit aan, de zij-afbeelding viel in de body-tak en was na
    // opslaan-en-heropenen weg.
    if (b.isSplit) {
      if (t.startsWith('<div class="split-image"')) {
        b.inSplitImageDiv = true;
      } else if (t == '</div>') {
        b.inSplitImageDiv = false;
      }
    }
    if (b.richTextHeaderPhase) {
      if (t.isEmpty) return;
      if (t.startsWith('<div') || t == '</div>') {
        return;
      }
      if (t.startsWith('# ') && b.h1.isEmpty) {
        b.h1 = t.substring(2);
        return;
      }
      if (t.startsWith('## ') && b.h2.isEmpty && b.h1.isNotEmpty) {
        b.h2 = t.substring(3);
        return;
      }
      b.richTextHeaderPhase = false;
    }
    // A rich-text body IS markdown: an embedded table or <video> stays in
    // the body verbatim. Lifting those out silently dropped a richText
    // slide's table (kept only for type==table) and would lose user content
    // (those fields aren't re-serialised for a bullets slide). EXCEPTIONS,
    // which must round-trip: an <audio> attachment (written for every slide
    // type by the common block after the type switch, so it is restored
    // here), and the bulletsImage split-image structure (its image and
    // caption). The image-caption check precedes the generic `<div>` skip,
    // which previously shadowed it dead.
    final isSplit = b.isSplit;
    if (isSplit && t.startsWith('<div class="image-caption">')) {
      final captionParts = _splitTwoCaptions(_decodeImageCaption(t));
      b.imageCaption = captionParts.isNotEmpty ? captionParts.first : '';
    } else if (isSplit && b.inSplitImageDiv && _reImageMd.hasMatch(t)) {
      // Alleen binnen `<div class="split-image">`: dát is de zij-afbeelding.
      // Een `![…]` in de `split-text`-helft is een afbeelding in de lopende
      // tekst en valt hieronder in de body-tak.
      final m = _reImageMd.firstMatch(t);
      if (m != null && b.imagePath.isEmpty) {
        b.imagePath = m.group(1) ?? '';
      }
    } else if (t.startsWith('<audio')) {
      final audio = _parseAudioAttrs(t);
      b.audioPath = audio.$1;
      b.audioAutoplay = audio.$2;
    } else if (isSplit && (t.startsWith('<div') || t == '</div>')) {
      // De stellage van een split-slide (`<div class="split-text">` en zijn
      // sluiting) hoort niet bij de tekst. Alleen op een split-slide: de
      // serialiser schrijft deze markup nergens anders, en zonder die
      // voorwaarde verdween een door de auteur getypte `<div>`-regel — met zijn
      // inhoud en al — uit een gewone vrije-tekstslide.
      //
      // De `split-image`-vlag wordt bovenaan deze methode al bijgehouden, want
      // die moet ook aangaan wanneer de kopfase deze regel opslokt.
    } else {
      b.richTextLines.add(line);
    }
  }

  void _consumeContentLine(
    String line,
    String t,
    List<String> bullets,
    _BodyParse b,
  ) {
    final htmlItems = _reLiItem.allMatches(t).toList();
    final bulletMatch = _reBullet.firstMatch(t);
    if (htmlItems.isNotEmpty) {
      for (final item in htmlItems) {
        final body = _stripInlineHtml(item.group(1) ?? '');
        if (body.trim().isNotEmpty) bullets.add(body.trim());
      }
    } else if (_reHtmlList.hasMatch(t)) {
      // HTML list container; individual <li> items are handled above.
    } else if (t.startsWith('|')) {
      b.tableLines.add(t);
    } else if (t.startsWith('# ')) {
      b.h1 = t.substring(2);
    } else if (t.startsWith('## ')) {
      b.h2 = t.substring(3);
    } else if (bulletMatch != null) {
      // Count leading spaces (2 per level)
      int spaces = 0;
      for (final ch in line.characters) {
        if (ch == ' ') {
          spaces++;
        } else if (ch == '\t') {
          spaces += 2;
        } else {
          break;
        }
      }
      final level = spaces ~/ 2;
      final marker = bulletMatch.group(1) ?? '';
      final body = bulletMatch.group(2) ?? '';
      bullets.add('\t' * level + body);
      if (_reChecklistMark.hasMatch(body)) {
        b.listStyle = ListStyle.checklist;
        b.sawMarkedItem = true;
      } else if (_reNumberedMark.hasMatch(marker)) {
        b.listStyle = ListStyle.numbered;
        b.sawMarkedItem = true;
      } else if (!isGroupHeading(body)) {
        // Een tussenkop draagt per ontwerp geen vinkje of nummer, dus hij zegt
        // niets over de stijl van de lijst eromheen.
        b.sawPlainItem = true;
      }
    } else if (t == '>' || t.startsWith('> ')) {
      // Aanvullen, niet overschrijven: een citaat mag meerdere regels beslaan.
      final line = t == '>' ? '' : t.substring(2);
      b.quote = b.quoteStarted ? '${b.quote}\n$line' : line;
      b.quoteStarted = true;
    } else if (t.startsWith('— ')) {
      b.quoteAuthor = t.substring(2);
    } else if (_reBgImage.hasMatch(t)) {
      final m = _reBgImageUrl.firstMatch(t);
      // Detect left/right side for title-column mode (#1405). Assign by side,
      // not by order, so `![bg right:25%]` always lands in imagePath2.
      final sideMatch = _reBgSide.firstMatch(t);
      final side = sideMatch?.group(1);
      if (m != null) {
        if (side == 'left') {
          b.sawBgLeft = true;
          b.imagePath = m.group(1) ?? '';
          final wMatch = _reBgSideWidth.firstMatch(t);
          if (wMatch != null) {
            b.bgLeftWidth = int.tryParse(wMatch.group(1)!) ?? 0;
          }
        } else if (side == 'right') {
          b.sawBgRight = true;
          b.imagePath2 = m.group(1) ?? '';
          final wMatch = _reBgSideWidth.firstMatch(t);
          if (wMatch != null) {
            b.bgRightWidth = int.tryParse(wMatch.group(1)!) ?? 0;
          }
        } else if (b.imagePath.isEmpty) {
          b.imagePath = m.group(1) ?? '';
        } else {
          b.imagePath2 = m.group(1) ?? ''; // tweede afbeelding
        }
      }
      // Parse size: ![bg 50%](...) or ![bg left:42%](...)
      final sizeMatch = _reBgImageSize.firstMatch(t);
      if (sizeMatch != null && b.imageSize == 0) {
        b.imageSize = int.tryParse(sizeMatch.group(1)!) ?? 0;
      }
    } else if (b.isSplit && _reImageMd.hasMatch(t)) {
      // Plain markdown image, e.g. the `![](path)` used inside a
      // bulletsImage `split-image` panel. Restricted to split slides so a
      // plain image inside free markdown is not mistaken for an image slide.
      final m = _reImageMd.firstMatch(t);
      if (m != null) {
        if (b.imagePath.isEmpty) {
          b.imagePath = m.group(1) ?? '';
        } else {
          b.imagePath2 = m.group(1) ?? '';
        }
      }
    } else if (t.startsWith('<div class="image-caption">')) {
      final captionParts = _splitTwoCaptions(_decodeImageCaption(t));
      b.imageCaption = captionParts.isNotEmpty ? captionParts.first : '';
      b.imageCaption2 = captionParts.length > 1
          ? captionParts.sublist(1).join(' | ')
          : '';
    } else if (t.startsWith('<video')) {
      final v = _parseVideoLine(t);
      b.videoPath = v.path;
      b.videoStartMs = v.startMs;
      b.videoEndMs = v.endMs;
      b.videoAutoplay = v.autoplay;
    } else if (t.startsWith('<iframe') && t.contains('ocideck-embed')) {
      final e = _parseEmbedLine(t);
      b.videoPath = e.path;
      b.videoStartMs = e.startMs;
      b.videoEndMs = e.endMs;
    } else if (t.startsWith('<audio')) {
      final audio = _parseAudioAttrs(t);
      b.audioPath = audio.$1;
      b.audioAutoplay = audio.$2;
    } else if (t.isNotEmpty && b.h1.isNotEmpty && b.paragraph.isEmpty) {
      b.paragraph = t;
    }
  }

  /// Decide the slide type from the class tokens, falling back to content
  /// heuristics (quote/images/bullets/video/table) when no explicit token says.
  SlideType _inferSlideType({
    required String cssClass,
    required String quote,
    required String imagePath,
    required String imagePath2,
    required List<String> bullets,
    required ListStyle listStyle,
    required String videoPath,
    required List<List<String>> tableRows,
    required String h1,
    required String h2,
    required String paragraph,
  }) {
    // Het token beslist, en welk token bij welk type hoort staat in de registry
    // die de serialisatie óók gebruikt ([slideTypeByMarpClass]) — niet in een
    // tweede lijst hier. Exacte tokens, dus geen conflict onderling ('finding'
    // matcht niet 'findings-summary').
    final declared = _declaredSlideType(cssClass.split(_reWhitespace));
    if (declared != null) return declared;

    // No explicit class token — fall back to content heuristics.
    if (quote.isNotEmpty) return SlideType.quote;
    if (imagePath.isNotEmpty && imagePath2.isNotEmpty) {
      return SlideType.twoImages;
    }
    if (bullets.isNotEmpty && imagePath.isNotEmpty) {
      return SlideType.bulletsImage;
    }
    if (listStyle == ListStyle.richText) return SlideType.bullets;
    if (bullets.isNotEmpty) return SlideType.bullets;
    if (videoPath.isNotEmpty) return SlideType.video;
    if (imagePath.isNotEmpty) return SlideType.image;
    if (tableRows.isNotEmpty &&
        bullets.isEmpty &&
        h2.isEmpty &&
        paragraph.isEmpty) {
      return SlideType.table;
    }
    if (h1.isEmpty && h2.isEmpty && bullets.isEmpty) {
      return SlideType.freeMarkdown;
    }
    return SlideType.bullets;
  }
}
