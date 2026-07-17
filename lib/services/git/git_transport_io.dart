import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import '../../models/git_settings.dart';
import '../../utils/net_guard.dart';
import 'git_forge.dart';
import 'git_transport.dart';

/// Het platformtransport op dart:io-targets (desktop).
GitTransport createGitTransport(GitRepoConfig config) =>
    PinnedGitTransport(config);

/// SSRF-gepind HTTP — hetzelfde recept als `webdav_service.dart` en de
/// URL-import: https afdwingen, de host resolven en interne adressen weigeren,
/// de socket pinnen op het gevalideerde adres (zodat een DNS-rebind niet alsnog
/// bij een intern IP komt), redirects blokkeren en de body cappen.
///
/// De pin wordt één keer gelegd en daarna hergebruikt: de host ligt vast in de
/// config, dus opnieuw resolven per request zou alleen maar een tweede kans
/// geven om ergens anders uit te komen.
class PinnedGitTransport implements GitTransport {
  PinnedGitTransport(this.config);

  final GitRepoConfig config;

  HttpClient? _client;

  @override
  Future<GitResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required int maxBytes,
  }) => _send('GET', uri, headers: headers, maxBytes: maxBytes);

  @override
  Future<GitResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required List<int> body,
    required int maxBytes,
  }) => _send('POST', uri, headers: headers, body: body, maxBytes: maxBytes);

  Future<GitResponse> _send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    required int maxBytes,
    List<int>? body,
  }) async {
    final client = await _ensureClient(uri);
    try {
      final request = await client.openUrl(method, uri);
      // Een 3xx mag de host-check niet omzeilen: de redirect-target is niet
      // gepind en zou naar een intern adres kunnen wijzen.
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      if (body != null) request.add(body);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );

      // Een Content-Length die de cap al overschrijdt weigeren we vóór het
      // lezen; de streaming-cap eronder vangt een liegende of ontbrekende.
      if (response.contentLength > maxBytes) {
        throw GitForgeException(
          GitForgeError.tooLarge,
          'Antwoord te groot (${response.contentLength} bytes)',
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > maxBytes) {
          throw const GitForgeException(
            GitForgeError.tooLarge,
            'Antwoord te groot',
          );
        }
      }
      return GitResponse(response.statusCode, builder.takeBytes());
    } on GitForgeException {
      rethrow;
    } catch (e) {
      throw GitForgeException(GitForgeError.network, 'Netwerkfout: $e');
    }
  }

  Future<HttpClient> _ensureClient(Uri uri) async {
    final existing = _client;
    if (existing != null) return existing;

    if (!config.isConfigured) {
      throw const GitForgeException(
        GitForgeError.config,
        'Git-repository niet ingesteld',
      );
    }
    final origin = config.origin;
    if (origin == null || config.host.isEmpty) {
      throw const GitForgeException(
        GitForgeError.config,
        'Ongeldige server-URL',
      );
    }
    // De request moet op de geconfigureerde origin uitkomen; anders zouden we
    // een gepinde client op een andere host loslaten.
    if (uri.host != origin.host || uri.scheme != origin.scheme) {
      throw const GitForgeException(
        GitForgeError.config,
        'Verzoek valt buiten de geconfigureerde server',
      );
    }
    // Het token gaat als header mee bij élke request. Over plain http zou dat
    // leesbaar over de lijn gaan, dus eisen we https — tenzij de gebruiker de
    // server bewust als vertrouwd intern heeft gemarkeerd, waar een box zonder
    // TLS gangbaar is.
    final scheme = origin.scheme.toLowerCase();
    if (scheme != 'https' && !(scheme == 'http' && config.trustedInternal)) {
      throw GitForgeException(
        GitForgeError.config,
        scheme == 'http'
            ? 'Gebruik https of markeer de server als vertrouwd intern; anders '
                  'gaat je token onversleuteld over het netwerk.'
            : 'Alleen https-servers worden ondersteund.',
      );
    }
    final addrs = await NetGuard.safeResolveTrusted(
      config.host,
      allowPrivate: config.trustedInternal,
    );
    if (addrs == null || addrs.isEmpty) {
      throw const GitForgeException(
        GitForgeError.blockedHost,
        'Server-host geweigerd of onbereikbaar',
      );
    }
    final pinned = addrs.first;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..connectionFactory = (u, _, _) => Socket.startConnect(pinned, u.port);
    _client = client;
    return client;
  }

  @override
  void close() {
    _client?.close(force: true);
    _client = null;
  }
}
