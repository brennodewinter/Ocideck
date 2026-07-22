import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart' show TlpLevel;
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/storage_connection.dart';
import 'package:ocideck/services/disk_traces.dart';
import 'package:ocideck/services/git/outbox.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late Directory temp;
  late DiskTraces traces;

  const repo = GitRepoConfig(
    baseUrl: 'https://git.example.org',
    owner: 'klant',
    repo: 'deck',
  );
  final slug = repo.storageSlug;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    support = Directory.systemTemp.createTempSync('ocideck_traces_support');
    temp = Directory.systemTemp.createTempSync('ocideck_traces_temp');
    traces = DiskTraces(supportDir: support, tempDir: temp);
  });

  tearDown(() {
    for (final dir in [support, temp]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  /// Legt een volledige werkkopie neer zoals de app hem achterlaat: een clone
  /// mét historie, de draft store en een wachtrij-sleutel.
  Directory workingCopy(String name, String forSlug) {
    final dir = Directory('${support.path}/$name/$forSlug/decks/kwartaal')
      ..createSync(recursive: true);
    File('${dir.path}/deck.md').writeAsStringSync('# Klantgegevens\n');
    return dir;
  }

  GitConnection connection({GitRepoConfig config = repo}) =>
      GitConnection(id: 'c1', name: 'Klant', repo: config);

  test(
    'een git-verbinding verwijderen neemt de sporen op schijf mee',
    () async {
      workingCopy('git_clone', slug);
      workingCopy('git_mirror', slug);

      final report = await traces.removeTracesOf(connection());

      expect(report.refused, isFalse);
      expect(report.removedPaths, hasLength(2));
      expect(
        Directory('${support.path}/git_clone/$slug').existsSync(),
        isFalse,
      );
      expect(
        Directory('${support.path}/git_mirror/$slug').existsSync(),
        isFalse,
      );
    },
  );

  test('de wachtrij-sleutels van die repo verdwijnen mee', () async {
    final outbox = Outbox(scope: slug);
    await outbox.enqueue(
      const PendingCommit(
        deckDir: 'decks/kwartaal',
        branch: 'main',
        message: 'Cijfers van de klant bijgewerkt',
        baseSha: 'abc',
      ),
    );

    await traces.removeTracesOf(connection(), discardPendingWork: true);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getKeys().where((k) => k.startsWith('git_outbox::')),
      isEmpty,
      reason: 'de getypte commitboodschap mag niet in prefs achterblijven',
    );
  });

  test('wachtend werk houdt het opruimen tegen', () async {
    workingCopy('git_clone', slug);
    final outbox = Outbox(scope: slug);
    await outbox.enqueue(
      const PendingCommit(
        deckDir: 'decks/kwartaal',
        branch: 'main',
        message: 'Nog niet gepusht',
        baseSha: 'abc',
      ),
    );

    final report = await traces.removeTracesOf(connection());

    expect(report.refused, isTrue);
    expect(report.refusedPendingCommits, 1);
    expect(
      Directory('${support.path}/git_clone/$slug').existsSync(),
      isTrue,
      reason: 'nooit stil weggooien wat nergens anders bestaat',
    );
    expect(await outbox.pending(), hasLength(1));
  });

  test('de wachtrij van een ándere repo blijft ongemoeid', () async {
    const other = GitRepoConfig(
      baseUrl: 'https://git.example.org',
      owner: 'anders',
      repo: 'deck',
    );
    workingCopy('git_clone', other.storageSlug);
    await Outbox(scope: other.storageSlug).enqueue(
      const PendingCommit(
        deckDir: 'decks/kwartaal',
        branch: 'main',
        message: 'Van iemand anders',
        baseSha: 'abc',
      ),
    );

    await traces.removeTracesOf(connection(), discardPendingWork: true);

    expect(
      Directory('${support.path}/git_clone/${other.storageSlug}').existsSync(),
      isTrue,
    );
    expect(await Outbox(scope: other.storageSlug).pending(), hasLength(1));
  });

  test(
    'een lokale verbinding raakt de map van de gebruiker niet aan',
    () async {
      final mine = Directory('${support.path}/mijn_presentaties')
        ..createSync(recursive: true);
      File('${mine.path}/deck.md').writeAsStringSync('# Van mij\n');

      final report = await traces.removeTracesOf(
        LocalConnection(id: 'l1', name: 'Mijn presentaties', path: mine.path),
      );

      expect(report.removedPaths, isEmpty);
      expect(File('${mine.path}/deck.md').existsSync(), isTrue);
    },
  );

  test('verweesde stijl-logo\'s gaan weg, gebruikte blijven', () async {
    final dir = Directory('${support.path}/style_logos')
      ..createSync(recursive: true);
    final used = File('${dir.path}/in-gebruik.png')..writeAsBytesSync([1]);
    final orphan = File('${dir.path}/verweesd.png')..writeAsBytesSync([2]);

    orphan.setLastModifiedSync(
      DateTime.now().subtract(const Duration(days: 30)),
    );

    final removed = await traces.pruneOrphanStyleLogos([used.path]);

    expect(removed, 1);
    expect(used.existsSync(), isTrue);
    expect(orphan.existsSync(), isFalse);
  });

  test('het opruimen meldt hoeveel wachtrij-sleutels het wiste', () async {
    await Outbox(scope: slug).enqueue(
      const PendingCommit(
        deckDir: 'decks/kwartaal',
        branch: 'main',
        message: 'weg',
        baseSha: 'abc',
      ),
    );

    final report = await traces.removeGitTraces(slug, discardPendingWork: true);

    expect(report.removedOutboxKeys, 1);
    expect(report.refused, isFalse);
  });

  test('een lege slug ruimt niets op', () async {
    final report = await traces.removeGitTraces('');
    expect(report.removedPaths, isEmpty);
    expect(report.removedOutboxKeys, 0);
  });

  test('eigenaar-alleen doet niets buiten Linux', () async {
    // De poort draait op macOS; daar is de map al per gebruiker afgeschermd en
    // hoort er geen subproces te starten.
    expect(await traces.restrictToOwner(), Platform.isLinux ? isNonZero : 0);
  });

  test('de git-zandbak wordt opgeruimd', () async {
    final sandbox = Directory('${temp.path}/ocideck_git_sandbox')
      ..createSync(recursive: true);
    File('${sandbox.path}/.gitconfig').writeAsStringSync('[user]\n');

    expect(await traces.clearGitSandbox(), isTrue);
    expect(sandbox.existsSync(), isFalse);
  });

  test('alles terugzetten wist elke werkkopie en de hele wachtrij', () async {
    workingCopy('git_clone', slug);
    workingCopy('git_mirror', 'een-andere-repo');
    await Outbox(scope: slug).enqueue(
      const PendingCommit(
        deckDir: 'decks/kwartaal',
        branch: 'main',
        message: 'weg',
        baseSha: 'abc',
      ),
    );
    await Outbox().enqueue(
      const PendingCommit(
        deckDir: 'decks/oud',
        branch: 'main',
        message: 'ook weg',
        baseSha: 'abc',
      ),
    );

    await traces.clearAllGitWorkingCopies();

    expect(Directory('${support.path}/git_clone').existsSync(), isFalse);
    expect(Directory('${support.path}/git_mirror').existsSync(), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith('git_outbox::')), isEmpty);
  });

  group('via de instellingen', () {
    test('een verbinding uit de lijst halen ruimt haar werkkopie op', () async {
      workingCopy('git_clone', slug);
      final notifier = SettingsNotifier(diskTraces: traces);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await notifier.addConnection(connection());

      await notifier.removeConnection('c1');

      expect(notifier.state.connections, isEmpty);
      expect(
        Directory('${support.path}/git_clone/$slug').existsSync(),
        isFalse,
      );
    });

    test(
      'wachtend werk laat de werkkopie staan tot het is bevestigd',
      () async {
        workingCopy('git_clone', slug);
        await Outbox(scope: slug).enqueue(
          const PendingCommit(
            deckDir: 'decks/kwartaal',
            branch: 'main',
            message: 'nog niet gepusht',
            baseSha: 'abc',
          ),
        );
        final notifier = SettingsNotifier(diskTraces: traces);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await notifier.addConnection(connection());

        await notifier.removeConnection('c1');
        expect(
          Directory('${support.path}/git_clone/$slug').existsSync(),
          isTrue,
        );

        await notifier.addConnection(connection());
        await notifier.removeConnection('c1', discardPendingWork: true);
        expect(
          Directory('${support.path}/git_clone/$slug').existsSync(),
          isFalse,
        );
      },
    );
  });

  group('stijl-logo\'s', () {
    late Directory logos;

    setUp(() {
      logos = Directory('${support.path}/style_logos')..createSync();
    });

    File logo(String name, {Duration? age}) {
      final file = File('${logos.path}/$name')..writeAsBytesSync([1, 2, 3]);
      if (age != null) file.setLastModifiedSync(DateTime.now().subtract(age));
      return file;
    }

    test('een vers logo overleeft de veger, ook zonder profiel', () async {
      final fresh = logo('vers.png');
      expect(await traces.pruneOrphanStyleLogos(const []), 0);
      expect(
        fresh.existsSync(),
        isTrue,
        reason: 'een tweede venster kan het net hebben neergezet',
      );
    });

    test('een oud, niet-aangehaald logo gaat weg', () async {
      final old = logo('oud.png', age: const Duration(days: 30));
      expect(await traces.pruneOrphanStyleLogos(const []), 1);
      expect(old.existsSync(), isFalse);
    });

    test('een profiel verwijderen wist zijn logo meteen', () async {
      final mine = logo('klantlogo.png');
      final notifier = SettingsNotifier(diskTraces: traces);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await notifier.saveThemeProfile(
        ThemeProfile(name: 'Klant', logoPath: mine.path),
        previousName: 'Klant',
      );
      expect(mine.existsSync(), isTrue);

      await notifier.deleteThemeProfile('Klant');

      expect(
        mine.existsSync(),
        isFalse,
        reason: 'het logo van een opdrachtgever hoort niet te blijven liggen',
      );
    });

    test('een pad buiten style_logos blijft van ons af', () async {
      final elders = File('${support.path}/eigen-map-logo.png')
        ..writeAsBytesSync([1]);
      expect(await traces.removeStyleLogos([elders.path]), 0);
      expect(elders.existsSync(), isTrue);
    });
  });

  group('de recente lijst en het terugzetten', () {
    Future<SettingsNotifier> loaded() async {
      final notifier = SettingsNotifier(diskTraces: traces);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return notifier;
    }

    test('de recente lijst wissen laat niets in prefs achter', () async {
      final notifier = await loaded();
      await notifier.addRecentFile(
        '/klanten/politie/incident.md',
        tlp: TlpLevel.red,
      );
      await notifier.setRecentFileOrigin(
        '/klanten/politie/incident.md',
        'https://cloud.klant.nl',
      );
      expect(notifier.state.recentFiles, hasLength(1));

      await notifier.clearRecentFiles();

      expect(notifier.state.recentFiles, isEmpty);
      expect(notifier.state.recentFileOrigins, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('recentFilesV2'), isNull);
      expect(prefs.getString('recentFileOrigins'), isNull);
    });

    test(
      'een gewiste lijst komt niet terug uit de oude prefs-sleutel',
      () async {
        SharedPreferences.setMockInitialValues({
          'recentFiles': ['/klanten/politie/incident.md'],
        });
        final notifier = await loaded();
        expect(notifier.state.recentFiles, hasLength(1));

        await notifier.clearRecentFiles();
        final reloaded = SettingsNotifier(diskTraces: traces);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(
          reloaded.state.recentFiles,
          isEmpty,
          reason: 'de migratie mag de opruiming niet ongedaan maken',
        );
      },
    );

    test('terugzetten wist prefs, werkkopieën en logo\'s', () async {
      workingCopy('git_clone', slug);
      Directory('${support.path}/style_logos').createSync();
      File('${support.path}/style_logos/logo.png').writeAsBytesSync([1]);
      final notifier = await loaded();
      await notifier.addRecentFile('/klanten/politie/incident.md');
      await notifier.setLanguageCode('de');

      expect(await notifier.resetToInitialState(), isTrue);

      expect(notifier.state.recentFiles, isEmpty);
      expect(notifier.state.languageCode, 'nl');
      expect(Directory('${support.path}/git_clone').existsSync(), isFalse);
      expect(Directory('${support.path}/style_logos').existsSync(), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    test('terugzetten weigert zolang er werk wacht', () async {
      workingCopy('git_clone', slug);
      await Outbox(scope: slug).enqueue(
        const PendingCommit(
          deckDir: 'decks/kwartaal',
          branch: 'main',
          message: 'nog niet gepusht',
          baseSha: 'abc',
        ),
      );
      final notifier = await loaded();

      expect(await notifier.pendingCommitCount(), 1);
      expect(await notifier.resetToInitialState(), isFalse);
      expect(Directory('${support.path}/git_clone').existsSync(), isTrue);

      expect(
        await notifier.resetToInitialState(discardPendingWork: true),
        isTrue,
      );
      expect(Directory('${support.path}/git_clone').existsSync(), isFalse);
    });
  });
}
