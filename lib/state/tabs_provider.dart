import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/deck.dart';
import '../models/webdav_settings.dart';
import '../services/file_service.dart';
import '../services/markdown_safety.dart';
import '../services/markdown_service.dart';
import '../services/recovery_service.dart';
import '../services/user_notes_codec.dart';
import '../services/webdav_service.dart';
import '../utils/log.dart';
import 'deck_provider.dart';
import 'editor_provider.dart';
import 'settings_provider.dart';

const _uuid = Uuid();

// ── Per-tab data ──────────────────────────────────────────────────────────────

class TabInfo {
  final int id;

  /// Stabiele sleutel voor het autosave-herstelbestand van dit tabblad.
  final String recoveryId;
  final DeckNotifier deckNotifier;
  final EditorNotifier editorNotifier;

  /// Gezet wanneer dit tabblad uit een WebDAV/Nextcloud-bron is geopend, zodat
  /// "Opslaan naar Nextcloud" terug weet te schrijven. Muteerbaar: wordt na het
  /// openen ingevuld en bij elke `state`-kopie hergebruikt.
  WebdavOrigin? webdavOrigin;

  TabInfo({
    required this.id,
    required this.recoveryId,
    required this.deckNotifier,
    required this.editorNotifier,
    this.webdavOrigin,
  });

  String get label {
    final st = deckNotifier.currentState;
    // A saved deck is identified by its file name — that is what the user
    // recognises, not the parsed first-slide title (which falls back to the
    // generic 'Presentatie').
    final path = st.filePath;
    if (path != null && path.isNotEmpty) {
      final name = p.basenameWithoutExtension(path);
      if (name.isNotEmpty) return name;
    }
    final deck = st.deck;
    return deck?.title.isNotEmpty == true ? deck!.title : 'Nieuw';
  }

  bool get isDirty => deckNotifier.currentState.isDirty;
  bool get isOpen => deckNotifier.currentState.isOpen;
}

// ── Tabs state ────────────────────────────────────────────────────────────────

class TabsState {
  final List<TabInfo> tabs;
  final int selectedIndex;

  const TabsState({required this.tabs, this.selectedIndex = 0});

  int get clampedIndex => selectedIndex.clamp(
    0,
    (tabs.length - 1).clamp(0, double.maxFinite.toInt()),
  );

  TabInfo? get current => tabs.isEmpty ? null : tabs[clampedIndex];

  bool get anyDirty => tabs.any((t) => t.isDirty);

  TabsState copyWith({List<TabInfo>? tabs, int? selectedIndex}) {
    return TabsState(
      tabs: tabs ?? this.tabs,
      selectedIndex: selectedIndex ?? this.selectedIndex,
    );
  }
}

/// How a single open/import attempt ended. Used by the import flows to decide
/// whether to clean up downloaded/extracted files and what to report.
enum OpenResult {
  /// The deck was opened in a tab.
  opened,

  /// The file could not be read or parsed (missing, over-size, corrupt).
  unreadable,

  /// The file is not a Marp/OciDeck presentation — readable, but not a deck.
  /// Kept distinct from [unreadable] so the UI can say so specifically.
  notAPresentation,

  /// The file was refused because it contains executable content; the security
  /// alarm has been raised via [importSecurityAlarmProvider].
  blocked,
}

/// A blocked import surfaced to the UI: the offending file plus what was found.
/// The shell listens on [importSecurityAlarmProvider] and shows the alarm.
class ImportSecurityAlarm {
  final String path;
  final List<MarkdownSafetyFinding> findings;
  const ImportSecurityAlarm({required this.path, required this.findings});
}

// ── Tabs notifier ─────────────────────────────────────────────────────────────

class TabsNotifier extends StateNotifier<TabsState> {
  final Ref _ref;
  final MarkdownService _md;
  final FileService _file;
  final SettingsNotifier _settings;
  final RecoveryService _recovery;
  final Map<int, StreamSubscription<DeckState>> _subs = {};

