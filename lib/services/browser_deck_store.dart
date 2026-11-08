import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../utils/log.dart';

/// Bewuste browseropslag van zelfstandige pakketten, inclusief media.
/// Elke presentatie heeft een eigen sleutel: tabbladen overschrijven elkaar
/// niet. Bij quotafouten melden we geen geslaagde opslag.
class BrowserDeckStore {
  static const key = 'browserDeckPackageV1.';
  static const maxEncodedLength = 5 * 1024 * 1024;

  Future<List<BrowserDeckEntry>> list() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return [
      for (final storageKey in prefs.getKeys().where((k) => k.startsWith(key)))
        BrowserDeckEntry.fromJson(
          jsonDecode(prefs.getString(storageKey)!) as Map<String, dynamic>,
        ),
    ];
  }

  static Future<void> _pending = Future<void>.value();

  /// Serialiseer schrijvers in deze app, inclusief bewaren tijdens verwijderen.
  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<String> save(String title, Uint8List bytes, {String? id}) =>
      _serialize(() async {
        final entries = await list();
        final entry = BrowserDeckEntry(
          id: id ?? const Uuid().v4(),
          title: title,
          savedAt: DateTime.now().toUtc().toIso8601String(),
          package: base64Encode(bytes),
        );
        entries.removeWhere((e) => e.id == entry.id);
        entries.add(entry);
        if (jsonEncode(entries.map((e) => e.toJson()).toList()).length >
            maxEncodedLength) {
          throw StateError('Browser storage budget exceeded');
        }
        await _write(entry);
        return entry.id;
      });

  Future<void> remove(String id) => _serialize(() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove('$key$id')) {
      throw StateError('Browser storage deletion rejected');
    }
  });

  Future<void> _write(BrowserDeckEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final storageKey = '$key${entry.id}';
    final previous = prefs.getString(storageKey);
    try {
      if (!await prefs.setString(storageKey, jsonEncode(entry.toJson()))) {
        throw StateError('Browser storage write rejected');
      }
    } catch (e, s) {
      logError('browser-storage: write failed', e, s);
      // SharedPreferences kan zijn cache al hebben aangepast vóór de fout.
      if (previous == null) {
        await prefs.remove(storageKey);
      } else {
        await prefs.setString(storageKey, previous);
      }
      rethrow;
    }
  }
}

class BrowserDeckEntry {
  const BrowserDeckEntry({
    required this.id,
    required this.title,
    required this.savedAt,
    required this.package,
  });
  final String id;
  final String title;
  final String savedAt;
  final String package;
  Uint8List get bytes => base64Decode(package);

  factory BrowserDeckEntry.fromJson(Map<String, dynamic> value) =>
      BrowserDeckEntry(
        id: value['id'] as String,
        title: value['title'] as String,
        savedAt: value['savedAt'] as String,
        package: value['package'] as String,
      );
  Map<String, String> toJson() => {
    'id': id,
    'title': title,
    'savedAt': savedAt,
    'package': package,
  };
}

/// Browserkopieën zijn documenten van de gebruiker, geen instellingen.
/// Een reset van instellingen mag die kopieën niet verwijderen.
Future<void> clearSettingsPreservingBrowserDecks(
  SharedPreferences prefs,
) async {
  for (final storageKey in prefs.getKeys().toList()) {
    if (!storageKey.startsWith(BrowserDeckStore.key)) {
      if (!await prefs.remove(storageKey)) {
        throw StateError('Preference reset rejected');
      }
    }
  }
}
