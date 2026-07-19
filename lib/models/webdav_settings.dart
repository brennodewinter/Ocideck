import 'package:path/path.dart' as p;

/// Waar een server zijn WebDAV-bestanden onder ophangt. Het protocol is in
/// beide gevallen gewone WebDAV (PROPFIND/GET/PUT/MKCOL); alleen het pad naar
/// de wortel verschilt, en dát is het enige wat Nextcloud bijzonder maakt.
enum WebdavServerKind {
  /// Nextcloud en ownCloud: bestanden onder `/remote.php/dav/files/<user>`.
  /// Het pad wordt afgeleid, de gebruiker vult alleen de server-origin in.
  nextcloud,

  /// Elke andere WebDAV-server. Er valt geen padschema te raden, dus geldt:
  /// het pad dat in [WebdavServer.baseUrl] staat *is* de DAV-wortel.
  generic,
}

/// Configuratie van één WebDAV-bron. Bewust géén wachtwoord: dat staat
/// versleuteld in de keychain (zie `SecretStore`), gekeyd op [baseUrl] +
/// [username]. Deze waarden mogen wél in het prefs-domein.
///
/// [rootPath] is een optionele submap binnen de DAV-wortel waar de browser
/// opent en waar decks landen — los van [kind], want die bepaalt alleen waar
/// de wortel zelf ligt.
class WebdavServer {
  /// Server-origin zonder pad, bv. `https://cloud.example.com`. Trailing
  /// slashes worden bij het bouwen van URL's genegeerd.
  final String baseUrl;

  /// Gebruikersnaam voor de aanmelding; bij [WebdavServerKind.nextcloud] ook
  /// onderdeel van het DAV-pad.
  final String username;

  /// Submap binnen de gebruikersbestanden, bv. `/Presentaties`. Leeg = wortel.
  final String rootPath;

  /// De gebruiker heeft expliciet bevestigd dat dit een vertrouwde interne
  /// server is; pas dán mag een privé/LAN-host de SSRF-blokkade passeren.
  final bool trustedInternal;

  /// Welk padschema de server aanhoudt. Standaard [WebdavServerKind.nextcloud]
  /// omdat dat het enige was voordat andere servers ondersteund werden — zo
  /// blijven bestaande, opgeslagen bronnen zonder migratie werken.
  final WebdavServerKind kind;

  const WebdavServer({
    required this.baseUrl,
    required this.username,
    this.rootPath = '',
    this.trustedInternal = false,
    this.kind = WebdavServerKind.nextcloud,
  });

  bool get isConfigured =>
      baseUrl.trim().isNotEmpty && username.trim().isNotEmpty;

  /// De host van [baseUrl], of leeg wanneer onparseerbaar.
  String get host => Uri.tryParse(baseUrl.trim())?.host ?? '';

