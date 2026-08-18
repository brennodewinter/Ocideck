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
      _menuBlocksHtml(category.blocks, layout, accent: accent, ink: ink),
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
}) {
  final out = StringBuffer();
  switch (layout) {
    case MenuLayout.grid:
      out
        ..write('<div class="menu-grid" style="grid-template-columns:')
        ..write('repeat(${menuGridColumns(blocks.length)},1fr)">');
    case MenuLayout.list:
      out.write('<div class="menu-grid menu-stack">');
    case MenuLayout.circle:
      out.write('<div class="menu-ring">');
  }
  for (var i = 0; i < blocks.length; i++) {
    out.write(
      layout == MenuLayout.circle
          ? _menuDiscHtml(blocks[i], i, blocks.length, accent: accent, ink: ink)
          : _menuCardHtml(blocks[i], accent: accent, ink: ink),
    );
  }
  out.write('</div>');
  return out.toString();
}

/// De rand- en vulkleur van een blok. Een doelblok krijgt de accentrand; een
/// tekstblok een rustige rand uit de tekstkleur. De alfa-achtervoegsels volgen de
/// preview (`_MenuBlockCard`): rand 0.55/0.18 (`8c`/`2e`), vulling 0.12/0.05
/// (`1f`/`0d`).
String _menuBlockStyle(MenuBlock block, String accent, String ink) =>
    block.hasTarget
    ? 'border-color:${accent}8c;background:${accent}1f'
    : 'border-color:${ink}2e;background:${ink}0d';

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
}) {
  final disc = math.min(34.0, 86 * math.pi / math.max(n, 3) * 0.86);
  final radius = (100 - disc) / 2;
  final angle = -math.pi / 2 + i * 2 * math.pi / n;
  final left = 50 + radius * math.cos(angle) - disc / 2;
  final top = 50 + radius * math.sin(angle) - disc / 2;
  final place =
      'left:${left.toStringAsFixed(2)}%;top:${top.toStringAsFixed(2)}%;'
      'width:${disc.toStringAsFixed(2)}%;height:${disc.toStringAsFixed(2)}%';
  final inner = StringBuffer();
  if (block.hasImage) {
    inner
      ..write('<img class="menu-disc-thumb" alt="" src="')
      ..write(MarpHtmlService._htmlAttr(block.imagePath))
      ..write('">');
  }
  inner
    ..write('<span class="menu-label">')
    ..write(_esc(block.label))
    ..write('</span>');
  final style = '$place;${_menuBlockStyle(block, accent, ink)}';
  if (block.hasTarget) {
    final href = MarpHtmlService._htmlAttr('#${block.targetAnchor}');
    return '<a class="menu-disc" href="$href" style="$style">$inner</a>';
  }
  return '<div class="menu-disc" style="$style">$inner</div>';
}
