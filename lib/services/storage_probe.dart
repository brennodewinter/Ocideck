import '../models/storage_connection.dart';
import 'git/git_forge_factory.dart';
import '../utils/log.dart';
import 's3/s3_service.dart';
import 'secret_store.dart';
import 'webdav_service.dart';

/// Eén bereikbaarheidstest per verbindingssoort — dezelfde `probe()` die de
/// testknop op het opslag-tabblad al gebruikte, nu ook aanspreekbaar zonder
/// dat de instellingendialoog open staat. De geheimen komen uit de
/// sleutelhanger via [SecretStore]; er wordt niets extra bewaard.
///
/// Geeft `true` als de verbinding antwoordt, `false` bij elke uitkomst die
/// niet "bereikbaar" is — onbereikbaar, verkeerd wachtwoord, weigering. Het
/// lampje kent maar drie kleuren; de onderscheidende foutteksten blijven
/// waar ze horen: bij de testknop op het tabblad.
Future<bool> probeStorageConnection(
  StorageConnection connection,
  SecretStore secrets,
) => switch (connection) {
  // Lokaal is per afspraak bereikbaar: een map op deze computer hoeft niet
  // "getest" te worden om groen te mogen tonen.
  LocalConnection() => Future.value(true),
  WebdavConnection() => _probeWebdav(connection, secrets),
  S3Connection() => _probeS3(connection, secrets),
  GitConnection() => _probeGit(connection, secrets),
};

Future<bool> _probeWebdav(WebdavConnection c, SecretStore secrets) async {
  try {
    final password = await secrets.readWebdavPassword(
      c.server.baseUrl,
      c.server.username,
    );
    await WebdavService(server: c.server, password: password ?? '').probe();
    return true;
  } catch (e, st) {
    logError('opslagprobe: WebDAV ${c.server.host}', e, st);
    return false;
  }
}

Future<bool> _probeS3(S3Connection c, SecretStore secrets) async {
  try {
    final key = await secrets.readS3SecretKey(
      c.bucket.endpoint,
      c.bucket.accessKeyId,
    );
    await S3Service(bucket: c.bucket, secretAccessKey: key ?? '').probe();
    return true;
  } catch (e, st) {
    logError('opslagprobe: S3 ${c.bucket.endpoint}', e, st);
    return false;
  }
}

Future<bool> _probeGit(GitConnection c, SecretStore secrets) async {
  try {
    final token = await secrets.readGitToken(c.repo.baseUrl, c.repo.owner);
    final forge = createGitForge(config: c.repo, token: token ?? '');
    try {
      await forge.probe();
    } finally {
      forge.close();
    }
    return true;
  } catch (e, st) {
    logError('opslagprobe: git ${c.repo.slug}', e, st);
    return false;
  }
}
