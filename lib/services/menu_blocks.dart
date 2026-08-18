// Keuze-menu-blokken (#1162).
//
// Een menudia bewaart zijn blokken als gewone bullets in [Slide.bullets], elk
// een stukje Markdown: `[label](#anker)` voor een blok dat naar een dia springt,
// optioneel gevolgd door ` — uitleg` en door `![](mem:…)` voor een afbeelding, of
// gewoon platte tekst voor een blok zonder doel. Zo blijft een menu een leesbare
// linklijst in elke Markdown-lezer, en round-trippt het verliesvrij via de
// bestaande bullet-opslag.
//
// Categorieën rijden mee op de bestaande tussenkop-bullet ([isGroupHeading]): een
// tussenkop begint een categorie, de blokken erna horen erbij. Dat kost geen
// tweede lijst om synchroon te houden — herordenen, verwijderen en de
// bestandsrondgang lopen allemaal over dezelfde bullets.
//
// Dit bestand is de enige plek die dat stukje Markdown leest en schrijft — puur,
// zonder Flutter, zodat editor, preview, presentator en beamer dezelfde
// interpretatie delen en het los te toetsen valt.

import 'dart:math' as math;

import '../models/slide.dart';
import 'slide_anchors.dart';

/// Scheidingsteken tussen label en uitleg in een blok-bullet. Een spatie-em-dash
/// -spatie leest in elke Markdown-lezer als een gedachtestreepje, dus het bestand
/// blijft zonder OciDeck te begrijpen.
const String kMenuDescriptionSeparator = ' — ';

/// Eén blok op een keuze-menudia: een label, optioneel een uitleg eronder,
/// optioneel een doel-anker (leeg = een gewoon tekstblok dat nergens heen
/// springt) en optioneel een afbeelding.
class MenuBlock {
  final String label;

  /// Korte uitleg onder het label. Leeg = alleen het label.
  final String description;

  /// Het [Slide.anchor] van de doeldia, zonder de `#`. Leeg = geen sprong.
  final String targetAnchor;

  /// `mem:`- of asset-pad van de blokafbeelding. Leeg = geen afbeelding.
  final String imagePath;

  const MenuBlock({
    this.label = '',
    this.description = '',
    this.targetAnchor = '',
    this.imagePath = '',
  });

  bool get hasTarget => targetAnchor.isNotEmpty;
  bool get hasImage => imagePath.isNotEmpty;
  bool get hasDescription => description.isNotEmpty;

  MenuBlock copyWith({
    String? label,
    String? description,
    String? targetAnchor,
    String? imagePath,
  }) => MenuBlock(
    label: label ?? this.label,
    description: description ?? this.description,
    targetAnchor: targetAnchor ?? this.targetAnchor,
    imagePath: imagePath ?? this.imagePath,
  );

  @override
  bool operator ==(Object other) =>
      other is MenuBlock &&
      other.label == label &&
      other.description == description &&
      other.targetAnchor == targetAnchor &&
      other.imagePath == imagePath;

  @override
  int get hashCode => Object.hash(label, description, targetAnchor, imagePath);
}

/// Eén categorie van een menudia: een naam en de blokken eronder. Een menu
/// zonder tussenkoppen levert precies één categorie met een lege naam op — dan
/// toont de dia geen categoriekiezer.
class MenuCategory {
  final String label;
  final List<MenuBlock> blocks;

  const MenuCategory({this.label = '', this.blocks = const []});

  bool get isNamed => label.isNotEmpty;
}

final _reMenuLink = RegExp(r'\[([^\]]*)\]\(#([^)]*)\)');
final _reMenuImage = RegExp(r'!\[[^\]]*\]\(([^)]+)\)');

/// Lees één bullet-tekst als [MenuBlock]. Een `[label](#anker)` levert label +
/// anker; een `![](pad)` levert de afbeelding; wat daarna nog rest is de uitleg
/// (achter het gedachtestreepje), of anders het platte label. Fail-safe:
/// onbekende opmaak wordt gewoon het label, nooit een fout.
MenuBlock parseMenuBlock(String bullet) {
  // Eerst de afbeelding eruit halen, zodat hij niet in het label blijft plakken.
  final imageMatch = _reMenuImage.firstMatch(bullet);
  final imagePath = imageMatch?.group(1)?.trim() ?? '';
  final withoutImage = bullet.replaceAll(_reMenuImage, '').trim();

  final linkMatch = _reMenuLink.firstMatch(withoutImage);
  if (linkMatch != null) {
    return MenuBlock(
      label: linkMatch.group(1)!.trim(),
      description: _stripSeparator(withoutImage.substring(linkMatch.end)),
      targetAnchor: linkMatch.group(2)!.trim(),
      imagePath: imagePath,
    );
  }
  // Zonder link splitst het gedachtestreepje label en uitleg. Een label waar de
  // gebruiker zélf zo'n streepje in typt valt dus uiteen — maar de tekst blijft
  // volledig zichtbaar en schrijft identiek terug, dus de rondgang is stabiel.
  final split = withoutImage.indexOf(kMenuDescriptionSeparator);
  if (split < 0) return MenuBlock(label: withoutImage, imagePath: imagePath);
  return MenuBlock(
    label: withoutImage.substring(0, split).trim(),
    description: withoutImage
        .substring(split + kMenuDescriptionSeparator.length)
        .trim(),
    imagePath: imagePath,
  );
}

