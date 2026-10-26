// Desktop-helft van de bronnenprovenance (#2529): `sources.json` naast de
// opnamewav's in de sessie-stagingmap. De herstelperiode van de staging
// geldt dus ook voor de provenance — ze verdwijnen samen.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/atomic_file.dart';

Future<void> writeCallSources(String stagingDir, String json) =>
    writeStringAtomic(File(p.join(stagingDir, 'sources.json')), json);

/// De bronnenprovenance van een bewaarde callopname teruglezen (#2530) —
/// de bewaarflow en de transcriptiepass noemen daarmee welke bronstukken
/// ontbraken. [wavPath] is de duurzame wav van de sessie; het manifest
/// ligt als `sources.json` ernaast. Synchroon opzet: het bestand is
/// hooguit enkele honderden bytes, en een async lees zou in een
/// widgettest-zone nooit terugkomen. Null bij geen manifest, stuk JSON
/// of een vreemde vorm: een provenance die we niet zeker weten claimen
/// we niet.
Map<String, Object?>? readCallSources(String wavPath) {
  try {
    final file = File(p.join(p.dirname(wavPath), 'sources.json'));
    if (!file.existsSync()) return null;
    final decoded = jsonDecode(file.readAsStringSync());
    // Alleen de vorm die de sessie zelf schreef tellen we mee — een
    // willekeurig `sources.json` naast een gebruikersbestand is geen
    // provenance van OciDeck.
    return decoded is Map<String, Object?> && decoded['version'] == 1
        ? decoded
        : null;
  } on Object {
    return null;
  }
}
