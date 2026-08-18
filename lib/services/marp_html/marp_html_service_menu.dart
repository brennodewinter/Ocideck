// Part of the marp_html_service library — see ../marp_html_service.dart.
//
// Keuze-menudia's (#1162) in de HTML-export: vervang de platte link-bullets door
// dezelfde blokken die de preview, de presentator en de PDF tekenen — in de
// indeling die de dia draagt (raster, onder elkaar of in een cirkel), en met de
// categorieën als kopjes eronder.
part of '../marp_html_service.dart';

final _menuClassComment = RegExp(r'<!--\s*_class:\s*([^>]+?)\s*-->');
final _menuHeading = RegExp(r'^#\s+(.*)$');

/// Rendert een keuze-menudia naar zijn blokken, of laat een dia die geen menu is
/// onaangeroerd.
///
/// De blokken staan als link-bullets (`[label](#anker)`, optioneel met een
/// ` — uitleg` en een `![](…)`), precies zoals `menu_blocks.dart` ze leest; die
/// parser is de enige bron van waarheid, gedeeld met editor en preview. De uitvoer
/// is ruwe HTML met klassen voor de vorm en de themakleuren inline (accent uit het
/// [ThemeProfile]), zoals de rapportagedia's dat ook doen — zonder lege regels
/// binnen het blok, zodat marked het als één HTML-blok doorlaat. DOMPurify laat
/// `<a href="#…">`, `<img>`, `class` en `style` staan; een doelblok is een `<a>`
/// naar het `#anker` van de doeldia (die sinds deze wijziging een `id` draagt),
/// een tekstblok is een rustige `<div>`.
///
/// Categorieën worden hier kopjes met hun blokken eronder, geen tabbladen: een
/// geëxporteerde HTML-dia heeft geen presentator die wisselt, en alles zichtbaar
/// is beter dan de helft achter een knop die niemand indrukt.
String renderMenuSlide(String slideMarkdown, {ThemeProfile? theme}) {
  final tokens =
      _menuClassComment
          .firstMatch(slideMarkdown)
          ?.group(1)
          ?.split(RegExp(r'\s+')) ??
      const <String>[];
  if (!tokens.contains('menu')) return slideMarkdown;

  var title = '';
  final bullets = <String>[];
  for (final line in slideMarkdown.split('\n')) {
    if (title.isEmpty) {
      final heading = _menuHeading.firstMatch(line.trim());
      if (heading != null) {
        title = heading.group(1)!.trim();
        continue;
      }
    }
    var rest = line.trimLeft();
    if (rest.startsWith('<!--')) continue;
    if (rest.startsWith('- ') || rest.startsWith('* ')) {
      bullets.add(rest.substring(2).trim());
    } else if (rest.startsWith(RegExp(r'\d+\.'))) {
      final dot = rest.indexOf('. ');
      if (dot >= 0) bullets.add(rest.substring(dot + 2).trim());
    }
  }

  final categories = menuCategoriesFor(bullets);
  // Alleen de dia-eigen chrome (het klasse-commentaar én het anker) blijft staan,
  // net als bij tree/flow; de bullets zijn nu de blokken geworden.
  final chrome = [
    for (final line in slideMarkdown.split('\n'))
      if (line.contains('_class:') || line.contains('ocideck_slide_anchor:'))
        line,
  ];
  final head = StringBuffer(chrome.join('\n'))..write('\n\n');
  if (title.isNotEmpty) head.write('# $title\n\n');
  if (categories.every((c) => c.blocks.isEmpty)) return head.toString();

  final accent = theme?.accentColor ?? '#003399';
  final ink = theme?.textColor ?? '#1a1a1a';
  final layout = menuLayoutFromTokens(tokens);
  // Alle categorieën staan onder elkaar op één dia, dus ze delen de hoogte.
  // Zonder die deling kreeg elke ring de volle maat en groeide een menu met drie
  // categorieën uit tot vijf schermen hoog (#1162, beeldkeuring).
  final filled = categories.where((c) => c.blocks.isNotEmpty).length;
  // Dichtheid en rijhoogte horen bij de dia, niet bij één categorie: twee
  // categorieën van acht zijn samen zestien blokken en moeten dus even klein
  // gezet worden als één categorie van zestien. Per categorie beslissen liet ze
  // allebei ontsnappen, en de dia werd twee schermen hoog (#1162, beeldkeuring).
  final total = categories.fold<int>(0, (n, c) => n + c.blocks.length);
  final body = StringBuffer();
  for (final category in categories) {
    if (category.blocks.isEmpty) continue;
    if (category.isNamed) {
      body
        ..write('<div class="menu-category" style="color:$ink">')
        ..write(_esc(category.label))
        ..write('</div>');
    }
    body.write(
      _menuBlocksHtml(
        category.blocks,
        layout,
        accent: accent,
        ink: ink,
        categoryCount: filled,
        slideBlockCount: total,
      ),
    );
  }
  return (head
        ..write(body)
        ..write('\n'))
      .toString();
}