/// De staart achter het label ontdoen van het gedachtestreepje ervoor.
String _stripSeparator(String tail) {
  final t = tail.trim();
  // Ook een gewoon streepje of dubbele punt accepteren: dat typt een mens
  // sneller dan een em-dash, en het bedoelt hetzelfde.
  for (final sep in ['—', '–', '-', ':']) {
    if (t.startsWith(sep)) return t.substring(sep.length).trim();
  }
  return t;
}

/// Schrijf een [MenuBlock] terug als bullet-tekst — de tegenhanger van
/// [parseMenuBlock], zodat een rondgang door de editor niets verliest.
String menuBlockToBullet(MenuBlock block) {
  final buf = StringBuffer(
    block.hasTarget ? '[${block.label}](#${block.targetAnchor})' : block.label,
  );
  if (block.hasDescription) {
    buf
      ..write(kMenuDescriptionSeparator)
      ..write(block.description);
  }
  if (block.hasImage) buf.write(' ![](${block.imagePath})');
  return buf.toString();
}

/// Alle blokken van een menudia, in volgorde en zonder de categoriekoppen.
List<MenuBlock> menuBlocksFor(List<String> bullets) => [
  for (final b in bullets)
    if (!isGroupHeading(b)) parseMenuBlock(b),
];

/// De blokken gegroepeerd per categorie. Blokken vóór de eerste tussenkop komen
/// in een naamloze eerste categorie; die krijgt in de interface een
/// verzamelnaam. Een menu zonder tussenkoppen levert één naamloze categorie.
List<MenuCategory> menuCategoriesFor(List<String> bullets) {
  final out = <MenuCategory>[];
  var label = '';
  var blocks = <MenuBlock>[];
  for (final bullet in bullets) {
    if (isGroupHeading(bullet)) {
      // Een lopende groep afsluiten; een tussenkop direct achter een andere
      // levert bewust een lege categorie op — die staat zo in het bestand.
      if (out.isNotEmpty || blocks.isNotEmpty) {
        out.add(MenuCategory(label: label, blocks: blocks));
      }
      label = groupHeadingText(bullet).trim();
      blocks = <MenuBlock>[];
      continue;
    }
    blocks.add(parseMenuBlock(bullet));
  }
  out.add(MenuCategory(label: label, blocks: blocks));
  return out;
}

/// Hoeveel kolommen het raster krijgt bij [n] blokken. Hier en niet in de
/// preview, omdat de HTML-export dezelfde trap moet lopen: stonden ze los, dan
/// week de geëxporteerde dia stilletjes af van wat de auteur zag.
int menuGridColumns(int n) => n <= 1
    ? 1
    : n <= 4
    ? 2
    : n <= 9
    ? 3
    : 4;

/// Hoe groot één schijf van de cirkelindeling is, als fractie van de zijde van
/// het vierkante vlak waarin de ring staat.
///
/// Volgt uit de meetkunde en niet uit een geraden trapje: twee buren op een ring
/// van straal `r` staan een koorde `2·r·sin(π/n)` uit elkaar, dus met
/// `r = (1 − d)/2` en wat lucht ertussen is `d = s/(1+s)` met `s = k·sin(π/n)`
/// de grootste schijf die nog niet tegen zijn buurman aan komt. Zonder die
/// afleiding raakten de schijven elkaar vanaf een stuk of acht. Boven de
/// [_menuDiscCap] blijft hij staan: bij twee of drie blokken zou een schijf
/// anders de halve dia vullen.
///
/// Gedeeld met de HTML-export, die dezelfde ring in percentages tekent.
double menuDiscFraction(int n) {
  if (n <= 1) return 0.42;
  final spread = _menuDiscSpacing * math.sin(math.pi / n);
  return math.min(_menuDiscCap, spread / (1 + spread));
}