  /// Laatst ge-autosavede deck per tab (op identiteit): het deck is immutable,
  /// dus zolang het object hetzelfde is, is er niets gewijzigd en kan de tick
  /// de volledige serialisatie + schrijfbeurt overslaan.
  final Map<int, Deck> _lastAutosavedDeck = {};
  Timer? _autosaveTimer;
  int _nextId = 0;

  /// Hoe vaak niet-opgeslagen tabbladen naar een herstelbestand worden bewaard.
  static const _autosaveInterval = Duration(seconds: 25);

  TabsNotifier(this._ref, this._md, this._file, this._settings, this._recovery)
    : super(const TabsState(tabs: [])) {
    // Start with one empty tab
    final tab = _createTab();
    state = TabsState(tabs: [tab], selectedIndex: 0);
    _autosaveTimer = Timer.periodic(_autosaveInterval, (_) => _autosaveTick());
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    for (final sub in _subs.values) {
      sub.cancel();
    }
    // Tab notifiers are released when each tab's ProviderScope unmounts (tab
    // close) or when the app shell tears down at process exit.
    super.dispose();
  }

  /// Tear down a tab that is being removed: stop listening to it.
  ///
  /// The notifiers are owned by the tab's [ProviderScope] (see
  /// `deckProvider.overrideWith` in [AppShell]): Riverpod disposes each one when
  /// that scope unmounts, *for every provider the scope actually initialised*.
  /// The heavy [DeckNotifier] (full deck + undo history) is always read — by the
  /// quality provider and the shell — so it is always disposed; this is verified
  /// by a regression test. We must NOT dispose it here too, or the later scope
  /// unmount would double-dispose it. A never-opened tab shows the welcome
  /// screen, so its lightweight [EditorNotifier] may never be initialised and is
  /// simply garbage-collected on close.
  void _disposeTab(TabInfo tab) {
    _subs.remove(tab.id)?.cancel();
    _lastAutosavedDeck.remove(tab.id);
  }

  TabInfo _createTab() {
    final id = _nextId++;
    final recoveryId = _uuid.v4();
    final deckNotifier = DeckNotifier(_md, _file);
    final tab = TabInfo(
      id: id,
      recoveryId: recoveryId,
      deckNotifier: deckNotifier,
      editorNotifier: EditorNotifier(),
    );
    _subs[id] = deckNotifier.stream.listen((st) {
      if (!mounted) return;
      // Zodra een tabblad is opgeslagen (schoon), het herstelbestand wissen.
      // Schrijven gebeurt gebufferd door de periodieke autosave-tick.
      if (!(st.isOpen && st.isDirty)) {
        _recovery.discard(recoveryId);
      }
      state = state.copyWith(tabs: List.from(state.tabs));
    });
    return tab;
  }

  /// Bewaar elk niet-opgeslagen tabblad naar zijn herstelbestand.
  void _autosaveTick() {
    if (!mounted) return;
    for (final tab in state.tabs) {
      final st = tab.deckNotifier.currentState;
      if (st.isOpen && st.isDirty) {
        final deck = st.deck!;
        if (identical(_lastAutosavedDeck[tab.id], deck)) continue;
        _recovery.save(
          RecoverySnapshot(
            id: tab.recoveryId,
            savedAt: DateTime.now(),
            filePath: st.filePath,
            label: tab.label,
            markdown: tab.deckNotifier.generateMarkdown(),
            userNotes: UserNotesCodec.encode(deck.slides, deck.userNotes),
          ),
        );
        _lastAutosavedDeck[tab.id] = deck;
      }
    }
  }

