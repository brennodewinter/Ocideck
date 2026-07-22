import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/storage_connection.dart';
import '../utils/log.dart';
import 'git/outbox.dart';

/// Wat er van OciDeck op déze schijf achterblijft, en hoe je het weghaalt.
///
/// Eén plek, omdat de lijst anders niet klopt. Elke voorziening die iets
/// wegschrijft — de werkkopie van een repo, een geïmporteerd logo, de zandbak
/// waarin `git` draait — koos zijn eigen map, en niemand hield bij wat er dan
/// weer weg moest. Het gevolg was een belofte in `docs/PRIVACY.md` die de code
/// niet waarmaakte: een verbinding verwijderen liet de volledige repo-inhoud
/// mét historie gewoon staan.
///
/// De opruimacties zijn stuk voor stuk *best effort*: een map die niet weg wil
/// levert een logregel op, nooit een uitzondering. Opruimen mag het werk van de
/// gebruiker niet in de weg zitten.
class DiskTraces {
  /// Tests injecteren mappen; in productie komen ze van `path_provider` — zelfde
  /// patroon als `RecoveryService(baseDir:)`.
  DiskTraces({Directory? supportDir, Directory? tempDir})
    : _resolveSupport = supportDir != null
          ? (() async => supportDir)
          : _defaultSupport,
      _resolveTemp = tempDir != null ? (() async => tempDir) : _defaultTemp;

  final Future<Directory?> Function() _resolveSupport;
  final Future<Directory?> Function() _resolveTemp;

  /// De submap van de app-supportmap waarin een native clone terechtkomt.
  static const cloneDirName = 'git_clone';

  /// De submap waarin de werkkopie (draft store) van een repo staat.
  static const mirrorDirName = 'git_mirror';

  /// De submap waarin logo's van geïmporteerde stijlprofielen belanden.
  static const styleLogosDirName = 'style_logos';

  /// De lege map die `git` als HOME krijgt (zie `GitCli`). Staat in de
  /// tijdelijke map van het OS, niet onder app-support.
  static const gitSandboxDirName = 'ocideck_git_sandbox';

  Future<Directory?> _support() => _resolveSupport();

  Future<Directory?> _temp() => _resolveTemp();

  static Future<Directory?> _defaultSupport() async {
    if (kIsWeb) return null;
    try {
      return await getApplicationSupportDirectory();
    } catch (e) {
      logWarning('DiskTraces: app-supportmap niet beschikbaar', e);
      return null;
    }
  }

  static Future<Directory?> _defaultTemp() async {
    if (kIsWeb) return null;
    try {
      return await getTemporaryDirectory();
    } catch (e) {
      logWarning('DiskTraces: tijdelijke map niet beschikbaar', e);
      return null;
    }
  }

  /// Het wachtende, nog niet gepushte werk van de repo met [slug].
  ///
  /// De vraag die vóór het opruimen gesteld moet worden: hierin staat werk dat
  /// nergens anders bestaat.
  Future<List<PendingCommit>> pendingCommitsFor(String slug) =>
      Outbox(scope: slug).pending();

  /// Ruim alles op wat [connection] op dit apparaat heeft achtergelaten.
  ///
  /// Weigert wanneer er nog werk in de wachtrij staat en [discardPendingWork]
  /// niet is gezet: die commits bestaan alleen hier, en ze stil weggooien is
  /// dataverlies. De aanroeper die de gebruiker heeft gevraagd — en verteld wát
  /// er verloren gaat — zet de vlag.
  ///
  /// Een lokale verbinding wijst naar een map van de gebruiker zélf. Daar blijft
  /// dit vanaf: "verbinding verwijderen" betekent "uit de lijst", niet "gooi
  /// mijn presentaties weg".
  ///
  /// Het geheim in de sleutelbos blijft ook staan — dat hoort bij het account en
  /// niet bij deze ene verbinding, en een tweede verbinding naar dezelfde server
  /// heeft het nog nodig. Dat staat zo in `docs/PRIVACY.md`.
  Future<TraceRemoval> removeTracesOf(
    StorageConnection connection, {
    bool discardPendingWork = false,
  }) async {
    if (connection is! GitConnection) return const TraceRemoval.nothingToDo();
    return removeGitTraces(
      connection.repo.storageSlug,
      discardPendingWork: discardPendingWork,
    );
  }

  /// De opruiming voor één repo, op zijn `storageSlug`.
  Future<TraceRemoval> removeGitTraces(
    String slug, {
    bool discardPendingWork = false,
  }) async {
    if (slug.isEmpty) return const TraceRemoval.nothingToDo();
    final outbox = Outbox(scope: slug);
    final pending = await outbox.pending();
    if (pending.isNotEmpty && !discardPendingWork) {
      logWarning(
        'DiskTraces: werkkopie van $slug blijft staan — '
        '${pending.length} wachtende commit(s)',
      );
      return TraceRemoval(refusedPendingCommits: pending.length);
    }

    final support = await _support();
    final removed = <String>[];
    if (support != null) {
      for (final name in const [cloneDirName, mirrorDirName]) {
        final dir = Directory(p.join(support.path, name, slug));
        if (await _deleteDir(dir)) removed.add(dir.path);
      }
    }
    final keys = await outbox.clear();
    return TraceRemoval(removedPaths: removed, removedOutboxKeys: keys);
  }

