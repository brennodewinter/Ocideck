import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/git_settings.dart';
import '../../utils/atomic_file.dart';
import '../../utils/log.dart';
import 'deck_mirror.dart';
import 'draft_store_io.dart';
import 'git_cli.dart';
import 'git_forge.dart';
import 'native_git_mirror_api.dart';

/// Bouwt de native mirror voor [config] op desktop. De aanroeper heeft al met de
/// probe vastgesteld dat er bruikbaar `git` is; hier wordt de clone-locatie
/// bepaald (onder app-support, of [baseDir] in tests).
Future<NativeGitMirror?> createNativeGitMirror({
  required GitCli git,
  required GitRepoConfig config,
  required String token,
  String? baseDir,
}) async {
  final worktree = baseDir != null
      ? Directory(baseDir)
      : Directory(
          p.join(
            (await getApplicationSupportDirectory()).path,
            'git_clone',
            config.storageSlug,
          ),
        );
  return _NativeGitMirror(
    git: git,
    config: config,
    token: token,
    worktree: worktree,
  );
}

class _NativeGitMirror implements NativeGitMirror {
  _NativeGitMirror({
    required this._git,
    required this._config,
    required this._token,
    required Directory worktree,
  }) : _worktree = worktree,
       _guarded = DraftMirror(store: FileDraftStore(baseDir: worktree));

  final GitCli _git;
  final GitRepoConfig _config;
  final String _token;
  final Directory _worktree;

  /// De gewone opslagcontract-methodes lenen we van een [DraftMirror] over de
  /// werkboom: die past de deckmap-guards toe en slaagt zo voor exact hetzelfde
  /// [DeckMirror]-contract als de REST-variant.
  final DeckMirror _guarded;

  String get _branch => _config.defaultBranch;

  bool get _cloned => Directory(p.join(_worktree.path, '.git')).existsSync();

  String get _cloneUrl {
    final base = _config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return '$base/${_config.owner}/${_config.repo}.git';
  }

  /// Identiteit en — als er een token is — de auth-header via `GIT_CONFIG_*`
  /// (§10.2): het token belandt zo nooit in argv, de URL of `.git/config`.
  /// De identiteit is voorlopig vast; per-repo naam/e-mail (D11) komt later.
  List<GitConfigOverride> get _config0 {
    final overrides = <GitConfigOverride>[
      const GitConfigOverride('user.name', 'OciDeck'),
      const GitConfigOverride('user.email', 'ocideck@localhost'),
    ];
    final token = _token.trim();
    if (token.isNotEmpty) {
      final basic = base64.encode(utf8.encode('${_config.owner}:$token'));
      overrides.add(
        GitConfigOverride(
          'http.extraHeader',
          'Authorization: Basic $basic',
          secret: true,
        ),
      );
    }
    return overrides;
  }

  Future<GitResult> _run(
    List<String> args, {
    List<String> operands = const [],
    Duration timeout = const Duration(seconds: 60),
  }) => _git.run(
    args,
    operands: operands,
    workingDirectory: _worktree.path,
    config: _config0,
    timeout: timeout,
  );

  // ── DeckMirror-contract (gedelegeerd) ──────────────────────────────────────
  @override
  Future<void> writeDeck(String deckDir, Map<String, Uint8List> files) =>
      _guarded.writeDeck(deckDir, files);
  @override
  Future<Map<String, Uint8List>> readDeck(String deckDir) =>
      _guarded.readDeck(deckDir);
  @override
  Future<bool> hasDeck(String deckDir) => _guarded.hasDeck(deckDir);
  @override
  Future<void> discardDeck(String deckDir) => _guarded.discardDeck(deckDir);
  @override
  Future<List<String>> deckDirs() => _guarded.deckDirs();
  @override
  bool get hasRealHistory => true;
  @override
  bool get isDurable => true;

  // ── Native versiebeheer ────────────────────────────────────────────────────
  @override
  Future<void> prepareForOpen() async {
    await _ensureClone();
    // Best-effort: offline openen mag, dan werken we met wat er lokaal is.
    try {
      await _run(['fetch', 'origin'], operands: [_branch]);
      // Alleen fast-forward: staat de branch verder, dan halen we die op; hebben
      // we zelf nog niet-gepushte commits (divergentie), dan faalt dit en houden
      // we ons eigen werk. Zo openen we de nieuwste versie zonder ooit iets weg
      // te gooien.
      await _run(['merge', '--ff-only'], operands: ['origin/$_branch']);
    } on GitCliException catch (e) {
      logWarning('NativeGitMirror: fetch/ff mislukt (offline of divergent)', e);
    }
  }

