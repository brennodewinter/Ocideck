// Part of the settings_provider library — see ../settings_provider.dart.
// Split out for navigability (de sporen op schijf); alle imports leven in het
// hoofdbestand.
part of '../settings_provider.dart';

/// Alles wat OciDeck op dit apparaat achterlaat, en de knoppen om het weg te
/// halen.
///
/// De instellingen zijn niet zomaar voorkeuren. De recente lijst bewaart
/// absolute paden plus het TLP-niveau van elk deck dat ooit open was — samen een
/// gegeven over waar iemand aan werkt, voor wie, en hoe gevoelig dat is. Wie de
/// app op een gedeelde of ingeleverde machine gebruikt, hoort dat te kunnen
/// wissen zonder een prefs-bestand te hoeven zoeken.
extension SettingsTraces on SettingsNotifier {
  /// De `logoPath`-waarden die de bewaarde stijlprofielen nu aanhalen.
  Set<String> get _referencedLogoPaths => {
    for (final profile in currentState.themeProfiles)
      if ((profile.logoPath ?? '').trim().isNotEmpty) profile.logoPath!.trim(),
  };

  /// Ruim verweesde logo's op zodra de profielenlijst verandert.
  ///
  /// Een geïmporteerde stijl legt zijn logo neer in `style_logos/`. Wordt het
  /// profiel verwijderd of krijgt het een ander logo, dan bleef dat bestand
  /// staan — soms het bedrijfslogo van een opdrachtgever, blijvend zichtbaar in
  /// de app-supportmap. Hier wordt precies weggehaald wat er uit de lijst is
  /// verdwenen; de grove veger bij het opstarten pakt de rest.
  Future<void> _sweepDroppedLogos() async {
    final before = _persistedLogoPaths;
    _persistedLogoPaths = _referencedLogoPaths;
    final dropped = before.difference(_persistedLogoPaths);
    if (dropped.isEmpty) return;
    await _diskTraces.removeStyleLogos(dropped);
  }

  /// De opstartveger: alles in `style_logos/` dat geen profiel meer aanhaalt en
  /// oud genoeg is. Vangt wat een oudere versie heeft laten liggen.
  Future<int> pruneOrphanStyleLogos() =>
      _diskTraces.pruneOrphanStyleLogos(_referencedLogoPaths);

  /// Recente lijst: de nieuwe JSON-opslag ('recentFilesV2') wint; de oude
  /// paden-lijst ('recentFiles') wordt eenmalig als metadata-loze entries
  /// gemigreerd en daarna alleen nog overschreven bij het wegschrijven.
  List<RecentFile> _loadRecentFiles(SharedPreferences prefs) {
    final v2 = RecentFile.decodeList(prefs.getString('recentFilesV2'));
    if (v2.isNotEmpty) return v2;
    return RecentFile.fromLegacyPaths(prefs.getStringList('recentFiles') ?? []);
  }

  Future<void> _persistRecentFiles(List<RecentFile> files) async {
    // Herkomsten volgen de lijst: wat eruit rolt, raakt ook zijn bron kwijt.
    // Een pad dat opnieuw wordt geopend behoudt zijn herkomst — remote
    // opgehaald blijft remote, ook wanneer de lokale kopie later via
    // "Openen…" of de recente lijst wordt geopend.
    final paths = {for (final f in files) f.path};
    final origins = {
      for (final e in currentState.recentFileOrigins.entries)
        if (paths.contains(e.key)) e.key: e.value,
    };
    currentState = currentState.copyWith(
      recentFiles: files,
      recentFileOrigins: origins,
    );
    await _persist('_persistRecentFiles', (prefs) async {
      await prefs.setString('recentFilesV2', RecentFile.encodeList(files));
      await prefs.setString('recentFileOrigins', jsonEncode(origins));
    });
  }

  /// Zet [path] bovenaan de recente lijst en ververs de metadata die bij het
  /// openen bekend is. Eerder geregistreerde export-info blijft bewaard.
  Future<void> addRecentFile(
    String path, {
    int? slideCount,
    TlpLevel? tlp,
    MarkdownKind? kind,
  }) async {
    final existing = currentState.recentFiles
        .where((f) => f.path == path)
        .firstOrNull;
    final entry = (existing ?? RecentFile(path: path)).copyWith(
      openedAt: DateTime.now(),
      slideCount: slideCount,
      tlp: tlp,
      kind: kind,
    );
    final updated = [
      entry,
      ...currentState.recentFiles.where((f) => f.path != path),
    ].take(10).toList();
    await _persistRecentFiles(updated);
  }