/// De blokken van één categorie in de gevraagde indeling.
String _menuBlocksHtml(
  List<MenuBlock> blocks,
  MenuLayout layout, {
  required String accent,
  required String ink,
  required int categoryCount,
  required int slideBlockCount,
}) {
  // Veel blokken op één dia betekent kleinere kaarten — anders loopt het label
  // de kaart uit, precies zoals in de app (#1162, beeldkeuring).
  final dense = slideBlockCount > 9;
  // De hoogte die dit blokkenvlak mag beslaan. Vaste pixels en geen `vh`: een
  // geëxporteerde dia is 1280×720 en de kijker scrollt door dia's, dus de
  // vensterhoogte zegt hier niets. De categorieën delen het budget.
  final budget = (_menuBodyHeight / categoryCount).clamp(140, _menuBodyHeight);
  final out = StringBuffer();
  switch (layout) {
    case MenuLayout.grid:
      final columns = menuGridColumns(blocks.length);
      final rows = (blocks.length / columns).ceil();
      out
        ..write('<div class="menu-grid${dense ? ' menu-dense' : ''}" ')
        ..write('style="grid-template-columns:repeat($columns,1fr);')
        ..write('grid-auto-rows:${_menuRowPx(budget, rows, 22)}px">');
    case MenuLayout.list:
      out
        ..write(
          '<div class="menu-grid menu-stack${dense ? ' menu-dense' : ''}"',
        )
        ..write(' style="grid-auto-rows:')
        ..write('${_menuRowPx(budget, blocks.length, 16)}px">');
    case MenuLayout.circle:
      // De ring is vierkant; met meer categorieën onder elkaar moet hij kleiner.
      out.write(
        '<div class="menu-ring" style="max-width:${budget.round()}px">',
      );
  }
  for (var i = 0; i < blocks.length; i++) {
    out.write(
      layout == MenuLayout.circle
          ? _menuDiscHtml(
              blocks[i],
              i,
              blocks.length,
              accent: accent,
              ink: ink,
              ringPx: budget.toDouble(),
            )
          : _menuCardHtml(blocks[i], accent: accent, ink: ink),
    );
  }
  out.write('</div>');
  return out.toString();
}

/// De hoogte die de blokken van één dia samen mogen beslaan in de HTML-export,
/// in pixels op de 1280×720-dia — de titel en wat marge eraf.
const double _menuBodyHeight = 560;

/// De rijhoogte die [rows] rijen met [gap] ertussen samen binnen [budget] houdt,
/// begrensd op wat nog leesbaar respectievelijk niet potsierlijk is.
int _menuRowPx(num budget, int rows, double gap) =>
    ((budget - gap * (rows - 1)) / rows).clamp(56, 180).round();

/// De rand- en vulkleur van een blok. Een doelblok krijgt de accentrand; een
/// tekstblok een rustige rand uit de tekstkleur. De alfa-achtervoegsels volgen de
/// preview (`_MenuBlockCard`): rand 0.55/0.18 (`8c`/`2e`), vulling 0.12/0.05
/// (`1f`/`0d`).
String _menuBlockStyle(MenuBlock block, String accent, String ink) =>
    block.hasTarget
    ? 'border-color:${accent}8c;background:${accent}1f'
    : 'border-color:${ink}2e;background:${ink}0d';

/// Dezelfde stijl voor een schijf, plus het sprongteken dat de app er ook op
/// zet: een dubbel zo zware rand, omdat er in een cirkel geen plek is voor de
/// pijl die een kaart draagt. Zonder dit gaf de export een sprong anders aan dan
/// de app (#1162, beeldkeuring).
String _menuDiscStyle(MenuBlock block, String accent, String ink) =>
    '${_menuBlockStyle(block, accent, ink)};'
    'border-width:${block.hasTarget ? 4 : 2}px';