  @override
  Future<String?> headSha() async {
    if (!_cloned) return null;
    try {
      final res = await _run(['rev-parse', 'HEAD']);
      return res.stdout.trim();
    } on GitCliException {
      return null;
    }
  }

  @override
  Future<GitCommitResult> commitDeck(
    String deckDir,
    Map<String, Uint8List> repoFiles,
    String message, {
    String? workBranch,
    String? forkFrom,
  }) async {
    await _ensureClone();

    // D3: een bewerkingsronde landt op een werkbranch, niet op de
    // standaardbranch. Check hem uit (of maak hem, afgetakt van [forkFrom]); de
    // push en het ongepusht-tellen volgen daarna de uitgecheckte branch. Zonder
    // werkbranch blijft alles op de standaardbranch, precies als voorheen.
    if (workBranch != null && workBranch != _branch) {
      await _ensureOnWorkBranch(workBranch, forkFrom ?? _branch);
    }

    // Scheid de deckmap-leden (die de map volledig vervangen) van de pool-blobs
    // (die er alleen bij komen — de pool wordt nooit hier opgeschoond, §6.2).
    final deckMembers = <String, Uint8List>{};
    final assetMembers = <String, Uint8List>{};
    for (final entry in repoFiles.entries) {
      if (!GitRepoLayout.isSafeRepoPath(entry.key)) {
        throw GitForgeException(
          GitForgeError.malformed,
          'Onveilig pad in commit: ${entry.key}',
        );
      }
      if (p.posix.isWithin(deckDir, p.posix.normalize(entry.key))) {
        deckMembers[entry.key] = entry.value;
      } else {
        assetMembers[entry.key] = entry.value;
      }
    }

    // De deckmap in z'n geheel vervangen zodat een verwijderd lid ook echt weg
    // is; daarna de blobs erbij schrijven.
    final deckAbs = Directory(
      p.join(_worktree.path, p.joinAll(deckDir.split('/'))),
    );
    if (await deckAbs.exists()) await deckAbs.delete(recursive: true);
    await _writeAll(deckMembers);
    await _writeAll(assetMembers);

    await _run(['add', '-A'], operands: [deckDir]);
    if (assetMembers.isNotEmpty) {
      await _run(['add'], operands: assetMembers.keys.toList());
    }

    final staged = await _run(['diff', '--cached', '--name-only']);
    if (staged.stdout.trim().isNotEmpty) {
      await _commit(message);
    } else if (await _unpushedCount() == 0) {
      return GitCommitResult(GitCommitOutcome.unchanged, sha: await headSha());
    }
    return _push();
  }

  @override
  Future<GitCommitResult> sync() async {
    if (!_cloned) {
      return const GitCommitResult(GitCommitOutcome.unchanged);
    }
    if (await _unpushedCount() == 0) {
      return GitCommitResult(GitCommitOutcome.unchanged, sha: await headSha());
    }
    return _push();
  }

