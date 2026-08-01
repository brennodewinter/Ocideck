import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// De app-/tabbrede grens voor gecodeerde `mem:`-assets is bereikt.
///
/// Deze fout ontstaat vóór de store verandert. UI-aanroepers kunnen hem dus
/// apart melden zonder een half toegevoegde asset te hoeven terugdraaien.
class WebAssetBudgetExceeded implements Exception {
  final int usedBytes;
  final int requestedBytes;
  final int maximumBytes;

  const WebAssetBudgetExceeded({
    required this.usedBytes,
    required this.requestedBytes,
    required this.maximumBytes,
  });

  @override
  String toString() =>
      'WebAssetBudgetExceeded(used: $usedBytes, requested: $requestedBytes, '
      'maximum: $maximumBytes)';
}

/// In-memory opslag voor afbeeldingen in de webversie.
///
/// Op web bestaat er geen bestandssysteem: een gekozen of geplakte afbeelding
/// leeft als bytes in het geheugen en krijgt een pad met het schema
/// `mem:<uuid>`. De renderlaag (media_previews_image) herkent dat schema en
/// tekent rechtstreeks uit deze store; de gewone pad-resolvers zien `mem:`
/// nooit. De store leeft zolang de pagina leeft — een los opgeslagen `.md` met
/// `mem:`-verwijzingen verliest zijn afbeeldingen dus bij herladen. Exporteren
/// als `.ocideck`-pakket neemt de `mem:`-assets wél mee (zie
/// file_service_package.dart).
class WebAssetStore {
  WebAssetStore._();

  static const scheme = 'mem:';

  /// Maximaal gecodeerde bytes in de hele webapp (alle open tabbladen samen).
  ///
  /// Vier maximale afbeeldingen passen binnen deze grens. Dit begrenst de
  /// bronbytes; Flutter-decodes hebben daarnaast hun eigen 4096px-grens.
  static const maxTotalBytes = 256 * 1024 * 1024; // 256 MiB

  static final Map<String, Uint8List> _bytes = {};
  static final Map<String, String> _names = {};
  static final Map<String, String> _hashForPath = {};
  static final Map<String, List<String>> _pathsForHash = {};
  static int _totalBytes = 0;
  static int? _totalBudgetOverride;
  static final List<Set<String>> _atomicScopes = [];

  static bool isMemPath(String path) => path.startsWith(scheme);

  /// Bewaar [bytes] onder een `mem:`-pad. [name] is de oorspronkelijke
  /// bestandsnaam (voor latere pakket-export en logregels). De aanroeper
  /// valideert de bytes (magic bytes + size-cap) vóór het bewaren.
  ///
  /// Identieke bytes krijgen hetzelfde pad en kosten dus maar eenmaal budget.
  /// Bij een nieuwe inhoud wordt het appbrede budget gecontroleerd vóór enige
  /// map verandert; overschrijding gooit [WebAssetBudgetExceeded].
  static String put(Uint8List bytes, {required String name}) {
    final maximum = _totalBudgetOverride ?? (kIsWeb ? maxTotalBytes : null);
    // Een asset groter dan de hele store kan onmogelijk al aanwezig zijn: zo'n
    // asset is nooit toegelaten. Weiger hem dus vóór de lineaire hashronde.
    if (maximum != null && bytes.length > maximum) {
      throw WebAssetBudgetExceeded(
        usedBytes: _totalBytes,
        requestedBytes: bytes.length,
        maximumBytes: maximum,
      );
    }

    final hash = sha256.convert(bytes).toString();
    for (final candidate in _pathsForHash[hash] ?? const <String>[]) {
      final stored = _bytes[candidate];
      if (stored != null && _sameBytes(stored, bytes)) return candidate;
    }

    if (maximum != null && bytes.length > maximum - _totalBytes) {
      throw WebAssetBudgetExceeded(
        usedBytes: _totalBytes,
        requestedBytes: bytes.length,
        maximumBytes: maximum,
      );
    }

    final path = '$scheme${_uuid.v4()}';
    _bytes[path] = bytes;
    _names[path] = name;
    _hashForPath[path] = hash;
    _pathsForHash.putIfAbsent(hash, () => <String>[]).add(path);
    _totalBytes += bytes.length;
    if (_atomicScopes.isNotEmpty) _atomicScopes.last.add(path);
    return path;
  }

