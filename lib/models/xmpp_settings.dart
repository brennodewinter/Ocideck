// The non-secret configuration of an XMPP account (F2, `NATIVE_CALLS.md` §5).
// The collaboration/calls counterpart of `MatrixServer`: the WebSocket endpoint,
// the bare JID and the same `trustedInternal`/`pinnedCertSha256` SSRF posture live
// here (prefs domain); the password goes to the keychain via `SecretStore`.
//
// Transport is XMPP-over-WebSocket (RFC 7395): [serverUrl] is the `wss://` endpoint
// the client connects to; [jid]'s domain is what the stream is opened `to` (it may
// differ from the WebSocket host — e.g. `alice@example.org` reached via
// `wss://xmpp.example.org/xmpp-websocket`). An empty localpart means anonymous
// access (public Jitsi).

class XmppSettings {
  const XmppSettings({
    required this.serverUrl,
    this.jid = '',
    this.trustedInternal = false,
    this.pinnedCertSha256 = '',
  });

  /// The `wss://host[/path]` WebSocket endpoint. `ws://` is only honoured for a
  /// literal loopback host (the connection layer enforces this).
  final String serverUrl;

  /// The bare JID `localpart@domain`, or empty for anonymous access.
  final String jid;

  /// The user confirmed this is a trusted internal server; only then may a
  /// private/LAN host pass the SSRF block (mirrors WebDAV/Matrix).
  final bool trustedInternal;

  /// SHA-256 of a certificate the user explicitly trusts, or empty for the
  /// ordinary chain (mirrors WebDAV/Matrix; desktop only — no pinning on web).
  final String pinnedCertSha256;

  /// The parsed WebSocket endpoint, or null when [serverUrl] is unparseable.
  Uri? get endpoint {
    final uri = Uri.tryParse(serverUrl.trim());
    if (uri == null || uri.host.isEmpty) return null;
    return uri;
  }

  /// The WebSocket host, or empty when unparseable.
  String get host => endpoint?.host ?? '';

  /// The JID localpart (the user), or empty for anonymous.
  String get localpart {
    final at = jid.indexOf('@');
    return at > 0 ? jid.substring(0, at) : '';
  }

  /// The XMPP domain the stream is opened `to`: the JID's domain, falling back to
  /// the WebSocket [host] when there is no JID (anonymous).
  String get domain {
    final at = jid.indexOf('@');
    if (at > 0 && at < jid.length - 1) return jid.substring(at + 1);
    return host;
  }

  /// Whether to authenticate anonymously (no localpart to log in as).
  bool get isAnonymous => localpart.isEmpty;

  /// Ready to attempt a connection: a parseable endpoint and a domain to open to.
  bool get isConfigured => endpoint != null && domain.isNotEmpty;

  XmppSettings copyWith({
    String? serverUrl,
    String? jid,
    bool? trustedInternal,
    String? pinnedCertSha256,
  }) => XmppSettings(
    serverUrl: serverUrl ?? this.serverUrl,
    jid: jid ?? this.jid,
    trustedInternal: trustedInternal ?? this.trustedInternal,
    pinnedCertSha256: pinnedCertSha256 ?? this.pinnedCertSha256,
  );

  Map<String, Object?> toJson() => {
    'serverUrl': serverUrl,
    'jid': jid,
    'trustedInternal': trustedInternal,
    'pinnedCertSha256': pinnedCertSha256,
  };

  factory XmppSettings.fromJson(Map<String, Object?> json) => XmppSettings(
    serverUrl: (json['serverUrl'] as String?) ?? '',
    jid: (json['jid'] as String?) ?? '',
    trustedInternal: (json['trustedInternal'] as bool?) ?? false,
    pinnedCertSha256: (json['pinnedCertSha256'] as String?) ?? '',
  );

  @override
  bool operator ==(Object other) =>
      other is XmppSettings &&
      other.serverUrl == serverUrl &&
      other.jid == jid &&
      other.trustedInternal == trustedInternal &&
      other.pinnedCertSha256 == pinnedCertSha256;

  @override
  int get hashCode =>
      Object.hash(serverUrl, jid, trustedInternal, pinnedCertSha256);
}
