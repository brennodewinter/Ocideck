/// Safe provenance for a local copy; never contains an access/share credential.
class OciServeFileOrigin {
  const OciServeFileOrigin({
    required this.server,
    this.organizationId,
    required this.fileId,
    required this.name,
    this.etag = '',
    this.publicShare = false,
  });
  final String server, fileId, name, etag;
  final String? organizationId;
  final bool publicShare;
}