  @override
  Future<GitCommitResult> mergeRemote({
    required String branch,
    required String deckDir,
    required String deckFile,
    required String message,
    required Future<({Map<String, Uint8List> files, bool clean})> Function(
      Uint8List? base,
      Uint8List? ours,
      Uint8List? theirs,
    )
    resolve,
  }) async {
    if (!_cloned) return const GitCommitResult(GitCommitOutcome.unchanged);
    final remote = 'origin/$branch';

    // Zonder verse ophaal weten we niet wat "die van hen" is.
    try {
      await _run(['fetch', 'origin'], operands: [branch]);
    } on GitCliException catch (e) {
      logWarning('mergeRemote: fetch mislukt (offline?)', e);
      return GitCommitResult(
        GitCommitOutcome.committedOffline,
        sha: await headSha(),
      );
    }

    // De gemeenschappelijke voorouder is hier écht op te vragen — anders dan op
    // het REST-pad, waar de gelezen basis-sha ervoor door moet gaan.
    final String base;
    try {
      final res = await _run(['merge-base'], operands: ['HEAD', remote]);
      base = res.stdout.trim();
    } on GitCliException catch (e) {
      logWarning('mergeRemote: geen gemeenschappelijke voorouder', e);
      return GitCommitResult(
        GitCommitOutcome.committedConflict,
        sha: await headSha(),
      );
    }
    if (base.isEmpty) {
      return GitCommitResult(
        GitCommitOutcome.committedConflict,
        sha: await headSha(),
      );
    }

    final resolved = await resolve(
      await _showAtRef(base, deckFile),
      await _showAtRef('HEAD', deckFile),
      await _showAtRef(remote, deckFile),
    );

    // Laat git de rest van de boom samenvoegen — de pool-blobs zijn
    // inhoudsgeadresseerd en komen er dus gewoon bij. Dat `deck.md` daarbij
    // botst is verwacht; die schrijven we er zo overheen.
    try {
      await _run(['merge', '--no-commit', '--no-ff'], operands: [remote]);
    } on GitCliException catch (e) {
      logWarning('mergeRemote: merge meldde botsingen (verwacht)', e);
    }

    try {
      final deckAbs = Directory(
        p.join(_worktree.path, p.joinAll(deckDir.split('/'))),
      );
      if (await deckAbs.exists()) await deckAbs.delete(recursive: true);
      await _writeAll(resolved.files);
      await _run(['add', '-A']);
      await _commit(message);
    } on GitCliException catch (e) {
      logWarning('mergeRemote: samengevoegde commit mislukt', e);
      try {
        await _run(['merge', '--abort']);
      } on GitCliException catch (e2) {
        logWarning('mergeRemote: afbreken mislukt', e2);
      }
      return GitCommitResult(
        GitCommitOutcome.committedConflict,
        sha: await headSha(),
      );
    }

    // Niet schoon? De merge-commit staat lokaal (de branch bevat nu hún werk,
    // dus de volgende poging botst niet opnieuw), maar publiceren doen we pas
    // als de gebruiker gekozen heeft.
    if (!resolved.clean) {
      return GitCommitResult(
        GitCommitOutcome.committedConflict,
        sha: await headSha(),
      );
    }
    return _push();
  }

  /// De bytes van [path] op [ref], of null wanneer het er niet staat.
  Future<Uint8List?> _showAtRef(String ref, String path) async {
    try {
      final res = await _run(['show'], operands: ['$ref:$path']);
      return Uint8List.fromList(utf8.encode(res.stdout));
    } on GitCliException {
      return null;
    }
  }

  Future<void> _ensureClone() async {
    if (_cloned) return;
    await _worktree.parent.create(recursive: true);
    // In een lege doelmap klonen; het subproces draait vanuit de ouder.
    await _git.run(
      [
        'clone',
        '--filter=blob:none',
        '--branch',
        _branch,
        '--origin',
        'origin',
      ],
      operands: [_cloneUrl, _worktree.path],
      workingDirectory: _worktree.parent.path,
      config: _config0,
      timeout: const Duration(minutes: 5),
    );
  }

  /// Zorg dat de werkboom op [branch] staat: check hem uit als hij al bestaat
  /// (lokaal of op origin), maak hem anders af van [start]. De clone blíjft op de
  /// werkbranch achter — daar wordt verder aan gewerkt tot de ronde uitkomt.
  ///
  /// Aanmaken en uitchecken zijn twee stappen (`git branch` dan `git checkout`),
  /// niet `checkout -b`: de gehardde runner schuift de branchnaam als operand
  /// achter `--end-of-options`, en `-b` eist zijn naam er juist pal naast.
  Future<void> _ensureOnWorkBranch(String branch, String start) async {
    if (await _currentBranch() == branch) return;
    if (!await _refExists(branch)) {
      final from = await _refExists('origin/$branch')
          ? 'origin/$branch'
          : start;
      await _run(['branch'], operands: [branch, from]);
    }
    await _run(['checkout'], operands: [branch]);
  }

  /// De naam van de uitgecheckte branch (`main`, of een werkbranch).
  Future<String> _currentBranch() async {
    try {
      final res = await _run(['rev-parse', '--abbrev-ref', 'HEAD']);
      return res.stdout.trim();
    } on GitCliException {
      return _branch;
    }
  }

  /// Of [ref] naar een commit verwijst (een branch bestaat, lokaal of remote).
  Future<bool> _refExists(String ref) async {
    try {
      await _run(
        ['rev-parse', '--verify', '--quiet'],
        operands: ['$ref^{commit}'],
      );
      return true;
    } on GitCliException {
      return false;
    }
  }

