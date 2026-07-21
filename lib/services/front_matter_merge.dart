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
/// niet implementeert (`header`, `footer`, `size`, `style`), een sleutel van een
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
  'ocideck_sig_name',
  'ocideck_sig_role',
  'ocideck_sig_cert',
  'ocideck_sig_date',
  'ocideck_sig_statement',
  'ocideck_sig_typed',
  'ocideck_sig_image',
  'ocideck_finalized',
  'ocideck_seal_hash',
  'ocideck_seal_algo',
  'ocideck_seal_at',
  'ocideck_seal_tsr',
  'ocideck_style_profile',
  'ocideck_miauw_waivers',
  'ocideck_miauw_confirmations',
};

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

/// Werk de front matter van een bestaand bestand bij met de regels die OciDeck
/// nú zou schrijven, zonder de rest aan te raken.
///
/// [original] zijn de front-matter-regels zoals ze in het bestand stonden
/// (zonder de `---`-hekken), [generated] de regels die de serialisatie
/// oplevert. De uitkomst:
///
/// - een sleutel uit [kOwnedFrontMatterKeys] die in [original] staat, wordt op
///   zijn eigen plek vervangen door wat [generated] ervoor heeft — of
///   weggelaten als [generated] hem niet meer schrijft;
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
      inOwnedBlock = kOwnedFrontMatterKeys.contains(key);
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
