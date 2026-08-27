import '../models/marp_style.dart';
import '../models/slide.dart';
import 'markdown_front_matter_codec.dart';

final _backgroundImage = RegExp(r'!\[bg');
final _wholeBackground = RegExp(r'^!\[([^\]]*)\]\([^)]+\)$');
final _htmlComment = RegExp(r'<!--([\s\S]*?)-->', multiLine: true);
final _directiveKey = RegExp(r'^([A-Za-z][A-Za-z0-9_-]*)\s*:');
final _imageFilter = RegExp(
  r'\b(?:blur(?::[^\s\]]+)?|brightness(?::[^\s\]]+)?|saturate(?::[^\s\]]+)?|grayscale|sepia|invert)\b',
  caseSensitive: false,
);
final _contain = RegExp(r'\b(?:fit|contain)\b', caseSensitive: false);

/// Whether typed serialization would move or rewrite authored Marpit source.
bool requiresWholeMarpBlockPreservation(String block) {
  final backgrounds = block
      .split('\n')
      .map((line) => line.trim())
      .where(_backgroundImage.hasMatch)
      .toList();
  if (backgrounds.length > 2) return true;
  for (var i = 0; i < backgrounds.length; i++) {
    if (!_hasOnlyTypedBackgroundOptions(
      backgrounds[i],
      allowVisualStyle: i == 0,
    )) {
      return true;
    }
  }

  final lines = block.split('\n');
  final fitLines = <int>[];
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() == '<!-- fit -->') fitLines.add(i);
  }
  if (fitLines.length > 1) return true;
  if (fitLines.length == 1) {
    final fit = fitLines.single;
    final firstHeading = lines.indexWhere(
      (line) => RegExp(r'^#{1,6}\s+\S').hasMatch(line.trim()),
    );
    if (fit == 0 || fit - 1 != firstHeading) return true;
  }
  final fitComments = _htmlComment
      .allMatches(block)
      .where((match) => match.group(1)!.trim() == 'fit')
      .length;
  if (fitComments != fitLines.length) return true;

  for (final match in _htmlComment.allMatches(block)) {
    final raw = match.group(1)!;
    if (raw.contains('\n')) continue;
    if (marpitDirectiveKey(raw.trim()) != null) return true;
  }
  return false;
}

/// De Marpit-richtlijnen die een dia-commentaar kan dragen, zónder het
/// `_`-voorvoegsel van de spot-vorm.
///
/// Dit is de sleutellijst van Marp zelf, niet die van OciDeck. De
/// `_`-varianten die OciDeck wél modelleert (`_color`, `_backgroundColor`,
/// `_backgroundImage`, `_header`, `_footer`) lopen langs
/// [parseMarpStyleDirective]; élke andere `_`-richtlijn wordt binnen de
/// getypeerde dia bewaard als `preservedMarpLines`. Wat hier staat is de kale
/// vorm, die Marp vanaf déze dia laat gelden en die OciDeck nergens modelleert
/// — dus moet het hele blok als bron blijven staan.
///
/// **Deze lijst kan verouderen, en dat is de prijs die #1815 bewust betaalt.**
/// De oude toets ("elk woord gevolgd door een dubbele punt") ving élke
/// toekomstige Marp-richtlijn vanzelf op; deze niet. Voegt Marp er een toe, dan
/// bewaart OciDeck een blok dat hem draagt niet meer en gaat de richtlijn bij
/// het opslaan verloren — tot die naam hier bijstaat.
///
/// Toch is dit de goede kant van de afweging. Wat de brede toets kocht was
/// toekomstvastheid voor een zeldzame gebeurtenis (Marpit heeft in jaren
/// nauwelijks richtlijnen toegevoegd); wat ze kostte was een dagelijkse,
/// stille: élke notitie van de vorm `Woord:` sloopte haar dia. Van gedachten
/// veranderen we zodra dit aan een poort hangt: `make check-marp` (#1804)
/// draait de échte, gepinde Marp CLI en is de plek om deze lijst tegen die
/// versie te toetsen. De structurele oplossing is de doorgeeflus van #1810 —
/// een onbekende richtlijn apart zetten en onveranderd terugschrijven — want
/// die maakt bewaren-of-niet een niet-vraag.
const kMarpitDirectiveNames = <String>{
  // Globaal.
  'marp',
  'theme',
  'style',
  'headingDivider',
  // Lokaal.
  'paginate',
  'header',
  'footer',
  'class',
  'backgroundColor',
  'backgroundImage',
  'backgroundPosition',
  'backgroundRepeat',
  'backgroundSize',
  'color',
  'size',
  'transition',
  // Marp CLI.
  'math',
  'lang',
};

/// De Marpit-richtlijn die [content] noemt, of `null` als het proza is.
///
/// Hoofdlettergevoelig, en dat is de kern van de zaak: Marpit vergelijkt zijn
/// sleutels letterlijk en negeert wat het niet kent. `Antwoord:` en `Footer:`
/// doen bij Marp dus niets, en er is geen reden om er een dia voor te bewaren.
/// Vóór #1815 stond hier "elk woord gevolgd door een dubbele punt", en dat is
/// nu juist de vorm van een gewone notitie: `Antwoord: onwaar.` zette een
/// vraagdia stil om in vrije Markdown, met de quiz als codeblok tot gevolg.
///
/// De keerzijde is even belangrijk: `footer:` of `paginate:` doet Marp wél
/// iets mee, dus dáár blijft de bron staan. Zie [requiresWholeMarpBlockPreservation].
String? marpitDirectiveKey(String content) {
  final key = _directiveKey.firstMatch(content)?.group(1);
  return key != null && kMarpitDirectiveNames.contains(key) ? key : null;
}

