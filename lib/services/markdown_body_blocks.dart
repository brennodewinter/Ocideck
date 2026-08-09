import 'slide_layout_metrics.dart';

/// One renderable chunk of a rich-text markdown body.
class MarkdownBodyBlock {
  final String markdown;

  const MarkdownBodyBlock(this.markdown);
}

/// Een afbeelding op een eigen regel in een vrije-tekstbody: `![alt](pad)`.
///
/// Alles buiten het pad is gewone alt-tekst, dus elke andere markdownlezer toont
/// gewoon de afbeelding — de maatvoering hieronder is Marp's eigen conventie en
/// kost niets aan uitwisselbaarheid.
/// Het pad mag leeg zijn (`![alt]()`): zo laat de privacyprojectie een
/// geredigeerde afbeelding achter. Het blok blijft dan een afbeeldingsblok en
/// houdt zijn plek in de layout, en de renderer maakt er een zwart vlak van in
/// plaats van de tekst te laten opschuiven alsof er nooit iets stond.
final _blockImage = RegExp(r'^\s*!\[([^\]]*)\]\(([^)\n]*)\)\s*$');

/// `w:600` / `h:400` in de alt-tekst, in Marp-pixels.
final _imageSizeDirective = RegExp(r'\b([wh]):(\d+(?:\.\d+)?)\b');

/// De diabreedte waar de `w:`/`h:`-aanwijzingen in tellen: 1280, Marp's eigen
/// maat, en de breedte waarop `marp_html_service` de HTML-export zet.
///
/// Bewust níét [kReferenceSlideWidth] (960, OciDeck's interne layoutmaat): een
/// `![w:600]` zou dan in de app iets anders betekenen dan in de geëxporteerde
/// HTML, en dat verschil is voor de auteur onverklaarbaar.
const double kMarkdownImageDirectiveSlideWidth = 1280.0;

/// De hoogte die een afbeelding zonder `h:`-aanwijzing krijgt: ruim genoeg om
/// iets te zien, klein genoeg dat er tekst omheen past.
const kMarkdownImageDefaultHeightFraction = 0.25;

/// Een afbeelding in de lopende tekst, met de maat die de auteur meegaf.
class MarkdownImageSpec {
  final String path;
  final String alt;

  /// Breedte uit `w:`, in Marp-pixels. `null` = de volle tekstkolom.
  final double? width;

  /// Hoogte uit `h:`, in Marp-pixels. `null` =
  /// [kMarkdownImageDefaultHeightFraction] van de referentiebreedte.
  final double? height;

  const MarkdownImageSpec({
    required this.path,
    this.alt = '',
    this.width,
    this.height,
  });
}

/// De afbeelding die [markdown] als los blok is, of `null` als het geen
/// afbeeldingsblok is. Een `![…]` midden in een alinea telt niet mee: die blijft
/// gewone tekst, zodat een zin niet halverwege door een plaatje wordt gebroken.
MarkdownImageSpec? parseMarkdownImageBlock(String markdown) {
  final match = _blockImage.firstMatch(markdown.trim());
  if (match == null) return null;
  final path = (match.group(2) ?? '').trim();
  final alt = match.group(1) ?? '';
  double? width;
  double? height;
  for (final directive in _imageSizeDirective.allMatches(alt)) {
    final value = double.tryParse(directive.group(2) ?? '');
    // Fail-closed op onzin: een `![w:900000]` mag het layoutvak niet opblazen,
    // dezelfde regel als de `![bg N%]`-maat elders in de parser hanteert.
    if (value == null || value <= 0 || !value.isFinite) continue;
    if (directive.group(1) == 'w') {
      width = value;
    } else {
      height = value;
    }
  }
  return MarkdownImageSpec(path: path, alt: alt, width: width, height: height);
}

