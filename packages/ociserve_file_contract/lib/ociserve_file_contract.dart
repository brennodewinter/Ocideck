import 'dart:convert';

const shareLandingPath = '/api/v1/public/file-shares/open';
const maxFileBytes = 32 * 1024 * 1024;
final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

String fileId(Object? value, {bool root = false}) {
  if (value is! String || !(root && value == 'root' || _uuid.hasMatch(value))) {
    throw const FormatException('invalid file identifier');
  }
  return value;
}

/// A capability URL. Never serialize this into preferences, logs or recents.
class FileShareLink {
  FileShareLink._(this.origin, this.id, this.secret);
  final Uri origin;
  final String id;
  final String secret;
  Uri get browserUri =>
      origin.replace(path: shareLandingPath, fragment: '$id.$secret');
  static bool resembles(Uri uri) =>
      uri.path.startsWith('/api/v1/public/file-shares');
  static FileShareLink parse(String value) {
    final uri = Uri.parse(value.trim());
    final parts = uri.fragment.split('.');
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.path != shareLandingPath ||
        uri.hasQuery ||
        parts.length != 2 ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(parts[1])) {
      throw const FormatException('invalid share link');
    }
    final bytes = base64Url.decode(base64Url.normalize(parts[1]));
    if (bytes.length != 32 ||
        base64Url.encode(bytes).replaceAll('=', '') != parts[1]) {
      throw const FormatException('invalid share secret');
    }
    return FileShareLink._(
      Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
      ),
      fileId(parts[0]),
      parts[1],
    );
  }

  @override
  String toString() => 'FileShareLink(redacted)';
}

class CatalogEntry {
  const CatalogEntry({
    required this.id,
    required this.name,
    required this.directory,
    this.size = 0,
    this.contentType = '',
    this.etag = '',
  });
  final String id, name, contentType, etag;
  final bool directory;
  final int size;
  bool get supported =>
      !directory &&
      (name.toLowerCase().endsWith('.md') ||
          name.toLowerCase().endsWith('.ocideck'));
  factory CatalogEntry.fromJson(Map<String, Object?> json) {
    final kind = json['kind'];
    final size = json['size'];
    if (kind != 'directory' && kind != 'file' || size is! int || size < 0) {
      throw const FormatException('invalid catalog entry');
    }
    return CatalogEntry(
      id: fileId(json['id'], root: true),
      name: json['name'] as String,
      directory: kind == 'directory',
      size: size,
      contentType: json['content_type'] as String? ?? '',
      etag: json['etag'] as String? ?? '',
    );
  }
}

Map<String, Object?> fileObject(Object? value) =>
    Map<String, Object?>.from(value as Map);

class CatalogCrumb {
  const CatalogCrumb(this.id, this.name);
  final String id, name;
}

class CatalogPage {
  const CatalogPage(this.folder, this.items, this.breadcrumbs, this.nextCursor);
  final CatalogEntry folder;
  final List<CatalogEntry> items;
  final List<CatalogCrumb> breadcrumbs;
  final String? nextCursor;
  factory CatalogPage.fromJson(
    Map<String, Object?> json, {
    bool public = false,
  }) {
    final items = json['items'] as List;
    if (items.length > 100) throw const FormatException('oversized listing');
    return CatalogPage(
      CatalogEntry.fromJson(fileObject(json[public ? 'node' : 'folder'])),
      items
          .map((v) => CatalogEntry.fromJson(fileObject(v)))
          .toList(growable: false),
      ((json['breadcrumbs'] as List?) ?? [])
          .map((v) {
            final c = fileObject(v);
            return CatalogCrumb(
              fileId(c['id'], root: true),
              c['name'] as String,
            );
          })
          .toList(growable: false),
      json['next_cursor'] as String?,
    );
  }
}

class ManagedFileShare {
  const ManagedFileShare({
    required this.id,
    required this.rootId,
    required this.expiresAt,
    required this.status,
    required this.passwordProtected,
    required this.revision,
    this.link,
  });
  final String id, rootId, status;
  final DateTime expiresAt;
  final bool passwordProtected;
  final int revision;
  final String? link;
  String get etag => '"$revision"';
  factory ManagedFileShare.fromJson(Map<String, Object?> json) =>
      ManagedFileShare(
        id: fileId(json['id']),
        rootId: fileId(json['root_id']),
        expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
        status: json['status'] as String,
        passwordProtected: json['password_protected'] as bool,
        revision: json['revision'] as int,
        link: json['link'] as String?,
      );
  @override
  String toString() => 'ManagedFileShare(redacted)';
}

class ManagedSharePage {
  const ManagedSharePage(this.items, this.nextCursor);
  final List<ManagedFileShare> items;
  final String? nextCursor;
  factory ManagedSharePage.fromJson(Map<String, Object?> json) =>
      ManagedSharePage(
        (json['items'] as List)
            .map((v) => ManagedFileShare.fromJson(fileObject(v)))
            .toList(),
        json['next_cursor'] as String?,
      );
}

/// UTC instants on the wire; local zone and exact instant in the UI.
void validateShareExpiry(DateTime? value, DateTime now) {
  if (value != null &&
      (!value.isAfter(now) ||
          value.isAfter(now.add(const Duration(days: 90))))) {
    throw const FormatException('expiry must be within ninety days');
  }
}

void validateSharePassword(String value) {
  final length = utf8.encode(value).length;
  if (value.isNotEmpty && (length < 8 || length > 256)) {
    throw const FormatException('password must contain eight to 256 bytes');
  }
}