bool _hasOnlyTypedBackgroundOptions(
  String line, {
  required bool allowVisualStyle,
}) {
  final match = _wholeBackground.firstMatch(line);
  if (match == null) return false;
  var options = match.group(1)!.trim();
  if (!RegExp(r'^bg(?:\s|$)').hasMatch(options)) return false;
  options = options.substring(2).trim();
  if (allowVisualStyle) {
    options = options
        .replaceAll(_imageFilter, '')
        .replaceAll(RegExp(r'\bopacity:\.45\b'), '')
        .replaceAll(_contain, '');
  }
  options = options
      .replaceAll(RegExp(r'\b(?:left|right):\d+%'), '')
      .replaceAll(RegExp(r'\b\d+%'), '')
      .trim();
  return options.isEmpty;
}

// De uitzonderingslijst die hier stond (`advance:`, `tlp:`, `ocideck_`, `_`)
// is met #1815 vervallen. Ze was nodig zolang de toets "elk woord gevolgd door
// een dubbele punt" luidde en OciDecks eigen richtlijnen er dus in liepen. Nu
// [marpitDirectiveKey] positief tegen de Marpit-sleutellijst toetst, valt geen
// van die vier er nog binnen: het zijn geen Marp-richtlijnen. Een uitzondering
// op een regel die niet meer bestaat, leest als een regel die er nog is.

/// Separates background lines the typed image fields cannot carry losslessly.
({String remaining, List<String> preserved}) unsupportedMarpImageLines(
  String source,
) {
  final preserved = <String>[];
  var backgroundCount = 0;
  final kept = <String>[];
  for (final line in source.split('\n')) {
    final trimmed = line.trim();
    if (!_backgroundImage.hasMatch(trimmed)) {
      kept.add(line);
      continue;
    }
    backgroundCount++;
    final laterExtended =
        backgroundCount > 1 &&
        (_imageFilter.hasMatch(trimmed) || _contain.hasMatch(trimmed));
    if (backgroundCount > 2 || laterExtended) {
      preserved.add(line);
    } else {
      kept.add(line);
    }
  }
  return (remaining: kept.join('\n').trim(), preserved: preserved);
}

/// Reads the visual options represented by the first Marp background image.
MarpStyle marpImageStyleFromSource(String source) {
  for (final line in source.split('\n')) {
    if (!_backgroundImage.hasMatch(line)) continue;
    final options = RegExp(r'!\[([^\]]*)\]').firstMatch(line)?.group(1) ?? '';
    return MarpStyle(
      imageFit: _contain.hasMatch(options) ? 'contain' : '',
      imageFilters: _imageFilter
          .allMatches(options)
          .map((match) => match.group(0)!)
          .toList(),
    );
  }
  return const MarpStyle();
}

/// Applies one standard local Marp style directive.
///
/// Unknown underscore directives are marked for verbatim preservation so a
/// newer Marp feature never disappears when an older OciDeck saves the slide.
({bool handled, bool preserve, MarpStyle style}) parseMarpStyleDirective(
  String content,
  MarpStyle current,
) {
  String valueAfter(String prefix) =>
      parseMarkdownYamlScalar(content.substring(prefix.length).trim());

  if (content.startsWith('_color:')) {
    return (
      handled: true,
      preserve: false,
      style: current.copyWith(color: valueAfter('_color:')),
    );
  }
  if (content.startsWith('_backgroundColor:')) {
    return (
      handled: true,
      preserve: false,
      style: current.copyWith(backgroundColor: valueAfter('_backgroundColor:')),
    );
  }
  if (content.startsWith('_backgroundImage:')) {
    return (
      handled: true,
      preserve: false,
      style: current.copyWith(backgroundImage: valueAfter('_backgroundImage:')),
    );
  }
  if (content.startsWith('_header:')) {
    return (
      handled: true,
      preserve: false,
      style: current.copyWith(header: valueAfter('_header:')),
    );
  }
  if (content.startsWith('_footer:')) {
    return (
      handled: true,
      preserve: false,
      style: current.copyWith(footer: valueAfter('_footer:')),
    );
  }
  if (content == 'fit') {
    return (
      handled: true,
      preserve: false,
      style: current.copyWith(headingFit: true),
    );
  }
  return (
    handled: content.startsWith('_'),
    preserve: content.startsWith('_'),
    style: current,
  );
}

/// Serializes the standard Marp options for a slide background image.
String marpBackgroundOptions(
  Slide slide, {
  String positional = '',
  bool overlay = false,
}) => [
  'bg',
  if (positional.isNotEmpty) positional,
  if (slide.marpStyle.imageFit == 'contain')
    'contain'
  else if (slide.imageSize > 0 && positional.isEmpty)
    '${slide.imageSize}%',
  ...slide.marpStyle.imageFilters,
  if (overlay) 'opacity:.45',
].join(' ');
