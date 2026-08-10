// Het formaatcontract van de front matter: welke sleutels OciDeck bezit, en hoe
// een bestaand bestand bij opslaan wordt bijgewerkt zonder de rest ervan aan te
// raken.
//
// Bewust een losse, afhankelijkheidsvrije module: dit is een tekstbewerking op
// regels, geen deck-kennis, en zo is het contract apart te toetsen.

/// De formaatversie die deze build schrijft (front-matter-sleutel
/// [kFormatVersionKey]).
///
/// Eén monotone integer, geen `major.minor`: er is maar één vraag te
/// beantwoorden — "is dit bestand ouder dan ik?" — en daar is een volgnummer
/// genoeg voor. Ontbreekt de sleutel, dan is het bestand versie 1; dat geldt
/// voor elk handgeschreven Marp-bestand, dus afwezigheid is nooit een fout.
const int kOciDeckFormatVersion = 1;

/// De oudste formaatversie die bestaat. Elk bestand zonder [kFormatVersionKey]
/// is er een — dat is niet uitzonderlijk maar de normale toestand van elk
/// handgeschreven Marp-bestand.
const int kOldestFormatVersion = 1;

/// De front-matter-sleutel die [kOciDeckFormatVersion] draagt.
const String kFormatVersionKey = 'ocideck_format';

/// De versie die het bestand declareert, uit de ruwe `ocideck_format`-waarde.
///
/// Alles wat geen bruikbaar versienummer is telt als [kOldestFormatVersion]. Een
/// bestand weigeren op een onleesbare versiesleutel zou het onbruikbaar maken om
/// een reden die de auteur niet kan zien; als oudste versie lezen betekent
/// hooguit dat het opwaarderingspad nog een keer overloopt, en dat is
/// onschadelijk.
int readFormatVersion(String raw) {
  final n = int.tryParse(raw.trim());
  return (n == null || n < kOldestFormatVersion) ? kOldestFormatVersion : n;
}

/// De versie die bij opslaan in het bestand komt: het hoogste van wat het
/// bestand al zei en wat deze build schrijft.
///
/// **Een lezer verlaagt de versie nooit.** Leest deze build een bestand met
/// `ocideck_format: 2`, dan schrijft hij `2` terug — anders liegt het bestand na
/// één keer opslaan over zichzelf. Dat kan alleen doordat [mergeFrontMatter] de
/// sleutels van die nieuwere versie laat staan: de versie klopt dan nog steeds
/// met wat er in het bestand staat.
int persistedFormatVersion(int fileVersion) =>
    fileVersion > kOciDeckFormatVersion ? fileVersion : kOciDeckFormatVersion;

/// De front-matter-sleutels die OciDeck zelf schrijft en dus mag vervangen of
/// weghalen. Alles daarbuiten is van iemand anders — een Marp-optie die OciDeck
/// niet implementeert (`size`, `style`), een sleutel van een
/// nieuwere OciDeck-versie, of een aantekening van de auteur — en blijft bij het
/// opslaan ongemoeid staan waar hij stond.
///
/// **Deze lijst moet meegroeien met de generator.** Een sleutel die OciDeck
/// schrijft maar hier ontbreekt, wordt bij elke opslag opnieuw achteraan
/// toegevoegd terwijl de oude regel blijft staan — dan verdubbelt hij per keer.
/// `front_matter_contract_test.dart` bewaakt dat: het serialiseert een deck
/// waarin élk veld gevuld is en eist dat elke geschreven sleutel hier staat.
const Set<String> kOwnedFrontMatterKeys = {
  'marp',
  'theme',
  'paginate',
  'color',
  'backgroundColor',
  'backgroundImage',
  'header',
  'footer',
  'title',
  'author',
  'organization',
  'version',
  'date',
  'description',
  'keywords',
  'standards',
  'tool',
  'language',
  'tlp',
  'privacy',
  kFormatVersionKey,
  'ocideck_target_seconds',
  'ocideck_show_rehearsal_summary',
  'ocideck_play_only',
  'ocideck_improvement_framework',
  'ocideck_improvement_y01',
  'ocideck_improvement_y01_unit',
  'ocideck_improvement_y01_usl',
  'ocideck_improvement_y01_lsl',
  'ocideck_improvement_y01_target',
  'ocideck_improvement_y01_baseline',
  'ocideck_improvement_y01_goal',
};

/// Sleutels die OciDeck ooit schreef en nu niet meer, maar nog wél bezit.
///
/// Ze zijn niet uit [kOwnedFrontMatterKeys] verdwenen maar hierheen verhuisd,
/// en dat verschil is het hele punt. Een sleutel die van beide lijsten af is,
/// valt onder "wat ik niet ken laat ik met rust": hij zou dan tot in lengte van
/// dagen in het bestand blijven staan. Hier staan betekent: bij het opslaan
/// gaat de regel eruit, en komt hij niet terug.
///
/// `ocideck_style_profile` reisde alleen mee in de vluchtige beamer-payload en
/// gaat nu naast de markdown mee in dezelfde boodschap; de twee MIAUW-sleutels
/// stonden wél op schijf en verhuizen naar de `.miauw.json`-sidecar.
///
/// Het zegel- en het handtekeningblok volgden in dezelfde beweging naar
/// `.seal.json`: ze gaan over het document in plaats van dat ze het document
/// zijn, twee van hun waarden waren ondoorzichtige base64 (`ocideck_seal_tsr`
/// is een DER-token, `ocideck_sig_image` een PNG), en zolang het zegel ín het
/// bestand stond kon de hash niet over het bestand gaan. Zie
/// docs/FILE_FORMAT.md §3.6 en §6.6.
const Set<String> kRetiredFrontMatterKeys = {
  'ocideck_style_profile',
  'ocideck_miauw_waivers',
  'ocideck_miauw_confirmations',
  'ocideck_finalized',
  'ocideck_seal_hash',
  'ocideck_seal_algo',
  'ocideck_seal_at',
  'ocideck_seal_tsr',
  'ocideck_sig_name',
  'ocideck_sig_role',
  'ocideck_sig_cert',
  'ocideck_sig_date',
  'ocideck_sig_statement',
  'ocideck_sig_typed',
  'ocideck_sig_image',
};

