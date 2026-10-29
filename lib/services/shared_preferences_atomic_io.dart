import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import '../platform/platform_features.dart';
import '../utils/atomic_file.dart';
import '../utils/log.dart';

/// Registreer de atomaire store op Windows/Linux; elders is de eigen
/// platform-implementatie al voldoende (NSUserDefaults, localStorage).
/// No-op op platforms waar deze store niet hoort.
void registerAtomicFilePreferences() {
  if (!isFilePrefsDesktop) return;
  SharedPreferencesStorePlatform.instance = AtomicFilePreferencesStore();
}

/// Atomaire, zelfherstellende `shared_preferences`-opslag voor Windows en
/// Linux — de twee platforms waar de plugin alles in één JSON-bestand
/// herschrijft (#2628).
///
/// Dezelfde map, bestandsnaam en JSON-vorm als `shared_preferences_windows`
/// en `shared_preferences_linux` (`<appSupport>/shared_preferences.json`,
/// een platte `Map<String, Object>`), dus bestaande installaties lezen hun
/// instellingen gewoon verder. Het verschil zit in de grenzen:
///
/// - **Schrijven is atomaar.** Elke mutatie serialiseert de cache en schrijft
///   via [writeStringAtomic] (tijdelijk bestand + rename) in plaats van het
///   bestand in-place af te kappen. Een crash midden in een schrijfbeurt laat
///   hooguit een tijdelijk bestand achter — het echte bestand is heel of
///   afwezig, nooit half.
/// - **Lezen herstelt zichzelf.** Is het bestand onleesbaar (afgekapt JSON,
///   stroomstoring), dan krijgt het een `.corrupt-<tijdstip>`-naam en gaat de
///   app met een lege voorraad verder — één melding via [onCorruption] in
///   plaats van een `FormatException` die elke start opnieuw om toestemming
///   liet vragen.
/// - **Lezen en schrijven zijn async**, waar de plugin `readAsStringSync` en
///   `writeAsStringSync` op de UI-isolate deed.
///
/// Geregistreerd in `main` op Windows en Linux; macOS (NSUserDefaults) en
/// web (localStorage) gebruiken deze grenzen niet.
class AtomicFilePreferencesStore extends SharedPreferencesStorePlatform {
  AtomicFilePreferencesStore({@visibleForTesting File? file})
    : _fileOverride = file;

  static const _fileName = 'shared_preferences.json';
  static const _prefix = 'flutter.';

  /// Wordt hooguit één keer per corrupt bestand aangeroepen; het argument is
  /// het pad van de quarantaine-kopie, of `null` als ook die mislukte. De
  /// instellingenlaag koppelt hier zijn gebruikersmelding aan.
  static void Function(String? quarantinedPath)? onCorruption;

  final File? _fileOverride;
  Map<String, Object>? _cache;
  File? _file;
  Future<void> _writeTail = Future<void>.value();

  Future<File?> _dataFile() async {
    final cached = _file ?? _fileOverride;
    if (cached != null) return cached;
    final dir = await getApplicationSupportDirectory();
    return _file = File(p.join(dir.path, _fileName));
  }

  Future<Map<String, Object>> _read() async {
    final cached = _cache;
    if (cached != null) return cached;
    var prefs = <String, Object>{};
    final file = await _dataFile();
    if (file != null && await file.exists()) {
      final text = await file.readAsString();
      if (text.isNotEmpty) {
        try {
          final data = json.decode(text);
          if (data is Map) prefs = data.cast<String, Object>();
        } on FormatException catch (e) {
          prefs = await _quarantine(file, e);
        }
      }
    }
    return _cache = prefs;
  }

  /// Geen verwijderen maar verplaatsen: het corrupte bestand bevat misschien
  /// nog een deel van de instellingen dat iemand handmatig kan terughalen —
  /// hetzelfde quarantaine-patroon als RecoveryService.
  Future<Map<String, Object>> _quarantine(
    File file,
    FormatException error,
  ) async {
    String? copy;
    try {
      copy = '${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}';
      await file.rename(copy);
    } on Object {
      copy = null;
    }
    logWarning('instellingenbestand onleesbaar; opnieuw begonnen', error);
    onCorruption?.call(copy);
    return <String, Object>{};
  }

  /// Ketent de schrijfbeurt achter de vorige zodat opeenvolgende `set`-
  /// aanroepen elkaar niet overlappen, en rapporteert de echte afloop terug
  /// — de plugin slikte schrijffouten stilzwijgend in `debugPrint`.
  Future<bool> _persist() {
    final task = _writeTail.then((_) async {
      try {
        final file = await _dataFile();
        if (file == null) return false;
        await file.parent.create(recursive: true);
        await writeStringAtomic(file, json.encode(_cache));
        return true;
      } on Object catch (e) {
        logWarning('instellingenbestand schrijven mislukt', e);
        return false;
      }
    });
    _writeTail = task.then((_) {});
    return task;
  }

  Future<bool> _mutate(void Function(Map<String, Object> map) change) async {
    final prefs = await _read();
    change(prefs);
    return _persist();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      _mutate((prefs) => prefs[key] = value);

  @override
  Future<bool> remove(String key) => _mutate((prefs) => prefs.remove(key));

  @override
  Future<bool> clear() => clearWithParameters(
    ClearParameters(filter: PreferencesFilter(prefix: _prefix)),
  );

  @override
  Future<bool> clearWithPrefix(String prefix) => clearWithParameters(
    ClearParameters(filter: PreferencesFilter(prefix: prefix)),
  );

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    final filter = parameters.filter;
    return _mutate(
      (prefs) => prefs.removeWhere(
        (key, _) =>
            key.startsWith(filter.prefix) &&
            (filter.allowList?.contains(key) ?? true),
      ),
    );
  }

  @override
  Future<Map<String, Object>> getAll() => getAllWithParameters(
    GetAllParameters(filter: PreferencesFilter(prefix: _prefix)),
  );

  @override
  Future<Map<String, Object>> getAllWithPrefix(String prefix) =>
      getAllWithParameters(
        GetAllParameters(filter: PreferencesFilter(prefix: prefix)),
      );

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    final filter = parameters.filter;
    final withPrefix = Map<String, Object>.from(await _read());
    withPrefix.removeWhere(
      (key, _) =>
          !(key.startsWith(filter.prefix) &&
              (filter.allowList?.contains(key) ?? true)),
    );
    return withPrefix;
  }
}
