import 'dart:typed_data';

import '../s3/s3_service.dart';
import '../webdav_service.dart';
import 'remote_file_client.dart';

/// [RemoteFileClient] bovenop een WebDAV-verbinding.
class WebdavFileClient implements RemoteFileClient {
  const WebdavFileClient(this.service);

  final WebdavService service;

  @override
  Future<List<RemoteFileEntry>> list(String path) async {
    final entries = await service.list(path);
    return [
      for (final e in entries)
        RemoteFileEntry(
          path: e.relativePath,
          name: e.name,
          isDirectory: e.isCollection,
          isMarkdown: e.isMarkdown,
          isPackage: e.isOcideck,
        ),
    ];
  }

  @override
  Future<Uint8List> download(String path) async =>
      (await service.download(path)).bytes;
}

/// [RemoteFileClient] bovenop een S3-verbinding.
class S3FileClient implements RemoteFileClient {
  const S3FileClient(this.service);

  final S3Service service;

  @override
  Future<List<RemoteFileEntry>> list(String path) async {
    final entries = await service.list(path);
    return [
      for (final e in entries)
        RemoteFileEntry(
          path: e.relativePath,
          name: e.name,
          isDirectory: e.isCollection,
          isMarkdown: e.isMarkdown,
          isPackage: e.isOcideck,
        ),
    ];
  }

  @override
  Future<Uint8List> download(String path) async =>
      (await service.download(path)).bytes;
}
