import 'package:path/path.dart' as p;

/// Configuratie van één WebDAV/Nextcloud-bron. Bewust géén wachtwoord: dat
/// staat versleuteld in de keychain (zie `SecretStore`), gekeyd op
/// [baseUrl] + [username]. Deze waarden mogen wél in het prefs-domein.
///
/// Nextcloud exposeert de bestanden van een gebruiker onder
/// `<baseUrl>/remote.php/dav/files/<username>/`. [rootPath] is een optionele
/// submap daarbinnen waar de browser opent en waar decks landen.
class WebdavServer {
  /// Server-origin zonder pad, bv. `https://cloud.example.com`. Trailing
  /// slashes worden bij het bouwen van URL's genegeerd.
  final String baseUrl;

  /// Nextcloud-gebruikersnaam (ook gebruikt in het DAV-pad).
  final String username;

  /// Submap binnen de gebruikersbestanden, bv. `/Presentaties`. Leeg = wortel.
  final String rootPath;

  /// De gebruiker heeft expliciet bevestigd dat dit een vertrouwde interne
  /// server is; pas dán mag een privé/LAN-host de SSRF-blokkade passeren.
  final bool trustedInternal;

  const WebdavServer({
    required this.baseUrl,
    required this.username,
    this.rootPath = '',
    this.trustedInternal = false,
  });

  bool get isConfigured => baseUrl.trim().isNotEmpty && username.trim().isNotEmpty;

  /// De host van [baseUrl], of leeg wanneer onparseerbaar.
  String get host => Uri.tryParse(baseUrl.trim())?.host ?? '';

  /// Origin (scheme + host + poort) van [baseUrl] zonder pad.
  Uri? get origin {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;
    return Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null);
  }

  /// Pad-prefix tot aan de gebruikersbestanden:
  /// `/remote.php/dav/files/<username>`.
  String get davPrefix => '/remote.php/dav/files/${Uri.encodeComponent(username.trim())}';

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
    final encoded = '$davPrefix${segments.isEmpty ? '' : '/${segments.map(Uri.encodeComponent).join('/')}'}';
    return base.replace(path: '$encoded${isCollection ? '/' : ''}');
  }

  WebdavServer copyWith({
    String? baseUrl,
    String? username,
    String? rootPath,
    bool? trustedInternal,
  }) {
    return WebdavServer(
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      rootPath: rootPath ?? this.rootPath,
      trustedInternal: trustedInternal ?? this.trustedInternal,
    );
  }

  Map<String, Object?> toJson() => {
    'baseUrl': baseUrl,
    'username': username,
    'rootPath': rootPath,
    'trustedInternal': trustedInternal,
  };

  factory WebdavServer.fromJson(Map<String, Object?> json) {
    return WebdavServer(
      baseUrl: (json['baseUrl'] as String?) ?? '',
      username: (json['username'] as String?) ?? '',
      rootPath: (json['rootPath'] as String?) ?? '',
      trustedInternal: (json['trustedInternal'] as bool?) ?? false,
    );
  }
}

/// Formaat waarin een deck naar de WebDAV-bron wordt teruggeschreven.
enum WebdavSaveFormat {
  /// Eén zelfstandig `.ocideck`-pakket (zip met assets).
  ocideck,

  /// Platte spiegel: `.md` plus losse asset-mappen in dezelfde map.
  flat,
}

/// Herkomst van een tab die uit een WebDAV-bron is geopend, zodat "Opslaan naar
/// Nextcloud" weet waar (en op welke server) terug te schrijven. [baseUrl] en
/// [username] dienen om een serverwissel te detecteren.
class WebdavOrigin {
  final String baseUrl;
  final String username;

  /// Pad van het oorspronkelijk geopende bestand, relatief aan de wortelmap.
  final String remotePath;

  const WebdavOrigin({
    required this.baseUrl,
    required this.username,
    required this.remotePath,
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
