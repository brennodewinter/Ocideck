// Genereert het gebundelde gezondheidslexicon uit Orphanet.
//
//   dart run tool/build_privacy_lexicon.dart <map-met-xml> [uitvoerpad]
//
// Invoer: de per-taal `product1`-bestanden van Orphadata, bijvoorbeeld
//
//   for l in nl en de fr es it pl pt cs; do
//     curl -sfL "https://www.orphadata.com/data/xml/${l}_product1.xml" -o "$dir/$l.xml"
//   done
//
// Uitvoer: `assets/privacy/health_lexicon.json`.
//
// ── Waarom Orphanet en niet ORDO ────────────────────────────────────────────
//
// OCIWACHT §13.3 noemde "ORDO in 9 talen (16.378 Nederlandse labels)". Dat klopt
// niet zoals het er staat, en het is bij de bouw nagemeten: ORDO is de
// OWL-ontologie, en die is **Engelstalig** — 4.9 draagt 1179 `xml:lang="en"`-tags
// in de eerste 600 kB en geen enkele andere taal, ook niet halverwege het
// bestand. De meertalige gegevens zitten in een ander product van dezelfde
// uitgever: de `product1`-bestanden, met 11.645 aandoeningen per taal in negen
// talen. Zelfde bron, zelfde licentie (CC BY 4.0, en die staat in het
// XML-bestand zélf onder `<Availability><Licence>`), ander artefact.
//
// ── Waarom alleen de namen, en waarom die lengteband ────────────────────────
//
// Alleen `Disorder/Name`, geen synoniemen: die vermenigvuldigen de omvang en
// voegen vooral spellingsvarianten toe van iets wat al gedekt is.
//
// De band van 10 tot 45 tekens is geen ronde afronding maar het snijpunt van
// twee metingen:
//
//   * **onder de 10** zitten de acroniemen (`MELAS`, `MERRF`, `NANS-CDG`). Vier
//     hoofdletters botsen met van alles, en ze dragen geen woordgrensbewijs;
//   * **boven de 45** staan de samengestelde namen ("Multipele epifysaire
//     dysplasie - macrocefalie - faciale dysmorfie-syndroom"). Volkomen veilig,
//     maar niemand tikt ze voluit, dus ze kosten alleen bytes. Dat scheelt
//     20.634 termen en ruim een megabyte.
//
// ── Wat de vals-positievenmeting opleverde ──────────────────────────────────
//
// De 59.564 kandidaten zijn vóór het bundelen losgelaten op de volledige
// repodocumentatie, met dezelfde hele-woordsemantiek als de scanner gebruikt.
// Eén treffer: `syndroom van epstein`, in OCIWACHT.md §13.2 — precies de zin die
// dat woord aanhaalt als voorbeeld van een naam zonder homoniem. De voorspelling
// uit het ontwerp ("zeldzame ziektenamen gedragen zich als codes") houdt dus
// stand op echte tekst.
//
// Die meting rechtvaardigt het **gewicht** (5, dus een aandoeningsnaam wint van
// een signaalwoord) en de **rol** (`value`, dus redactie haalt hem echt weg) —
// niet de zekerheid. Die blijft `possible`, want onmiskenbaar-een-ziektenaam is
// iets anders dan onmiskenbaar-een-persoonsgegeven: een slide "onze afdeling
// behandelt cystinose" is een dienstbeschrijving. Pas met iemand erbij tilt de
// persoonskoppelingspoort hem omhoog, en dat is precies de bedoeling.
import 'dart:convert';
import 'dart:io';

/// De talen die Orphanet als `product1` publiceert.
const _langs = ['nl', 'en', 'de', 'fr', 'es', 'it', 'pl', 'pt', 'cs'];

/// De lengteband waarin een naam bruikbaar is — zie de kop.
const _minLen = 10;
const _maxLen = 45;

/// De aandoeningsnaam, en niet de naam van het *type* of de *groep*.
///
/// Een `<Disorder>` bevat verderop nog een `<DisorderType><Name>` ("Ziekte",
/// "Malformatiesyndroom") en soms een groepsnaam. Die zijn categorieën en geen
/// aandoeningen, en ze zouden als losse term rampzalig zijn. Vandaar het anker
/// op de voorafgaande `OrphaCode` + `ExpertLink`: dat paar staat alleen vóór de
/// echte naam.
final _namePattern = RegExp(
  r'<OrphaCode>\d+</OrphaCode>\s*'
  r'<ExpertLink[^>]*>[^<]*</ExpertLink>\s*'
  r'<Name lang="[a-z]+">([^<]*)</Name>',
);

