import 'dart:convert';
import 'dart:typed_data';

import '../../models/git_settings.dart';
import '../file_service.dart';
import 'git_forge.dart';
import 'git_transport.dart';
import 'git_transport_factory.dart';

/// Forgejo en Gitea achter één adapter: Forgejo is een fork van Gitea en de
/// REST-API's zijn op de punten die wij raken identiek.
///
/// Alleen het read-only oppervlak van Fase 0. De adapter is de enige plek waar
/// Gitea-specifieke kennis mag zitten (P6): de URL-vormen, de auth-header en de
/// JSON-vormen. Naar boven komt alleen [GitForge] met [GitForgeException].
class GiteaForge implements GitForge {
  GiteaForge({
    required this.config,
    required this.token,
    GitTransport? transport,
  }) : _transport = transport ?? createGitTransport(config);

  final GitRepoConfig config;

  /// Het personal access token, uit de keychain gehaald door de aanroeper.
  /// Leeg is toegestaan: een publieke repo lezen mag zonder.
  final String token;

  final GitTransport _transport;

  /// Een blob mag zo groot zijn als een pakket: assets zijn hier de grote
  /// jongens, en de limiet verwijst naar de bron zodat de twee niet kunnen
  /// divergeren.
  static const int maxBlobBytes = FileService.maxPackageBytes;

  /// Cap op een listing-respons, zodat een vijandige forge het geheugen niet kan
  /// laten vollopen.
  static const int maxListingBytes = 16 * 1024 * 1024;

  /// Maximaal aantal entries dat we uit één listing accepteren.
  static const int maxListingEntries = 5000;

  /// Gitea/Forgejo verwacht `Authorization: token <PAT>` — niet `Bearer`.
  Map<String, String> get _headers => {
    'Accept': 'application/json',
    if (token.trim().isNotEmpty) 'Authorization': 'token ${token.trim()}',
  };

  Uri _apiUri(List<String> segments, {Map<String, String>? query}) {
    final origin = config.origin;
    if (origin == null) {
      throw const GitForgeException(
        GitForgeError.config,
        'Ongeldige server-URL',
      );
    }
    return origin.replace(
      pathSegments: [
        'api',
        'v1',
        'repos',
        config.owner.trim(),
        config.repo.trim(),
        ...segments,
      ],
      queryParameters: query,
    );
  }

  /// Vertaal een HTTP-status naar een [GitForgeException]. Alleen 2xx gaat door.
  void _checkStatus(int status) {
    if (status >= 200 && status < 300) return;
    if (status == 401 || status == 403) {
      throw GitForgeException(
        GitForgeError.auth,
        'Aanmelden bij de forge mislukt ($status). Controleer je token en of '
        'het toegang heeft tot ${config.slug}.',
      );
    }
    if (status == 404) {
      // Een forge geeft ook 404 wanneer het token de repo niet mag zien: hij
      // verraadt liever niet dát hij bestaat. De melding mag dat niet als
      // zekerheid presenteren.
      throw const GitForgeException(
        GitForgeError.notFound,
        'Niet gevonden — of je token heeft er geen toegang toe.',
      );
    }
    if (status == 409) {
      throw const GitForgeException(
        GitForgeError.notFound,
        'Repository is leeg.',
      );
    }
    if (status >= 500) {
      throw GitForgeException(GitForgeError.server, 'Serverfout ($status)');
    }
    throw GitForgeException(GitForgeError.server, 'Onverwachte status $status');
  }

