import 'dart:typed_data';

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
  }) => _send(uri, headers: headers, maxBytes: maxBytes);

  @override
  Future<GitResponse> send(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    required List<int> body,
    required int maxBytes,
  }) async {
    if (!GitTransport.writeMethods.contains(method)) {
      throw GitForgeException(
        GitForgeError.malformed,
        'Onbekend schrijf-werkwoord: $method',
      );
    }
    return _send(
      uri,
      headers: headers,
      body: body,
      maxBytes: maxBytes,
      method: method,
    );
  }

  Future<GitResponse> _send(
    Uri uri, {
    required Map<String, String> headers,
    required int maxBytes,
    List<int>? body,
    String method = 'GET',
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
    // En een token gaat nooit over platte tekst, ook niet naar een vertrouwde
    // interne host — dezelfde regel als op io (`NetGuard.maySendReusableSecret`),
    // hier met de koppenlijst die deze klasse al bijhoudt. De pagina-CSP
    // (`connect-src 'self' https:`) houdt plain http in de praktijk al tegen;
    // dit staat er zodat de regel niet aan die ene laag hangt. Zonder token —
    // een publieke repo — blijft plain http op een vertrouwd LAN werken.
    // (Toegevoegd 2026-07-22.)
    if (scheme != 'https' && !_mayUseProxy(headers)) {
      throw const GitForgeException(
        GitForgeError.config,
        'Een git-server met een token vereist https: het token gaat bij élk '
        'verzoek mee, dus het zou onversleuteld over het netwerk gaan.',
      );
    }

    final direct = await _fetchCapped(
      uri,
      headers,
      maxBytes,
      body: body,
      method: method,
    );
    if (direct != null) return direct;

    // Een schrijfactie gaat nooit door het fetch-hulppunt. Los van het token
    // (dat er sowieso bij zit, zie _mayUseProxy): dat punt is een leesproxy, en
    // een POST erdoorheen jassen zou van OciDeck's eigen server een schrijfpad
    // naar andermans forge maken.
    if (body != null) {
      throw const GitForgeException(
        GitForgeError.network,
        'Server onbereikbaar vanuit de browser. Bij een eigen Forgejo is dit '
        'meestal CORS: sta deze origin toe op de server.',
      );
    }

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

  /// Eén http-verzoek met het gevraagde werkwoord. De browser-client kent ze
  /// allemaal; dit vertaalt alleen de naam naar de juiste aanroep.
  http.Request _request(
    String method,
    Uri uri,
    Map<String, String>? headers,
    List<int>? body,
  ) {
    final request = http.Request(method, uri);
    if (headers != null) request.headers.addAll(headers);
    if (body != null) request.bodyBytes = Uint8List.fromList(body);
    return request;
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
    List<int>? body,
    String method = 'GET',
  }) async {
    try {
      final h = headers.isEmpty ? null : headers;
      // Streamen in plaats van `.get`/`.post`, zodat de cap net als op io in
      // twee stappen bijt: eerst een Content-Length die het plafond al meldt
      // weigeren vóór het lezen, dan een lopende cap die midden in de stroom
      // afbreekt. Kanttekening voor web: de standaard browserclient (XHR)
      // buffert het antwoord al ín de browser voordat deze stroom iets levert,
      // dus daar is de cap in de praktijk pas ná die buffer effectief — een
      // liegende forge kan zo nog geheugen kosten. De Content-Length-poort
      // vangt het eerlijke geval, en zodra de client wél echt streamt (fetch)
      // breekt de lopende cap ook op web af. Zie SECURITY_DESIGN §"web".
      final streamed = await _client
          .send(_request(method, uri, h, body))
          .timeout(timeout);
      final declared = streamed.contentLength;
      if (declared != null && declared > maxBytes) {
        throw GitForgeException(
          GitForgeError.tooLarge,
          'Antwoord te groot ($declared bytes)',
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in streamed.stream) {
        builder.add(chunk);
        if (builder.length > maxBytes) {
          throw const GitForgeException(
            GitForgeError.tooLarge,
            'Antwoord te groot',
          );
        }
      }
      return GitResponse(streamed.statusCode, builder.takeBytes());
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