  /// Open elke teruggehaalde snapshot als (gewijzigd) tabblad en ruim de oude
  /// herstelbestanden op. Aangeroepen vanuit het herstel-dialoog bij opstart.
  void restoreRecovered(List<RecoverySnapshot> snapshots) {
    final restored = <TabInfo>[];
    for (final snap in snapshots) {
      var deck = _md.parseDeck(snap.markdown, filePath: snap.filePath);
      _recovery.discard(snap.id); // oude sleutel; tab krijgt een nieuwe
      if (deck == null) continue;
      if (snap.userNotes != null && snap.userNotes!.isNotEmpty) {
        final notes = UserNotesCodec.decode(snap.userNotes!, deck.slides);
        if (notes.isNotEmpty) {
          deck = deck.copyWith(userNotes: notes);
        }
      }
      final tab = _createTab();
      tab.deckNotifier.loadDeck(deck, filePath: snap.filePath);
      tab.deckNotifier.markDirty(); // herstelde inhoud is nog niet opgeslagen
      restored.add(tab);
    }
    if (restored.isEmpty) return;

    // Een ongebruikt leeg begin-tabblad vervangen, anders toevoegen.
    final replaceEmpty = state.tabs.length == 1 && !state.tabs.first.isOpen;
    if (replaceEmpty) {
      _disposeTab(state.tabs.first);
      state = state.copyWith(tabs: restored, selectedIndex: 0);
    } else {
      final tabs = [...state.tabs, ...restored];
      state = state.copyWith(tabs: tabs, selectedIndex: state.tabs.length);
    }
  }

  void newEmptyTab() {
    final tab = _createTab();
    final newTabs = [...state.tabs, tab];
    state = state.copyWith(tabs: newTabs, selectedIndex: newTabs.length - 1);
  }

  void newDeckInCurrentTab(String title) {
    final tab = state.current;
    if (tab == null) return;
    tab.deckNotifier.newDeck(title);
    tab.editorNotifier.select(0);
    // Force rebuild by copying state (label may have changed)
    state = state.copyWith(tabs: List.from(state.tabs));
  }

  void newDeckInNewTab(String title) {
    final tab = _createTab();
    tab.deckNotifier.newDeck(title);
    tab.editorNotifier.select(0);
    final newTabs = [...state.tabs, tab];
    state = state.copyWith(tabs: newTabs, selectedIndex: newTabs.length - 1);
  }

  /// Open a file picker and load the chosen deck.
  /// If the current tab is empty, replaces it; otherwise opens a new tab.
  Future<void> openFile({String? initialDirectory}) async {
    final path = await _file.pickMarkdownFile(
      initialDirectory: initialDirectory,
    );
    if (path == null) return;
    final deck = await _file.openDeck(path);
    if (deck == null) return;
    if (!mounted) return; // notifier disposed during the await

    final current = state.current;
    if (current != null && !current.isOpen) {
      // Replace the empty current tab
      current.deckNotifier.loadDeck(deck, filePath: path);
      current.editorNotifier.select(0);
      state = state.copyWith(tabs: List.from(state.tabs));
    } else {
      // Open in a new tab
      final tab = _createTab();
      tab.deckNotifier.loadDeck(deck, filePath: path);
      final newTabs = [...state.tabs, tab];
      state = state.copyWith(tabs: newTabs, selectedIndex: newTabs.length - 1);
    }
    await _settings.addRecentFile(path);
  }

  Future<OpenResult> openFileByPath(String path, {int? selectIndex}) async {
    // Security gate: every file that enters the app (open, recent, drag-drop,
    // URL/package import) is scanned first. A presentation is data only — if the
    // file carries anything executable we refuse it and raise the alarm instead
    // of parsing/opening it. Fail-closed.
    final findings = await _file.scanForUnsafeMarkdown(path);
    if (findings.isNotEmpty) {
      if (mounted) {
        _ref.read(importSecurityAlarmProvider.notifier).state =
            ImportSecurityAlarm(path: path, findings: findings);
      }
      return OpenResult.blocked;
    }
    // The scan above only drives the alarm; openDeck re-reads and re-scans the
    // exact bytes it parses, so a file swapped after this point is still caught
    // (it simply returns null here rather than loading unsafe content).
    final outcome = await _file.openDeckDetailed(path);
    final deck = outcome.deck;
    if (deck == null) {
      // A readable file that simply isn't a presentation gets its own result so
      // the UI can say "not a Marp/OciDeck presentation" rather than a generic
      // "couldn't open".
      return outcome.failure == OpenFailure.notPresentation
          ? OpenResult.notAPresentation
          : OpenResult.unreadable;
    }
    // notifier disposed during the await
    if (!mounted) return OpenResult.unreadable;
    final index = (selectIndex ?? 0).clamp(0, deck.slides.length - 1);
    final current = state.current;
    if (current != null && !current.isOpen) {
      current.deckNotifier.loadDeck(deck, filePath: path);
      current.editorNotifier.select(index);
      state = state.copyWith(tabs: List.from(state.tabs));
    } else {
      final tab = _createTab();
      tab.deckNotifier.loadDeck(deck, filePath: path);
      tab.editorNotifier.select(index);
      final newTabs = [...state.tabs, tab];
      state = state.copyWith(tabs: newTabs, selectedIndex: newTabs.length - 1);
    }
    await _settings.addRecentFile(path);
    return OpenResult.opened;
  }

