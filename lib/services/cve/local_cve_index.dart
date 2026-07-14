import 'dart:convert';
import 'dart:io';

import '../../models/local_cve_record.dart';
import '../../models/local_cve_status.dart';
import '../../utils/atomic_file.dart';

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
class LocalCveIndex {
  /// De map waarin index + meta staan (onder app-support).
  final Directory directory;

  LocalCveIndex(this.directory);

  File get indexFile => File('${directory.path}/cve-index.jsonl');
  File get metaFile => File('${directory.path}/cve-index-meta.json');

  Future<bool> get exists async =>
      indexFile.existsSync() && metaFile.existsSync();

  Future<LocalCveStats?> stats() async {
    if (!metaFile.existsSync()) return null;
    try {
      final json = jsonDecode(await metaFile.readAsString());
      if (json is! Map<String, dynamic>) return null;
      return LocalCveStats.fromJson(json);
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
    if (indexFile.existsSync()) indexFile.deleteSync();
    temp.renameSync(indexFile.path);

    final stats = LocalCveStats(
      release: release,
      builtOn: builtOn,
      records: records,
      bytes: indexFile.lengthSync(),
    );
    // Atomisch: het metabestand is wat "er ligt een bruikbare index" betekent.
    // Een half geschreven meta zou een complete index als kapot laten lezen.
    await writeStringAtomic(metaFile, jsonEncode(stats.toJson()));
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
      if (exact.isNotEmpty && hits.length >= limit) break;
    }

    return [...exact, ...hits].take(limit).toList();
  }
}
