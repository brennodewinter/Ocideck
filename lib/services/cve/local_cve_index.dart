import 'dart:convert';
import 'dart:io';

import '../../models/local_cve_record.dart';
import '../../models/local_cve_status.dart';
import '../../utils/atomic_file.dart';
import '../../utils/log.dart';

/// De lokale CVE-index op schijf: een JSONL-bestand plus een klein metabestand.
///
/// Waarom geen database: de enige vraag die we stellen is "welke records
/// bevatten deze tekst", over een corpus die één keer per keer volledig
/// vervangen wordt. Een regelscan beantwoordt dat prima, en scheelt een
/// afhankelijkheid die op vier platforms gebouwd moet worden.
///
/// Waarom niet in het geheugen: 300.000 records als Dart-objecten kosten
/// honderden megabytes. Zoeken scant daarom het bestand en ontleedt alléén de
/// regels die de zoekterm bevatten — de scan is een substring-test op ruwe
/// tekst, geen JSON-parse per record.
/// De vorm van een volledige CVE-id, zoals de gebruiker hem intikt.
final _reCveId = RegExp(r'^cve-\d{4}-\d+$');

class LocalCveIndex {
  /// De map waarin index + meta staan (onder app-support).
  final Directory directory;

  LocalCveIndex(this.directory);

  File get indexFile => File('${directory.path}/cve-index.jsonl');
  File get metaFile => File('${directory.path}/cve-index-meta.json');

  Future<bool> get exists async =>
      indexFile.existsSync() && metaFile.existsSync();

  /// De cijfers van de index die er ligt, of null wanneer er geen bruikbare
  /// index is. Dít is wat "lokaal beschikbaar" betekent.
  ///
  /// Het metabestand alleen is daarvoor geen bewijs. Het is een paar honderd
  /// byte naast een index van honderden megabytes, en juist die grote is wat
  /// een opruimtool weghaalt of een volle schijf afkapt. Bleef de meta dan
  /// staan, dan meldde de app "lokaal beschikbaar — opzoeken gebeurt offline"
  /// terwijl [search] leeg terugkwam. Het opzoekpad valt bewust níét terug op
  /// de online keten, dus las de gebruiker "geen treffers" — in een hulpmiddel
  /// voor beveiligingsbevindingen niet te onderscheiden van "niet van
  /// toepassing". Dat is de gevaarlijkste stille fout die dit onderdeel kan
  /// maken, en daarom telt hier alleen de index zelf.
  ///
  /// De lengte doet mee omdat [LocalCveStats.bytes] bij het bevestigen wordt
  /// vastgelegd en verder nergens werd gelezen: een afgekapte index misleidt
  /// net zo goed als een ontbrekende. Bij twijfel liever opnieuw bouwen dan
  /// stilzwijgend half zoeken.
  Future<LocalCveStats?> stats() async {
    if (!metaFile.existsSync()) return null;
    try {
      final json = jsonDecode(await metaFile.readAsString());
      if (json is! Map<String, dynamic>) return null;
      final parsed = LocalCveStats.fromJson(json);
      if (!indexFile.existsSync()) {
        logWarning('LocalCveIndex.stats: meta zonder index', indexFile.path);
        return null;
      }
      final onDisk = indexFile.lengthSync();
      if (onDisk != parsed.bytes) {
        logWarning(
          'LocalCveIndex.stats: index is $onDisk bytes, meta zegt '
          '${parsed.bytes} — als onbruikbaar behandeld',
        );
        return null;
      }
      return parsed;
    } on FormatException {
      return null;
    }
  }

  /// Opent een schrijfkanaal voor een nieuwe index. Schrijft naar een tijdelijk
  /// bestand: een afgebroken download mag de bestaande, werkende index niet
  /// half overschrijven.
  IOSink openWriter() {
    directory.createSync(recursive: true);
    return _tempFile.openWrite();
  }

  File get _tempFile => File('${indexFile.path}.tmp');

  /// Maakt de zojuist geschreven index de actieve, en legt de meta vast. Pas
  /// hier wordt de oude index vervangen.
  Future<LocalCveStats> commit({
    required String release,
    required String builtOn,
    required int records,
  }) async {
    final temp = _tempFile;
    if (!temp.existsSync()) {
      throw StateError('geen index geschreven om te bevestigen');
    }
    // Eerst de meta van de nieuwe index klaarzetten, dan pas de index zelf
    // omzetten. Andersom — en zo stond het hier — was er een moment waarop de
    // nieuwe index er lag met de méta van de oude ernaast: de instellingen
    // toonden dan de vorige releasetag en bouwdatum boven een andere index. Wie
    // daarop afgaat om te beoordelen of een recente CVE erin kan zitten, kijkt
    // naar het verkeerde antwoord. De lengte kan pas ná het hernoemen worden
    // vastgesteld, dus die komt van het tijdelijke bestand.
    final stats = LocalCveStats(
      release: release,
      builtOn: builtOn,
      records: records,
      bytes: temp.lengthSync(),
    );
    await writeStringAtomic(metaFile, jsonEncode(stats.toJson()));
    if (indexFile.existsSync()) indexFile.deleteSync();
    temp.renameSync(indexFile.path);
    return stats;
  }

  /// Gooit een half geschreven index weg (afgebroken of mislukte bouw).
  void discardPartial() {
    final temp = _tempFile;
    if (temp.existsSync()) temp.deleteSync();
  }

  /// Verwijdert de lokale database volledig.
  Future<void> delete() async {
    discardPartial();
    if (indexFile.existsSync()) indexFile.deleteSync();
    if (metaFile.existsSync()) metaFile.deleteSync();
  }

  /// Zoekt offline. Een exacte CVE-id wint altijd en komt bovenaan; verder is
  /// het een substring-match op id, titel en beschrijving.
  ///
  /// Er gaat geen byte het apparaat uit — dát is de hele reden dat deze index
  /// bestaat.
  Future<List<LocalCveRecord>> search(String query, {int limit = 25}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty || !indexFile.existsSync()) return const [];

    final hits = <LocalCveRecord>[];
    final exact = <LocalCveRecord>[];
    // Alleen een volledige id kan een exacte treffer opleveren.
    final wantsExact = _reCveId.hasMatch(q);

    final lines = indexFile
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      // De goedkope poort: een ruwe substring-test op de regel. Alleen wat hier
      // doorheen komt wordt daadwerkelijk ontleed.
      if (!line.toLowerCase().contains(q)) continue;

      final record = LocalCveRecord.tryParseIndexLine(line);
      if (record == null) continue;

      if (record.id.toLowerCase() == q) {
        exact.add(record);
      } else if (hits.length < limit) {
        hits.add(record);
      }
      // Stoppen zodra er genoeg is.
      //
      // De oude voorwaarde eiste óók een exacte treffer, en die krijg je alleen
      // bij het intikken van een volledige CVE-id. Bij elke trefwoordzoektocht
      // bleef `exact` dus leeg en werd de hele index van honderden megabytes
      // uitgelezen — en regel voor regel in kleine letters omgezet — lang nadat
      // de gevraagde resultaten al binnen waren.
      //
      // Ziet de zoekterm eruit als een id, dan loopt hij wél door tot die
      // gevonden is: een exacte treffer hoort bovenaan en kan verderop nog
      // komen. Anders is vol ook klaar.
      if (hits.length >= limit && (!wantsExact || exact.isNotEmpty)) break;
    }

    return [...exact, ...hits].take(limit).toList();
  }
}
