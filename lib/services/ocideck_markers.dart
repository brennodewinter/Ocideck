/// De grammatica van `<!-- ocideck:<kind> v<N> <key=value> … -->` —
/// de tabelmarkers uit het risicodossier-contract
/// (docs/design/RISK_FORMAT.md §2).
///
/// Waarom los van de bestaande `ocideck_*`-richtlijnen: die zijn
/// dia-metadata (`ocideck_template:`, `ocideck_layout:`) en leven in het
/// commentaarblok boven een dia. Deze markers annoteren een *tabel* in
/// lopende tekst, dragen een versie en een ordenlijst van `key=value`-tokens,
/// en mogen gestapeld voorkomen (`calc` op een `risks`-blok). Twee aparte
/// naamruimtes — `ocideck:` met dubbele punt voor tabelcontracten,
/// `ocideck_` voor diadirectieven — zodat geen van beide parsers de ander
/// per ongeluk opeet.
///
/// Zuiver Dart, zoals `markdown_table_lines.dart`: geen imports, geen Flutter.
library;

/// De soorten die het contract kent (§2). Een marker met een onbekende soort
/// parseert óók — [OciTableMarker.kindKnown] zegt dan `false` — zodat een
/// nieuwere marker door een oudere OciDeck intact heenreist (§6).
abstract final class OciMarkerKinds {
  static const risks = 'risks';
  static const measures = 'measures';
  static const scale = 'scale';
  static const view = 'view';
  static const bowtie = 'bowtie';
  static const calc = 'calc';

  static const all = {risks, measures, scale, view, bowtie, calc};
}

/// Eén `<!-- ocideck:… -->`-commentaarregel: soort, grammaticaversie,
/// geordende attributen, en — voor de byte-getrouwe rondreis — de originele
/// regel zelf.
class OciTableMarker {
  /// De `kind` uit `ocideck:<kind>`; altijd aanwezig, mogelijk onbekend.
  final String kind;

  /// Het `v<N>`-getal na de soort. Afwezig of onleesbaar → `0`, want "geen
  /// versie" is niet hetzelfde als "versie 1" (een lezer mag `v2` pas
  /// negeren als hij weet dát het `v2` is).
  final int version;

  /// De `key=value`-tokens in schrijfvolgorde. Onbekende sleutels horen
  /// hier óók in: een oudere lezer die een nieuw attribuut niet kent,
  /// schrijft het ongemoeid terug (§5 regel 2).
  final Map<String, String> attrs;

  /// Tokens na `v<N>` die geen `key=value` zijn — bewaard zodat een
  /// herschreven marker ze niet stil laat vallen.
  final List<String> extras;

  /// De regel zoals hij in het bestand stond, getrimd. Wordt een marker niet
  /// aangepast, dan gaat exact deze tekst terug — geen herformattering van
  /// wat de auteur of een andere tool schreef.
  final String raw;

  const OciTableMarker({
    required this.kind,
    this.version = 0,
    this.attrs = const {},
    this.extras = const [],
    this.raw = '',
  });

  /// Of [kind] in [OciMarkerKinds.all] staat.
  bool get kindKnown => OciMarkerKinds.all.contains(kind);

  /// Of deze grammaticaversie door deze lezer gedragen wordt (v1 nu). Een
  /// hogere versie lezen wij als tabel-plús-onbekende-marker: bewaren, niet
  /// interpreteren (§2).
  bool get versionSupported => version <= 1;

  String? attr(String key) => attrs[key];

  int? intAttr(String key) => int.tryParse(attrs[key] ?? '');

  /// Dezelfde marker met [key] gezet op [value] — of weggelaten bij `null`.
  /// De schrijfvolgorde van de overige attributen blijft staan; een nieuwe
  /// sleutel landt achteraan.
  OciTableMarker withAttr(String key, String? value) {
    final next = Map<String, String>.of(attrs);
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    return OciTableMarker(
      kind: kind,
      version: version,
      attrs: next,
      extras: extras,
    );
  }

  /// De canonieke schrijfvorm (`<!-- ocideck:kind v1 a=b c="d e" -->`).
  /// Alleen gebruiken wanneer de marker inhoudelijk verandert; de ongemoeide
  /// marker gaat als [raw] terug.
  String toComment() => formatOciTableMarker(this);