  Object? _decodeJson(Uint8List bytes) {
    try {
      return jsonDecode(utf8.decode(bytes));
    } catch (e) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Antwoord van de forge is geen geldige JSON',
      );
    }
  }

  @override
  Future<String> headSha(String branch) async {
    _requireRef(branch);
    final response = await _transport.get(
      _apiUri(['branches', branch]),
      headers: _headers,
      maxBytes: maxListingBytes,
    );
    _checkStatus(response.status);
    final json = _decodeJson(response.bytes);
    if (json is! Map) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Onverwacht antwoord op een branch-opvraging',
      );
    }
    final commit = json['commit'];
    final sha = commit is Map ? commit['id'] : null;
    if (sha is! String || sha.trim().isEmpty) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Branch zonder commit-sha',
      );
    }
    return sha;
  }

  @override
  Future<List<RepoEntry>> listTree(
    String ref,
    String path, {
    bool recursive = false,
  }) async {
    _requireRef(ref);
    if (path.isNotEmpty && !GitRepoLayout.isSafeRepoPath(path)) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Onveilig pad opgevraagd',
      );
    }
    return recursive ? _listRecursive(ref, path) : _listContents(ref, path);
  }

  /// Niet-recursief: `/contents/{path}` geeft één mapniveau.
  Future<List<RepoEntry>> _listContents(String ref, String path) async {
    final response = await _transport.get(
      _apiUri(
        ['contents', ...path.split('/').where((s) => s.isNotEmpty)],
        query: {'ref': ref},
      ),
      headers: _headers,
      maxBytes: maxListingBytes,
    );
    _checkStatus(response.status);
    final json = _decodeJson(response.bytes);
    if (json is! List) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Onverwacht antwoord op een maplisting',
      );
    }
    _requireEntryCount(json.length);
    final entries = <RepoEntry>[];
    for (final raw in json) {
      final entry = _contentsEntry(raw);
      if (entry != null) entries.add(entry);
    }
    return entries;
  }

  /// Recursief: `/git/trees/{ref}?recursive=1` geeft de hele boom in één keer.
  Future<List<RepoEntry>> _listRecursive(String ref, String path) async {
    final response = await _transport.get(
      _apiUri(['git', 'trees', ref], query: {'recursive': '1'}),
      headers: _headers,
      maxBytes: maxListingBytes,
    );
    _checkStatus(response.status);
    final json = _decodeJson(response.bytes);
    if (json is! Map) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Onverwacht antwoord op een tree-opvraging',
      );
    }
    // Gitea kapt een grote tree af en zegt dat eerlijk. Een halve boom stil
    // teruggeven zou erger zijn dan falen: de aanroeper zou denken dat een deck
    // niet bestaat terwijl het alleen niet meegestuurd is.
    if (json['truncated'] == true) {
      throw const GitForgeException(
        GitForgeError.tooLarge,
        'De repository-boom is te groot om in één keer te lezen.',
      );
    }
    final tree = json['tree'];
    if (tree is! List) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Tree-antwoord zonder entries',
      );
    }
    _requireEntryCount(tree.length);
    final prefix = path.isEmpty
        ? ''
        : '${path.replaceAll(RegExp(r'/+$'), '')}/';
    final entries = <RepoEntry>[];
    for (final raw in tree) {
      final entry = _treeEntry(raw);
      if (entry == null) continue;
      if (prefix.isEmpty || entry.path.startsWith(prefix)) entries.add(entry);
    }
    return entries;
  }

  void _requireEntryCount(int count) {
    if (count > maxListingEntries) {
      throw GitForgeException(
        GitForgeError.tooLarge,
        'Te veel entries in één listing ($count)',
      );
    }
  }

  /// Eén entry uit `/contents`. Geeft null wanneer de entry onbruikbaar is —
  /// een onveilig pad wordt overgeslagen, niet doorgegeven.
  RepoEntry? _contentsEntry(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'];
    final sha = raw['sha'];
    if (path is! String || sha is! String) return null;
    if (!GitRepoLayout.isSafeRepoPath(path)) return null;
    final size = raw['size'];
    return RepoEntry(
      path: path,
      sha: sha,
      size: size is int ? size : null,
      type: switch (raw['type']) {
        'file' => RepoEntryType.file,
        'dir' => RepoEntryType.dir,
        _ => RepoEntryType.other,
      },
    );
  }

  /// Eén entry uit `/git/trees`. Daar heten de soorten `blob` en `tree`.
  RepoEntry? _treeEntry(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'];
    final sha = raw['sha'];
    if (path is! String || sha is! String) return null;
    if (!GitRepoLayout.isSafeRepoPath(path)) return null;
    final size = raw['size'];
    return RepoEntry(
      path: path,
      sha: sha,
      size: size is int ? size : null,
      type: switch (raw['type']) {
        'blob' => RepoEntryType.file,
        'tree' => RepoEntryType.dir,
        _ => RepoEntryType.other,
      },
    );
  }

  @override
  Future<Uint8List> readBlob(String ref, String path) async {
    _requireRef(ref);
    if (!GitRepoLayout.isSafeRepoPath(path)) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Onveilig pad opgevraagd',
      );
    }
    // `/raw` geeft de bytes zoals ze zijn. De `/contents`-variant zou base64 in
    // JSON geven: een derde groter, en voor een video onzinnig.
    final response = await _transport.get(
      _apiUri(
        ['raw', ...path.split('/').where((s) => s.isNotEmpty)],
        query: {'ref': ref},
      ),
      headers: {
        if (token.trim().isNotEmpty) 'Authorization': 'token ${token.trim()}',
      },
      maxBytes: maxBlobBytes,
    );
    _checkStatus(response.status);
    return response.bytes;
  }

  /// Een ref komt soms uit door de gebruiker of de forge geleverde data. Hij
  /// belandt in een URL-pad, dus weigeren we alles wat daar een betekenis heeft
  /// of wat git zelf niet als refnaam accepteert.
  void _requireRef(String ref) {
    final r = ref.trim();
    if (r.isEmpty ||
        r.length > 255 ||
        r.startsWith('-') ||
        r.contains('..') ||
        r.contains('?') ||
        r.contains('#') ||
        r.contains('&') ||
        r.codeUnits.any((c) => c < 0x20 || c == 0x7f)) {
      throw const GitForgeException(
        GitForgeError.malformed,
        'Ongeldige branch-, tag- of commitnaam',
      );
    }
  }

  void close() => _transport.close();
}