/// De straal van de ring waarop de schijven staan, als fractie van dezelfde
/// zijde. Eén blok staat in het midden — een ring van één is geen ring.
double menuRingRadius(int n) => n <= 1 ? 0 : (1 - menuDiscFraction(n)) / 2;

/// Hoeveel van de koorde tussen twee buren een schijf mag beslaan; de rest is
/// lucht.
const double _menuDiscSpacing = 0.85;

/// Bovengrens aan de schijfmaat, als fractie van de zijde.
const double _menuDiscCap = 0.34;

/// Hoe de tekst van één menublok in de hoogte past die de kaart of de schijf
/// hem geeft: een lettergrootte en een regelbudget voor het label en voor de
/// uitleg.
class MenuTextFit {
  final double labelSize;
  final int labelLines;
  final double descriptionSize;
  final int descriptionLines;

  const MenuTextFit({
    required this.labelSize,
    required this.labelLines,
    required this.descriptionSize,
    required this.descriptionLines,
  });

  bool get showsDescription => descriptionLines > 0;

  double get labelLineHeight => labelSize * _menuLabelLineFactor;
  double get descriptionLineHeight =>
      descriptionSize * _menuDescriptionLineFactor;

  /// De hoogte die deze verdeling werkelijk opeist.
  double get height =>
      labelLines * labelLineHeight + descriptionLines * descriptionLineHeight;
}

/// De regelhoogtes waarmee [menuTextFit] rekent. Openbaar, want de widget moet
/// exact dezelfde waarden in zijn `TextStyle` zetten: rekende de een met 1,15
/// terwijl de ander 1,2 tekende, dan klopt het toegewezen budget niet met wat er
/// werkelijk op de dia staat.
const double kMenuLabelLineHeight = 1.15;
const double kMenuDescriptionLineHeight = 1.2;

const double _menuLabelLineFactor = kMenuLabelLineHeight;
const double _menuDescriptionLineFactor = kMenuDescriptionLineHeight;

/// Verdeel [available] hoogte over label en uitleg van een menublok.
///
/// Waarom een eigen regel en niet gewoon een vast aantal regels: `maxLines`
/// begrenst het aantal regels, maar zegt niets over de hoogte die er ís. In een
/// lage kaart — de indeling "onder elkaar", of een raster van zestien — liep de
/// tekst daardoor buiten zijn vak en werd hij weggeknipt: de bovenste helft van
/// elk label verdween, zonder ellips, dus zonder enig teken dat er meer stond
/// (#1162, beeldkeuring). Er viel geen enkele test over, want wegknippen is geen
/// overloop.
///
/// Daarom volgt hier alles uit de ruimte: eerst krimpt de letter mee met het
/// vak, dan wordt geteld hoeveel regels er echt in passen. Er blijft altijd één
/// labelregel over — een blok zonder zichtbaar label is geen keuze meer.
MenuTextFit menuTextFit({
  required double available,
  required double maxLabelSize,
  required bool hasDescription,
  int maxLabelLines = 3,
}) {
  final labelSize = math.max(
    0.0,
    math.min(maxLabelSize, available * _menuLabelShare),
  );
  final labelLine = labelSize * _menuLabelLineFactor;
  final descriptionSize = labelSize * _menuDescriptionShare;
  final descriptionLine = descriptionSize * _menuDescriptionLineFactor;
  if (labelLine <= 0) {
    return MenuTextFit(
      labelSize: labelSize,
      labelLines: 1,
      descriptionSize: descriptionSize,
      descriptionLines: 0,
    );
  }
  // Onder deze maat is de uitleg geen tekst meer maar een grijze veeg. Dan is
  // hem laten vallen eerlijker dan hem onleesbaar meeschalen: het label krijgt
  // de ruimte, en de uitleg staat nog gewoon in de editor en in de export.
  final descriptionReadable =
      descriptionSize >= maxLabelSize * _menuDescriptionFloor;
  var labelLines = math.max(1, math.min(maxLabelLines, available ~/ labelLine));
  var descriptionLines = 0;
  if (hasDescription &&
      descriptionReadable &&
      available >= labelLine + descriptionLine) {
    descriptionLines = math.min(2, (available - labelLine) ~/ descriptionLine);
    // De uitleg mag het label niet verdringen: het label houdt voorrang, maar
    // krijgt naast een uitleg hoogstens twee regels zodat er wat te lezen valt.
    labelLines = math.min(
      2,
      math.max(
        1,
        (available - descriptionLines * descriptionLine) ~/ labelLine,
      ),
    );
  }
  return MenuTextFit(
    labelSize: labelSize,
    labelLines: labelLines,
    descriptionSize: descriptionSize,
    descriptionLines: descriptionLines,
  );
}