  /// Gooi precies deze logo's weg — de bestanden waar zojuist het laatste
  /// stijlprofiel van af is gehaald.
  ///
  /// De nauwkeurige helft van het opruimen: de aanroeper wéét welke paden er uit
  /// zijn lijst zijn verdwenen. Paden buiten `style_logos/` worden genegeerd,
  /// want een logo kan ook gewoon in de projectmap van de gebruiker liggen en
  /// dat is niet van ons.
  Future<int> removeStyleLogos(Iterable<String> paths) async {
    if (kIsWeb) return 0;
    final support = await _support();
    if (support == null) return 0;
    final root = p.join(support.path, styleLogosDirName);
    var removed = 0;
    for (final raw in paths) {
      final path = p.normalize(raw.trim());
      if (path.isEmpty || !p.isWithin(root, path)) continue;
      try {
        final file = File(path);
        if (file.existsSync()) {
          file.deleteSync();
          removed++;
        }
      } catch (e) {
        logWarning('DiskTraces: logo niet verwijderd', e);
      }
    }
    return removed;
  }

  /// Hoe lang een niet-aangehaald logo mag blijven liggen voordat de veger hem
  /// meeneemt.
  ///
  /// De veger is de grove helft van het opruimen en draait bij het opstarten,
  /// met de profielenlijst van dít venster. Draait er een tweede venster dat
  /// zojuist een stijl heeft geïmporteerd, dan staat dat logo nog niet in de
  /// lijst die hier binnenkomt. De ondergrens maakt dat onschadelijk: een vers
  /// bestand blijft altijd staan, hoe de twee vensters ook uit de pas lopen.
  static const orphanLogoGrace = Duration(days: 7);

  /// Gooi logo's weg die bij geen enkel bewaard stijlprofiel meer horen.
  ///
  /// [referenced] zijn de `logoPath`-waarden van de profielen die de gebruiker
  /// nú heeft. Een profiel verwijderen liet zijn logo achter, en dat kan het
  /// bedrijfslogo van een opdrachtgever zijn — een bestand dat verraadt voor wie
  /// er gewerkt is, lang nadat de klus voorbij is.
  ///
  /// De vergelijking gaat over paden en niet over namen: twee profielen mogen
  /// dezelfde naam dragen, hun logo's hebben altijd een eigen uuid.
  Future<int> pruneOrphanStyleLogos(
    Iterable<String> referenced, {
    Duration? minAge,
  }) async {
    if (kIsWeb) return 0;
    final support = await _support();
    if (support == null) return 0;
    final grace = minAge ?? orphanLogoGrace;
    final keep = {
      for (final path in referenced)
        if (path.trim().isNotEmpty) p.normalize(path.trim()),
    };
    final dir = Directory(p.join(support.path, styleLogosDirName));
    if (!dir.existsSync()) return 0;
    final now = DateTime.now();
    var removed = 0;
    try {
      for (final entry in dir.listSync()) {
        if (entry is! File) continue;
        if (keep.contains(p.normalize(entry.path))) continue;
        try {
          if (now.difference(entry.statSync().modified) <= grace) continue;
          entry.deleteSync();
          removed++;
        } catch (e) {
          logWarning('DiskTraces: verweesd logo niet verwijderd', e);
        }
      }
    } catch (e) {
      logWarning('DiskTraces: style_logos niet doorlopen', e);
    }
    return removed;
  }

  /// Gooi de git-zandbak weg.
  ///
  /// `GitCli` geeft `git` een lege map als HOME zodat de configuratie en de
  /// hooks van de gebruiker buiten spel staan. Die map bleef daarna staan, met
  /// wat `git` er zelf in achterliet. Bij het opstarten is er zeker geen `git`
  /// van ons aan het werk, dus dat is het veilige moment om hem op te ruimen.
  Future<bool> clearGitSandbox() async {
    if (kIsWeb) return false;
    final temp = await _temp();
    if (temp == null) return false;
    return _deleteDir(Directory(p.join(temp.path, gitSandboxDirName)));
  }

  /// Gooi élke git-werkkopie weg, van welke verbinding ook, plus de hele
  /// wachtrij. Voor de terugzetknop in Instellingen; de aanroeper heeft de
  /// gebruiker al gevraagd.
  Future<int> clearAllGitWorkingCopies() async {
    if (kIsWeb) return 0;
    final support = await _support();
    var removed = 0;
    if (support != null) {
      for (final name in const [cloneDirName, mirrorDirName]) {
        if (await _deleteDir(Directory(p.join(support.path, name)))) removed++;
      }
    }
    // Zonder scope raakt `clear()` alleen de ongescopede sleutels; hier moet
    // álles weg, dus eerst per gevonden scope en dan de oude, ongescopede rest.
    final scopeless = Outbox();
    for (final slug in await scopeless.knownScopes()) {
      await Outbox(scope: slug).clear();
    }
    await scopeless.clear();
    return removed;
  }

  Future<bool> _deleteDir(Directory dir) async {
    try {
      if (!await dir.exists()) return false;
      await dir.delete(recursive: true);
      return true;
    } catch (e) {
      logWarning('DiskTraces: map niet verwijderd (${dir.path})', e);
      return false;
    }
  }
}

/// Wat een opruimpoging heeft gedaan — of juist bewust niet.
class TraceRemoval {
  const TraceRemoval({
    this.removedPaths = const [],
    this.removedOutboxKeys = 0,
    this.refusedPendingCommits = 0,
  });

  /// Er viel niets op te ruimen voor deze verbinding.
  const TraceRemoval.nothingToDo()
    : removedPaths = const [],
      removedOutboxKeys = 0,
      refusedPendingCommits = 0;

  /// De mappen die daadwerkelijk zijn verwijderd.
  final List<String> removedPaths;

  /// Het aantal gewiste wachtrij-sleutels.
  final int removedOutboxKeys;

  /// Meer dan nul wanneer er níets is opgeruimd omdat er nog werk wachtte.
  final int refusedPendingCommits;

  /// Of het opruimen is tegengehouden door wachtend werk.
  bool get refused => refusedPendingCommits > 0;
}