/// Eén keuzeblok als kaart: kleine afbeelding links, label en uitleg ernaast,
/// een pijl rechts als het blok ergens heen springt. Attribuutwaarden (anker,
/// afbeeldingspad) gaan door [MarpHtmlService._htmlAttr] zodat een handgeschreven
/// anker met een aanhalingsteken nooit uit het attribuut kan breken; DOMPurify is
/// de tweede laag.
String _menuCardHtml(
  MenuBlock block, {
  required String accent,
  required String ink,
}) {
  final inner = StringBuffer();
  if (block.hasImage) {
    inner
      ..write('<img class="menu-thumb" alt="" src="')
      ..write(MarpHtmlService._htmlAttr(block.imagePath))
      ..write('">');
  }
  inner
    ..write('<div class="menu-text"><div class="menu-label">')
    ..write(_esc(block.label))
    ..write('</div>');
  if (block.hasDescription) {
    inner
      ..write('<div class="menu-desc">')
      ..write(_esc(block.description))
      ..write('</div>');
  }
  inner.write('</div>');
  if (block.hasTarget) {
    inner
      ..write('<span class="menu-arrow" style="color:$accent">')
      ..write('&#8594;</span>');
    final href = MarpHtmlService._htmlAttr('#${block.targetAnchor}');
    return '<a class="menu-card" href="$href" '
        'style="${_menuBlockStyle(block, accent, ink)}">$inner</a>';
  }
  return '<div class="menu-card" '
      'style="${_menuBlockStyle(block, accent, ink)}">$inner</div>';
}

/// Eén keuzeblok als schijf in de ring. De plek op de cirkel wordt hier
/// uitgerekend en als percentage meegegeven — zonder script, zodat een
/// geëxporteerde dia ook in een lezer zonder JavaScript klopt.
String _menuDiscHtml(
  MenuBlock block,
  int i,
  int n, {
  required String accent,
  required String ink,
  required double ringPx,
}) {
  final disc = 100 * menuDiscFraction(n);
  final radius = 100 * menuRingRadius(n);
  final angle = -math.pi / 2 + i * 2 * math.pi / n;
  final left = 50 + radius * math.cos(angle) - disc / 2;
  final top = 50 + radius * math.sin(angle) - disc / 2;
  final place =
      'left:${left.toStringAsFixed(2)}%;top:${top.toStringAsFixed(2)}%;'
      'width:${disc.toStringAsFixed(2)}%;height:${disc.toStringAsFixed(2)}%';
  // De schijf is een percentage van de ring, maar de letter stond op een vaste
  // 20 px: bij zestien blokken was de schijf 84 px breed en werd elk label links
  // én rechts weggesneden, zonder ellips (#1162, beeldkeuring). De lettermaat
  // volgt nu dezelfde verhouding als in de app (0,15 · doorsnede).
  final discPx = ringPx * menuDiscFraction(n);
  final labelPx = (discPx * 0.15).clamp(9, 22).toStringAsFixed(1);
  final descPx = (discPx * 0.11).clamp(8, 17).toStringAsFixed(1);
  final inner = StringBuffer();
  if (block.hasImage) {
    inner
      ..write('<img class="menu-disc-thumb" alt="" src="')
      ..write(MarpHtmlService._htmlAttr(block.imagePath))
      ..write('">');
  }
  inner
    ..write('<span class="menu-label" style="font-size:${labelPx}px">')
    ..write(_esc(block.label))
    ..write('</span>');
  // Ook hier de uitleg tonen zolang er geen beeld in de weg staat, zodat de
  // export niet minder laat zien dan de app.
  if (block.hasDescription && !block.hasImage) {
    inner
      ..write('<span class="menu-desc" style="font-size:${descPx}px">')
      ..write(_esc(block.description))
      ..write('</span>');
  }
  final style = '$place;${_menuDiscStyle(block, accent, ink)}';
  if (block.hasTarget) {
    final href = MarpHtmlService._htmlAttr('#${block.targetAnchor}');
    return '<a class="menu-disc" href="$href" style="$style">$inner</a>';
  }
  return '<div class="menu-disc" style="$style">$inner</div>';
}
