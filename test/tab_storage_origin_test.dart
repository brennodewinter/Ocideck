import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/models/s3_settings.dart';
import 'package:ocideck/models/webdav_settings.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/state/tabs_provider.dart';

/// Een tabblad droeg vroeger drie losse herkomstvelden met de opmerking erbij
/// dat een deck er hooguit één zou hebben. Niets handhaafde dat: een deck dat
/// van WebDAV kwam en naar S3 werd weggeschreven droeg er twee, en dan is niet
/// meer te zeggen waar "terug naar de herkomst" heen moet. Nu is het één veld.
void main() {
  // De tabs-notifier raakt bij het aanmaken van het eerste tabblad de
  // platformkanalen aan (herstelbestanden), dus de binding moet er zijn.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const webdav = WebdavOrigin(
    baseUrl: 'https://cloud.example/remote.php/dav',
    username: 'brenno',
    remotePath: 'decks/kwartaal.md',
    connectionId: 'conn-webdav',
  );
  const s3 = S3Origin(
    endpoint: 'https://s3.example',
    bucket: 'presentaties',
    remotePath: 'decks/kwartaal.md',
    connectionId: 'conn-s3',
  );
  const git = GitOrigin(
    config: GitRepoConfig(
      baseUrl: 'https://git.example',
      owner: 'ocideck',
      repo: 'decks',
    ),
    branch: 'main',
    deckDir: 'decks/kwartaal',
    baseSha: 'abc123',
    connectionId: 'conn-git',
  );

  TabInfo tab() {
    final container = ProviderContainer(
      overrides: [
        recoveryServiceProvider.overrideWithValue(
          RecoveryService(baseDir: Directory.systemTemp),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container.read(tabsProvider).current!;
  }

  test('a fresh tab has no origin at all', () {
    final t = tab();
    expect(t.origin, isNull);
    expect(t.webdavOrigin, isNull);
    expect(t.s3Origin, isNull);
    expect(t.gitOrigin, isNull);
  });

  test('setting one origin replaces an origin of another kind', () {
    final t = tab();
    t.webdavOrigin = webdav;
    expect(t.webdavOrigin, webdav);
    expect(t.origin, webdav);

    // Hetzelfde deck naar S3 wegschrijven: het komt nu dáárvandaan, dus de
    // WebDAV-herkomst hoort te verdwijnen in plaats van ernaast te blijven
    // staan.
    t.s3Origin = s3;
    expect(t.s3Origin, s3);
    expect(t.webdavOrigin, isNull);
    expect(t.origin, s3);

    t.gitOrigin = git;
    expect(t.gitOrigin, git);
    expect(t.s3Origin, isNull);
    expect(t.webdavOrigin, isNull);
  });

  test('clearing through the wrong accessor leaves the origin alone', () {
    final t = tab();
    t.gitOrigin = git;
    // Een WebDAV-pad dat afsluit met "geen herkomst" mag een git-herkomst niet
    // wissen; het gaat over een andere opslag.
    t.webdavOrigin = null;
    expect(t.gitOrigin, git);

    t.gitOrigin = null;
    expect(t.origin, isNull);
  });
}