/// Het vak dat [spec] in de tekstkolom inneemt, bij een dia van [refW] breed en
/// een tekstkolom van [contentW].
///
/// De afbeelding wordt bínnen dit vak passend geschaald (nooit vervormd), en het
/// vak is met opzet alleen uit de markdown af te leiden: de paginaberekening is
/// synchroon en mag niet hoeven wachten tot een bestand gedecodeerd is. Zonder
/// `h:` staat er dus een vaste hoogte gereserveerd, ongeacht hoe hoog het
/// plaatje zelf blijkt te zijn — voorspelbaar, en met `h:` bij te sturen.
({double width, double height}) markdownImageBlockBox({
  required MarkdownImageSpec spec,
  required double contentW,
  required double refW,
  double scale = 1.0,
}) {
  final unit = refW / kMarkdownImageDirectiveSlideWidth;
  final width = spec.width == null
      ? contentW
      : (spec.width! * unit * scale).clamp(1.0, contentW);
  final height = (spec.height == null
      ? refW * kMarkdownImageDefaultHeightFraction * scale
      : spec.height! * unit * scale);
  return (width: width, height: height.clamp(1.0, refW * 9 / 16));
}

/// Een HTML-commentaarregel (`<!-- … -->`): volgens de markdown-spec levert die
/// niets zichtbaars op. OciDeck rendert geen HTML, dus een commentaar als
/// `<!-- _class: logo-safe -->` zou anders als lopende tekst op de dia komen te
/// staan (#1409). Alleen de één-regelige variant — `_class`-aanwijzingen en
/// vergelijkbare directive's zijn altijd één regel; een meerregelig commentaar
/// in slidemarkdown is zeldzaam en valt buiten deze plafond.
final htmlCommentLine = RegExp(r'^\s*<!--.*-->\s*$');

/// Parses [markdown] into blocks (paragraphs, headings, lists, code, math).
List<MarkdownBodyBlock> parseMarkdownBodyBlocks(String markdown) {
  if (markdown.trim().isEmpty) return const [];

  final lines = markdown.split('\n');
  final blocks = <MarkdownBodyBlock>[];
  var i = 0;

  while (i < lines.length) {
    final line = lines[i];

    // HTML-commentaar telt niet mee: het levert geen zichtbaar blok op en mag
    // ook geen hoogte claimen in de paginering (#1409).
    if (htmlCommentLine.hasMatch(line)) {
      i++;
      continue;
    }

    final fence = RegExp(r'^\s*```(.*)$').firstMatch(line);
    if (fence != null) {
      final chunk = <String>[line];
      i++;
      while (i < lines.length && !RegExp(r'^\s*```\s*$').hasMatch(lines[i])) {
        chunk.add(lines[i]);
        i++;
      }
      if (i < lines.length) {
        chunk.add(lines[i]);
        i++;
      }
      blocks.add(MarkdownBodyBlock(chunk.join('\n')));
      continue;
    }

    if (line.trim() == r'$$') {
      final chunk = <String>[line];
      i++;
      while (i < lines.length && lines[i].trim() != r'$$') {
        chunk.add(lines[i]);
        i++;
      }
      if (i < lines.length) {
        chunk.add(lines[i]);
        i++;
      }
      blocks.add(MarkdownBodyBlock(chunk.join('\n')));
      continue;
    }

    if (RegExp(r'^\s*\$\$(.+)\$\$\s*$').hasMatch(line)) {
      blocks.add(MarkdownBodyBlock(line));
      i++;
      continue;
    }

    if (line.trim().isEmpty) {
      blocks.add(MarkdownBodyBlock(''));
      i++;
      continue;
    }

    // Een afbeelding op een eigen regel is een eigen blok: alleen zo kan de
    // paginering hem in zijn geheel naar de volgende pagina schuiven in plaats
    // van hem van zijn alinea te scheiden.
    if (_blockImage.hasMatch(line)) {
      blocks.add(MarkdownBodyBlock(line));
      i++;
      continue;
    }

    final chunk = <String>[line];
    i++;
    while (i < lines.length) {
      final next = lines[i];
      if (next.trim().isEmpty) break;
      if (RegExp(r'^\s*```').hasMatch(next)) break;
      if (next.trim() == r'$$') break;
      if (RegExp(r'^\s*\$\$(.+)\$\$\s*$').hasMatch(next)) break;
      if (next.startsWith('# ')) break;
      if (next.startsWith('## ')) break;
      if (_blockImage.hasMatch(next)) break;
      chunk.add(next);
      i++;
    }
    blocks.add(MarkdownBodyBlock(chunk.join('\n')));
  }

  return blocks;
}