/// Hoeveel van de beschikbare hoogte één labelregel hoogstens mag beslaan.
const double _menuLabelShare = 0.42;

/// De uitleg staat op deze fractie van de labelgrootte.
const double _menuDescriptionShare = 0.73;

/// Onder deze fractie van de volle labelgrootte valt de uitleg weg in plaats van
/// mee te krimpen.
///
/// 0,25 en niet 0,35: op een dia van 1280 px is de volle labelmaat 33 px, dus
/// 0,35 zette de uitleg al uit bij 11,6 px — een maat die prima leesbaar is. Het
/// gevolg was een klifrand die niemand kon verklaren: bij vijf blokken onder
/// elkaar stond de uitleg er, bij zes was hij weg, met een verschil van een halve
/// procent (#1162, beeldkeuring). Met 0,25 ligt de grens rond 8 px, en dáár is
/// het werkelijk een grijze veeg.
const double _menuDescriptionFloor = 0.25;

/// De kleinste lettergrootte waarop een bloklabel nog iets zegt, als fractie van
/// de diabreedte — op een dia van 1280 px is dat ruim 12 px.
///
/// Zonder zo'n vloer bleef een vol menu keurig binnen zijn vak, maar met een
/// letter van 3,7 px: geen overloop, geen enkele test die klaagt, en toch een
/// rij streepjes in plaats van een menu (#1162, beeldkeuring). Een dia die
/// onleesbaar is, is niet minder stuk dan een dia die overloopt.
const double kMenuMinLabelFraction = 0.0095;

/// De maten van een blokkaart, als fractie van de diabreedte: de rand, de marge
/// binnen de rand, en het plafond dat die marge bij een lage kaart terugbrengt.
///
/// Ze staan hier en niet in de widget omdat de indelingen ermee móéten rekenen:
/// die bepalen hoeveel blokken er leesbaar passen, en dat kan alleen als ze
/// precies weten hoeveel hoogte een kaart aan zichzelf houdt. Stonden de getallen
/// in de widget, dan zou de indeling ze naschatten — en een schatting die de
/// echte maat voorspelt, rot stil weg.
const double kMenuCardBorderFraction = 0.0026;
const double kMenuCardPadFraction = 0.014;
const double kMenuCardPadCap = 0.12;

/// De marge binnen een kaart van [boxHeight] hoog (de maat binnen de rand).
double menuCardPadding(double boxHeight, double w) =>
    math.min(w * kMenuCardPadFraction, boxHeight * kMenuCardPadCap);

/// De hoogte die er in een kaart van [boxHeight] overblijft voor tekst.
double menuCardTextHeight(double boxHeight, double w) =>
    math.max(0, boxHeight - menuCardPadding(boxHeight, w) * 2);

/// De labelmaat die een blokrij van [rowHeight] (buitenmaat, rand inbegrepen)
/// oplevert. Hiermee kan een indeling narekenen of een rij nog leesbaar is,
/// zonder de rekensom van de kaart over te schrijven.
double menuRowLabelSize({
  required double rowHeight,
  required double w,
  required bool hasDescription,
}) => menuTextFit(
  available: menuCardTextHeight(
    math.max(0, rowHeight - w * kMenuCardBorderFraction * 2),
    w,
  ),
  maxLabelSize: w * kMenuCardLabelFraction,
  hasDescription: hasDescription,
).labelSize;

/// De volle labelmaat op een blokkaart, als fractie van de diabreedte.
const double kMenuCardLabelFraction = 0.026;

/// De maten van een schijf in de cirkelindeling, als fractie van de doorsnede:
/// het label, de binnenmarge (in een cirkel is er in de hoeken geen vlak), de
/// afbeelding en de ruimte eromheen. Zelfde reden als bij de kaart: de ring moet
/// ermee kunnen narekenen hoeveel schijven er leesbaar op passen.
const double kMenuDiscLabelFraction = 0.15;
const double kMenuDiscPadFraction = 0.16;
const double kMenuDiscThumbFraction = 0.34;
const double kMenuDiscGapFraction = 0.04;

/// De hoogte die er binnen een schijf van [diameter] overblijft voor tekst.
double menuDiscTextHeight({
  required double diameter,
  required double borderWidth,
  required bool hasImage,
}) =>
    diameter * (1 - kMenuDiscPadFraction * 2) -
    borderWidth * 2 -
    (hasImage ? diameter * (kMenuDiscThumbFraction + 0.05) : 0) -
    diameter * kMenuDiscGapFraction;