  /// Onthoud dat [path] zojuist als [formatLabel] ("PDF", "PPTX", "HTML") is
  /// geëxporteerd, zodat de recente lijst dat kan tonen. Alleen bestanden die
  /// al in de lijst staan worden bijgewerkt — exporteren maakt een bestand
  /// niet "recent geopend".
  Future<void> recordRecentFileExport(String path, String formatLabel) async {
    if (!currentState.recentFiles.any((f) => f.path == path)) return;
    final updated = [
      for (final f in currentState.recentFiles)
        f.path == path
            ? f.copyWith(
                lastExportFormat: formatLabel,
                lastExportAt: DateTime.now(),
              )
            : f,
    ];
    await _persistRecentFiles(updated);
  }

  /// Haal een pad uit de recente lijst (bijv. omdat het bestand naar de
  /// prullenbak is verplaatst); de herkomst gaat mee.
  Future<void> removeRecentFile(String path) async {
    if (!currentState.recentFiles.any((f) => f.path == path)) return;
    await _persistRecentFiles(
      currentState.recentFiles.where((f) => f.path != path).toList(),
    );
  }

  /// Leg vast waar een recent bestand vandaan is gehaald (Nextcloud-server of
  /// import-URL). Aan te roepen ná [addRecentFile]; alleen paden die in de
  /// recente lijst staan krijgen een herkomst, zodat de map niet meegroeit
  /// met verdwenen vermeldingen.
  Future<void> setRecentFileOrigin(String path, String origin) async {
    if (!currentState.recentFiles.any((f) => f.path == path)) return;
    final origins = {
      ...currentState.recentFileOrigins,
      path: SettingsNotifier.scrubbedOrigin(origin),
    };
    currentState = currentState.copyWith(recentFileOrigins: origins);
    await _persist(
      'setRecentFileOrigin',
      (prefs) => prefs.setString('recentFileOrigins', jsonEncode(origins)),
    );
  }

  Map<String, String> _decodeRecentFileOrigins(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (e) {
      logWarning('SettingsNotifier: recentFileOrigins decode failed', e);
      return const {};
    }
  }

  /// Wis de hele recente lijst, inclusief de herkomsten.
  ///
  /// Niet hetzelfde als tien keer [removeRecentFile]: dit is de knop voor "ik
  /// wil niet dat de volgende die dit scherm ziet weet waar ik mee bezig was".
  /// De bestanden zelf blijven staan — dit is een spoor wissen, geen werk
  /// weggooien.
  Future<void> clearRecentFiles() async {
    currentState = currentState.copyWith(
      recentFiles: const [],
      recentFileOrigins: const {},
    );
    await _persist('clearRecentFiles', (prefs) async {
      await prefs.remove('recentFilesV2');
      await prefs.remove('recentFileOrigins');
      // De pre-V2-lijst met kale paden zou anders bij de volgende start weer
      // gemigreerd worden, en dan staat de opruiming er gewoon weer.
      await prefs.remove('recentFiles');
    });
  }

  /// Hoeveel nog niet gepushte commits er in totaal wachten, over alle repo's.
  ///
  /// De vraag vóór [resetToInitialState]: die gooit élke werkkopie weg.
  Future<int> pendingCommitCount() => _diskTraces.pendingCommitCount();

  /// Zet de app terug naar de begintoestand: alle instellingen weg, alle sporen
  /// op schijf weg, alle geheimen uit de sleutelbos.
  ///
  /// Wat er níet aan wordt geraakt: de presentaties van de gebruiker. Die staan
  /// in zijn eigen mappen en zijn niet van ons. "Terugzetten" gaat over wat
  /// OciDeck heeft neergelegd, niet over wat de gebruiker heeft gemaakt.
  ///
  /// Weigert wanneer er nog niet-gepusht werk wacht en [discardPendingWork] niet
  /// is gezet — zie [DiskTraces.removeGitTraces]. De aanroeper vraagt het de
  /// gebruiker, met het aantal erbij.
  Future<bool> resetToInitialState({bool discardPendingWork = false}) async {
    if (!discardPendingWork && await pendingCommitCount() > 0) return false;

    // Eerst de geheimen, zolang we nog weten welke verbindingen er waren. Een
    // wachtwoord dat in de sleutelbos achterblijft nadat de gebruiker "alles
    // terug" heeft gekozen, is precies het spoor dat hij dacht te wissen.
    await _secrets.deleteSecretsOf(currentState.connections);
    await _secrets.deletePrivacyOwnIdentity();

    await _diskTraces.clearAllGitWorkingCopies();
    await _diskTraces.clearStyleLogos();
    await _diskTraces.clearGitSandbox();
    await RecoveryService().clearAll();

    await _persist('resetToInitialState', (prefs) => prefs.clear());
    _persistedLogoPaths = const {};
    currentState = const AppSettings();
    return true;
  }
}
