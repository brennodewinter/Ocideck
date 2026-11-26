part of 'ociserve_gateway.dart';

abstract interface class OciServeFilesApi {
  Future<CatalogPage> files({
    required String accessToken,
    required String organizationId,
    String folderId = 'root',
    String? cursor,
  });
  Future<Uint8List> fileContent({
    required String accessToken,
    required String organizationId,
    required CatalogEntry entry,
  });
  Future<ManagedSharePage> fileShares({
    required String accessToken,
    required String organizationId,
    String? cursor,
  });
  Future<ManagedFileShare> createFileShare({
    required String accessToken,
    required String organizationId,
    required String fileId,
    required String requestKey,
    DateTime? expiresAt,
    String password = '',
  });
  Future<ManagedFileShare> updateFileShare({
    required String accessToken,
    required String organizationId,
    required ManagedFileShare share,
    DateTime? expiresAt,
    String? password,
    bool clearPassword = false,
    bool rotate = false,
  });
  Future<void> revokeFileShare({
    required String accessToken,
    required String organizationId,
    required String shareId,
  });
}

mixin _OciServeFiles on OciServeGatewayBase {
  @override
  Future<CatalogPage> files({
    required String accessToken,
    required String organizationId,
    String folderId = 'root',
    String? cursor,
  }) async {
    fileId(folderId, root: true);
    final response = await _send(
      method: 'GET',
      accessToken: accessToken,
      url: _api([
        'organizations',
        organizationId,
        'files',
      ]).replace(queryParameters: {'folder_id': folderId, 'cursor': ?cursor}),
    );
    return _fileDecode(() => CatalogPage.fromJson(_jsonObject(response)));
  }

  @override
  Future<Uint8List> fileContent({
    required String accessToken,
    required String organizationId,
    required CatalogEntry entry,
  }) async {
    fileId(entry.id);
    _checkFileEntry(entry);
    final response = await _send(
      method: 'GET',
      accessToken: accessToken,
      url: _api([
        'organizations',
        organizationId,
        'files',
        entry.id,
        'content',
      ]),
      headers: {
        'accept': 'text/markdown, application/zip, application/octet-stream',
        if (entry.etag.isNotEmpty) 'if-match': entry.etag,
      },
      cap: maxFileBytes,
    );
    return _fileBytes(response, entry);
  }

  @override
  Future<ManagedSharePage> fileShares({
    required String accessToken,
    required String organizationId,
    String? cursor,
  }) async {
    final response = await _send(
      method: 'GET',
      accessToken: accessToken,
      url: _api([
        'organizations',
        organizationId,
        'file-shares',
      ]).replace(queryParameters: {'cursor': ?cursor}),
    );
    return _fileDecode(() => ManagedSharePage.fromJson(_jsonObject(response)));
  }

  @override
  Future<ManagedFileShare> createFileShare({
    required String accessToken,
    required String organizationId,
    required String fileId,
    required String requestKey,
    DateTime? expiresAt,
    String password = '',
  }) async {
    validateShareExpiry(expiresAt, DateTime.now().toUtc());
    validateSharePassword(password);
    final response = await _send(
      method: 'POST',
      accessToken: accessToken,
      url: _api(['organizations', organizationId, 'file-shares']),
      headers: {
        'content-type': 'application/json',
        'idempotency-key': requestKey,
      },
      body: utf8.encode(
        jsonEncode({
          'file_id': fileId,
          if (expiresAt != null)
            'expires_at': expiresAt.toUtc().toIso8601String(),
          if (password.isNotEmpty) 'password': password,
        }),
      ),
    );
    return _managedShare(response, settings);
  }

  @override
  Future<ManagedFileShare> updateFileShare({
    required String accessToken,
    required String organizationId,
    required ManagedFileShare share,
    DateTime? expiresAt,
    String? password,
    bool clearPassword = false,
    bool rotate = false,
  }) async {
    fileId(share.id);
    validateShareExpiry(expiresAt, DateTime.now().toUtc());
    if (password != null) validateSharePassword(password);
    final response = await _send(
      method: 'PUT',
      accessToken: accessToken,
      url: _api(['organizations', organizationId, 'file-shares', share.id]),
      headers: {'content-type': 'application/json', 'if-match': share.etag},
      body: utf8.encode(
        jsonEncode({
          if (expiresAt != null)
            'expires_at': expiresAt.toUtc().toIso8601String(),
          if (password != null && password.isNotEmpty) 'password': password,
          if (clearPassword) 'clear_password': true,
          if (rotate) 'rotate_link': true,
        }),
      ),
    );
    return _managedShare(response, settings);
  }

  @override
  Future<void> revokeFileShare({
    required String accessToken,
    required String organizationId,
    required String shareId,
  }) async {
    fileId(shareId);
    await _send(
      method: 'DELETE',
      accessToken: accessToken,
      url: _api(['organizations', organizationId, 'file-shares', shareId]),
    );
  }
}

T _fileDecode<T>(T Function() decode) {
  try {
    return decode();
  } catch (error, stack) {
    logError('OciServe: bestandsantwoord lezen', error.runtimeType, stack);
    throw const OciServeException('invalid_response');
  }
}

