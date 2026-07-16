import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import '../../models/git_settings.dart';
import '../../utils/log.dart';
import 'git_forge.dart';
import 'git_transport.dart';

/// Het platformtransport op web.
GitTransport createGitTransport(GitRepoConfig config) =>
    BrowserGitTransport(config);

/// Browser-fetch. De dart:io SSRF-pinning van de desktopvariant bestaat hier
/// niet en kan hier ook niet draaien; de browser-sandbox en de pagina-CSP
/// (`connect-src`) bewaken welke hosts bereikbaar zijn. Wat wij hier bewaken is
/// schema, omvang en — vooral — waar het token wel en niet heen mag.
class BrowserGitTransport implements GitTransport {
  BrowserGitTransport(this.config, {@visibleForTesting http.Client? client})
    : _injected = client;

  final GitRepoConfig config;
  final http.Client? _injected;
  http.Client? _owned;

  http.Client get _client => _injected ?? (_owned ??= http.Client());

  /// Headernamen die een geheim dragen. Zie [_mayUseProxy].
  static const _credentialHeaders = <String>{
    'authorization',
    'private-token',
    'x-gitlab-token',
  };

  @override
  Future<GitResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required int maxBytes,
  }) async {
    if (!config.isConfigured) {
      throw const GitForgeException(
        GitForgeError.config,
        'Git-repository niet ingesteld',
      );
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && !(scheme == 'http' && config.trustedInternal)) {
      throw const GitForgeException(
        GitForgeError.config,
        'Alleen https-servers worden ondersteund.',
      );
    }

    final direct = await _fetchCapped(uri, headers, maxBytes);
    if (direct != null) return direct;

    // Een self-hosted Forgejo stuurt vaak geen CORS-headers, dus weigert de
    // browser de directe lezing. Het same-origin fetch-hulppunt kan dat
    // omzeilen — maar alleen voor een verzoek zónder geheim (§11 + de grens
    // hieronder). Met een token vertellen we de gebruiker liever dat CORS op
    // de forge geregeld moet worden.
    if (_mayUseProxy(headers)) {
      final proxied = Uri.base.resolve(
        'fetch-proxy?url=${Uri.encodeComponent(uri.toString())}',
      );
      final viaProxy = await _fetchCapped(
        proxied,
        const {},
        maxBytes,
        timeout: const Duration(seconds: 120),
      );
      if (viaProxy != null) return viaProxy;
    }

    throw GitForgeException(
      GitForgeError.network,
      _mayUseProxy(headers)
          ? 'Server onbereikbaar vanuit de browser.'
          : 'Server onbereikbaar vanuit de browser. Bij een eigen Forgejo is '
                'dit meestal CORS: sta deze origin toe op de server.',
    );
  }

  /// Een verzoek mét token gaat **nooit** door het fetch-hulppunt. Dat punt
  /// haalt server-zijdig op, dus het zou het personal access token in handen
  /// krijgen en het namens de gebruiker doorsturen — precies wat §10.1 met
  /// "het token staat in de keychain, nergens anders" wil voorkomen. Voor een
  /// publieke repo is er geen geheim en mag de terugval wel.
  static bool _mayUseProxy(Map<String, String> headers) =>
      !headers.keys.any((k) => _credentialHeaders.contains(k.toLowerCase()));

  /// Eén begrensde GET. Geeft null bij een transportfout (dan volgt de
  /// terugval); een HTTP-foutstatus komt wél terug, want die betekent dat de
  /// server bereikbaar wás en de proxy niets zou toevoegen.
  Future<GitResponse?> _fetchCapped(
    Uri uri,
    Map<String, String> headers,
    int maxBytes, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      final response = await _client
          .get(uri, headers: headers.isEmpty ? null : headers)
          .timeout(timeout);
      final bytes = response.bodyBytes;
      if (bytes.length > maxBytes) {
        throw const GitForgeException(
          GitForgeError.tooLarge,
          'Antwoord te groot',
        );
      }
      return GitResponse(response.statusCode, bytes);
    } on GitForgeException {
      rethrow;
    } catch (e) {
      // Null, niet gooien: de aanroeper beslist of de proxy-terugval nog mag en
      // maakt er anders een nette melding van.
      logError('BrowserGitTransport: request failed', e);
      return null;
    }
  }

  @override
  void close() {
    _owned?.close();
    _owned = null;
  }
}
