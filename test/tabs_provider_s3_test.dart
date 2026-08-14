import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/services/s3/s3_service.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Eén upload zoals de bucket hem zag.
typedef _Put = ({String path, String? ifMatch, int bytes});

/// Een bucket die niets over de lijn doet, maar wél onthoudt wát er in welke
/// volgorde heen ging — dat is precies waar dit pad op stukging.
class _RecordingS3 extends S3Service {
  _RecordingS3({required super.bucket, this.etag = '"nieuw"', this.conflictOn})
    : super(secretAccessKey: 'wegwerp');

  final puts = <_Put>[];
  final String? etag;

  /// Pad waarop het endpoint een botsing meldt (412 Precondition Failed).
  final String? conflictOn;

  @override
  Future<String?> upload(
    String remotePath,
    List<int> bytes, {
    String? ifMatch,
    bool onlyIfAbsent = false,
  }) async {
    puts.add((path: remotePath, ifMatch: ifMatch, bytes: bytes.length));
    if (remotePath == conflictOn) {
      throw const S3ConflictException(expectedEtag: '"oud"', message: 'botst');
    }
    return etag;
  }
}

/// Terugschrijven naar een S3-bucket vanuit een tabblad. De volgorde is hier
/// geen detail: alleen het markdownbestand draagt de conflictbewaking, dus als
/// de assets eerst gaan, staan andermans afbeeldingen al overschreven op het
/// moment dat de `.md` met 412 wordt geweigerd — en de melding erna wekt de
/// indruk dat er niets is aangeraakt.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('ocideck_tabs_s3_');
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  const bucket = S3Bucket(
    endpoint: 'https://s3.example',
    region: 'eu-central-1',
    bucket: 'presentaties',
    accessKeyId: 'AKIA-wegwerp',
  );

  FileService fileService() =>
      FileService(MarkdownService(), ImageService(), ThemeProfile.new);

  ({TabsNotifier notifier, TabInfo tab}) tabs() {
    final container = ProviderContainer(
      overrides: [
        recoveryServiceProvider.overrideWithValue(
          RecoveryService(baseDir: Directory.systemTemp),
        ),
      ],
    );
    addTearDown(container.dispose);
    return (
      notifier: container.read(tabsProvider.notifier),
      tab: container.read(tabsProvider).current!,
    );
  }

  /// Een deck met een grafiek dat op schijf is opgeslagen, zodat het pakket
  /// naast de `.md` ook een `data/…json` draagt — anders valt er over volgorde
  /// niets te bewijzen.
  Future<Deck> deckWithAsset() async {
    final deck = Deck(
      title: 'Cijfers',
      slides: [
        Slide.create(SlideType.chart).copyWith(
          customMarkdown: const ChartSpec(
            title: 'Omzet',
            x: ['Jan', 'Feb'],
            series: [
              ChartSeries(name: 'Omzet', data: [120, 138]),
            ],
          ).toBlock(),
        ),
      ],
    );
    return fileService().saveDeck(deck, p.join(temp.path, 'deck.md'));
  }

  test('een plat opgeslagen deck zet het markdownbestand vooraan', () async {
    final t = tabs();
    t.tab.deckNotifier.loadDeck(await deckWithAsset());
    final s3 = _RecordingS3(bucket: bucket);

    await t.notifier.saveToS3(
      t.tab,
      s3,
      format: DeckSaveFormat.flat,
      targetPath: 'decks/cijfers.md',
    );

    expect(
      s3.puts.length,
      greaterThan(1),
      reason: 'zonder tweede lid bewijst de volgorde niets',
    );
    expect(s3.puts.first.path, 'decks/cijfers.md');
    expect(
      s3.puts.skip(1).every((put) => !put.path.endsWith('.md')),
      isTrue,
      reason: 'na het deck horen alleen nog assets te gaan',
    );
  });

  test('een botsing op het deck laat de assets ongemoeid', () async {
    final t = tabs();
    t.tab.deckNotifier.loadDeck(await deckWithAsset());
    // De gebruiker haalde het object eerder op; sindsdien wijzigde het.
    t.tab.s3Origin = const S3Origin(
      connectionId: 'conn-1',
      endpoint: 'https://s3.example',
      bucket: 'presentaties',
      remotePath: 'decks/cijfers.md',
      etag: '"oud"',
    );
    final s3 = _RecordingS3(bucket: bucket, conflictOn: 'decks/cijfers.md');

    await expectLater(
      t.notifier.saveToS3(
        t.tab,
        s3,
        format: DeckSaveFormat.flat,
        targetPath: 'decks/cijfers.md',
        connectionId: 'conn-1',
      ),
      throwsA(isA<S3ConflictException>()),
    );

    expect(s3.puts.map((put) => put.path), [
      'decks/cijfers.md',
    ], reason: 'er ging al een asset overheen vóór de botsing');
    // En de herkomst mag niet stiekem naar de niet-geschreven versie springen.
    expect(t.tab.s3Origin!.etag, '"oud"');
  });

  test('de bewaking geldt alleen voor precies het opgehaalde object', () async {
    final t = tabs();
    t.tab.deckNotifier.loadDeck(await deckWithAsset());
    t.tab.s3Origin = const S3Origin(
      connectionId: 'conn-1',
      endpoint: 'https://s3.example',
      bucket: 'presentaties',
      remotePath: 'decks/cijfers.md',
      etag: '"oud"',
    );

    // Zelfde pad → de etag gaat mee als If-Match.
    final same = _RecordingS3(bucket: bucket);
    await t.notifier.saveToS3(
      t.tab,
      same,
      format: DeckSaveFormat.ocideck,
      targetPath: 'decks/cijfers.md',
      connectionId: 'conn-1',
    );
    expect(same.puts.single.ifMatch, '"oud"');

    // Een ander pad koos de gebruiker zelf; daar valt niets te toetsen, dus
    // meesturen zou het opslaan zonder reden laten mislukken.
    t.tab.s3Origin = const S3Origin(
      connectionId: 'conn-1',
      endpoint: 'https://s3.example',
      bucket: 'presentaties',
      remotePath: 'decks/cijfers.md',
      etag: '"oud"',
    );
    final elsewhere = _RecordingS3(bucket: bucket);
    await t.notifier.saveToS3(
      t.tab,
      elsewhere,
      format: DeckSaveFormat.ocideck,
      targetPath: 'decks/kopie.md',
      connectionId: 'conn-1',
    );
    expect(elsewhere.puts.single.ifMatch, isNull);
  });

  test('overschrijven zet de bewaking bewust uit', () async {
    final t = tabs();
    t.tab.deckNotifier.loadDeck(await deckWithAsset());
    t.tab.s3Origin = const S3Origin(
      connectionId: 'conn-1',
      endpoint: 'https://s3.example',
      bucket: 'presentaties',
      remotePath: 'decks/cijfers.md',
      etag: '"oud"',
    );
    final s3 = _RecordingS3(bucket: bucket);

    await t.notifier.saveToS3(
      t.tab,
      s3,
      format: DeckSaveFormat.ocideck,
      targetPath: 'decks/cijfers.md',
      connectionId: 'conn-1',
      overwrite: true,
    );

    expect(s3.puts.single.ifMatch, isNull);
  });

  test('na het opslaan wijst de herkomst naar de nieuwe versie', () async {
    final t = tabs();
    t.tab.deckNotifier.loadDeck(await deckWithAsset());
    final s3 = _RecordingS3(bucket: bucket, etag: '"vers"');

    await t.notifier.saveToS3(
      t.tab,
      s3,
      format: DeckSaveFormat.ocideck,
      targetPath: 'decks/cijfers.ocideck',
      connectionId: 'conn-1',
    );

    final origin = t.tab.s3Origin!;
    expect(origin.remotePath, 'decks/cijfers.ocideck');
    expect(origin.bucket, 'presentaties');
    expect(origin.endpoint, 'https://s3.example');
    expect(origin.connectionId, 'conn-1');
    // Hierop toetst de vólgende opslag; blijft hij op de oude staan, dan
    // weigert het endpoint elke verdere opslag.
    expect(origin.etag, '"vers"');
  });

  test('een leeg verbindings-id wist de herkomst niet', () async {
    final t = tabs();
    t.tab.deckNotifier.loadDeck(await deckWithAsset());
    t.tab.s3Origin = const S3Origin(
      connectionId: 'conn-1',
      endpoint: 'https://s3.example',
      bucket: 'presentaties',
      remotePath: 'decks/cijfers.ocideck',
    );

    await t.notifier.saveToS3(
      t.tab,
      _RecordingS3(bucket: bucket),
      format: DeckSaveFormat.ocideck,
      targetPath: 'decks/cijfers.ocideck',
    );

    // Zonder terugval zou het deck zijn verbinding kwijtraken en zou "opslaan
    // naar de herkomst" nergens meer heen kunnen.
    expect(t.tab.s3Origin!.connectionId, 'conn-1');
  });

  test('een endpoint zonder etag laat de bewaking zichtbaar leeg', () async {
    final t = tabs();
    t.tab.deckNotifier.loadDeck(await deckWithAsset());
    final s3 = _RecordingS3(bucket: bucket, etag: null);

    await t.notifier.saveToS3(
      t.tab,
      s3,
      format: DeckSaveFormat.ocideck,
      targetPath: 'decks/cijfers.ocideck',
    );

    // Niet stilletjes de oude etag laten staan: dan denkt de volgende opslag
    // bewaakt te zijn terwijl hij dat niet is.
    expect(t.tab.s3Origin!.etag, isNull);
  });

  test('een tabblad zonder deck schrijft niets weg', () async {
    final t = tabs();
    final s3 = _RecordingS3(bucket: bucket);

    await t.notifier.saveToS3(
      t.tab,
      s3,
      format: DeckSaveFormat.ocideck,
      targetPath: 'decks/leeg.ocideck',
    );

    expect(s3.puts, isEmpty);
    expect(t.tab.s3Origin, isNull);
  });

  test('een pakket gaat als één object omhoog', () async {
    final t = tabs();
    t.tab.deckNotifier.loadDeck(await deckWithAsset());
    final s3 = _RecordingS3(bucket: bucket);

    await t.notifier.saveToS3(
      t.tab,
      s3,
      format: DeckSaveFormat.ocideck,
      targetPath: 'decks/cijfers.ocideck',
    );

    expect(s3.puts.length, 1);
    expect(s3.puts.single.path, 'decks/cijfers.ocideck');
    expect(s3.puts.single.bytes, greaterThan(0));
  });

  test('platte leden houden hun submap onder dezelfde prefix', () async {
    final t = tabs();
    t.tab.deckNotifier.loadDeck(await deckWithAsset());
    final s3 = _RecordingS3(bucket: bucket);

    await t.notifier.saveToS3(
      t.tab,
      s3,
      format: DeckSaveFormat.flat,
      targetPath: 'decks/2026/cijfers.md',
    );

    // Het deck krijgt de naam die de gebruiker koos, de rest blijft staan waar
    // het pakket het zette — maar wel onder dezelfde map.
    expect(s3.puts.first.path, 'decks/2026/cijfers.md');
    for (final put in s3.puts.skip(1)) {
      expect(put.path, startsWith('decks/2026/'));
      expect(put.ifMatch, isNull, reason: 'assets dragen geen bewaking');
    }
  });
}