/// De inner-TeX van een blok dat één display-formule is (`$$ … $$`), of null.
///
/// Een `$$`-blok is bij het splitsen altijd zijn eigen blok (zie
/// [parseMarkdownBodyBlocks]), meerregelig (`$$` op eigen regels) of op één
/// regel. Beide leveren dezelfde inner-TeX.
String? displayMathTex(String blockMarkdown) {
  final t = blockMarkdown.trim();
  if (t.length > 4 && t.startsWith(r'$$') && t.endsWith(r'$$')) {
    final inner = t.substring(2, t.length - 2).trim();
    return inner.isEmpty ? null : inner;
  }
  return null;
}

/// De hoogte die een display-formule (`$$ … $$`) op de dia opeist.
///
/// De formule rendert op een vaste grootte (`refW * 0.032`, zie
/// `_markdownMathBlock`) — niet meegeschaald met de tekst. Anders dan een
/// tekstregel is een formule zelden één regel hoog: breukstrepen, wortels, grote
/// operatoren met grenzen en gestapelde scripts maken hem twee à drie keer zo
/// hoog. Hem als één regel meten reserveerde te weinig, en een hoge formule zakte
/// bij presentatiemaat in de logo-/footerband (#947). We schatten de verticale
/// omvang uit de constructies die hoogte toevoegen, ruim aan de veilige kant:
/// overschatten pagineert hooguit iets eerder, onderschatten raakt het logo.
///
/// De factoren zijn geijkt tegen de werkelijke `Math.tex`-hoogte van een
/// batterij formules (zie `math_block_height_test.dart`); elke schatting ligt
/// daar boven de gemeten hoogte.
double displayMathBlockHeight(String tex, double refW) {
  // `(?![a-zA-Z])` in plaats van `\b`: een `\sum_`/`\int^` wordt gevolgd door `_`
  // of `^`, en die tellen als word-char, dus `\b` zou daar juist níet grijpen.
  var factor = 1.1; // een gewone regel, met wat marge boven de gemeten ~0.8×
  // Gestapelde scripts (super-/subscript) maken een regel hoger.
  if (RegExp(r'[_^]').hasMatch(tex)) {
    factor += 0.5;
  }
  // Display-breuken (`\frac`, `\dfrac`, `\cfrac`, `\binom`) stapelen teller,
  // streep en noemer; `\tfrac` is tekststijl en compacter.
  factor +=
      RegExp(
        r'\\(?:d|c)?frac(?![a-zA-Z])|\\binom(?![a-zA-Z])',
      ).allMatches(tex).length *
      1.3;
  factor += RegExp(r'\\tfrac(?![a-zA-Z])').allMatches(tex).length * 0.8;
  // Het wortelteken voegt een dak boven zijn inhoud toe.
  if (tex.contains(r'\sqrt')) {
    factor += 0.5;
  }
  // Grote operatoren dragen hun grenzen erboven en eronder.
  if (RegExp(
    r'\\(?:sum|prod|coprod|iiint|iint|int|oint|bigcup|bigcap|bigvee'
    r'|bigwedge|bigotimes|bigoplus|biguplus)(?![a-zA-Z])',
  ).hasMatch(tex)) {
    factor += 1.7;
  }
  final content = refW * 0.032 * factor;
  final verticalPadding = refW * 0.012 * 2;
  return content + verticalPadding;
}