  OciTableMarker copy() => OciTableMarker(
    kind: kind,
    version: version,
    attrs: Map.of(attrs),
    extras: List.of(extras),
    raw: raw,
  );
}

final _markerLine = RegExp(
  r'^\s*<!--\s*ocideck:([a-z][a-z0-9_]*)\b(.*?)\s*-->\s*$',
);
final _versionToken = RegExp(r'^v(\d+)$');
final _keyToken = RegExp(r'^([a-z][a-z0-9_]*)=');
final _keyName = RegExp(r'^[a-z][a-z0-9_]*$');

/// Of [line] (mogelijk met inspringing) een `<!-- ocideck:… -->`-regel is,
/// los van of de inhoud verder klopt. De scanner gebruikt dit om een
/// marker-*run* te herkennen vóór hij aan grammatica toekomt; een regel die
/// hier op `true` valt maar niet parseert, reist als [OciTableMarker] met
/// alleen [OciTableMarker.raw] mee.
bool isOciTableMarkerLine(String line) => _markerLine.hasMatch(line.trim());

/// Ontleedt één markerregel. `null` als de regel geen `ocideck:`-commentaar
/// is; anders een marker die ook onbekende soorten en kapotte tokens
/// vasthoudt — de rondreis-regel gaat vóór op grammatica-strengheid.
OciTableMarker? parseOciTableMarker(String line) {
  final m = _markerLine.firstMatch(line.trim());
  if (m == null) return null;
  final kind = m.group(1)!;
  var rest = m.group(2)!.trim();
  var version = 0;
  final tokens = <String>[];
  var i = 0;
  // Tokenize: spaties scheiden tokens, behalve binnen dubbele aanhaling.
  while (i < rest.length) {
    while (i < rest.length && rest[i] == ' ') {
      i++;
    }
    if (i >= rest.length) break;
    final start = i;
    var inQuote = false;
    while (i < rest.length && (inQuote || rest[i] != ' ')) {
      if (rest[i] == '"' && (i == start || rest[i - 1] != r'\')) {
        inQuote = !inQuote;
      }
      i++;
    }
    tokens.add(rest.substring(start, i));
  }
  if (tokens.isNotEmpty) {
    final v = _versionToken.firstMatch(tokens.first);
    if (v != null) {
      version = int.parse(v.group(1)!);
      tokens.removeAt(0);
    }
  }
  final attrs = <String, String>{};
  final extras = <String>[];
  for (final token in tokens) {
    final kv = _keyToken.firstMatch(token);
    if (kv == null) {
      extras.add(token);
      continue;
    }
    final key = kv.group(1)!;
    var value = token.substring(kv.end);
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value
          .substring(1, value.length - 1)
          .replaceAll(r'\"', '"')
          .replaceAll(r'\\', r'\');
    }
    attrs[key] = value;
  }
  return OciTableMarker(
    kind: kind,
    version: version,
    attrs: attrs,
    extras: extras,
    raw: line.trim(),
  );
}

/// Schrijft [marker] in de canonieke vorm. Waarden met een spatie, `|` of
/// `"` krijgen dubbele aanhalingstekens met `\"`/`\\`-ontsnapping (§2);
/// sleutels die geen contractnaam zijn, gaan als extra-token mee zodat ze
/// niet verdwijnen.
String formatOciTableMarker(OciTableMarker marker) {
  final buf = StringBuffer('<!-- ocideck:${marker.kind}');
  if (marker.version > 0) buf.write(' v${marker.version}');
  for (final entry in marker.attrs.entries) {
    buf.write(' ${entry.key}=');
    final v = entry.value;
    if (v.isEmpty ||
        v.contains(' ') ||
        v.contains('\t') ||
        v.contains('|') ||
        v.contains('"')) {
      buf.write('"${v.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"');
    } else {
      buf.write(v);
    }
  }
  for (final extra in marker.extras) {
    buf.write(' $extra');
  }
  buf.write(' -->');
  return buf.toString();
}

/// Valideert een contractnaam (`[a-z][a-z0-9_]*`, §2) — o.a. voor `cols=`- en
/// `col=`-sleutels die later als kolomsleutel dienen.
bool isOciContractKey(String key) => _keyName.hasMatch(key);