  /// Voer een synchrone samengestelde materialisatie atomair uit.
  ///
  /// Alleen paden die binnen [operation] nieuw zijn gemaakt worden bij een
  /// fout teruggedraaid; bestaande of gededupliceerde assets blijven staan.
  /// De bewerking is bewust synchroon, zodat geen andere event-looptaak tussen
  /// een `put` en de commit een nieuw pad kan publiceren.
  static T atomic<T>(T Function() operation) {
    final created = <String>{};
    _atomicScopes.add(created);
    try {
      final result = operation();
      _atomicScopes.removeLast();
      if (_atomicScopes.isNotEmpty) _atomicScopes.last.addAll(created);
      return result;
    } on Object catch (error, stackTrace) {
      _atomicScopes.removeLast();
      for (final path in created) {
        _remove(path);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Of de store leeg is. Op desktop is hij dat altijd (afbeeldingen gaan naar
  /// schijf), dus een sweep kan er goedkoop op afhaken.
  static bool get isEmpty => _bytes.isEmpty;

  /// Het aantal unieke gecodeerde bytes dat nu budget inneemt.
  static int get totalBytes => _totalBytes;

  /// Het productieplafond geldt alleen voor de browserstore. Tests kunnen het
  /// met [overrideTotalBudgetForTest] activeren op de VM.
  static bool get budgetEnforced => kIsWeb || _totalBudgetOverride != null;

  /// Houd alleen de assets in [live] aan; gooi de rest weg. Retourneert hoeveel
  /// er zijn opgeruimd.
  ///
  /// Dit is de enige plek waar een asset wordt vergeten zonder dat de pagina
  /// herlaadt, dus [live] moet écht compleet zijn: elke `mem:`-verwijzing die
  /// nog terug kan komen — in een open tabblad, in de ongedaan-/opnieuw-stapel,
  /// of op het diaklembord. De aanroeper ([TabsNotifier.sweepWebAssets]) stelt
  /// die verzameling samen; hier vertrouwen we erop dat hij volledig is.
  static int retain(Set<String> live) {
    final dood = _bytes.keys.where((k) => !live.contains(k)).toList();
    for (final k in dood) {
      _remove(k);
    }
    return dood.length;
  }

  static void _remove(String path) {
    final removed = _bytes.remove(path);
    _names.remove(path);
    final hash = _hashForPath.remove(path);
    if (hash != null) {
      final paths = _pathsForHash[hash];
      paths?.remove(path);
      if (paths?.isEmpty ?? false) _pathsForHash.remove(hash);
    }
    if (removed != null) _totalBytes -= removed.length;
  }

  /// De bytes achter een `mem:`-pad, of null (geen mem-pad / niet aanwezig,
  /// bv. na een herlaad van de pagina).
  static Uint8List? bytesFor(String path) => _bytes[path];

  /// De oorspronkelijke bestandsnaam achter een `mem:`-pad.
  static String? nameFor(String path) => _names[path];

  /// Alles wissen — alleen voor tests.
  static void clear() {
    _bytes.clear();
    _names.clear();
    _hashForPath.clear();
    _pathsForHash.clear();
    _totalBytes = 0;
    _atomicScopes.clear();
  }

  /// Verlaag het budget voor snelle grensgevallen zonder honderden MiB te
  /// alloceren. `null` herstelt de productiegrens.
  @visibleForTesting
  static void overrideTotalBudgetForTest(int? bytes) {
    if (bytes != null && bytes < 0) {
      throw ArgumentError.value(bytes, 'bytes', 'must not be negative');
    }
    _totalBudgetOverride = bytes;
  }
}