/// Of [key] van OciDeck is: geschreven óf opgeruimd. Dit is de toets die
/// bepaalt of een regel bij het opslaan door de generator gaat; alles daarbuiten
/// blijft staan waar het stond.
bool ownsFrontMatterKey(String key) =>
    kOwnedFrontMatterKeys.contains(key) ||
    kRetiredFrontMatterKeys.contains(key);

/// Een sleutelregel op kolom 0 (`key:` of `key: waarde`). Ingesprongen regels
/// vallen er bewust buiten: die horen bij het blok erboven, en dat is precies
/// wat een genest YAML-blok van een losse sleutel onderscheidt.
final _reFrontMatterKey = RegExp(r'^([A-Za-z_][A-Za-z0-9_.-]*)[ \t]*:');

/// Een vervolgregel van het blok erboven: ingesprongen tekst of een
/// lijstitem op kolom 0.
final _reContinuation = RegExp(r'^([ \t]|-(\s|$))');

/// De sleutel die [line] declareert, of null als de regel geen sleutel op
/// kolom 0 is (commentaar, lege regel, vervolgregel).
String? frontMatterKeyOf(String line) =>
    _reFrontMatterKey.firstMatch(line)?.group(1);

/// Of [line] een vervolgregel is van het blok erboven: ingesprongen tekst of
/// een lijstitem.
///
/// Dit is de enige plek waar "hoort bij het blok erboven" wordt vastgelegd; de
/// lezer, de schrijver en de checker moeten er hetzelfde over denken. Deden ze
/// dat niet, dan las de één een ingesprongen `theme:` in een `style: |`-blok als
/// deck-thema terwijl de ander hem als CSS liet staan.
bool isFrontMatterContinuation(String line) => _reContinuation.hasMatch(line);

/// Werk de front matter van een bestaand bestand bij met de regels die OciDeck
/// nú zou schrijven, zonder de rest aan te raken.
///
/// [original] zijn de front-matter-regels zoals ze in het bestand stonden
/// (zonder de `---`-hekken), [generated] de regels die de serialisatie
/// oplevert. De uitkomst:
///
/// - een sleutel die OciDeck bezit ([ownsFrontMatterKey]) en die in [original]
///   staat, wordt op zijn eigen plek vervangen door wat [generated] ervoor
///   heeft — of weggelaten als [generated] hem niet meer schrijft;
/// - elke andere regel blijft exact staan waar hij stond, inclusief
///   `#`-commentaar, lege regels, ingesprongen blokken, de oorspronkelijke
///   volgorde en de oorspronkelijke aanhalingstekens;
/// - sleutels die OciDeck schrijft maar die het bestand nog niet had, komen
///   achteraan in de volgorde waarin de generator ze levert.
///
/// De bewerking is idempotent: de uitkomst nog eens door dezelfde molen halen
/// levert dezelfde regels op. Dat is de eigenschap waar het zegel op leunt —
/// openen-en-opslaan mag de gecanonicaliseerde inhoud niet verschuiven.
///
/// Bewust géén YAML-parser: die zou de tekst herschrijven (aanhalingstekens,
/// inspringing, commentaar) en dan is de belofte "wat ik niet ken laat ik met
/// rust" niet meer waar te maken.
List<String> mergeFrontMatter({
  required List<String> original,
  required List<String> generated,
}) {
  // Geen bronregels (een nieuw deck, of een bestand zonder front matter): dan is
  // de uitkomst simpelweg wat de generator schrijft.
  if (original.isEmpty) return List<String>.of(generated);

  final byKey = <String, List<String>>{};
  final order = <String>[];
  for (final line in generated) {
    final key = frontMatterKeyOf(line);
    if (key == null) continue;
    byKey
        .putIfAbsent(key, () {
          order.add(key);
          return <String>[];
        })
        .add(line);
  }

  final out = <String>[];
  final placed = <String>{};
  // Staat de laatst geziene sleutel op naam van OciDeck? Dan horen zijn
  // vervolgregels bij de waarde die we vervangen en gaan ze mee weg. Lege regels
  // en commentaar op kolom 0 zetten dit niet terug: die horen bij niemand.
  var inOwnedBlock = false;
  for (final line in original) {
    final key = frontMatterKeyOf(line);
    if (key != null) {
      inOwnedBlock = ownsFrontMatterKey(key);
      if (!inOwnedBlock) {
        out.add(line);
      } else if (placed.add(key)) {
        // Alleen de eerste keer: een sleutel die meermaals mag voorkomen
        // (`tool:`) levert al zijn regels hier af, de latere bronregels
        // vervallen.
        out.addAll(byKey[key] ?? const <String>[]);
      }
      continue;
    }
    if (_reContinuation.hasMatch(line)) {
      if (!inOwnedBlock) out.add(line);
      continue;
    }
    out.add(line);
  }

  for (final key in order) {
    if (placed.contains(key)) continue;
    out.addAll(byKey[key]!);
  }
  return out;
}