  /// Remove the unique folder an import extracted/downloaded into when the deck
  /// was not opened (blocked or unreadable). Only ever deletes folders the
  /// import itself just created — never a folder the user opened in place.
  Future<void> _discardImportArtifacts(String mdPath) async {
    try {
      final dir = Directory(p.dirname(mdPath));
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      logWarning('TabsNotifier._discardImportArtifacts: cleanup failed', e);
    }
  }

  /// Map waarin geïmporteerde pakketten worden uitgepakt.
  Future<String> _importDestDir(String? homeDir) async {
    if (homeDir != null && homeDir.trim().isNotEmpty) return homeDir;
    return (await getApplicationDocumentsDirectory()).path;
  }

  /// Importeer een `.ocideck`-pakket (zip) en open het in een tab.
  ///
  /// Retourneert `true` wanneer het pakket is opgehaald én verwerkt — ook als de
  /// veiligheidscontrole de inhoud blokkeert (dan toont de shell het alarm).
  /// `false` betekent dat het pakket niet kon worden gelezen/uitgepakt.
  Future<bool> importPackageFile(String zipPath, {String? homeDir}) async {
    final dest = await _importDestDir(homeDir);
    final file = File(zipPath);
    if (await file.length() > FileService.maxPackageBytes) return false;
    final bytes = await file.readAsBytes();
    final mdPath = await _file.importPackageBytes(bytes, dest);
    if (mdPath == null) return false;
    final result = await openFileByPath(mdPath);
    if (result != OpenResult.opened) await _discardImportArtifacts(mdPath);
    return result == OpenResult.opened || result == OpenResult.blocked;
  }

  /// Haal een presentatie op via een URL (pakket of platte markdown) en open
  /// het in een tab. Zie [importPackageFile] voor de betekenis van de retour.
  Future<bool> importFromUrl(String url, {String? homeDir}) async {
    final dest = await _importDestDir(homeDir);
    final mdPath = await _file.importFromUrl(url, dest);
    if (mdPath == null) return false;
    final result = await openFileByPath(mdPath);
    if (result != OpenResult.opened) await _discardImportArtifacts(mdPath);
    return result == OpenResult.opened || result == OpenResult.blocked;
  }

  /// Download [entry] van de WebDAV-bron, haal het door de bestaande
  /// security-gate en open het in een tab. Het tabblad onthoudt zijn herkomst
  /// zodat "Opslaan naar Nextcloud" terug kan schrijven. Een netwerk-/auth-fout
  /// wordt als [WebdavException] doorgegeven aan de aanroeper.
  Future<OpenResult> openFromWebdav(
    WebdavService service,
    WebdavEntry entry, {
    String? homeDir,
  }) async {
    final dest = await _importDestDir(homeDir);
    final maxBytes = entry.isMarkdown
        ? FileService.maxDeckMarkdownBytes
        : FileService.maxPackageBytes;
    final bytes = await service.download(
      entry.relativePath,
      maxBytes: maxBytes,
    );
    if (!mounted) return OpenResult.unreadable;
    final mdPath = entry.isMarkdown
        ? await _file.importMarkdownBytes(bytes, dest, entry.name)
        : await _file.importPackageBytes(bytes, dest);
    if (mdPath == null) return OpenResult.unreadable;
    final result = await openFileByPath(mdPath);
    if (result != OpenResult.opened) {
      await _discardImportArtifacts(mdPath);
      return result;
    }
    // De zojuist geopende deck zit in het huidige tabblad (zie openFileByPath).
    state.current?.webdavOrigin = WebdavOrigin(
      baseUrl: service.server.baseUrl,
      username: service.server.username,
      remotePath: entry.relativePath,
    );
    if (mounted) state = state.copyWith(tabs: List.from(state.tabs));
    return OpenResult.opened;
  }