ManagedFileShare _managedShare(
  OciServeHttpResponse response,
  OciServeSettings settings,
) {
  return _fileDecode(() {
    final share = ManagedFileShare.fromJson(
      fileObject(jsonDecode(utf8.decode(response.body))),
    );
    if (share.link case final link?) {
      final parsed = FileShareLink.parse(link);
      if (parsed.origin.origin !=
              Uri.parse(settings.normalizedBaseUrl).origin ||
          parsed.id != share.id) {
        throw const FormatException('share origin mismatch');
      }
    }
    return share;
  });
}

void _checkFileEntry(CatalogEntry entry) {
  if (!entry.supported) throw const OciServeException('unsupported_file');
  if (entry.size > maxFileBytes) {
    throw const OciServeException('response_too_large');
  }
}

Uint8List _fileBytes(OciServeHttpResponse response, CatalogEntry entry) {
  final type = (response.headers['content-type'] ?? '')
      .split(';')
      .first
      .trim()
      .toLowerCase();
  if (!{
    'text/markdown',
    'text/plain',
    'application/zip',
    'application/octet-stream',
    'application/x-ocideck',
    'application/vnd.ocideck',
  }.contains(type)) {
    throw const OciServeException('unsupported_file');
  }
  if (response.body.length != entry.size ||
      response.body.length > maxFileBytes) {
    throw const OciServeException('file_changed');
  }
  final etag = response.headers['etag'];
  if (entry.etag.isNotEmpty && etag != null && etag != entry.etag) {
    throw const OciServeException('file_changed');
  }
  return response.body;
}

/// Separate capability-only client. Never receives an account token or a
/// tenant gateway. Secrets and grants exist only for the lifetime of a dialog.
class OciServePublicFiles {
  OciServePublicFiles(
    this.link, {
    bool trustedInternal = false,
    OciServeHttpTransport? transport,
  }) : _gateway = OciServeGateway(
         settings: OciServeSettings(
           enabled: true,
           baseUrl: link.origin.toString(),
           trustedInternal: trustedInternal,
         ),
         transport: transport ?? createPublicOciServeHttpTransport(),
       );
  final FileShareLink link;
  final OciServeGateway _gateway;
  String? _grant;
  DateTime? _expiresAt;
  bool _closed = false;
  Uri _url(List<String> path, [String? cursor]) => _gateway
      ._api(['public', 'file-shares', link.id, ...path])
      .replace(queryParameters: {'cursor': ?cursor});

  Future<void> unlock({String password = ''}) async {
    if (_closed) throw const OciServeException('cancelled');
    final response = await _request(
      'POST',
      _url(['unlock']),
      body: utf8.encode(
        jsonEncode({
          'token': link.secret,
          if (password.isNotEmpty) 'password': password,
          'browser': false,
        }),
      ),
    );
    if (_closed) throw const OciServeException('cancelled');
    final json = _fileDecode(
      () => fileObject(jsonDecode(utf8.decode(response.body))),
    );
    _grant = json['grant'] as String?;
    _expiresAt = DateTime.tryParse(json['expires_at'] as String? ?? '');
    if (_grant == null || _grant!.isEmpty || _expiresAt == null) {
      close();
      throw const OciServeException('invalid_response');
    }
  }

  Future<OciServeHttpResponse> _request(
    String method,
    Uri url, {
    List<int>? body,
    bool granted = false,
    int cap = _jsonCap,
  }) async {
    if (_closed) throw const OciServeException('cancelled');
    if (granted &&
        (_grant == null || !(_expiresAt?.isAfter(DateTime.now()) ?? false))) {
      throw const OciServeException('share_unavailable');
    }
    try {
      final result = await _gateway._send(
        method: method,
        url: url,
        headers: {
          if (body != null) 'content-type': 'application/json',
          if (granted) 'authorization': 'Bearer $_grant',
        },
        body: body,
        cap: cap,
      );
      if (_closed) throw const OciServeException('cancelled');
      return result;
    } on OciServeException catch (error) {
      // No untrusted problem details or capability URL in errors or logs.
      throw OciServeException(switch (error.statusCode) {
        401 => 'share_password_required',
        429 => 'share_rate_limited',
        404 => 'share_unavailable',
        _ => error.code,
      }, statusCode: error.statusCode);
    }
  }

  Future<CatalogPage> browse({String? nodeId, String? cursor}) async {
    if (nodeId != null) fileId(nodeId);
    final response = await _request(
      'GET',
      _url(nodeId == null ? [] : ['nodes', nodeId], cursor),
      granted: true,
    );
    return _fileDecode(
      () => CatalogPage.fromJson(
        fileObject(jsonDecode(utf8.decode(response.body))),
        public: true,
      ),
    );
  }

  Future<Uint8List> download(CatalogEntry entry) async {
    fileId(entry.id);
    _checkFileEntry(entry);
    final response = await _request(
      'GET',
      _url(['nodes', entry.id, 'content']),
      granted: true,
      cap: maxFileBytes,
    );
    return _fileBytes(response, entry);
  }

  void close() {
    _closed = true;
    final transport = _gateway._transport;
    if (transport is OciServeClosableTransport) {
      (transport as OciServeClosableTransport).close();
    }
    _grant = null;
    _expiresAt = null;
  }
}
