import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/models/s3_settings.dart';
import 'package:ocideck/models/storage_connection.dart';
import 'package:ocideck/models/webdav_settings.dart';
import 'package:ocideck/services/git/git_forge.dart';
import 'package:ocideck/services/s3/s3_service.dart';
import 'package:ocideck/services/webdav_service.dart';
import 'package:ocideck/state/git_provider.dart';
import 'package:ocideck/state/presentation_sources.dart';
import 'package:ocideck/state/s3_provider.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/state/webdav_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'git_forge_fake.dart';

/// De bronnenlijst voor 'Slide zoeken': per geconfigureerde verbinding één
/// [PresentationSource], mits daar een bruikbare client bij hoort.
///
/// De regel die hier telt: een verbinding die half is ingevuld of waarvan het
/// geheim ontbreekt, hoort géén lege bron op te leveren. Een lege bron zoekt
/// mee, vindt niets, en laat de gebruiker geloven dat er niets stond.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const repo = GitRepoConfig(
    baseUrl: 'https://git.example',
    owner: 'ocideck',
    repo: 'decks',
  );
  const server = WebdavServer(
    baseUrl: 'https://cloud.example',
    username: 'aisha',
  );
  const bucket = S3Bucket(
    endpoint: 'https://s3.example',
    region: 'eu-central-1',
    bucket: 'presentaties',
    accessKeyId: 'AKIA-wegwerp',
  );

  /// Bouwt de bronnen binnen een echte widget-boom, want de functie vraagt om
  /// een [WidgetRef].
  Future<List<String>> labelsFor(
    WidgetTester tester, {
    required List<StorageConnection> connections,
    GitForge? forge,
    WebdavService? webdav,
    S3Service? s3,
  }) async {
    late List<String> labels;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(
            (_) => SettingsNotifier()..setConnections(connections),
          ),
          gitForgeProvider.overrideWith((ref, id) async => forge),
          webdavServiceProvider.overrideWith((ref, id) async => webdav),
          s3ServiceProvider.overrideWith((ref, id) async => s3),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              return TextButton(
                onPressed: () async {
                  final sources = await buildRemotePresentationSources(ref);
                  labels = [for (final s in sources) s.label];
                },
                child: const Text('bouw'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('bouw'));
    await tester.pumpAndSettle();
    return labels;
  }

  testWidgets('zonder verbindingen is er geen enkele externe bron', (
    tester,
  ) async {
    expect(await labelsFor(tester, connections: const []), isEmpty);
  });

  testWidgets('een verbinding zonder bruikbare client valt weg', (
    tester,
  ) async {
    // De configuratie staat er, maar het geheim ontbreekt: de providers geven
    // null. Een bron aanmaken zou een zoekbron opleveren die niets kan.
    final labels = await labelsFor(
      tester,
      connections: const [
        GitConnection(id: 'g1', name: 'Werk', repo: repo),
        WebdavConnection(id: 'w1', name: 'Kantoor', server: server),
        S3Connection(id: 's1', name: 'Archief', bucket: bucket),
      ],
    );

    expect(labels, isEmpty);
  });

  testWidgets('elke bron draagt de naam die de gebruiker gaf', (tester) async {
    final labels = await labelsFor(
      tester,
      connections: const [
        GitConnection(id: 'g1', name: 'Werk', repo: repo),
        WebdavConnection(id: 'w1', name: 'Kantoor', server: server),
        S3Connection(id: 's1', name: 'Archief', bucket: bucket),
      ],
      forge: FakeForge(FakeRepo.sample()),
      webdav: WebdavService(server: server, password: 'wegwerp'),
      s3: S3Service(bucket: bucket, secretAccessKey: 'wegwerp'),
    );

    expect(labels, ['Git: Werk', 'WebDAV: Kantoor', 'S3: Archief']);
  });

  testWidgets('een naamloze verbinding valt terug op iets herkenbaars', (
    tester,
  ) async {
    final labels = await labelsFor(
      tester,
      connections: const [
        GitConnection(id: 'g1', name: '  ', repo: repo),
        WebdavConnection(id: 'w1', name: '', server: server),
        S3Connection(id: 's1', name: '   ', bucket: bucket),
      ],
      forge: FakeForge(FakeRepo.sample()),
      webdav: WebdavService(server: server, password: 'wegwerp'),
      s3: S3Service(bucket: bucket, secretAccessKey: 'wegwerp'),
    );

    // Een lege naam mag geen "Git: " met niets erachter opleveren.
    expect(labels, ['Git: ${repo.slug}', 'WebDAV', 'S3']);
  });

  testWidgets('twee verbindingen van dezelfde soort leveren twee bronnen', (
    tester,
  ) async {
    final labels = await labelsFor(
      tester,
      connections: const [
        WebdavConnection(id: 'w1', name: 'Kantoor', server: server),
        WebdavConnection(id: 'w2', name: 'Thuis', server: server),
      ],
      webdav: WebdavService(server: server, password: 'wegwerp'),
    );

    expect(labels, ['WebDAV: Kantoor', 'WebDAV: Thuis']);
  });
}