  Future<void> _writeAll(Map<String, Uint8List> files) async {
    for (final entry in files.entries) {
      final abs = p.normalize(
        p.join(_worktree.path, p.joinAll(entry.key.split('/'))),
      );
      // Vangnet: nooit buiten de werkboom schrijven.
      if (!p.isWithin(_worktree.path, abs)) {
        throw GitForgeException(
          GitForgeError.malformed,
          'Pad valt buiten de werkkopie: ${entry.key}',
        );
      }
      final file = File(abs);
      await file.parent.create(recursive: true);
      await writeBytesAtomic(file, entry.value);
    }
  }

  /// Commit met de boodschap uit een tijdelijk bestand, zodat de tekst —
  /// gebruikersdata — nooit in argv terechtkomt (§10.2). Het bestandspad is
  /// door de app bepaald (niet onvertrouwd) en gaat als `--file=` mee: `-F`
  /// eist zijn waarde ernaast, wat botst met `--end-of-options` voor operands.
  Future<void> _commit(String message) async {
    final msgFile = File(p.join(_worktree.path, '.git', 'OCIDECK_COMMITMSG'));
    await writeBytesAtomic(msgFile, Uint8List.fromList(utf8.encode(message)));
    try {
      await _run(['commit', '--cleanup=verbatim', '--file=${msgFile.path}']);
    } finally {
      if (await msgFile.exists()) await msgFile.delete();
    }
  }

  @override
  Future<List<GitLogEntry>> history(String deckDir, {int limit = 50}) async {
    if (!_cloned) return const [];
    // deckDir is al gevalideerd (deckNameOf); na `--` is het ondubbelzinnig een
    // pad, dus het mag hier als vertrouwd pathspec in de args.
    if (GitRepoLayout.deckNameOf(deckDir) == null) return const [];
    final unpushed = await _unpushedShas();
    final GitResult res;
    try {
      // Velden gescheiden door unit-separator (0x1f), zodat een boodschap met
      // spaties of tabs niet in de war raakt.
      res = await _run([
        'log',
        '--max-count=$limit',
        '--format=%H%x1f%s%x1f%an%x1f%aI',
        '--',
        deckDir,
      ]);
    } on GitCliException {
      return const [];
    }
    final out = <GitLogEntry>[];
    for (final line in const LineSplitter().convert(res.stdout)) {
      if (line.trim().isEmpty) continue;
      final parts = line.split('\x1f');
      if (parts.length < 4) continue;
      out.add(
        GitLogEntry(
          sha: parts[0],
          subject: parts[1],
          author: parts[2],
          date: DateTime.tryParse(parts[3]),
          pushed: !unpushed.contains(parts[0]),
        ),
      );
    }
    return out;
  }

  Future<Set<String>> _unpushedShas() async {
    final branch = await _currentBranch();
    try {
      final res = await _run(['rev-list', 'origin/$branch..HEAD']);
      return const LineSplitter()
          .convert(res.stdout)
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet();
    } on GitCliException {
      return const {};
    }
  }

  Future<int> _unpushedCount() async {
    final branch = await _currentBranch();
    try {
      final res = await _run(['rev-list', '--count', 'origin/$branch..HEAD']);
      return int.tryParse(res.stdout.trim()) ?? 0;
    } on GitCliException {
      // Geen origin-ref bekend (nooit gefetcht, of een verse werkbranch):
      // behandel alles als ongepusht.
      return 1;
    }
  }

  Future<GitCommitResult> _push() async {
    final sha = await headSha();
    final branch = await _currentBranch();
    try {
      await _run(['push', 'origin'], operands: ['HEAD:$branch']);
      return GitCommitResult(GitCommitOutcome.pushed, sha: sha);
    } on GitCliException catch (e) {
      final lower = e.stderr.toLowerCase();
      final rejected =
          lower.contains('non-fast-forward') ||
          lower.contains('fetch first') ||
          lower.contains('stale info') ||
          (lower.contains('rejected') && !lower.contains('resolve'));
      logWarning('NativeGitMirror: push mislukt', e);
      return GitCommitResult(
        rejected
            ? GitCommitOutcome.committedConflict
            : GitCommitOutcome.committedOffline,
        sha: sha,
      );
    }
  }
}
