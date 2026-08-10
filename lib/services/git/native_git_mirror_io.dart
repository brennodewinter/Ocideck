import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/git_settings.dart';
import '../../utils/atomic_file.dart';
import '../../utils/log.dart';
import '../../utils/net_guard.dart';
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

/// De extra git-config die de certificaat-pin op Windows écht laat gelden.
///
/// Git-for-Windows kiest standaard de **schannel**-backend, en die négeert
/// `http.sslCAInfo`: de installer haalt de sleutel er zelfs uit, om de
/// Windows-certificaatlade niet te overrulen. Ons gepinde zelfondertekende
/// certificaat zou daar dus stilzwijgend géén geldig anker zijn — de pin op de
/// native git-weg was op Windows anders een papieren maatregel (#934). Door voor
/// déze verbinding de openssl-backend te forceren, valideert git tegen precies
/// het CA-bestand dat wij meegeven: exact het gedrag dat op macOS/Linux al met
/// een echte server is getoetst (`git_native_cert_pin_test.dart`).
///
/// Alleen op de gepinde weg. Bij een gewone publieke-CA-server geven we geen
/// `sslCAInfo` mee en komt deze config er niet bij; de gebruiker houdt dan
/// schannel met de Windows-certificaatlade, inclusief een eventuele bedrijfsroot.
/// De backend-onafhankelijke sleutels (`http.curloptResolve`,
/// `http.followRedirects`) leunen niet op curl-vs-schannel en gelden op elk
/// platform ongewijzigd.
///
/// Buiten Windows wordt niets geforceerd: Apple's git kan zonder openssl-backend
/// gebouwd zijn, en macOS/Linux honoreren `sslCAInfo` al met de eigen backend.
@visibleForTesting
List<GitConfigOverride> pinnedCertBackendConfig({required bool isWindows}) =>
    isWindows
    ? const [GitConfigOverride('http.sslBackend', 'openssl')]
    : const [];

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

  /// Dezelfde poort als elke andere uitgaande weg, maar voor een verbinding die
  /// wij niet zelf leggen.
  ///
  /// `git` doet zijn eigen DNS en zijn eigen socket, dus `NetGuard` kan er niet
  /// omheen zoals bij een `HttpClient`: er is geen `connectionFactory` om in te
  /// haken. Wat wél kan is git de uitkomst ópleggen. `http.curloptResolve`
  /// bindt de hostnaam aan het adres dat NetGuard goedkeurde — TLS blijft tegen
  /// de naam valideren, dus er hoeft geen certificaat op een IP te staan —
  /// en `http.followRedirects=false` maakt van elke omleiding een fout in
  /// plaats van een tweede host die niemand heeft getoetst.
  ///
  /// Die tweede is hier belangrijker dan elders. Het token reist als
  /// `http.extraHeader` mee, en een header volgt een omleiding gewoon mee: een
  /// remote die 302 antwoordt, kreeg anders de `Authorization` cadeau.
  ///
  /// Getoetst dat git dit ook echt doet en het geen papieren maatregel is: met
  /// een opzettelijk verkeerd adres weigert de verbinding
  /// (`test/git_network_guard_test.dart`).
  Future<List<GitConfigOverride>> _networkConfig() async {
    final base = Uri.tryParse(_config.baseUrl.trim());
    if (base == null) {
      throw const GitForgeException(
        GitForgeError.config,
        'Server-URL onbruikbaar',
      );
    }
    final scheme = base.scheme.toLowerCase();
    // `file://` gaat de lijn niet op: geen host, geen DNS, geen TLS. Er valt
    // hier niets te pinnen en niets te weigeren — de guard hoort over
    // netwerkverkeer te gaan, niet over een pad op deze schijf. (Het is ook wat
    // de tests als origin gebruiken.)
    if (scheme == 'file') return _config0;
    // Verder: https, tenzij de gebruiker de server bewust als vertrouwd intern
    // heeft gemarkeerd. Al het overige — `git://` (onversleuteld), `ssh://`,
    // wat dan ook — gaat er niet in: de app ondersteunt het niet, en een schema
    // dat hier stilletjes doorglipt is precies hoe dit gat is ontstaan.
    if (scheme != 'https' && !(scheme == 'http' && _config.trustedInternal)) {
      throw GitForgeException(
        GitForgeError.config,
        scheme == 'http'
            ? 'Gebruik https of markeer de server als vertrouwd intern; anders '
                  'gaan je presentaties onversleuteld over het netwerk.'
            : 'Alleen https-servers worden ondersteund.',
      );
    }
    // Maar een tóken gaat nooit over platte tekst, ook niet naar een vertrouwde
    // interne host: `_hardenedEnv` hangt er een `Authorization: Basic` aan, en
    // dat is een herbruikbaar geheim dat blijft werken nadat iemand het van de
    // lijn heeft geplukt. Zonder token — een openbare spiegel — blijft plain
    // http op een vertrouwd LAN gewoon werken; daar valt niets te stelen wat de
    // verbinding overleeft. (Toegevoegd 2026-07-22; zie
    // [NetGuard.maySendReusableSecret].)
    if (_token.trim().isNotEmpty &&
        !NetGuard.maySendReusableSecret(scheme, host: base.host)) {
      throw const GitForgeException(
        GitForgeError.config,
        'Een git-server met een token vereist https: het token gaat bij élk '
        'verzoek mee, dus het zou onversleuteld over het netwerk gaan. '
        'Vertrouwd intern verandert daar niets aan — die instelling gaat over '
        'de server, niet over de verbinding ernaartoe.',
      );
    }
    if (base.host.isEmpty) {
      throw const GitForgeException(
        GitForgeError.config,
        'Server-URL mist een hostnaam',
      );
    }
    final resolved = await NetGuard.resolveConfigured(
      base.host,
      allowPrivate: _config.trustedInternal,
    );
    if (!resolved.isOk) {
      throw switch (resolved.refusal!) {
        HostRefusal.unknownHost => const GitForgeException(
          GitForgeError.unknownHost,
          'Servernaam niet gevonden',
        ),
        HostRefusal.blocked => const GitForgeException(
          GitForgeError.blockedHost,
          'Server-host geweigerd',
        ),
      };
    }
    final port = base.hasPort ? base.port : (scheme == 'https' ? 443 : 80);
    final pinned = resolved.addresses!.first;
    return [
      ..._config0,
      GitConfigOverride(
        'http.curloptResolve',
        '${base.host}:$port:${pinned.address}',
      ),
      const GitConfigOverride('http.followRedirects', 'false'),
      ...await _trustedCertConfig(pinned, base, port),
    ];
  }

  /// Laat git hetzelfde ene certificaat vertrouwen als de REST-weg.
  ///
  /// De REST-weg hangt een `badCertificateCallback` op die de vingerafdruk
  /// vergelijkt. Git heeft zoiets niet — het kent alleen een CA-bestand
  /// (`http.sslCAInfo`) of een publieke sleutel, en géén vingerafdruk van een
  /// heel certificaat. Zonder dit stond de gebruiker met een werkende
  /// verbindingstest en een falende clone: de REST-weg vertrouwde het
  /// zelfondertekende certificaat, git wees het af.
  ///
  /// Daarom: het certificaat ópvragen bij het gepinde adres, de vingerafdruk
  /// zelf controleren, en het pas dán als trust-anker aan git meegeven. De
  /// controle blijft dus bij ons — `sslCAInfo` krijgt nooit iets te zien dat
  /// wij niet eerst tegen de vastgelegde vingerafdruk hebben gehouden.
  ///
  /// Wat *niet* gebeurt: `http.sslVerify=false`. Dat zou de hele controle
  /// uitzetten, inclusief de naamcontrole. Met een CA-bestand blijft git
  /// gewoon valideren — alleen is dit certificaat nu een geldig anker.
  ///
  /// Levert niets op wanneer er geen vingerafdruk is vastgelegd, of wanneer
  /// het certificaat het ook zonder redt: [NetGuard.peekCertificate] geeft dan
  /// `null`, en dat is precies wat de REST-weg óók doet — een
  /// `badCertificateCallback` wordt alleen geraadpleegd als de gewone
  /// validatie faalt. De pin is "vertrouw dit certificaat *erbij*", niet
  /// "vertrouw alléén dit certificaat".
  Future<List<GitConfigOverride>> _trustedCertConfig(
    InternetAddress pinned,
    Uri base,
    int port,
  ) async {
    final expected = _config.pinnedCertSha256.trim();
    if (expected.isEmpty) return const [];

    final probe = Uri(scheme: base.scheme, host: base.host, port: port);
    final cert = await NetGuard.peekCertificate(pinned, probe);
    if (cert == null) return const [];

    final actual = NetGuard.certificateFingerprint(cert);
    if (actual != expected.toLowerCase()) {
      throw const GitForgeException(
        GitForgeError.blockedHost,
        'Het certificaat van de server wijkt af van de vastgelegde '
        'vingerafdruk.',
      );
    }

    // Naast de werkboom, niet erin: in de werkboom zou het als een onbekend
    // bestand in `git status` opduiken en in een commit kunnen belanden.
    final file = File('${_worktree.path}.pem');
    await file.parent.create(recursive: true);
    await writeStringAtomic(file, cert.pem);
    return [
      GitConfigOverride('http.sslCAInfo', file.path),
      ...pinnedCertBackendConfig(isWindows: Platform.isWindows),
    ];
  }

  /// [network] hoort aan te staan voor alles wat de lijn op gaat — clone,
  /// fetch, push. Lokale aanroepen (commit, checkout) hebben de guard niet
  /// nodig en zouden er een DNS-lookup per aanroep bij krijgen.
  Future<GitResult> _run(
    List<String> args, {
    List<String> operands = const [],
    Duration timeout = const Duration(seconds: 60),
    bool network = false,
    List<GitConfigOverride> extraConfig = const [],
  }) async => _git.run(
    args,
    operands: operands,
    workingDirectory: _worktree.path,
    config: [...(network ? await _networkConfig() : _config0), ...extraConfig],
    timeout: timeout,
  );

  /// De merge-driver voor de ink-sidecar (§9.7, D7), meegegeven aan precies de
  /// merge-aanroep — nooit in `.git/config`, om dezelfde reden als de rest van
  /// §10.2: configuratie hoort bij de aanroep die hem nodig heeft.
  ///
  /// De driver is `false`: altijd falen. Dat klinkt vreemd en is precies goed —
  /// git laat het bestand dan ongemoeid op ónze kant staan (gemeten: geen
  /// conflictmarkeringen) en meldt een conflict, waarna `resolveRepoDeckMerge`
  /// er de echte unie-met-grafstenen overheen schrijft. Zonder driver zou git's
  /// tekst-merge van twee JSON-kanten een bestand met markers maken dat geen
  /// enkele build nog leest.
  static const _inkMergeDriver = [
    GitConfigOverride('merge.ocideck-ink.name', 'OciDeck ink-unie (in de app)'),
    GitConfigOverride('merge.ocideck-ink.driver', 'false'),
  ];

  /// Bind `deck.ink.json` aan die driver, in de kloon zelf:
  /// `.git/info/attributes` is clone-lokaal en reist niet mee. Een kloon van
  /// een ander werktuig heeft dit bestand dus niet — daar valt git terug op de
  /// tekst-merge, en het is de leeskant (`repoInkState`) die markers herkent en
  /// het bestand dan niet aanraakt.
  Future<void> _ensureInkMergeAttributes() async {
    final attrs = File(p.join(_worktree.path, '.git', 'info', 'attributes'));
    const line = 'deck.ink.json merge=ocideck-ink';
    if (attrs.existsSync()) {
      final txt = await attrs.readAsString();
      if (txt.contains(line)) return;
      await writeStringAtomic(attrs, '${txt.trimRight()}\n$line\n');
    } else {
      await attrs.parent.create(recursive: true);
      await writeStringAtomic(attrs, '$line\n');
    }
  }

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
  @override
  // De clone ís de werkkopie waar de editor uit leest; zie de toelichting bij
  // [DeckMirror.discardsLandedWork].
  bool get discardsLandedWork => false;

  // ── Native versiebeheer ────────────────────────────────────────────────────
  @override
  Future<void> prepareForOpen() async {
    await _ensureClone();
    await _refreshCurrentBranch();
  }

  /// Haal de branch bij en fast-forward hem. Best-effort: offline openen mag, dan
  /// werken we met wat er lokaal is.
  ///
  /// Alleen fast-forward: staat de branch verder, dan halen we die op; hebben we
  /// zelf nog niet-gepushte commits (divergentie), dan faalt dit en houden we ons
  /// eigen werk. Zo werken we met de nieuwste versie zonder ooit iets weg te
  /// gooien.
  Future<void> _refreshCurrentBranch() async {
    try {
      await _run(['fetch', 'origin'], operands: [_branch], network: true);
      await _run(['merge', '--ff-only'], operands: ['origin/$_branch']);
    } on GitCliException catch (e) {
      logWarning('NativeGitMirror: fetch/ff mislukt (offline of divergent)', e);
    } on GitForgeException catch (e) {
      // De netwerk-poort weigert offline al vóór git start (DNS mislukt →
      // unknownHost). Offline openen mag: we werken met de lokale clone verder,
      // een verse ophaal is niet de prijs van het openen.
      logWarning('NativeGitMirror: fetch/ff overgeslagen (netwerk-poort)', e);
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
    required Future<
      ({Map<String, Uint8List> files, List<String> deletes, bool clean})
    >
    Function(
      Uint8List? base,
      Uint8List? ours,
      Uint8List? theirs,
      MergeSideReader read,
    )
    resolve,
  }) async {
    if (!_cloned) return const GitCommitResult(GitCommitOutcome.unchanged);
    final remote = 'origin/$branch';

    // Zonder verse ophaal weten we niet wat "die van hen" is.
    try {
      await _run(['fetch', 'origin'], operands: [branch], network: true);
    } on GitCliException catch (e) {
      logWarning('mergeRemote: fetch mislukt (offline?)', e);
      return GitCommitResult(
        GitCommitOutcome.committedOffline,
        sha: await headSha(),
      );
    } on GitForgeException catch (e) {
      // Ook hier weigert de netwerk-poort offline vóór git start. De lokale
      // commit staat er al; behandel het als de GitCliException-tak hierboven,
      // zodat de merge niet stil als hard falen naar boven lekt.
      logWarning(
        'mergeRemote: fetch overgeslagen (netwerk-poort, offline?)',
        e,
      );
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

    // De drie refs één keer vastleggen, zodat de lezer die de aanroeper
    // meekrijgt naar exact dezelfde kanten wijst als de drie bytes hierboven.
    final refOf = {
      MergeSide.base: base,
      MergeSide.ours: 'HEAD',
      MergeSide.theirs: remote,
    };
    final resolved = await resolve(
      await _showAtRef(base, deckFile),
      await _showAtRef('HEAD', deckFile),
      await _showAtRef(remote, deckFile),
      (side, path) => _showAtRef(refOf[side]!, path),
    );

    // Laat git de rest van de boom samenvoegen — de pool-blobs zijn
    // inhoudsgeadresseerd en komen er dus gewoon bij. Dat `deck.md` daarbij
    // botst is verwacht; die schrijven we er zo overheen. De ink-sidecar krijgt
    // zijn eigen driver mee zodat de tekst-merge er geen markers in achterlaat
    // (§9.7): de unie komt uit de resolver, niet uit git.
    await _ensureInkMergeAttributes();
    try {
      await _run(
        ['merge', '--no-commit', '--no-ff'],
        operands: [remote],
        extraConfig: _inkMergeDriver,
      );
    } on GitCliException catch (e) {
      logWarning('mergeRemote: merge meldde botsingen (verwacht)', e);
    }

    try {
      // Bijwerken, niet vervangen. De aanroeper kent de deckmap niet — alleen
      // de drie `deck.md`'s — dus "wat hij niet noemt, hoort weg" was een
      // belofte die hij niet kon nakomen: het kostte de grafiekdata bij élke
      // merge (#670). Verwijderen gebeurt daarom alleen op verzoek.
      await _deleteAll(resolved.deletes);
      await _writeAll(resolved.files);
      await _run(['add', '-A']);
      await _commit(message);
      // Breed: dit blok verwijdert, schrijft én commit. Een mislukte schrijf
      // of verwijdering gooit een FileSystemException, geen GitCliException —
      // die viel eerst langs de recovery en liet de merge half toegepast met
      // een openstaande MERGE_HEAD achter. Elke fout hier hoort tot dezelfde
      // afbreken-en-teruggeven-afhandeling.
    } on Exception catch (e) {
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
      config: await _networkConfig(),
      timeout: const Duration(minutes: 5),
    );
  }

  /// Zorg dat de werkboom op [branch] staat: check hem uit als hij al bestaat
  /// (lokaal of op origin), maak hem anders af van [start]. De clone blíjft op de
  /// werkbranch achter — daar wordt verder aan gewerkt tot de ronde uitkomt.
  ///
  /// Aanmaken en uitchecken zijn twee stappen (`git branch` dan `git switch`),
  /// niet `checkout -b`: de gehardde runner schuift de branchnaam als operand
  /// achter `--end-of-options`, en `-b` eist zijn naam er juist pal naast.
  ///
  /// `switch` en niet `checkout`: checkout op git ≤ 2.43 (Ubuntu 24.04 LTS)
  /// kent `--end-of-options` niet en leest hem als pathspec — "pathspec did
  /// not match any file(s)". `switch` neemt alleen een branch en verstaat de
  /// markering wel; de CI-poort draait op 2.43 en bewaakt dit.
  Future<void> _ensureOnWorkBranch(String branch, String start) async {
    if (await _currentBranch() == branch) return;
    if (!await _refExists(branch)) {
      final from = await _refExists('origin/$branch')
          ? 'origin/$branch'
          : start;
      await _run(['branch'], operands: [branch, from]);
    }
    await _run(['switch'], operands: [branch]);
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

  /// Verwijder de genoemde repo-paden uit de werkkopie. Een pad dat er niet is
  /// telt als gedaan: verwijderen is idempotent, en de aanroeper hoeft niet te
  /// weten wat er al weg was.
  Future<void> _deleteAll(List<String> paths) async {
    for (final path in paths) {
      final abs = p.normalize(
        p.join(_worktree.path, p.joinAll(path.split('/'))),
      );
      // Zelfde vangnet als bij het schrijven: nooit buiten de werkboom.
      if (!p.isWithin(_worktree.path, abs)) {
        throw GitForgeException(
          GitForgeError.malformed,
          'Pad valt buiten de werkkopie: $path',
        );
      }
      final file = File(abs);
      if (await file.exists()) await file.delete();
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

  @override
  Future<List<String>?> grepDeckDirs(
    String needle, {
    required bool caseSensitive,
    required String branch,
  }) async {
    final term = needle.trim();
    // Leeg, of een leidend streepje dat de gehardde runner als operand weigert:
    // niet te versnellen, dus terugvallen op de volledige scan.
    if (term.isEmpty || term.startsWith('-')) return null;
    // We doorzoeken de werkboom van de uitgecheckte branch. Alleen zinnig als dat
    // ook de gevraagde branch is; staat de clone ergens anders (een werkbranch,
    // of er is nog geen clone), val dan terug in plaats van de verkeerde branch
    // te doorzoeken.
    if (branch != _branch || !_cloned) return null;
    await _refreshCurrentBranch();
    if (await _currentBranch() != _branch) return null;

    final GitResult res;
    try {
      // `-I` slaat binaire bestanden over (de assets), `-l` geeft alleen de
      // padnamen, `-F` matcht de term als letterlijke tekst — nooit als regex
      // uit gebruikersinvoer. De term is aan `-e` gebonden en het `decks`-pad
      // staat achter `--`, dus geen van beide kan als vlag worden gelezen
      // (§10.2). Niet via `--end-of-options`: git grep op ≤ 2.43 (Ubuntu
      // 24.04 LTS) leest die markering zelf als patroon en de term als
      // revisie — de CI-poort draait op 2.43 en bewaakt dit.
      res = await _run([
        'grep',
        '-I',
        '-l',
        '-F',
        if (!caseSensitive) '-i',
        '-e',
        term,
        '--',
        GitRepoLayout.decksRoot,
      ]);
    } on GitCliException catch (e) {
      // Exitcode 1 = niets gevonden: een leeg, exhaustief antwoord — geen fout.
      if (e.exitCode == 1) return const [];
      // Elke andere fout: terugvallen op de volledige scan, niet onderrapporteren.
      logWarning('NativeGitMirror: git grep faalde', e);
      return null;
    }

    final dirs = <String>{};
    for (final line in const LineSplitter().convert(res.stdout)) {
      final dir = GitRepoLayout.deckDirOfDeckFile(line.trim());
      if (dir != null) dirs.add(dir);
    }
    return dirs.toList()..sort();
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
      await _run(['push', 'origin'], operands: ['HEAD:$branch'], network: true);
      return GitCommitResult(GitCommitOutcome.pushed, sha: sha);
    } on GitCliException catch (e) {
      logWarning('NativeGitMirror: push mislukt', e);
      // Een afwijzing is geen storing maar "iemand was je voor": dat blijft een
      // conflict, ongeacht de rest van de stderr.
      if (isPushRejection(e.stderr)) {
        return GitCommitResult(GitCommitOutcome.committedConflict, sha: sha);
      }
      return _afterFailedPush(sha, classifyGitCliError(e));
    } on GitForgeException catch (e) {
      // De netwerk-poort (`_networkConfig`) weigert nog vóór git start: offline
      // (DNS mislukt → unknownHost), een geweigerde host, of een verkeerd
      // schema. De commit staat dan al lokaal — alleen publiceren lukte niet.
      logWarning('NativeGitMirror: push geweigerd door de netwerk-poort', e);
      return _afterFailedPush(sha, e);
    }
  }

  /// De commit staat lokaal (duurzaam, P2 — "verbinding kwijt is nooit werk
  /// kwijt"); alleen de push mislukte. Kies de afloop op grond van [reason]: een
  /// verbinding die wegviel of een naam die (offline) niet oploste, gaat de
  /// wachtrij in en komt vanzelf mee. Een fout die zichzelf níét oplost —
  /// verkeerd token, geen rechten, een afgewezen certificaat — wordt gemeld
  /// zodat de gebruiker hem kan verhelpen; "gaat later mee" zou dan liegen.
  GitCommitResult _afterFailedPush(String? sha, GitForgeException reason) {
    final offline =
        reason.kind == GitForgeError.network ||
        reason.kind == GitForgeError.unknownHost;
    if (offline) {
      return GitCommitResult(GitCommitOutcome.committedOffline, sha: sha);
    }
    return GitCommitResult(
      GitCommitOutcome.committedButPushFailed,
      sha: sha,
      pushError: reason,
    );
  }
}
