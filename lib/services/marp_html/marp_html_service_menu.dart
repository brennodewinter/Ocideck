// Part of the marp_html_service library — see ../marp_html_service.dart.
//
// Keuze-menudia's (#1162) in de HTML-export: vervang de platte link-bullets door
// hetzelfde kaartenraster dat de preview, de presentator en de PDF tekenen.
part of '../marp_html_service.dart';

final _menuClassComment = RegExp(r'<!--\s*_class:\s*([^>]+?)\s*-->');
final _menuHeading = RegExp(r'^#\s+(.*)$');

/// Zoveel kolommen als bij het aantal blokken past — hetzelfde trapje als de
/// preview (`_menuGrid`), zodat de raster-indeling over alle oppervlakken
/// gelijk oogt.
int _menuColumns(int n) => n <= 1
    ? 1
    : n <= 4
    ? 2
    : n <= 9
    ? 3
    : 4;

/// Rendert een keuze-menudia naar het kaartenraster, of laat een dia die geen
/// menu is onaangeroerd.
///
/// De blokken staan als link-bullets (`[label](#anker)`, optioneel met een
/// `![](…)`), precies zoals `menu_blocks.dart` ze leest; die parser is de enige
/// bron van waarheid, gedeeld met editor en preview. De uitvoer is ruwe HTML met
/// klassen voor de vorm en de themakleuren inline (accent uit het
/// [ThemeProfile]), zoals de rapportagedia's dat ook doen — zonder lege regels
/// binnen het blok, zodat marked het als één HTML-blok doorlaat. DOMPurify laat
/// `<a href="#…">`, `<img>`, `class` en `style` staan; een doelblok is een `<a>`
/// naar het `#anker` van de doeldia (die sinds deze wijziging een `id` draagt),
/// een tekstblok is een rustige `<div>`.
String renderMenuSlide(String slideMarkdown, {ThemeProfile? theme}) {
  final cssClass = _menuClassComment
      .firstMatch(slideMarkdown)
      ?.group(1)
      ?.split(RegExp(r'\s+'))
      .firstWhere((t) => t == 'menu', orElse: () => '');
  if (cssClass == null || cssClass.isEmpty) return slideMarkdown;

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

  final blocks = menuBlocksFor(bullets);
  // Alleen de dia-eigen chrome (het klasse-commentaar én het anker) blijft staan,
  // net als bij tree/flow; de bullets zijn nu het raster geworden.
  final chrome = [
    for (final line in slideMarkdown.split('\n'))
      if (line.contains('_class:') || line.contains('ocideck_slide_anchor:'))
        line,
  ];
  final head = StringBuffer(chrome.join('\n'))..write('\n\n');
  if (title.isNotEmpty) head.write('# $title\n\n');
  if (blocks.isEmpty) return head.toString();

  final accent = theme?.accentColor ?? '#003399';
  final ink = theme?.textColor ?? '#1a1a1a';
  final cols = _menuColumns(blocks.length);
  final grid = StringBuffer()
    ..write('<div class="menu-grid" style="grid-template-columns:')
    ..write('repeat($cols,1fr)">');
  for (final block in blocks) {
    grid.write(_menuCardHtml(block, accent: accent, ink: ink));
  }
  grid.write('</div>');
  return (head
        ..write(grid)
        ..write('\n'))
      .toString();
}

/// Eén keuzeblok als kaart. Een doelblok krijgt de accentrand en wordt een
/// `<a>` naar zijn `#anker`; een tekstblok is een `<div>` met een rustige rand
/// uit de tekstkleur. De alfa-achtervoegsels volgen de preview
/// (`_MenuBlockCard`): rand 0.55/0.22 (`8c`/`38`), vulling 0.10/0.04
/// (`1a`/`0a`). Attribuutwaarden (anker, afbeeldingspad) gaan door
/// [MarpHtmlService._htmlAttr] zodat een handgeschreven anker met een
/// aanhalingsteken nooit uit het attribuut kan breken; DOMPurify is de tweede
/// laag.
String _menuCardHtml(
  MenuBlock block, {
  required String accent,
  required String ink,
}) {
  final border = block.hasTarget ? '${accent}8c' : '${ink}38';
  final fill = block.hasTarget ? '${accent}1a' : '${accent}0a';
  final style = 'border-color:$border;background:$fill';
  final inner = StringBuffer();
  if (block.hasImage) {
    inner
      ..write('<img class="menu-thumb" alt="" src="')
      ..write(MarpHtmlService._htmlAttr(block.imagePath))
      ..write('">');
  }
  inner
    ..write('<div class="menu-label">')
    ..write(_esc(block.label))
    ..write('</div>');
  if (block.hasTarget) {
    final href = MarpHtmlService._htmlAttr('#${block.targetAnchor}');
    return '<a class="menu-card" href="$href" style="$style">$inner</a>';
  }
  return '<div class="menu-card" style="$style">$inner</div>';
}