  /// Schrijf het deck van [tab] terug naar de WebDAV-bron op [targetPath]
  /// (relatief aan de wortelmap). Bij [WebdavSaveFormat.ocideck] gaat er één
  /// pakketbestand omhoog; bij [WebdavSaveFormat.flat] worden de pakket-leden
  /// (`.md` + assetmappen) los geüpload in dezelfde map. Werkt de herkomst van
  /// het tabblad bij. Gooit [WebdavException] bij een netwerk-/auth-fout.
  Future<void> saveToWebdav(
    TabInfo tab,
    WebdavService service, {
    required WebdavSaveFormat format,
    required String targetPath,
  }) async {
    final deck = tab.deckNotifier.currentState.deck;
    if (deck == null) return;
    if (format == WebdavSaveFormat.ocideck) {
      final bytes = await _file.buildPackageBytes(deck);
      await service.upload(targetPath, bytes);
    } else {
      final members = await _file.buildPackageMembers(deck);
      final dir = p.posix.dirname(targetPath);
      final mdBase = p.posix.basename(targetPath);
      for (final entry in members.entries) {
        // Het pakket-markdownbestand heet naar de deck-titel; geef het op de
        // server de naam die de gebruiker koos. Assets behouden hun submap.
        final isRootMd =
            entry.key.toLowerCase().endsWith('.md') && !entry.key.contains('/');
        final remote = isRootMd
            ? p.posix.join(dir, mdBase)
            : p.posix.join(dir, entry.key);
        await service.upload(remote, entry.value);
      }
    }
    tab.webdavOrigin = WebdavOrigin(
      baseUrl: service.server.baseUrl,
      username: service.server.username,
      remotePath: targetPath,
    );
    if (mounted) state = state.copyWith(tabs: List.from(state.tabs));
  }

  void selectTab(int index) {
    if (index >= 0 && index < state.tabs.length) {
      state = state.copyWith(selectedIndex: index);
    }
  }

  /// Close the tab at [index].
  /// If it is the only tab, just clears the deck (welcome screen remains).
  void closeTab(int index) {
    if (state.tabs.length == 1) {
      _recovery.discard(state.tabs.first.recoveryId);
      state.tabs.first.deckNotifier.closeDeck();
      state = state.copyWith(tabs: List.from(state.tabs));
      return;
    }
    final tab = state.tabs[index];
    _recovery.discard(tab.recoveryId);
    _disposeTab(tab);
    final newTabs = List<TabInfo>.from(state.tabs)..removeAt(index);
    final newSelected = index >= newTabs.length ? newTabs.length - 1 : index;
    state = state.copyWith(tabs: newTabs, selectedIndex: newSelected);
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final tabsProvider = StateNotifierProvider<TabsNotifier, TabsState>((ref) {
  return TabsNotifier(
    ref,
    ref.read(markdownServiceProvider),
    ref.read(fileServiceProvider),
    ref.read(settingsProvider.notifier),
    ref.read(recoveryServiceProvider),
  );
});

/// Holds the most recent blocked-import alarm, or null. The shell listens on
/// this and shows [ImportSecurityAlarmDialog] when it becomes non-null, then
/// resets it to null. Set by [TabsNotifier.openFileByPath].
final importSecurityAlarmProvider = StateProvider<ImportSecurityAlarm?>(
  (ref) => null,
);
