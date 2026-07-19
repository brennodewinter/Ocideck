// Genereert het gebundelde overtuigingslexicon uit EuroVoc.
//
//   dart run tool/build_eurovoc_lexicon.dart <sparql-resultaat.json> [uitvoerpad]
//
// Zie `make refresh-lexicon` voor de bijbehorende SPARQL-query.
//
// ── Waarom dit er eerst niet in zat, en nu wel ──────────────────────────────
//
// Bij de eerste poging is EuroVoc afgewezen op een **trefwoordzoekopdracht**:
// zoek concepten met "vakbond" of "godsdienst" in het label, en kijk wat je
// krijgt. Dat leverde "Europees Vakbondsinstituut", "Politieke Commissie (73)"
// en "discriminatie op grond van godsdienst" op — instellingsnamen en
// beleidsbegrippen, waardeloos als indicator en soms schadelijk.
//
// Die conclusie was voorbarig, en het lag aan de vraag en niet aan de bron. Loop
// je in plaats daarvan de **hiërarchie** af — alles ónder "godsdienst",
// "politieke ideologie", "vakbond" en "etnische groep" — dan komt er iets heel
// anders boven: `islam`, `jodendom`, `katholicisme`, `protestantisme`,
// `boeddhisme`, `atheïsme`, `communisme`, `fascisme`, `liberalisme`,
// `sociaal-democratie`. Dat zijn precies wél kenmerken van een persoon.
//
// En dan blijkt EuroVoc te doen waar het goed in is: **27 talen**, waarvan 24
// EU-officieel. Religie en politiek hadden in het handgeschreven lexicon termen
// in vijf talen. Dit is de enige bron in dit project die dat gat in één keer
// dicht.
//
// ── Uitsluiten op concept, niet op string ──────────────────────────────────
//
// Ongeveer een derde van de subboom gaat *over* het onderwerp in plaats van
// iemand te beschrijven: `kerk`, `theologie`, `heilige boeken`, `concilie`,
// `interreligieuze dialoog`, `Internationale`. Die vliegen eruit — maar op hun
// **concept-URI** en niet op hun Nederlandse naam. Zo geldt één uitsluiting
// meteen in alle 27 talen, en kan er geen vertaling doorheen glippen die wij
// niet gelezen hebben.
// ── Wat het níét vindt, en dat is gemeten ──────────────────────────────────
//
// EuroVoc levert **zelfstandignaamwoorden**: `katholicisme`, `protestantisme`,
// `jodendom`. In gewone tekst staat vaker het bijvoeglijk naamwoord — "betrokkene
// is katholiek opgevoed" — en dat wordt niet gevonden, want de bulk matcht op
// hele woorden en `katholiek` is geen achtervoegselvariant van `katholicisme`.
//
// Dat is geen oplosbaar detail van deze generator maar een eigenschap van de
// bron: een thesaurus indexeert begrippen, geen woordvormen. Wie die vormen wil,
// zet ze in de handgeschreven vloer (`privacy_lexicon_data.dart`), per taal.
//
// Wat er wél uitkomt, gemeten na het bundelen:
//
//   "Dhr. Bakker: protestantisme, actief in de kerk"   → religie, zeker
//   "Mevr. De Jong is lid van de vakcentrale"          → vakbond, zeker
//   "Onze cursus behandelt islam en jodendom"          → religie, informatief
//   "Het communisme viel in 1989"                      → politiek, informatief
//
// De laatste twee zijn het punt: zonder persoon erbij onderbreekt het niets.
import 'dart:convert';
import 'dart:io';

/// Anker → de regel waaronder zijn subboom valt.
const _anchors = {
  '3257': 'special.religion',
  '1282': 'special.politics',
  '3575': 'special.union',
  '1202': 'special.ethnicity',
};

