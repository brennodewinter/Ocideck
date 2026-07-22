import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/services/git/git_forge.dart';
import 'package:ocideck/services/git/work_branch.dart';

/// Ontwerpbesluit D3: bewerken gebeurt op een werkbranch, nooit rechtstreeks op
/// de standaardbranch. Deze keuze zat tot #518 in de state-laag, waar hij alleen
/// via een opslag met een forge eromheen te bereiken was — vandaar dat er geen
/// enkele test op stond terwijl hij twee dingen tegelijk beslist: waar dit werk
/// landt, én wat de commit is waar de guard straks tegenaan botst.
///
/// Die tweede is de subtiele. `baseSha` leeg betekent "er is geen voorouder";
/// dat is iets anders dan een lege string uit slordigheid, want de aanroeper
/// weigert dan de opslag in plaats van er blind overheen te schrijven.
void main() {
  const config = GitRepoConfig(
    baseUrl: 'https://git.example.org',
    owner: 'acme',
    repo: 'decks',
    provider: GitProvider.gitea,
    defaultBranch: 'main',
  );
  const andereRepo = GitRepoConfig(
    baseUrl: 'https://git.example.org',
    owner: 'acme',
    repo: 'anders',
    provider: GitProvider.gitea,
    defaultBranch: 'main',
  );
  final vandaag = DateTime(2026, 7, 22);

  GitOrigin origin({
    GitRepoConfig cfg = config,
    String branch = 'decks/kwartaalcijfers/2026-07-21',
    String deckDir = 'decks/kwartaalcijfers',
    String baseSha = 'sha-gelezen',
  }) => GitOrigin(
    config: cfg,
    branch: branch,
    deckDir: deckDir,
    baseSha: baseSha,
  );

  WorkBranchChoice kies({
    GitOrigin? van,
    String deckDir = 'decks/kwartaalcijfers',
    String deckName = 'kwartaalcijfers',
    String branch = 'main',
  }) => workBranchFor(
    origin: van,
    config: config,
    deckDir: deckDir,
    deckName: deckName,
    branch: branch,
    now: vandaag,
  );

  group('midden in een ronde', () {
    test('blijft op de branch waar dit werk vandaan komt', () {
      final keuze = kies(van: origin());

      expect(keuze.workBranch, 'decks/kwartaalcijfers/2026-07-21');
      expect(keuze.midRound, isTrue);
      // Niets af te takken: die branch bestaat al en we staan erop.
      expect(keuze.forkFrom, isNull);
      expect(keuze.baseSha, 'sha-gelezen');
    });

    test('de datum van gisteren houdt de ronde van gisteren vast', () {
      // Anders zou wie 's nachts doorwerkt halverwege naar een nieuwe branch
      // springen en zijn eigen werk als "iemand anders" tegenkomen.
      final keuze = kies(
        van: origin(branch: 'decks/kwartaalcijfers/2026-07-01'),
      );

      expect(keuze.workBranch, 'decks/kwartaalcijfers/2026-07-01');
      expect(keuze.midRound, isTrue);
    });
  });

  group('een verse ronde', () {
    test('krijgt de branch van vandaag en takt af van de standaardbranch', () {
      final keuze = kies();

      expect(keuze.workBranch, 'decks/kwartaalcijfers/2026-07-22');
      expect(keuze.midRound, isFalse);
      expect(keuze.forkFrom, 'main');
    });

    test('zonder herkomst is er geen voorouder', () {
      // Een deck dat nog nooit uit deze repo is gelezen. Leeg is hier een
      // uitspraak, geen slordigheid: de aanroeper weigert dan liever dan
      // ergens overheen te schrijven.
      expect(kies().baseSha, isEmpty);
    });

    test('mét herkomst reist de gelezen basis wél mee', () {
      // De werkbranch draagt alleen een datum, dus die van vandaag kán al
      // bestaan — een tweede ronde op dezelfde dag, of een collega die eerder
      // was. Dit is de voorouder waar de guard op botst en waarmee de
      // driewegs-merge kan werken.
      final keuze = kies(van: origin(branch: 'main'));

      expect(keuze.midRound, isFalse);
      expect(keuze.baseSha, 'sha-gelezen');
    });
  });

  group('wanneer de herkomst niet over dít deck gaat', () {
    test('een ander deck in dezelfde repo telt niet mee', () {
      final keuze = kies(van: origin(deckDir: 'decks/jaarplan'));

      expect(keuze.midRound, isFalse);
      expect(keuze.workBranch, 'decks/kwartaalcijfers/2026-07-22');
      expect(keuze.baseSha, isEmpty, reason: 'andermans sha is geen voorouder');
    });

    test('hetzelfde pad in een andere repo evenmin', () {
      // Twee repo's mogen dezelfde deckmap hebben. Een sha uit de ene tegen de
      // andere aanhouden zou een guard opleveren die nergens over gaat.
      final keuze = kies(van: origin(cfg: andereRepo));

      expect(keuze.midRound, isFalse);
      expect(keuze.baseSha, isEmpty);
    });
  });

  group('een naam waar geen geldige branch van te maken is', () {
    test('wordt geweigerd, niet stilzwijgend omgevormd', () {
      // Een branchnaam is ook een git-ref; een naam die daar niet in past moet
      // een fout worden en geen benadering, want dan schrijf je naar een
      // andere ref dan je denkt.
      expect(
        () => kies(deckName: '..'),
        throwsA(
          isA<GitForgeException>().having(
            (e) => e.kind,
            'kind',
            GitForgeError.malformed,
          ),
        ),
      );
    });
  });
}
