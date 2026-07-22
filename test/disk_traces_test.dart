import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/git_settings.dart';
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

    final removed = await traces.pruneOrphanStyleLogos([used.path]);

    expect(removed, 1);
    expect(used.existsSync(), isTrue);
    expect(orphan.existsSync(), isFalse);
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
}
