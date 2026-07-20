import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/services/git/deck_search.dart';
import 'package:ocideck/services/git/git_forge.dart';
import 'package:ocideck/services/git/gitea_forge.dart';
import 'package:ocideck/services/git/github_forge.dart';
import 'package:ocideck/services/git/gitlab_forge.dart';

import 'git_forge_fake.dart';
import 'git_forge_fake_github.dart';
import 'git_forge_fake_gitlab.dart';

// De server-side codezoekopdracht (§9.3): GitHub en GitLab kunnen aanwijzen
// wélke decks een term bevatten, zodat DeckSearch alleen die leest. Gitea/Forgejo
// heeft er geen REST-endpoint voor en doet dus niet mee.

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

FakeRepo _repo() => FakeRepo(
  branches: {'main': 'c'},
  files: {
    'decks/jaarplan/deck.md': _b('# Jaarplan\n\ndekking 80 procent'),
    'decks/kwartaal/deck.md': _b('# Kwartaal\n\ndekking 79 procent'),
    // Geen deck.md — moet door de adapter worden weggefilterd, ook al matcht het.
    'decks/kwartaal/notes.md': _b('losse dekking-notitie'),
    'decks/leeg/deck.md': _b('# Leeg\n\nniets bijzonders'),
    'README.md': _b('dekking staat ook hier'),
  },
);

const _githubConfig = GitRepoConfig(
  baseUrl: 'https://github.com',
  owner: 'librekat',
  repo: 'decks',
);
const _gitlabConfig = GitRepoConfig(
  baseUrl: 'https://gitlab.com',
  owner: 'librekat',
  repo: 'decks',
);
const _giteaConfig = GitRepoConfig(
  baseUrl: 'https://gitea.example',
  owner: 'librekat',
  repo: 'decks',
);

void main() {
  group('GitHubForge.searchDeckCodeDirs', () {
    GitHubForge forge(FakeRepo repo) => GitHubForge(
      config: _githubConfig,
      token: 't',
      transport: FakeGitHubTransport(repo),
    );

    test('geeft de deckmappen terug en filtert niet-deck.md weg', () async {
      final dirs = await forge(
        _repo(),
      ).searchDeckCodeDirs('dekking', branch: 'main', defaultBranch: 'main');
      expect(dirs, {'decks/jaarplan', 'decks/kwartaal'});
    });

    test('een andere branch dan de standaard: geen versnelling', () async {
      // GitHub indexeert alléén de standaardbranch.
      final dirs = await forge(
        _repo(),
      ).searchDeckCodeDirs('dekking', branch: 'feature', defaultBranch: 'main');
      expect(dirs, isNull);
    });

    test('geen serverzijdige treffer geeft null, niet leeg', () async {
      // Leeg is dubbelzinnig — geen treffer óf niet geïndexeerd — dus terugvallen.
      final dirs = await forge(_repo()).searchDeckCodeDirs(
        'nietbestaand',
        branch: 'main',
        defaultBranch: 'main',
      );
      expect(dirs, isNull);
    });
  });

  group('GitLabForge.searchDeckCodeDirs', () {
    GitLabForge forge(FakeRepo repo) => GitLabForge(
      config: _gitlabConfig,
      token: 't',
      transport: FakeGitLabTransport(repo),
    );

    test('geeft de deckmappen terug en filtert niet-deck.md weg', () async {
      final dirs = await forge(
        _repo(),
      ).searchDeckCodeDirs('dekking', branch: 'main', defaultBranch: 'main');
      expect(dirs, {'decks/jaarplan', 'decks/kwartaal'});
    });

    test('werkt ook op een niet-standaardbranch via de ref', () async {
      // Anders dan GitHub kent GitLab een ref-parameter.
      final dirs = await forge(
        _repo(),
      ).searchDeckCodeDirs('dekking', branch: 'feature', defaultBranch: 'main');
      expect(dirs, {'decks/jaarplan', 'decks/kwartaal'});
    });

    test('geen treffer geeft null', () async {
      final dirs = await forge(_repo()).searchDeckCodeDirs(
        'nietbestaand',
        branch: 'main',
        defaultBranch: 'main',
      );
      expect(dirs, isNull);
    });
  });

  group('ServerCodeSearchShortlister', () {
    test('verpakt de servertreffers als een best-effort shortlist', () async {
      final forge = GitHubForge(
        config: _githubConfig,
        token: 't',
        transport: FakeGitHubTransport(_repo()),
      );
      final result = await ServerCodeSearchShortlister(
        forge,
      ).shortlist('dekking', caseSensitive: false, branch: 'main');
      expect(result, isNotNull);
      expect(result!.deckDirs, {'decks/jaarplan', 'decks/kwartaal'});
      // Geïndexeerd: nooit als volledig gepresenteerd.
      expect(result.coverage, DeckSearchCoverage.bestEffort);
    });

    test('een forge zonder codezoeken versnelt niet', () async {
      final forge = GiteaForge(
        config: _giteaConfig,
        token: 't',
        transport: FakeGiteaTransport(_repo()),
      );
      final result = await ServerCodeSearchShortlister(
        forge,
      ).shortlist('dekking', caseSensitive: false, branch: 'main');
      expect(result, isNull);
    });
  });

  group('CodeSearchCapable', () {
    test('GitHub en GitLab kunnen het, Gitea/Forgejo niet', () {
      expect(
        GitHubForge(
          config: _githubConfig,
          token: '',
          transport: FakeGitHubTransport(_repo()),
        ),
        isA<CodeSearchCapable>(),
      );
      expect(
        GitLabForge(
          config: _gitlabConfig,
          token: '',
          transport: FakeGitLabTransport(_repo()),
        ),
        isA<CodeSearchCapable>(),
      );
      expect(
        GiteaForge(
          config: _giteaConfig,
          token: '',
          transport: FakeGiteaTransport(_repo()),
        ),
        isNot(isA<CodeSearchCapable>()),
      );
    });
  });
}