/// Concepten die het onderwerp beschrijven in plaats van een persoon.
///
/// Elk met de reden erbij, want dit is de lijst waarop iemand later terecht een
/// keuze wil kunnen betwisten.
const _excluded = {
  // Instellingen, gebouwen, gebeurtenissen en vakgebieden — geen kenmerk van
  // iemand, en `kerk` is bovendien een doodgewoon woord.
  '4101': 'kerk',
  '1454': 'religieuze instelling',
  '7342': 'concilie',
  '6009': 'geestelijkheid',
  '7397': 'heilige boeken',
  '7371': 'mythologie',
  '3297': 'theologie',
  'c_57946f1a': 'religieus symbool',
  'c_847fc9f2': 'interreligieuze dialoog',
  // Een categorie van religies, geen religie.
  '6561': 'nieuwe religie',
  // In het Nederlands betekent "anglicisme" een Engels leenwoord. EuroVoc
  // bedoelt het anglicanisme. Zo'n homoniem in een standaard-aan categorie is
  // precies het soort vals-positieve dat de hele controle ongeloofwaardig maakt.
  '5162': 'anglicisme',
  // Organisaties en beleidsbegrippen, geen overtuiging. "Internationale" is
  // daarbij ook nog een alledaags woord.
  '1478': 'Internationale',
  '1479': 'Socialistische Internationale',
  '6862': 'scheiding tussen kerk en staat',
  '907': 'Eurorechts',
};

/// Onder deze lengte matcht een term te veel. Vooral relevant voor de
/// vertalingen: sommige talen korten deze begrippen fors in.
const _minLen = 5;

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'build_eurovoc_lexicon: geef het SPARQL-resultaat (JSON) mee.',
    );
    exit(2);
  }
  final input = File(args.first);
  if (!input.existsSync()) {
    stderr.writeln('build_eurovoc_lexicon: ${input.path} bestaat niet.');
    exit(2);
  }
  final outPath = args.length > 1
      ? args[1]
      : 'assets/privacy/belief_lexicon.json';

  final raw = jsonDecode(input.readAsStringSync()) as Map<String, dynamic>;
  final rows = ((raw['results'] as Map)['bindings'] as List)
      .cast<Map<String, dynamic>>();

  // categorie → taal → termen
  final byCategory = <String, Map<String, Set<String>>>{};
  final concepts = <String>{};
  var skipped = 0;

  for (final row in rows) {
    final anchor = _idOf(row['anchor']?['value'] as String? ?? '');
    final concept = _idOf(row['c']?['value'] as String? ?? '');
    final lang = row['lang']?['value'] as String? ?? '';
    final label = (row['label']?['value'] as String? ?? '').trim();
    final category = _anchors[anchor];
    if (category == null || lang.isEmpty || label.isEmpty) continue;
    if (_excluded.containsKey(concept)) {
      skipped++;
      continue;
    }
    if (label.length < _minLen) {
      skipped++;
      continue;
    }
    concepts.add(concept);
    ((byCategory[category] ??= {})[lang] ??= <String>{}).add(label);
  }

  if (byCategory.isEmpty) {
    stderr.writeln('build_eurovoc_lexicon: niets bruikbaars gevonden.');
    exit(2);
  }

  final terms = {
    for (final e in byCategory.entries)
      e.key: {
        for (final l in e.value.entries) l.key: (l.value.toList()..sort()),
      },
  };

  final payload = {
    'source':
        'EuroVoc (subbomen onder godsdienst, politieke ideologie, '
        'vakbond en etnische groep)',
    'sourceUrl': 'https://op.europa.eu/en/web/eu-vocabularies',
    'licence': 'EU-hergebruiksbeleid (Besluit 2011/833/EU)',
    'licenceUrl':
        'https://eur-lex.europa.eu/legal-content/NL/TXT/?uri=CELEX:32011D0833',
    'attribution':
        '© Europese Unie, 1998-heden. EuroVoc, meertalige thesaurus van de '
        'Europese Unie — hergebruik toegestaan onder Besluit 2011/833/EU.',
    'excludedConcepts': _excluded,
    'minLength': _minLen,
    'terms': terms,
  };

  final out = File(outPath);
  out.parent.createSync(recursive: true);
  out.writeAsStringSync('${jsonEncode(payload)}\n');

  final total = terms.values.fold<int>(
    0,
    (a, b) => a + b.values.fold<int>(0, (c, d) => c + d.length),
  );
  final langs = <String>{for (final c in terms.values) ...c.keys};
  stdout.writeln(
    '$total termen, ${concepts.length} concepten, ${langs.length} talen → '
    '${out.path} (${(out.lengthSync() / 1024).toStringAsFixed(0)} kB)\n'
    '$skipped labels overgeslagen (${_excluded.length} uitgesloten concepten, '
    'plus alles korter dan $_minLen tekens).',
  );
  for (final e in terms.entries) {
    stdout.writeln('  ${e.key}: ${e.value.length} talen');
  }
}

/// Het laatste padsegment van een concept-URI.
String _idOf(String uri) =>
    uri.isEmpty ? '' : uri.substring(uri.lastIndexOf('/') + 1);
