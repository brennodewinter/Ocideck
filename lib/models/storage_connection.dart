import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../utils/log.dart';
import 'git_settings.dart';
import 'webdav_settings.dart';

/// Eén bestandsverbinding: een benoemde plek waar presentaties vandaan komen en
/// naartoe gaan.
///
/// Hiervóór was dit drie losse dingen. Lokale mappen waren een lijst
/// (`LibraryFolder`), WebDAV was er precies één en git ook precies één. Dat
/// hield de vraag "waar staat het werk van deze klant?" verspreid over twee
/// UI-idiomen en drie prefs-sleutels, en het maakte het onmogelijk om voor twee
/// opdrachtgevers naast elkaar te werken — wat juist de normale situatie is
/// zodra je voor meer dan één partij presenteert.
///
/// Hier is elke opslagplek dezelfde soort ding: een [id], een [name] die de
/// gebruiker zelf kiest, en de configuratie die bij de soort hoort. De volgorde
/// waarin ze in [Settings.connections] staan is de volgorde die de gebruiker
/// sleept, en die volgorde is betekenisvol — zie [Settings.primaryOf].
///
/// Bewust géén geheimen in dit object: wachtwoorden en tokens blijven in de
/// keychain (zie `SecretStore`), gekeyd op server + gebruiker. Twee
/// verbindingen naar hetzelfde account delen daardoor één geheim, wat precies
/// klopt: het ís hetzelfde account.
sealed class StorageConnection {
  /// Stabiele sleutel, ook als de gebruiker de naam of de server verandert.
  /// Herkomstgegevens van een geopend deck wijzen hiernaar, zodat hernoemen een
  /// geopend deck niet losweekt van zijn bron.
  final String id;

  /// Vrije naam, bijv. "Klant A – Nextcloud". Mag leeg zijn; de UI valt dan
  /// terug op een afgeleide omschrijving ([fallbackLabel]).
  final String name;

  const StorageConnection({required this.id, required this.name});

  /// Genereer een nieuwe, stabiele verbindings-id.
  static String newId() => const Uuid().v4();

  /// Of de verbinding compleet genoeg is om te gebruiken. Een half ingevulde
  /// verbinding blijft in de lijst staan — hem stilletjes weggooien zou het
  /// werk van de gebruiker opeten — maar telt niet mee als bruikbare bron.
  bool get isConfigured;

  /// Wat de UI toont als de gebruiker geen naam heeft ingevuld.
  String get fallbackLabel;

  StorageConnectionKind get kind;

  Map<String, Object?> toJson();

  /// Serialiseer de hele lijst voor het prefs-domein.
  static String encodeList(List<StorageConnection> connections) =>
      jsonEncode([for (final c in connections) c.toJson()]);

  /// Lees de lijst terug. Een onleesbare waarde levert een lege lijst op; losse
  /// onleesbare items vallen weg zonder de rest mee te nemen, want één kapotte
  /// verbinding mag niet alle andere onbereikbaar maken.
  static List<StorageConnection> decodeList(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map)
            ?StorageConnection.fromJson(Map<String, Object?>.from(item)),
      ];
    } catch (e) {
      logWarning(
        'StorageConnection.decodeList: onleesbare verbindingenlijst',
        e,
      );
      return const [];
    }
  }

  /// Bouw één verbinding uit JSON, of `null` bij een onbekende soort of een
  /// ontbrekende id — beide betekenen dat we het item niet betrouwbaar kunnen
  /// terugzetten.
  static StorageConnection? fromJson(Map<String, Object?> json) {
    final id = (json['id'] as String?)?.trim() ?? '';
    if (id.isEmpty) return null;
    final name = (json['name'] as String?) ?? '';
    final rawConfig = json['config'];
    final config = rawConfig is Map
        ? Map<String, Object?>.from(rawConfig)
        : const <String, Object?>{};
    return switch (json['kind']) {
      'local' => LocalConnection(
        id: id,
        name: name,
        path: (config['path'] as String?) ?? '',
      ),
      'webdav' => WebdavConnection(
        id: id,
        name: name,
        server: WebdavServer.fromJson(config),
      ),
      'git' => GitConnection(
        id: id,
        name: name,
        repo: GitRepoConfig.fromJson(config),
      ),
      _ => null,
    };
  }
}

/// De soorten verbinding. De volgorde hier bepaalt de volgorde in het
/// "verbinding toevoegen"-menu, niet die in de lijst zelf — die kiest de
/// gebruiker.
enum StorageConnectionKind { local, webdav, git }

/// Een map op de schijf van deze computer. De opvolger van `LibraryFolder`:
/// zelfde inhoud (naam + pad), maar nu als gelijkwaardige verbinding naast de
/// netwerkbronnen in plaats van een aparte lijst erboven.
final class LocalConnection extends StorageConnection {
  final String path;

  const LocalConnection({
    required super.id,
    required super.name,
    required this.path,
  });

  @override
  StorageConnectionKind get kind => StorageConnectionKind.local;

  @override
  bool get isConfigured => path.trim().isNotEmpty;

  @override
  String get fallbackLabel => path;

  LocalConnection copyWith({String? name, String? path}) =>
      LocalConnection(id: id, name: name ?? this.name, path: path ?? this.path);

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': 'local',
    'config': {'path': path},
  };
}

/// Een map op een WebDAV-server (Nextcloud, ownCloud of generiek).
final class WebdavConnection extends StorageConnection {
  final WebdavServer server;

  const WebdavConnection({
    required super.id,
    required super.name,
    required this.server,
  });

  @override
  StorageConnectionKind get kind => StorageConnectionKind.webdav;

  @override
  bool get isConfigured => server.isConfigured;

  @override
  String get fallbackLabel => server.host;

  WebdavConnection copyWith({String? name, WebdavServer? server}) =>
      WebdavConnection(
        id: id,
        name: name ?? this.name,
        server: server ?? this.server,
      );

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': 'webdav',
    'config': server.toJson(),
  };
}

/// Een git-repository, waarin elke opgeslagen versie bewaard blijft.
final class GitConnection extends StorageConnection {
  final GitRepoConfig repo;

  const GitConnection({
    required super.id,
    required super.name,
    required this.repo,
  });

  @override
  StorageConnectionKind get kind => StorageConnectionKind.git;

  @override
  bool get isConfigured => repo.isConfigured;

  @override
  String get fallbackLabel => repo.slug;

  GitConnection copyWith({String? name, GitRepoConfig? repo}) =>
      GitConnection(id: id, name: name ?? this.name, repo: repo ?? this.repo);

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': 'git',
    'config': repo.toJson(),
  };
}