  /// Origin (scheme + host + poort) van [baseUrl] zonder pad.
  Uri? get origin {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    );
  }

  /// Gedecodeerde pad-segmenten tot aan de DAV-wortel. Dit is de enige plek
  /// waar het verschil tussen de servertypes leeft; zowel het bouwen van URL's
  /// ([davPrefix]) als het terugvertalen van hrefs uit een PROPFIND-antwoord
  /// leest hiervan af, zodat die twee niet uiteen kunnen lopen.
  List<String> get davSegments => switch (kind) {
    WebdavServerKind.nextcloud => [
      'remote.php',
      'dav',
      'files',
      username.trim(),
    ],
    // `pathSegments` decodeert percent-codering, precies wat de href-kant
    // verwacht. Een URL zonder pad levert een lege lijst: DAV op de wortel.
    WebdavServerKind.generic =>
      (Uri.tryParse(baseUrl.trim())?.pathSegments ?? const <String>[])
          .where((s) => s.isNotEmpty)
          .toList(),
  };

  /// Pad-prefix tot aan de DAV-wortel, percent-gecodeerd en zonder trailing
  /// slash — leeg wanneer de wortel de server-wortel zelf is.
  String get davPrefix => davSegments.isEmpty
      ? ''
      : '/${davSegments.map(Uri.encodeComponent).join('/')}';

  /// Normaliseer een door de UI gegeven (mogelijk lege) submap tot een pad dat
  /// met `/` begint en geen trailing slash heeft. Geen `..` toegestaan.
  static String normalizeRoot(String raw) {
    var r = raw.trim();
    if (r.isEmpty) return '';
    r = r.replaceAll(RegExp(r'/+'), '/');
    if (!r.startsWith('/')) r = '/$r';
    if (r.length > 1 && r.endsWith('/')) r = r.substring(0, r.length - 1);
    return r;
  }

  /// Bouw de absolute DAV-URL voor een [remotePath] dat relatief is aan
  /// [rootPath]. Containment wordt afgedwongen: een pad dat met `..` uit de
  /// wortel zou breken levert `null`. Een trailing slash markeert een map.
  Uri? uriFor(String remotePath, {bool isCollection = false}) {
    final base = origin;
    if (base == null) return null;
    final root = normalizeRoot(rootPath);
    // Combineer root + relatief pad en normaliseer; weiger als het buiten root valt.
    final rawJoin = p.posix.normalize('$root/${remotePath.trim()}');
    final scoped = rawJoin == '.' ? '' : rawJoin;
    final rootForCheck = root.isEmpty ? '' : root;
    if (rootForCheck.isNotEmpty &&
        scoped != rootForCheck &&
        !p.posix.isWithin(rootForCheck, scoped)) {
      return null; // pad-traversal buiten de geconfigureerde wortel
    }
    final segments = scoped.split('/').where((s) => s.isNotEmpty).toList();
    final encoded =
        '$davPrefix${segments.isEmpty ? '' : '/${segments.map(Uri.encodeComponent).join('/')}'}';
    return base.replace(path: '$encoded${isCollection ? '/' : ''}');
  }

  WebdavServer copyWith({
    String? baseUrl,
    String? username,
    String? rootPath,
    bool? trustedInternal,
    WebdavServerKind? kind,
  }) {
    return WebdavServer(
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      rootPath: rootPath ?? this.rootPath,
      trustedInternal: trustedInternal ?? this.trustedInternal,
      kind: kind ?? this.kind,
    );
  }

  Map<String, Object?> toJson() => {
    'baseUrl': baseUrl,
    'username': username,
    'rootPath': rootPath,
    'trustedInternal': trustedInternal,
    'kind': kind.name,
  };

  factory WebdavServer.fromJson(Map<String, Object?> json) {
    return WebdavServer(
      baseUrl: (json['baseUrl'] as String?) ?? '',
      username: (json['username'] as String?) ?? '',
      rootPath: (json['rootPath'] as String?) ?? '',
      trustedInternal: (json['trustedInternal'] as bool?) ?? false,
      // Ontbrekend veld = bron uit een versie van vóór de servertype-keuze;
      // die was per definitie Nextcloud. Een onbekende waarde valt om
      // dezelfde reden terug, in plaats van de bron onbruikbaar te maken.
      kind: WebdavServerKind.values.firstWhere(
        (k) => k.name == json['kind'],
        orElse: () => WebdavServerKind.nextcloud,
      ),
    );
  }
}

/// Formaat waarin een deck naar een netwerkbron wordt teruggeschreven.
///
/// Niet WebDAV-specifiek: S3 kent exact dezelfde twee vormen, en de keuze die
/// de gebruiker maakt is dezelfde vraag. Eén enum in plaats van twee gelijke,
/// zodat het opslaan-dialoog voor beide bronnen kan werken.
enum DeckSaveFormat {
  /// Eén zelfstandig `.ocideck`-pakket (zip met assets).
  ocideck,

  /// Platte spiegel: `.md` plus losse asset-mappen in dezelfde map.
  flat,
}

/// Herkomst van een tab die uit een WebDAV-bron is geopend, zodat "Opslaan naar
/// Nextcloud" weet waar (en op welke server) terug te schrijven. [baseUrl] en
/// [username] dienen om een serverwissel te detecteren.
class WebdavOrigin {
  /// De verbinding waar dit deck vandaan kwam. Hiermee gaat "Opslaan naar
  /// WebDAV" terug naar dezelfde klant zonder opnieuw te vragen — en blijft dat
  /// kloppen als de gebruiker de verbinding hernoemt of de server-URL
  /// corrigeert. Leeg voor herkomst uit een versie van vóór de
  /// verbindingenlijst; dan valt de app terug op [baseUrl] + [username].
  final String connectionId;

  final String baseUrl;
  final String username;

  /// Pad van het oorspronkelijk geopende bestand, relatief aan de wortelmap.
  final String remotePath;

  /// De versie die op de server stond toen wij dit bestand ophaalden (of er
  /// voor het laatst naartoe schreven). Hiermee kan een volgende opslag zeggen
  /// "alleen als er sindsdien niets veranderd is". `null` wanneer de server
  /// geen ETag gaf — dan valt er niets te bewaken en schrijven we zoals
  /// voorheen onvoorwaardelijk.
  final String? etag;

  const WebdavOrigin({
    required this.baseUrl,
    required this.username,
    required this.remotePath,
    this.connectionId = '',
    this.etag,
  });

  /// Map waarin het bestand staat (relatief aan de wortel), of leeg voor de
  /// wortel zelf.
  String get parentPath {
    final i = remotePath.lastIndexOf('/');
    return i < 0 ? '' : remotePath.substring(0, i);
  }

  bool matchesServer(WebdavServer server) =>
      server.baseUrl.trim() == baseUrl.trim() &&
      server.username.trim() == username.trim();
}