/// De labelmaat die een schijf van [diameter] oplevert — de tegenhanger van
/// [menuRowLabelSize] voor de cirkelindeling.
double menuDiscLabelSize({
  required double diameter,
  required double borderWidth,
  required bool hasImage,
  required bool hasDescription,
}) => menuTextFit(
  available: menuDiscTextHeight(
    diameter: diameter,
    borderWidth: borderWidth,
    hasImage: hasImage,
  ),
  maxLabelSize: diameter * kMenuDiscLabelFraction,
  hasDescription: hasDescription,
  maxLabelLines: 2,
).labelSize;

/// Hoeveel blokken er van [count] getoond worden als er maar [fits] plekken
/// leesbaar zijn, plus hoeveel er dan buiten beeld blijven.
///
/// Past niet alles, dan gaat de láátste plek naar een telblok — anders zou het
/// verschil tussen "dit is het hele menu" en "hier staat de helft van" nergens
/// te zien zijn. Liever een zichtbaar tekort dan een stilzwijgend tekort.
({int shown, int hidden}) menuVisibleBlocks(int count, int fits) {
  final room = fits < 1 ? 1 : fits;
  if (count <= room) return (shown: count, hidden: 0);
  final shown = room - 1;
  return (shown: shown, hidden: count - shown);
}

/// Of dit menu een categoriekiezer verdient: pas vanaf twee categorieën, of bij
/// één categorie die een naam draagt.
bool menuHasCategories(List<MenuCategory> categories) =>
    categories.length > 1 ||
    (categories.length == 1 && categories.first.isNamed);

/// Schrijf categorieën terug als bullets — de tegenhanger van
/// [menuCategoriesFor]. Een naamloze eerste categorie schrijft geen tussenkop.
List<String> menuBulletsFrom(List<MenuCategory> categories) => [
  for (var i = 0; i < categories.length; i++) ...[
    if (i > 0 || categories[i].isNamed) groupHeadingBullet(categories[i].label),
    for (final block in categories[i].blocks) menuBlockToBullet(block),
  ],
];

/// De positie in [bullets] van het [blockIndex]-de blok (koppen overgeslagen),
/// of -1 als dat blok niet bestaat. Zo kan een aanroeper één bullet herschrijven
/// zonder de categoriekoppen te verliezen.
int menuBulletIndexForBlock(List<String> bullets, int blockIndex) {
  if (blockIndex < 0) return -1;
  var seen = 0;
  for (var i = 0; i < bullets.length; i++) {
    if (isGroupHeading(bullets[i])) continue;
    if (seen == blockIndex) return i;
    seen++;
  }
  return -1;
}

/// De dia-lijst nadat menublok [blockIndex] van de menudia [menuIndex] naar dia
/// [targetIndex] is gaan wijzen (`null` = geen doel meer). De doeldia krijgt zo
/// nodig een uniek, bevroren anker — de gebruiker kiest een dia, niet een anker.
/// `null` terug = er verandert niets (ongeldige index of sprong naar de menudia
/// zelf). Puur over de lijst zodat de notifier alleen hoeft te muteren.
List<Slide>? slidesWithMenuTarget(
  List<Slide> slides,
  int menuIndex,
  int blockIndex,
  int? targetIndex,
) {
  if (menuIndex < 0 || menuIndex >= slides.length) return null;
  final bullets = slides[menuIndex].bullets;
  final bulletIndex = menuBulletIndexForBlock(bullets, blockIndex);
  if (bulletIndex < 0) return null;
  final out = List<Slide>.from(slides);

  var anchor = '';
  if (targetIndex != null) {
    if (targetIndex < 0 ||
        targetIndex >= out.length ||
        targetIndex == menuIndex) {
      return null;
    }
    var target = out[targetIndex];
    if (target.anchor.isEmpty) {
      final taken = {
        for (final s in out)
          if (s.anchor.isNotEmpty) s.anchor,
      };
      target = target.copyWith(
        anchor: uniqueAnchor(slugifyAnchor(target.title), taken),
      );
      out[targetIndex] = target;
    }
    anchor = target.anchor;
  }

  // Alleen de bullet van dit blok herschrijven: de koppen eromheen — en de
  // opmaak van de andere blokken — blijven letterlijk staan.
  final updated = List<String>.from(bullets);
  updated[bulletIndex] = menuBlockToBullet(
    parseMenuBlock(bullets[bulletIndex]).copyWith(targetAnchor: anchor),
  );
  out[menuIndex] = out[menuIndex].copyWith(bullets: updated);
  return out;
}