/// De licentie zoals de bron hem zelf declareert. Uitgelezen en niet
/// overgeschreven: als Orphanet hem ooit wijzigt, hoort dat hier op te vallen
/// en niet stilzwijgend door te lopen.
final _licencePattern = RegExp(r'<ShortIdentifier>([^<]*)</ShortIdentifier>');

/// De datum die de bron in de wortel meegeeft; die wordt onze bundelversie.
final _datePattern = RegExp(r'<JDBOR date="(\d{4}-\d{2}-\d{2})');

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'build_privacy_lexicon: geef de map met <taal>.xml mee.\n'
      'Voorbeeld: dart run tool/build_privacy_lexicon.dart /tmp/orpha',
    );
    exit(2);
  }
  final dir = Directory(args.first);
  if (!dir.existsSync()) {
    stderr.writeln('build_privacy_lexicon: ${dir.path} bestaat niet.');
    exit(2);
  }
  final outPath = args.length > 1
      ? args[1]
      : 'assets/privacy/health_lexicon.json';

  final terms = <String, List<String>>{};
  final licences = <String>{};
  final dates = <String>{};
  var dropped = 0;

  for (final lang in _langs) {
    final file = File('${dir.path}/$lang.xml');
    if (!file.existsSync()) {
      stderr.writeln(
        'build_privacy_lexicon: $lang.xml ontbreekt — overgeslagen.',
      );
      continue;
    }
    final xml = file.readAsStringSync();

    final licence = _licencePattern.firstMatch(xml)?.group(1);
    if (licence != null) licences.add(licence);
    final date = _datePattern.firstMatch(xml)?.group(1);
    if (date != null) dates.add(date);

    final kept = <String>{};
    for (final m in _namePattern.allMatches(xml)) {
      final name = _unescape(m.group(1)!.trim());
      if (name.length < _minLen || name.length > _maxLen) {
        dropped++;
        continue;
      }
      kept.add(name);
    }
    terms[lang] = kept.toList()..sort();
    stdout.writeln('$lang: ${kept.length} namen');
  }

  if (terms.isEmpty) {
    stderr.writeln('build_privacy_lexicon: niets gevonden — klopt de map?');
    exit(2);
  }

  // Eén onverwachte licentie is genoeg om te stoppen. Deze lijst mag alleen
  // meegeleverd worden zolang de bron CC BY 4.0 is; dat stilzwijgend laten
  // verschuiven is precies de fout die §13.8 bij drie andere bronnen tegenhoudt.
  if (licences.length != 1 || licences.single != 'CC-BY-4.0') {
    stderr.writeln(
      'build_privacy_lexicon: onverwachte licentie(s) in de bron: $licences.\n'
      'Verwacht precies CC-BY-4.0. Controleer de voorwaarden vóór je bundelt.',
    );
    exit(1);
  }

  final payload = {
    'source': 'Orphanet (product1, nomenclatuur)',
    'sourceUrl': 'https://www.orphadata.com/data/xml/',
    'licence': licences.single,
    'licenceUrl': 'https://creativecommons.org/licenses/by/4.0/',
    'attribution':
        'Orphanet. INSERM 1997. Portal for rare diseases and orphan drugs. '
        'https://www.orpha.net/ — CC BY 4.0.',
    'version': (dates.toList()..sort()).last,
    'category': 'special.health',
    'minLength': _minLen,
    'maxLength': _maxLen,
    'terms': terms,
  };

  final out = File(outPath);
  out.parent.createSync(recursive: true);
  out.writeAsStringSync('${jsonEncode(payload)}\n');

  final total = terms.values.fold<int>(0, (a, b) => a + b.length);
  stdout.writeln(
    '\n$total termen in ${terms.length} talen → ${out.path} '
    '(${(out.lengthSync() / 1024 / 1024).toStringAsFixed(2)} MB)\n'
    '$dropped namen vielen buiten de band $_minLen-$_maxLen.\n'
    'Versie ${payload['version']}, licentie ${payload['licence']}.',
  );
}

/// De vijf XML-entiteiten. Geen volledige parser: dit is een build-gereedschap
/// met één bekende invoervorm, en een parser voor 55 MB per taal is hier duurder
/// dan hij oplevert.
String _unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');