double _measureBlock({
  required MarkdownBodyBlock block,
  required double scale,
  required double contentW,
  required double refW,
  required double bodySize,
  required String font,
}) {
  final lines = block.markdown.split('\n');
  if (lines.length == 1 && lines.single.trim().isEmpty) {
    return refW * 0.01 * scale;
  }

  final image = parseMarkdownImageBlock(block.markdown);
  if (image != null) {
    return markdownImageBlockBox(
      spec: image,
      contentW: contentW,
      refW: refW,
      scale: scale,
    ).height;
  }

  // Een display-formule (`$$ … $$`) is bij het splitsen altijd zijn eigen blok,
  // dus meten we hem hier met zijn eigen, hoogte-bewuste schatting in plaats van
  // per regel als één tekstregel (#947).
  final mathTex = displayMathTex(block.markdown);
  if (mathTex != null) return displayMathBlockHeight(mathTex, refW);

  var height = 0.0;
  for (final line in lines) {
    final fence = RegExp(r'^\s*```(.*)$').firstMatch(line);
    if (fence != null) {
      final codeLines = lines.length > 2 ? lines.length - 2 : 1;
      // Code blocks render at fixed [refW] sizes (not scaled by text scale).
      height +=
          refW * 0.008 * 2 + refW * 0.018 * 2 + codeLines * refW * 0.02 * 1.3;
      return height;
    }
    if (line.trim() == r'$$' ||
        RegExp(r'^\s*\$\$(.+)\$\$\s*$').hasMatch(line)) {
      // Vangnet voor een misvormd blok dat displayMathTex niet herkende: de oude,
      // conservatieve één-regel-schatting.
      height += refW * 0.032 + refW * 0.012 * 2;
      return height;
    }
    if (line.startsWith('# ')) {
      height += measureTextHeight(
        line.substring(2),
        refW * 0.04 * scale,
        contentW,
        bold: true,
        lineHeight: kRichTextBodyLineHeight,
        fontFamily: font,
      );
    } else if (line.startsWith('## ')) {
      height += measureTextHeight(
        line.substring(3),
        refW * 0.03 * scale,
        contentW,
        lineHeight: kRichTextBodyLineHeight,
        fontFamily: font,
      );
      // Bullets meten met het '• '-prefix waarmee de render ze tekent. In het
      // testfont meet '•' even breed als '-', dus voor de mutatie-check is dit
      // predicaat daar niet te onderscheiden — alleen proportionele
      // productiefonts laten het verschil zien.
    } else if (line.startsWith('- ')) {
      // mutation: equivalent
      height += measureTextHeight(
        '• ${line.substring(2)}',
        bodySize * scale,
        contentW,
        lineHeight: kRichTextBodyLineHeight,
        fontFamily: font,
      );
    } else if (line.isEmpty) {
      height += refW * 0.01 * scale;
    } else {
      height += measureTextHeight(
        line,
        bodySize * scale,
        contentW,
        lineHeight: kRichTextBodyLineHeight,
        fontFamily: font,
      );
    }
  }
  return height;
}

double measureMarkdownBlocksHeight({
  required List<MarkdownBodyBlock> blocks,
  required double scale,
  required double contentW,
  required double refW,
  required double bodySize,
  required String font,
  double blockGap = 0,
}) {
  if (blocks.isEmpty) return 0;
  var h = 0.0;
  for (var i = 0; i < blocks.length; i++) {
    h += _measureBlock(
      block: blocks[i],
      scale: scale,
      contentW: contentW,
      refW: refW,
      bodySize: bodySize,
      font: font,
    );
    if (i < blocks.length - 1 && blockGap > 0) h += blockGap;
  }
  return h;
}

/// Height of a rich-text markdown body at [scale], wrapping at [contentW].
double markdownBodyHeight({
  required String markdown,
  required double contentW,
  required double refW,
  required double bodySize,
  required String font,
  double scale = 1.0,
}) {
  return measureMarkdownBlocksHeight(
    blocks: parseMarkdownBodyBlocks(markdown),
    scale: scale,
    contentW: contentW,
    refW: refW,
    bodySize: bodySize,
    font: font,
  );
}
