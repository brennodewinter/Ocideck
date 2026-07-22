// Part of the tabs_provider library — see tabs_provider.dart.
// [TabInfo] en [TabsState]: wat één tabblad is en wat de verzameling tabbladen
// is. Losgetrokken zodat tabs_provider.dart onder de groottegrens blijft; het
// zijn de twee datatypes waar de rest van dat bestand op werkt, dus ze horen
// bij elkaar en nergens anders.
part of 'tabs_provider.dart';

// ── Per-tab data ──────────────────────────────────────────────────────────────

class TabInfo {
  final int id;

  /// Stabiele sleutel voor het autosave-herstelbestand van dit tabblad.
  final String recoveryId;
  final DeckNotifier deckNotifier;
  final EditorNotifier editorNotifier;

  /// Waar het deck in dit tabblad vandaan kwam, of `null` voor een nieuw of
  /// puur lokaal deck. Muteerbaar: wordt na het openen ingevuld en bij elke
  /// `state`-kopie hergebruikt.
  ///
  /// Eén veld, geen drie. Vroeger droeg een tabblad een `webdavOrigin`, een
  /// `s3Origin` en een `gitOrigin` naast elkaar met een opmerking erbij dat een
  /// deck er hooguit één zou hebben — maar niets handhaafde dat, dus een deck
  /// dat van WebDAV kwam en naar S3 werd weggeschreven droeg er twee. Sinds
  /// opslaan de herkomst volgt, moet die vraag één antwoord hebben.
  StorageOrigin? origin;

  /// De herkomst als die van WebDAV komt, anders `null`. De backends werken met
  /// hun eigen type; deze accessors houden dat leesbaar zonder het ene veld op
  /// te geven. Iets toekennen vervangt een herkomst van een andere soort — dat
  /// is precies de bedoeling: het deck komt nu daarvandaan.
  WebdavOrigin? get webdavOrigin {
    final o = origin;
    return o is WebdavOrigin ? o : null;
  }

  set webdavOrigin(WebdavOrigin? value) {
    if (value != null || origin is WebdavOrigin) origin = value;
  }

  /// De herkomst als die uit een git-repository komt, anders `null`. Draagt
  /// naast de repo ook de `baseSha` waartegen dit werk is geschreven — dát is
  /// wat versiebeheer toevoegt boven de andere twee.
  GitOrigin? get gitOrigin {
    final o = origin;
    return o is GitOrigin ? o : null;
  }

  set gitOrigin(GitOrigin? value) {
    if (value != null || origin is GitOrigin) origin = value;
  }

  /// De herkomst als die uit een S3-bucket komt, anders `null`.
  S3Origin? get s3Origin {
    final o = origin;
    return o is S3Origin ? o : null;
  }

  set s3Origin(S3Origin? value) {
    if (value != null || origin is S3Origin) origin = value;
  }

  TabInfo({
    required this.id,
    required this.recoveryId,
    required this.deckNotifier,
    required this.editorNotifier,
    this.origin,
  });

  String get label {
    // Rond het sluiten van een tab of het venster kan Riverpod de notifier al
    // hebben opgeruimd (de ProviderScope van de tab is dan ontmanteld) terwijl
    // dit TabInfo nog één rebuild lang in beeld is. Lezen van een gedisposede
    // StateNotifier gooit; val dan terug op neutrale waarden.
    // Via de actieve taal en niet als kale literal: dit is het eerste woord
    // linksboven in het venster, en het stond in alle 32 talen in het
    // Nederlands (#576). De Locale is hier een handvat — `d()` leest de
    // statisch gezette taal.
    if (!deckNotifier.mounted) return _newTabLabel;
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
    return deck?.title.isNotEmpty == true ? deck!.title : _newTabLabel;
  }

  bool get isDirty => deckNotifier.mounted && deckNotifier.currentState.isDirty;
  bool get isOpen => deckNotifier.mounted && deckNotifier.currentState.isOpen;
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

/// Het opschrift van een tabblad zonder deck.
String get _newTabLabel => const AppLocalizations(Locale('nl')).d('Nieuw');
