import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/storage_connection.dart';

/// Welke git-verbinding hoort bij een geopend deck?
///
/// Dit is de vraag die stil fout kan gaan. Kiest de app de verkeerde, dan wordt
/// het werk van de ene opdrachtgever naar de repository van de andere
/// geschreven — en dat geeft geen foutmelding, want technisch klopt elke stap.
/// Vandaar dat de terugvallen hier expliciet vastliggen.
void main() {
  const repoA = GitRepoConfig(
    baseUrl: 'https://git.a.example',
    owner: 'klant-a',
    repo: 'decks',
  );
  const repoB = GitRepoConfig(
    baseUrl: 'https://git.b.example',
    owner: 'klant-b',
    repo: 'decks',
  );

  const connA = GitConnection(id: 'a', name: 'Klant A', repo: repoA);
  const connB = GitConnection(id: 'b', name: 'Klant B', repo: repoB);

  const settings = AppSettings(connections: [connA, connB]);

  GitOrigin origin({required GitRepoConfig config, String connectionId = ''}) =>
      GitOrigin(
        config: config,
        branch: 'main',
        deckDir: 'decks/kwartaalcijfers',
        baseSha: 'abc123',
        connectionId: connectionId,
      );

  test('op id, ook als de configuratie inmiddels is bijgewerkt', () {
    // De gebruiker herstelde een typefout in de server-URL. De id blijft
    // gelijk, dus het deck hoort nog steeds bij dezelfde opdrachtgever.
    final verouderd = origin(
      config: repoA.copyWith(baseUrl: 'https://gti.a.example'),
      connectionId: 'a',
    );
    expect(
      settings.gitConnectionFor(verouderd.connectionId, verouderd.config)?.id,
      'a',
    );
  });

  test('zonder id valt hij terug op de configuratie', () {
    // Herkomst uit een versie van vóór de verbindingenlijst draagt geen id.
    // Zonder deze terugval raakt zo'n deck losgeslagen van zijn repo.
    final oud = origin(config: repoB);
    expect(settings.gitConnectionFor(oud.connectionId, oud.config)?.id, 'b');
  });

  test('een verwijderde verbinding levert null, geen andere repo', () {
    // Het gevaarlijke geval: als dit stilletjes de bovenste verbinding koos,
    // schreef een opslag het werk naar de verkeerde klant.
    final weg = origin(
      config: const GitRepoConfig(
        baseUrl: 'https://git.c.example',
        owner: 'klant-c',
        repo: 'decks',
      ),
      connectionId: 'weg',
    );
    expect(settings.gitConnectionFor(weg.connectionId, weg.config), isNull);
  });

  test('een half ingevulde verbinding telt niet als standaard', () {
    const half = GitConnection(
      id: 'half',
      name: 'In aanbouw',
      repo: GitRepoConfig(baseUrl: '', owner: '', repo: ''),
    );
    const s = AppSettings(connections: [half, connA]);
    expect(s.gitRepo, repoA);
    expect(s.connectionsOf<GitConnection>().map((c) => c.id), ['a']);
  });

  test('de bovenste git-verbinding is de standaard, en volgt de volgorde', () {
    expect(settings.gitRepo, repoA);
    const omgedraaid = AppSettings(connections: [connB, connA]);
    expect(omgedraaid.gitRepo, repoB);
  });

  test('GitOrigin bewaart de verbinding over een copyWith heen', () {
    final o = origin(config: repoA, connectionId: 'a');
    expect(o.copyWith(baseSha: 'def456').connectionId, 'a');
  });
}
