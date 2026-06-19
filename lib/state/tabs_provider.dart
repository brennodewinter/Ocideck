import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../services/file_service.dart';
import '../services/markdown_service.dart';
import '../services/recovery_service.dart';
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

  const TabInfo({
    required this.id,
    required this.recoveryId,
    required this.deckNotifier,
    required this.editorNotifier,
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

// ── Tabs notifier ─────────────────────────────────────────────────────────────

class TabsNotifier extends StateNotifier<TabsState> {
  final MarkdownService _md;
  final FileService _file;
  final SettingsNotifier _settings;
  final RecoveryService _recovery;
  final Map<int, StreamSubscription<DeckState>> _subs = {};
  Timer? _autosaveTimer;
  int _nextId = 0;

  /// Hoe vaak niet-opgeslagen tabbladen naar een herstelbestand worden bewaard.
  static const _autosaveInterval = Duration(seconds: 25);

  TabsNotifier(this._md, this._file, this._settings, this._recovery)
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
  /// [DeckNotifier] and [EditorNotifier] are disposed by Riverpod when the tab's
  /// [ProviderScope] unmounts (see `deckProvider.overrideWith` in [AppShell]).
  void _disposeTab(TabInfo tab) {
    _subs.remove(tab.id)?.cancel();
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
        _recovery.save(
          RecoverySnapshot(
            id: tab.recoveryId,
            savedAt: DateTime.now(),
            filePath: st.filePath,
            label: tab.label,
            markdown: tab.deckNotifier.generateMarkdown(),
          ),
        );
      }
    }
  }

  /// Open elke teruggehaalde snapshot als (gewijzigd) tabblad en ruim de oude
  /// herstelbestanden op. Aangeroepen vanuit het herstel-dialoog bij opstart.
  void restoreRecovered(List<RecoverySnapshot> snapshots) {
    final restored = <TabInfo>[];
    for (final snap in snapshots) {
      final deck = _md.parseDeck(snap.markdown, filePath: snap.filePath);
      _recovery.discard(snap.id); // oude sleutel; tab krijgt een nieuwe
      if (deck == null) continue;
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

  Future<void> openFileByPath(String path, {int? selectIndex}) async {
    final deck = await _file.openDeck(path);
    if (deck == null) return;
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
  }

  /// Map waarin geïmporteerde pakketten worden uitgepakt.
  Future<String> _importDestDir(String? homeDir) async {
    if (homeDir != null && homeDir.trim().isNotEmpty) return homeDir;
    return (await getApplicationDocumentsDirectory()).path;
  }

  /// Importeer een `.ocideck`-pakket (zip) en open het in een tab.
  Future<bool> importPackageFile(String zipPath, {String? homeDir}) async {
    final dest = await _importDestDir(homeDir);
    final bytes = await File(zipPath).readAsBytes();
    final mdPath = await _file.importPackageBytes(bytes, dest);
    if (mdPath == null) return false;
    await openFileByPath(mdPath);
    return true;
  }

  /// Haal een presentatie op via een URL (pakket of platte markdown) en open
  /// het in een tab.
  Future<bool> importFromUrl(String url, {String? homeDir}) async {
    final dest = await _importDestDir(homeDir);
    final mdPath = await _file.importFromUrl(url, dest);
    if (mdPath == null) return false;
    await openFileByPath(mdPath);
    return true;
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
    ref.read(markdownServiceProvider),
    ref.read(fileServiceProvider),
    ref.read(settingsProvider.notifier),
    ref.read(recoveryServiceProvider),
  );
});
