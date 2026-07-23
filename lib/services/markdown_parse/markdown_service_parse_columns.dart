// Part of the markdown_service library — see ../markdown_service.dart.
// Split out for navigability (de lezer van de zichtbare tweekolomsopmaak); alle
// imports leven in het hoofdbestand.
part of '../markdown_service.dart';

/// Wat de zichtbare tweekolomsopmaak van een dia oplevert.
///
/// [found] is de scharnier: hij zegt of er überhaupt lijst-HTML stond. Zo niet,
/// dan is er niets gelezen en mag de aanroeper terugvallen op wat er verder in
/// het blok staat — in een oud bestand de base64-richtlijn, in een
/// handgeschreven blok gewone Markdown-bullets.
typedef _TwoColumnBullets = ({
  List<String> left,
  List<String> right,
  String leftTitle,
  String rightTitle,

  /// De stijl die de opmaak zelf aanwijst, of null als ze er niets over zegt
  /// (geen items, of alleen tussenkoppen). Dan blijft de richtlijn staan.
  ListStyle? listStyle,
  bool found,
});

/// De onderdelen van de tweekolomsopmaak, in de volgorde waarin ze in het blok
/// staan: een lijst begint een kolom, een `<h3>` benoemt de kolom die daarna
/// komt, en een `<li>` is een item van de kolom waarin we zitten.
///
/// Bewust tolerant in de attributen (`<ul>` zonder stijl, `<li>` met of zonder
/// `value=`): wat een teksteditor-gebruiker met de hand typt draagt geen van de
/// stijlattributen die de serialisatie erbij zet.
final _reTwoColumnPart = RegExp(
  r'<(?<list>ul|ol)\b[^>]*>'
  r'|<h3\b[^>]*>(?<title>[\s\S]*?)</h3>'
  r'|<li(?<attrs>[^>]*)>(?<item>[\s\S]*?)</li>',
  caseSensitive: false,
);

/// Hoeveel `em` inspringing één niveau is; zie [_writeHtmlBulletItems].
const double _twoColumnIndentEm = 1.4;

final _reListItemIndent = RegExp(r'margin-left:\s*([0-9.]+)em');
final _reListItemValue = RegExp(r'\bvalue\s*=');
final _reListItemUnmarked = RegExp(r'list-style:\s*none');

/// De aanvinkbare glyphs die [_writeHtmlBulletItems] voor een checklist zet.
const String _checkedGlyph = '☑';
const String _uncheckedGlyph = '☐';

/// Leest de zichtbare tweekolomsopmaak van [block].
///
/// Dit is de kern van "de zichtbare Markdown is de waarheid": tot nu toe stond
/// de inhoud van beide kolommen in een base64-richtlijn erboven en werd de
/// `<ul><li>` eronder bij het inlezen volledig overgeslagen. Een met de hand
/// geschreven tweekolomsdia kwam daardoor als twee lege kolommen binnen — de
/// zichtbare tekst werd niet overruled, ze werd nooit gelezen.
_TwoColumnBullets _parseTwoColumnBullets(String block) {
  final columns = [<String>[], <String>[]];
  final titles = ['', ''];
  var column = -1;
  var pendingTitle = '';
  var found = false;
  var sawNumbered = false;
  var sawChecklist = false;
  var sawPlainItem = false;

  for (final m in _reTwoColumnPart.allMatches(block)) {
    final list = m.namedGroup('list');
    if (list != null) {
      found = true;
      column++;
      if (column < titles.length) titles[column] = pendingTitle;
      pendingTitle = '';
      if (list.toLowerCase() == 'ol') sawNumbered = true;
      continue;
    }
    final title = m.namedGroup('title');
    if (title != null) {
      pendingTitle = _unescapeHtml(title).trim();
      continue;
    }
    // Een `<li>` zonder omhullende lijst hoort nog altijd ergens: zet hem in de
    // eerste kolom in plaats van hem te laten vallen.
    final target = column < 0 ? 0 : column;
    if (target >= columns.length) continue;
    found = true;
    final attrs = m.namedGroup('attrs') ?? '';
    final text = _unescapeHtml(m.namedGroup('item') ?? '').trim();
    if (_reListItemValue.hasMatch(attrs)) sawNumbered = true;

    if (_reListItemUnmarked.hasMatch(attrs)) {
      // Een markerloos item is een tussenkop; zonder tekst een scheidingslijn.
      columns[target].add(groupHeadingBullet(text));
      continue;
    }
    if (text.isEmpty) continue;

    final indent = _reListItemIndent.firstMatch(attrs);
    final level = indent == null
        ? 0
        : ((double.tryParse(indent.group(1)!) ?? 0) / _twoColumnIndentEm)
              .round();
    final prefix = '\t' * (level < 0 ? 0 : level);

    if (text.startsWith(_checkedGlyph) || text.startsWith(_uncheckedGlyph)) {
      sawChecklist = true;
      final checked = text.startsWith(_checkedGlyph);
      columns[target].add(
        '$prefix[${checked ? 'x' : ' '}] ${text.substring(1).trim()}',
      );
      continue;
    }
    sawPlainItem = true;
    columns[target].add('$prefix$text');
  }

  return (
    left: columns[0],
    right: columns[1],
    leftTitle: titles[0],
    rightTitle: titles[1],
    // Een opwaardering wint van een terugval: staat er ook maar één vinkje,
    // dan is het een checklist. Alleen wanneer élk item gewoon is, zet de
    // opmaak de stijl terug op een gewone opsomming.
    listStyle: sawNumbered
        ? ListStyle.numbered
        : sawChecklist
        ? ListStyle.checklist
        : sawPlainItem
        ? ListStyle.bullets
        : null,
    found: found,
  );
}
