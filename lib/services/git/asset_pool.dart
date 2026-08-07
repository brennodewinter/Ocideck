import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:path/path.dart' as p;

import '../../models/git_settings.dart';
import '../../utils/lru_cache.dart';
import 'git_forge.dart';

/// Isolate-werkfunctie: sha-256 over de bytes. Buiten de UI-isolate omdat een
/// video van honderden megabytes anders een frame-drop kost.
String _sha256Worker(Uint8List bytes) => sha256.convert(bytes).toString();

/// De gedeelde, content-geadresseerde asset-pool van §6.
///
/// Eén afbeelding of video staat per repo één keer onder `assets/<sha256>.<ext>`
/// en wordt door vele decks aangehaald. Dat is geen hoop maar een gevolg: de
/// bestandsnaam ís de hash van de inhoud, dus twee decks met dezelfde afbeelding
/// verwijzen onvermijdelijk naar hetzelfde pad (P4).
///
/// Waarom sha-256 en niet de md5 die `image_dedup_service` al gebruikt (D1): die
/// vergelijking is vluchtig — hij groepeert duplicaten binnen één sessie en de
/// uitkomst wordt nooit ergens vastgelegd. Een poolnaam is juist permanent en
/// wordt door andere decks vertrouwd, dus daar telt botsingsbestendigheid wél.
/// De md5 blijft dus waar hij zit.
class AssetPool {
  AssetPool({required this.forge, required this.branch});

  final GitForge forge;

  /// De ref waartegen blobs worden gelezen. Een blob is onveranderlijk, dus dit
  /// bepaalt alleen wáár gezocht wordt, niet wat er terugkomt.
  final String branch;

  /// Bytes per `repo:`-verwijzing.
  ///
  /// Bewust statisch en zonder vervaltijd: bij content-adressering kan deze
  /// cache niet verouderen. De sleutel is de hash van de inhoud, dus verandert
  /// de inhoud, dan verandert de sleutel — een stale hit bestaat niet.
  ///
  /// Maar die eigenschap is geléénd, niet gegeven: ze geldt alleen zolang de
  /// bytes ook echt bij de hash hóren. Een forge is onvertrouwd (P5) en kan bij
  /// `assets/<sha>.png` van alles serveren. Omdat deze cache repo-overstijgend
  /// is, zou één vijandige repo daarmee de bytes vergiftigen die een eerlijke
  /// repo later leest. Daarom verifieert [resolve] de hash vóór het opslaan —
  /// zie [_verifyOrThrow]. Content-adressering die het adres niet controleert
  /// is niet meer dan een bestandsnaam.
  ///
  /// De cache is begrensd op 256 entries (LRU): een lange sessie met veel
  /// verschillende assets zou anders het geheugen onbegrensd laten groeien.
  /// Content-adressering maakt LRU veilig — een geëvicteerde entry wordt bij
  /// de volgende resolve gewoon opnieuw opgehaald en geverifieerd.
  static final LruCache<String, Uint8List> _cache = LruCache(256);

  /// De poolverwijzing voor [bytes], afgeleid van de inhoud plus de extensie van
  /// [name]. Null wanneer er geen bruikbare extensie te maken is.
  static Future<String?> refFor(Uint8List bytes, {required String name}) async {
    final ext = extensionOf(name);
    if (ext == null) return null;
    final hash = await compute(_sha256Worker, bytes);
    return GitRepoLayout.assetRef(hash, ext);
  }

  /// De extensie van [name], zonder punt en in kleine letters. Null wanneer er
  /// geen is, of wanneer hij geen pad-segment mag worden.
  static String? extensionOf(String name) {
    final ext = p.extension(name.trim()).replaceFirst('.', '').toLowerCase();
    return ext.isEmpty ? null : ext;
  }

  /// De bytes achter een `repo:`-verwijzing. Haalt hem één keer op en onthoudt
  /// hem daarna. Gooit [GitForgeException] wanneer de verwijzing onveilig is of
  /// de blob niet te lezen valt.
  Future<Uint8List> resolve(String reference) async {
    final cached = _cache[reference];
    if (cached != null) return cached;

    final path = GitRepoLayout.assetPathOf(reference);
    if (path == null) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Geen geldige asset-verwijzing',
      );
    }
    final bytes = await forge.readBlob(branch, path);
    await _verifyOrThrow(reference, path, bytes);
    _cache[reference] = bytes;
    return bytes;
  }

  /// Controleer dat [bytes] daadwerkelijk hashen naar de sha in [path].
  ///
  /// Dit is wat content-adressering betekent, en het is geen formaliteit: zonder
  /// deze controle kan een forge onder een hash-naam iets anders serveren, en
  /// belandt dat via de gedeelde cache ook bij andere repo's. Fail-closed (P5):
  /// een blob die niet bij zijn naam past nemen we niet aan.
  Future<void> _verifyOrThrow(
    String reference,
    String path,
    Uint8List bytes,
  ) async {
    final expected = p.basenameWithoutExtension(path).toLowerCase();
    final actual = await compute(_sha256Worker, bytes);
    if (actual != expected) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'De inhoud van een asset komt niet overeen met zijn hash. De '
        'repository is beschadigd of de server levert iets anders dan hij '
        'belooft.',
      );
    }
  }

  /// Welke van [references] al in de repo staan.
  ///
  /// Dít is waar de pool zijn geld verdient bij het opslaan (Fase 2): een asset
  /// die er al is hoeft niet opnieuw omhoog, hoeveel decks hem ook aanhalen. De
  /// tree wordt één keer opgesomd, niet één vraag per verwijzing.
  Future<Set<String>> existing(Iterable<String> references) async {
    final wanted = <String, String>{}; // repo-pad -> verwijzing
    for (final ref in references) {
      final path = GitRepoLayout.assetPathOf(ref);
      if (path != null) wanted[path] = ref;
    }
    if (wanted.isEmpty) return {};

    final entries = await forge.listTree(
      branch,
      GitRepoLayout.assetsRoot,
      recursive: true,
    );
    final present = <String>{};
    for (final entry in entries) {
      if (entry.type != RepoEntryType.file) continue;
      final ref = wanted[entry.path];
      if (ref != null) present.add(ref);
    }
    return present;
  }

  /// Alles vergeten — alleen voor tests. De cache is statisch, dus zonder dit
  /// zou de ene test de andere kunnen beïnvloeden.
  static void clearCache() => _cache.clear();
}
