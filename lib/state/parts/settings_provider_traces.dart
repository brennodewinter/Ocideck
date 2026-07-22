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
