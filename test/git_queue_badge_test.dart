@TestOn('vm')
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/models/storage_connection.dart';
import 'package:ocideck/services/git/outbox.dart';
import 'package:ocideck/state/git_provider.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De teller onder de wachtrij-indicator in de statusbalk.
///
/// Werk dat offline is opgeslagen wácht: het is niet weg, maar het staat ook
/// nog nergens waar een ander erbij kan. Tot nu toe zag je dat alleen wanneer
/// je er zelf naar vroeg, en dan stond het er meestal al even.
void main() {
  const klantA = GitRepoConfig(
    baseUrl: 'https://git.a.example',
    owner: 'klant-a',
    repo: 'decks',
  );
  const klantB = GitRepoConfig(
    baseUrl: 'https://git.b.example',
    owner: 'klant-b',
    repo: 'decks',
  );

  PendingCommit commit(String deck) => PendingCommit(
    deckDir: 'decks/$deck',
    branch: 'main',
    message: 'werk',
    baseSha: 'abc123',
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Zet de verbindingen klaar en geef een container die ze kent.
  Future<ProviderContainer> containerWith(
    List<StorageConnection> connections,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(settingsProvider.notifier);
    // Wachten tot de instellingen geladen zijn, anders leest de teller een
    // lege lijst en telt hij niets.
    await Future<void>.delayed(Duration.zero);
    await notifier.setConnections(connections);
    return container;
  }

  test('zonder git-verbindingen is de teller nul', () async {
    final container = await containerWith([
      const LocalConnection(id: 'l', name: 'Privé', path: '/tmp/x'),
    ]);
    expect(await container.read(gitQueueCountProvider.future), 0);
  });

  test('telt over alle git-verbindingen samen', () async {
    // Twee opdrachtgevers, elk hun eigen wachtrij. De balk toont één getal,
    // want de gebruiker wil weten of er íets wacht — niet waar.
    await Outbox(scope: klantA.storageSlug).enqueue(commit('kwartaalcijfers'));
    await Outbox(scope: klantB.storageSlug).enqueue(commit('alpha'));
    await Outbox(scope: klantB.storageSlug).enqueue(commit('beta'));

    final container = await containerWith([
      GitConnection(id: 'a', name: 'Klant A', repo: klantA),
      GitConnection(id: 'b', name: 'Klant B', repo: klantB),
    ]);
    expect(await container.read(gitQueueCountProvider.future), 3);
  });

  test('een lege wachtrij telt niet mee', () async {
    final container = await containerWith([
      GitConnection(id: 'a', name: 'Klant A', repo: klantA),
    ]);
    expect(await container.read(gitQueueCountProvider.future), 0);
  });
}
