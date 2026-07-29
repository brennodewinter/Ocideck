import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/asset_origin.dart';
import '../models/chart.dart';
import '../models/deck.dart';
import '../models/improvement_y01.dart';
import '../models/settings.dart';
import '../models/seal_record.dart';
import '../models/slide.dart';
import '../models/storage_origin.dart';
import '../services/annotation_codec.dart';
import '../services/classification_enforcement_policy.dart';
import '../services/duplicate_service.dart';
import '../services/file_service.dart';
import '../services/git/asset_pool.dart';
import '../services/git/deck_mirror.dart';
import '../services/git/offline_queue.dart';
import '../services/git/deck_merge.dart';
import '../services/git/deck_repo_serializer.dart';
import '../services/git/work_branch.dart';
import '../services/git/git_forge.dart';
import '../services/git/native_git_mirror_api.dart';
import '../services/git/outbox.dart';
import '../services/git/repo_asset_resolver.dart';
import '../services/package_asset_resolver.dart';
import 'git_provider.dart';
import '../services/git/sync_engine.dart';
import '../services/image_service.dart';
import '../services/markdown_safety.dart';
import '../services/markdown_service.dart';
import '../services/recovery_service.dart';
import '../services/miauw_codec.dart';
import '../services/seal_codec.dart';
import '../services/user_notes_codec.dart';
import '../services/web_asset_store.dart';
import '../services/s3/s3_service.dart';
import '../services/webdav_service.dart';
import '../platform/platform_features.dart';
import '../utils/log.dart';
import 'deck_provider.dart';
import 'editor_provider.dart';
import 'settings_provider.dart';
import 'slide_clipboard_provider.dart';
import '../services/classification_policy.dart';
import 'package:flutter/widgets.dart';
import '../l10n/app_localizations.dart';

part 'tabs_provider_import_types.dart';
part 'tabs_provider_import.dart';
part 'tabs_provider_tab_info.dart';
part 'tabs_provider_package.dart';
part 'tabs_provider_s3.dart';
part 'tabs_provider_git.dart';
part 'tabs_provider_git_native.dart';
part 'tabs_provider_git_review.dart';

const _uuid = Uuid();

// ── Tabs notifier ─────────────────────────────────────────────────────────────

/// Owns the open tabs: which decks are open, which one is in front, and where
/// each of them came from (a local file, WebDAV, S3, or a git branch).
///
/// The distinction that matters: [DeckNotifier] holds *the* deck being edited —
/// one at a time — while this class holds the set of decks the user has open
/// and swaps the active one in and out. So per-tab state that must survive a
/// switch (the origin, the dirty flag, the undo history's owner) lives here,
/// and anything about the slides themselves lives there.
///
/// Opening is where the untrusted input arrives — an import from a URL, a
/// package from someone else — so the import gate and its security alarm are
/// reached from here rather than from the file layer.
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

  /// Duplicaat-melding maximaal één keer per paar per sessie, anders wordt
  /// elke her-open van hetzelfde bestand een herhaalde snackbar.
  final Set<String> _noticedDuplicatePairs = {};
  final DuplicateService _duplicates = DuplicateService();
  Timer? _autosaveTimer;
  int _nextId = 0;

  /// Leesbare state voor de part-extensies van deze library (zie
  /// `tabs_provider_git.dart`): `state` zelf is protected en mag alleen binnen
  /// de klasse. Zelfde truc als [DeckNotifier.currentState].
  TabsState get currentState => state;

  /// Herbouw de tabbladlijst zodat luisteraars een mutatie ín een [TabInfo] —
  /// zoals een net ingevulde origin — daadwerkelijk zien. [TabInfo] is
  /// muteerbaar, dus zonder nieuwe lijst verandert er niets voor Riverpod.
  void refreshTabs() {
    if (mounted) state = state.copyWith(tabs: List.from(state.tabs));
  }

  /// Ruimt de `mem:`-assets op die nergens meer worden gebruikt (webversie).
  ///
  /// Dit is de enige plek die het volledige plaatje heeft: elk open tabblad met
  /// zijn ongedaan-/opnieuw-stapel, plus de ene dia op het klembord. Alles wat
  /// dáárin nog een `mem:`-pad aanhaalt, blijft; de rest gaat weg. Onvolledig
  /// zou het beeld op een andere dia of een ongedaan-stap wegvagen, dus de
  /// verzameling wordt hier bewust breed opgebouwd.
  ///
  /// Op desktop is de store leeg (afbeeldingen staan op schijf), dus dan haakt
  /// hij meteen af.
  void sweepWebAssets() {
    if (WebAssetStore.isEmpty) return;
    final live = <String>{};
    for (final tab in state.tabs) {
      if (!tab.deckNotifier.mounted) continue;
      tab.deckNotifier.collectLiveMemoryAssetPaths(live);
    }
    final clipboard = _ref.read(slideClipboardProvider);
    if (clipboard != null) addSlideMemoryAssetPaths(clipboard, live);
    WebAssetStore.retain(live);
  }

  /// UI-callback die het wachtwoord van een versleuteld pakket ophaalt.
  /// Geregistreerd door de shell (die een [BuildContext] heeft); zonder
  /// registratie kan er niet om een wachtwoord worden gevraagd en falen
  /// versleutelde pakketten met [ImportFailure.needsPassword].
  PackagePasswordResolver? packagePasswordResolver;

  /// UI-callback die vraagt of de web-import mag terugvallen op het
  /// same-origin fetch-hulppunt. Geregistreerd door de shell. Zonder
  /// registratie is er geen toestemming en vervalt de terugval — dat is de
  /// bedoeling: die terugval geeft de volledige URL aan een derde partij.
  ProxyFallbackConfirm? proxyFallbackConfirm;

  /// Hoe vaak niet-opgeslagen tabbladen naar een herstelbestand worden bewaard.
  static const _autosaveInterval = Duration(seconds: 25);

  TabsNotifier(this._ref, this._md, this._file, this._settings, this._recovery)
    : super(const TabsState(tabs: [])) {
    // Start with one empty tab
    final tab = _createTab();
    state = TabsState(tabs: [tab], selectedIndex: 0);
    // Zonder bestandssysteem (web) is er geen herstelmap; de tick zou elke
    // 25s voor niets serialiseren, dus start hem daar helemaal niet.
    if (supportsLocalProjectFolders) {
      _autosaveTimer = Timer.periodic(
        _autosaveInterval,
        (_) => _autosaveTick(),
      );
    }
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

  /// [recoveryId] hergebruikt de sleutel van een bestaande herstelkopie (zie
  /// [restoreRecovered]); zonder krijgt het tabblad een verse.
  TabInfo _createTab({String? recoveryId}) {
    final id = _nextId++;
    final key = recoveryId ?? _uuid.v4();
    final deckNotifier = DeckNotifier(_md, _file);
    // De webversie houdt gekozen afbeeldingen in het geheugen (mem:-paden). Als
    // dit tabblad dia's verwijdert of opslaat, ruimt de sweep de assets op die
    // nergens meer — in geen enkel tabblad, ongedaan-stapel of klembord —
    // gebruikt worden. Op desktop is de store leeg, dus dit is er een no-op.
    deckNotifier.onSweepWebAssets = sweepWebAssets;
    // Een opslag die de grafiekcijfers niet kwijt kon, mag niet als geslaagd
    // voorbijgaan: dezelfde melding als bij het openen, met een eigen tekst.
    deckNotifier.onChartDataWarnings = (sources) {
      if (!mounted) return;
      _ref.read(chartDataWarningProvider.notifier).state = ChartDataWarning(
        sources,
        whileSaving: true,
      );
    };
    final tab = TabInfo(
      id: id,
      recoveryId: key,
      deckNotifier: deckNotifier,
      editorNotifier: EditorNotifier(),
    );
    _subs[id] = deckNotifier.stream.listen((st) {
      if (!mounted) return;
      // Zodra een tabblad is opgeslagen (schoon), het herstelbestand wissen.
      // Schrijven gebeurt gebufferd door de periodieke autosave-tick.
      if (!(st.isOpen && st.isDirty)) {
        _recovery.discard(key);
      }
      state = state.copyWith(tabs: List.from(state.tabs));
    });
    return tab;
  }

  /// Bewaar elk niet-opgeslagen tabblad naar zijn herstelbestand.
  void _autosaveTick() {
    if (!mounted) return;
    // Dezelfde tik ruimt verlopen herstelbestanden op. Anders gold de
    // houdbaarheid van zeven dagen alleen bij het opstarten, en hield een
    // machine die aan blijft staan de klaartekst van een oude crash vast.
    // Zelf-beperkend op een uur; zie [RecoveryService.pruneIfDue].
    unawaited(_recovery.pruneIfDue());
    for (final tab in state.tabs) {
      // Zie TabInfo.label: een tab kan kortstondig een al-gedisposede
      // notifier dragen; die heeft niets meer te autosaven.
      if (!tab.deckNotifier.mounted) continue;
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
            miauw: MiauwCodec.encodeDisposition(deck.miauw),
            seal: SealCodec.encode(SealRecord.of(deck)),
            // Tekeningen staan niet in de markdown (eigen sidecar), en tekenen
            // maakt het deck wél vuil. Zonder deze regel kwam een herstelde
            // presentatie stil zonder annotaties terug.
            annotations: AnnotationCodec.encode(deck.slides, deck.annotations),
          ),
        );
        _lastAutosavedDeck[tab.id] = deck;
      }
    }
  }

  /// Open elke teruggehaalde snapshot als (gewijzigd) tabblad en ruim de oude
  /// herstelbestanden op. Aangeroepen vanuit het herstel-dialoog bij opstart.
  /// Zet de herstelde momentopnames terug in tabbladen. Geeft terug hoeveel er
  /// níét gelezen konden worden; die blijven op schijf staan.
  int restoreRecovered(List<RecoverySnapshot> snapshots) {
    final restored = <TabInfo>[];
    var unreadable = 0;
    for (final snap in snapshots) {
      final parsed = _md.parseDeck(snap.markdown, filePath: snap.filePath);
      if (parsed == null) {
        // Niet weggooien. `parseDeck` vangt zijn eigen fouten af juist omdát hij
        // in de praktijk struikelt, en een crash ín de parser is een van de
        // waarschijnlijkere redenen dat deze momentopname er überhaupt ligt.
        // Eerst wissen en dan pas kijken of het lukte, betekende dat één klik op
        // "Herstellen" het enige exemplaar van andermans avond opruimde.
        unreadable++;
        logWarning('restoreRecovered: momentopname onleesbaar', snap.filePath);
        continue;
      }
      var deck = parsed;
      if (snap.userNotes != null && snap.userNotes!.isNotEmpty) {
        final notes = UserNotesCodec.decode(snap.userNotes!, deck.slides);
        if (notes.isNotEmpty) {
          deck = deck.copyWith(userNotes: notes);
        }
      }
      if (snap.miauw != null && snap.miauw!.isNotEmpty) {
        final d = MiauwCodec.decode(snap.miauw!);
        if (!d.isEmpty) {
          deck = deck.copyWith(miauw: d);
        }
      }
      if (snap.seal != null && snap.seal!.isNotEmpty) {
        final record = SealCodec.decode(snap.seal!);
        if (record != null) deck = record.applyTo(deck);
      }
      final ink = snap.annotations;
      if (ink != null && ink.isNotEmpty) {
        try {
          final strokes = AnnotationCodec.decode(ink, deck.slides);
          if (strokes.isNotEmpty) deck = deck.copyWith(annotations: strokes);
        } catch (e) {
          // Een kapotte tekenlaag mag het herstel van de tekst nooit blokkeren;
          // hetzelfde als bij een onleesbare sidecar op schijf.
          logWarning('restoreRecovered: annotaties onleesbaar', e);
        }
      }
      // Hergebruik de sleutel van de momentopname. Het bestand dat er al ligt ís
      // daarmee meteen de herstelkopie van dit tabblad, in plaats van dat het
      // wordt weggegooid en de nieuwe pas bij de volgende autosave-tik ontstaat.
      // Dat gat duurde tot [_autosaveInterval] — en juist in die seconden crasht
      // een app die zojuist opnieuw dezelfde inhoud heeft geopend.
      final tab = _createTab(recoveryId: snap.id);
      tab.deckNotifier.loadDeck(deck, filePath: snap.filePath);
      tab.deckNotifier.markDirty(); // herstelde inhoud is nog niet opgeslagen
      restored.add(tab);
    }
    if (restored.isEmpty) return unreadable;

    // Een ongebruikt leeg begin-tabblad vervangen, anders toevoegen.
    final replaceEmpty = state.tabs.length == 1 && !state.tabs.first.isOpen;
    if (replaceEmpty) {
      _disposeTab(state.tabs.first);
      state = state.copyWith(tabs: restored, selectedIndex: 0);
    } else {
      final tabs = [...state.tabs, ...restored];
      state = state.copyWith(tabs: tabs, selectedIndex: state.tabs.length);
    }
    return unreadable;
  }

  void newEmptyTab() {
    final tab = _createTab();
    final newTabs = [...state.tabs, tab];
    state = state.copyWith(tabs: newTabs, selectedIndex: newTabs.length - 1);
  }

  void newDeckInCurrentTab(
    String title, {
    List<Slide>? slides,
    String improvementFramework = '',
    String improvementY01 = '',
    ImprovementY01Metric? improvementY01Metric,
  }) {
    final tab = state.current;
    if (tab == null) return;
    tab.deckNotifier.newDeck(
      title,
      slides: slides,
      improvementFramework: improvementFramework,
      improvementY01: improvementY01,
      improvementY01Metric: improvementY01Metric,
    );
    tab.editorNotifier.select(0);
    // Force rebuild by copying state (label may have changed)
    state = state.copyWith(tabs: List.from(state.tabs));
  }

  void newDeckInNewTab(
    String title, {
    List<Slide>? slides,
    String improvementFramework = '',
    String improvementY01 = '',
    ImprovementY01Metric? improvementY01Metric,
  }) {
    final tab = _createTab();
    tab.deckNotifier.newDeck(
      title,
      slides: slides,
      improvementFramework: improvementFramework,
      improvementY01: improvementY01,
      improvementY01Metric: improvementY01Metric,
    );
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
    // Detailed, niet de dunne wrapper: die gooit de grafiekdata-waarschuwingen
    // weg, en dan opent een deck met een ontbrekend databestand hier met stille
    // lege plots — precies wat [chartDataWarningProvider] hoort te melden.
    final outcome = await _file.openDeckDetailed(path);
    final deck = outcome.deck;
    if (deck == null) return;
    if (!mounted) return; // notifier disposed during the await
    _reportOpenOutcome(_ref, outcome);

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
    await _settings.addRecentFile(
      path,
      slideCount: deck.slides.length,
      tlp: deck.tlp,
    );
  }

  Future<OpenResult> openFileByPath(String path, {int? selectIndex}) async {
    // Dezelfde presentatie hoort maar één keer open te staan. Staat dit bestand
    // al in een tabblad, spring er dan naartoe in plaats van een tweede kopie te
    // openen — dat voorkomt versieverwarring (twee tabs, twee losse bewerkingen
    // van hetzelfde bestand). De veiligheidsscan is bij het eerste openen al
    // gedaan, dus die hoeft hier niet opnieuw.
    _clearOpenFailure(_ref, mounted);
    // Een `.ocideck`/zip-pakket gaat door het uitpakpad, niet de markdown-open —
    // anders weigert die het als te grote of onleesbare tekst (#905).
    if (_isPackagePath(path)) {
      final homeDir = _ref.read(settingsProvider).homeDirectory;
      final failure = await importPackageFile(path, homeDir: homeDir);
      return _packageOpenResult(_ref, mounted, failure);
    }
    final existing = _indexOfOpenPath(path);
    if (existing != null) {
      selectTab(existing);
      if (selectIndex != null) {
        final tab = state.tabs[existing];
        if (tab.deckNotifier.mounted) {
          final count = tab.deckNotifier.currentState.deck?.slides.length ?? 0;
          if (count > 0) {
            tab.editorNotifier.select(selectIndex.clamp(0, count - 1));
          }
        }
      }
      return OpenResult.opened;
    }
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
      return _openFailureResult(_ref, mounted, outcome.failure);
    }
    // notifier disposed during the await
    if (!mounted) return OpenResult.unreadable;
    _reportOpenOutcome(_ref, outcome);
    final index = (selectIndex ?? 0).clamp(0, deck.slides.length - 1);
    _placeDeckInTab(deck, filePath: path, index: index);
    await _settings.addRecentFile(
      path,
      slideCount: deck.slides.length,
      tlp: deck.tlp,
    );
    // Los van het open-pad: een byte-identieke kopie elders in de recente
    // lijst is het melden waard, maar mag het openen nooit vertragen.
    unawaited(_noticeIdenticalCopy(path));
    return OpenResult.opened;
  }

  /// Zoek een byte-identieke kopie van het zojuist geopende bestand in de
  /// recente lijst en meld die eenmalig via [duplicateCopyNoticeProvider];
  /// de shell toont daarop een snackbar met een opruim-ingang.
  Future<void> _noticeIdenticalCopy(String openedPath) async {
    try {
      final recents = [
        for (final f in _ref.read(settingsProvider).recentFiles) f.path,
      ];
      final copy = await _duplicates.findIdenticalCopy(openedPath, recents);
      if (copy == null || !mounted) return;
      final pair = ([openedPath, copy]..sort()).join('\u0000');
      if (!_noticedDuplicatePairs.add(pair)) return;
      _ref.read(duplicateCopyNoticeProvider.notifier).state =
          DuplicateCopyNotice(openedPath: openedPath, copyPath: copy);
    } catch (e) {
      logWarning('TabsNotifier._noticeIdenticalCopy', e);
    }
  }

  /// Index van het tabblad waarin het bestand met [path] al open is, of `null`.
  /// Vergelijkt genormaliseerde absolute paden zodat een relatief pad en het
  /// volledige pad naar hetzelfde bestand hetzelfde tabblad raken.
  int? _indexOfOpenPath(String path) {
    final target = p.canonicalize(path);
    for (var i = 0; i < state.tabs.length; i++) {
      final tab = state.tabs[i];
      if (!tab.deckNotifier.mounted) continue;
      final open = tab.deckNotifier.currentState.filePath;
      if (open != null && open.isNotEmpty && p.canonicalize(open) == target) {
        return i;
      }
    }
    return null;
  }

  /// Zet een zojuist geopend deck in een tabblad: een leeg huidig tabblad
  /// wordt hergebruikt, anders komt er een nieuw tabblad naast. Gedeelde
  /// staart van pad-, bytes- en URL-opens.
  void _placeDeckInTab(
    Deck deck, {
    String? filePath,
    int index = 0,
    String? remoteOrigin,
  }) {
    final current = state.current;
    if (current != null && !current.isOpen) {
      current.deckNotifier.loadDeck(
        deck,
        filePath: filePath,
        remoteOrigin: remoteOrigin,
      );
      current.editorNotifier.select(index);
      state = state.copyWith(tabs: List.from(state.tabs));
    } else {
      final tab = _createTab();
      tab.deckNotifier.loadDeck(
        deck,
        filePath: filePath,
        remoteOrigin: remoteOrigin,
      );
      tab.editorNotifier.select(index);
      final newTabs = [...state.tabs, tab];
      state = state.copyWith(tabs: newTabs, selectedIndex: newTabs.length - 1);
    }
    _maybePromptSecurityModule(deck);
    _maybePromptImprovementModule(deck);
  }

  /// A just-opened deck carrying Informatieveiligheid slide types is worth a
  /// one-time "enable the module" nudge. Signalled here — the single chokepoint
  /// every real open funnels through — so it fires exactly once per open; an
  /// edit builds a new [Deck] via copyWith but never touches this path, so it
  /// never re-fires. Whether to actually prompt (module off, not still loading)
  /// is decided by the shell's listener, which reads the freshest module state;
  /// this layer stays decoupled from the module and just reports the fact. Same
  /// one-shot listen pattern as [importSecurityAlarmProvider].
  void _maybePromptSecurityModule(Deck deck) {
    if (!deck.hasSecuritySlides) return;
    // Aangeroepen ná het plaatsen, dus `current` is het tabblad dat dit deck
    // net heeft gekregen — de melding kan zich er zo aan vastknopen.
    final tab = state.current;
    if (tab == null) return;
    _ref.read(securityModulePromptProvider.notifier).state =
        SecurityModulePrompt(tabId: tab.id);
  }

  /// Same chokepoint as [_maybePromptSecurityModule] for Procesverbetering
  /// (PROCESS_IMPROVEMENT.md Phase 0). No-op until engine types exist.
  void _maybePromptImprovementModule(Deck deck) {
    if (!deck.hasImprovementSlides) return;
    final tab = state.current;
    if (tab == null) return;
    _ref.read(improvementModulePromptProvider.notifier).state =
        ImprovementModulePrompt(tabId: tab.id);
  }

  /// Open een deck uit in-memory bytes — het open-pad voor web, waar de
  /// file-picker, drag-drop én URL-import geen pad maar inhoud aanleveren.
  /// Een `.ocideck`/zip-pakket wordt volledig in het geheugen uitgepakt
  /// ([_openPackageFromBytes]); platte markdown gaat door dezelfde
  /// fail-closed security-gate als [openFileByPath]. Er is geen TOCTOU-gat,
  /// want gescand en geparsed wordt exact dezelfde in-memory string. Het
  /// tabblad krijgt geen [DeckState.filePath], dus opslaan wordt een
  /// download. [name] labelt het importalarm en de logregels (bestandsnaam
  /// of URL).
  Future<OpenResult> openDeckFromBytes(
    Uint8List bytes,
    String name, {
    String? remoteOrigin,
  }) async {
    _clearOpenFailure(_ref, mounted);
    if (FileService.looksLikeZipBytes(bytes)) {
      return _openPackageFromBytes(bytes, name, remoteOrigin: remoteOrigin);
    }
    if (bytes.length > FileService.maxDeckMarkdownBytes) {
      return _failOpen(_ref, mounted, OpenFailure.tooLarge);
    }
    final String raw;
    try {
      raw = utf8.decode(bytes);
    } on FormatException catch (e) {
      logWarning('TabsNotifier.openDeckFromBytes: not valid UTF-8', e);
      return _failOpen(_ref, mounted, OpenFailure.unreadable);
    }
    final gated = _gateAndParseContent(raw, sourceName: name);
    final deck = gated.deck;
    if (deck == null) return gated.failure;
    if (!mounted) return OpenResult.unreadable;
    _warnUnfilledChartData(deck);
    _placeDeckInTab(deck, remoteOrigin: remoteOrigin);
    return OpenResult.opened;
  }

  /// Pak een `.ocideck`/zip-pakket volledig in het geheugen uit en open het:
  /// de hoofd-markdown gaat door dezelfde security-gate als elk bytes-open,
  /// afbeeldings-leden gaan (na de pickImage-validatie) de [WebAssetStore] in
  /// en de slidepaden worden naar hun mem:-pad herschreven, en de sidecars
  /// (annotaties, sprekersnotities) reizen mee. Er raakt geen bestandssysteem
  /// aan te pas, dus dit werkt ook in de webversie.
  Future<OpenResult> _openPackageFromBytes(
    Uint8List bytes,
    String name, {
    String? remoteOrigin,
  }) async {
    // Versleuteld pakket: vraag (met retry) het wachtwoord vóór het decoderen.
    String? password;
    if (FileService.isEncryptedPackage(bytes)) {
      final resolver = packagePasswordResolver;
      if (resolver == null) return OpenResult.passwordCancelled;
      var retry = false;
      while (true) {
        final pw = await resolver(retry: retry);
        if (pw == null || !mounted) return OpenResult.passwordCancelled;
        if (_file.canDecodePackage(bytes, pw)) {
          password = pw;
          break;
        }
        retry = true;
      }
    }
    final entries = _file.decodePackageEntries(bytes, password: password);
    if (entries == null) return OpenResult.unreadable;
    final mdEntry = FileService.mainMarkdownEntry(entries);
    if (mdEntry == null) return OpenResult.notAPresentation;
    final String raw;
    try {
      raw = utf8.decode(mdEntry.bytes);
    } on FormatException catch (e) {
      logWarning('TabsNotifier._openPackageFromBytes: md not UTF-8', e);
      return OpenResult.unreadable;
    }
    final gated = _gateAndParseContent(
      raw,
      sourceName: '$name → ${mdEntry.name}',
    );
    var deck = gated.deck;
    if (deck == null) return gated.failure;

    deck = _attachPackageAssets(deck, entries, mdEntry.name);
    deck = _attachPackageChartData(deck, entries, mdEntry.name);
    deck = _attachPackageSidecars(deck, entries, mdEntry.name);
    if (!mounted) return OpenResult.unreadable;
    // Ná het aanhaken: wat het pakket wél meebracht is nu ingevuld, dus wat
    // hier nog leeg is, ontbrak echt.
    _warnUnfilledChartData(deck);
    _placeDeckInTab(deck, remoteOrigin: remoteOrigin);
    return OpenResult.opened;
  }

  /// Gedeelde poort van elk bytes-open: veiligheidsscan (met alarm bij
  /// treffers, dan [OpenResult.blocked]) en daarna de contentpoort van
  /// [FileService]. Bij succes draagt het record het deck; anders het
  /// [OpenResult] dat de UI moet melden.
  ({Deck? deck, OpenResult failure}) _gateAndParseContent(
    String raw, {
    required String sourceName,
  }) {
    final findings = MarkdownSafetyScanner.scan(raw);
    if (findings.isNotEmpty) {
      // Ook vastleggen, niet alleen tonen. De twee andere poorten op deze
      // scanner (`FileService.openDeck` en `openDeckFromContent`) loggen hun
      // weigering wél; deze deed dat niet, terwijl het juist de weg is waarlangs
      // een deck van buiten binnenkomt. Een alarm dat de gebruiker wegklikt,
      // laat niets na — en "dit deck tripte de poort" is precies wat je
      // achteraf wilt kunnen navertellen bij een gereedschap dat verzegelde
      // rapporten uitgeeft. Alleen de telling — net als de twee zusterpoorten
      // in `FileService`. De bevinding zelf draagt deckinhoud, en zelfs de
      // soorten opsommen zou een waardenlijst in de log zetten; welke regel
      // aansloeg leest de gebruiker in zijn eigen bestand.
      logWarning(
        'TabsProvider: geopend deck geweigerd — uitvoerbare inhoud '
        '(${findings.length} bevinding(en))',
        sourceName,
      );
      if (mounted) {
        _ref.read(importSecurityAlarmProvider.notifier).state =
            ImportSecurityAlarm(path: sourceName, findings: findings);
      }
      return (deck: null, failure: OpenResult.blocked);
    }
    final outcome = _file.openDeckFromContent(raw, sourceName: sourceName);
    final deck = outcome.deck;
    if (deck == null) {
      return (
        deck: null,
        failure: outcome.failure == OpenFailure.notPresentation
            ? OpenResult.notAPresentation
            : OpenResult.unreadable,
      );
    }
    return (deck: deck, failure: OpenResult.opened);
  }

  /// Remove the unique folder an import extracted/downloaded into when the deck
  /// was not opened (blocked or unreadable). Only ever deletes folders the
  /// import itself just created — never a folder the user opened in place.

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

/// De reden van de laatst mislukte open, of null wanneer die onbekend is.
///
/// `FileService.openDeckDetailed` wéét al waarom het misging — [OpenFailure]
/// onderscheidt zes gevallen — maar de state-laag gooide dat weg en vertaalde
/// alles behalve "geen presentatie" naar één [OpenResult.unreadable]. De
/// gebruiker kreeg dus "Kon dit bestand niet openen.", zonder reden en zonder
/// suggestie, terwijl het antwoord twee lagen lager gewoon bekend was.
///
/// Zelfde vorm als [importSecurityAlarmProvider]: het openpad zet hem, de schil
/// leest hem bij het tonen van de melding. Dat scheelt een reden door 26
/// return-plekken heen dragen die hem meestal toch niet kennen — en bij die
/// plekken is de generieke melding ook eerlijk.
///
/// Wordt bij elke open gewist voordat er iets kan mislukken: een reden van de
/// vorige keer is erger dan geen reden, want die wijst de verkeerde kant op.
final openFailureProvider = StateProvider<OpenFailure?>((ref) => null);

/// Legt vast waaróm een open mislukte en geeft [OpenResult.unreadable] terug.
///
/// Eén plek, zodat een volgend geval de reden niet vergeet te zetten. Buiten
/// [TabsNotifier] omdat die klasse tegen haar plafond zit — en omdat dit geen
/// state is maar een notitie erover; [alive] draagt de `mounted`-controle mee,
/// want na dispose is er geen container meer om in te schrijven.
OpenResult _failOpen(Ref ref, bool alive, OpenFailure reason) {
  if (alive) ref.read(openFailureProvider.notifier).state = reason;
  return OpenResult.unreadable;
}

/// Vertaalt de uitkomst van `FileService.openDeckDetailed` naar een
/// [OpenResult] én legt de reden vast.
///
/// "Geen presentatie" had altijd al zijn eigen uitkomst, zodat de schil dat kon
/// zeggen in plaats van een algemeen "kon niet openen". De ándere vijf oorzaken
/// kende `openDeckDetailed` net zo goed, maar die werden hier weggegooid — dus
/// wist de gebruiker niet of hij het verkeerde bestand koos, of dat er iets
/// stuk was. Nu reizen ze mee (#646).
OpenResult _openFailureResult(Ref ref, bool alive, OpenFailure? failure) {
  if (failure == null) return OpenResult.unreadable;
  _failOpen(ref, alive, failure);
  return failure == OpenFailure.notPresentation
      ? OpenResult.notAPresentation
      : OpenResult.unreadable;
}

/// Wist de reden aan het begin van een open.
///
/// Vóór de poging, niet erna: blijft de reden van de vorige mislukking staan,
/// dan krijgt de volgende fout een verklaring die niet van hem is — en een
/// melding die de verkeerde kant op wijst kost meer tijd dan een vage.
void _clearOpenFailure(Ref ref, bool alive) {
  if (alive) ref.read(openFailureProvider.notifier).state = null;
}

/// True als [path] op zijn extensie een `.ocideck`-pakket of losse `.zip` is:
/// een zip met de deck plus assets, niet de platte markdown die de gewone open
/// verwacht. Zelfde extensie-afslag als slepen-en-neerzetten
/// ([AppShell._onFilesDropped]) en de web-bytes-open, zodat "Openen", drag-drop
/// en web hetzelfde pakket op dezelfde manier behandelen.
bool _isPackagePath(String path) {
  final ext = p.extension(path).toLowerCase();
  return ext == '.${FileService.packageExtension}' || ext == '.zip';
}

/// Vertaalt de uitkomst van [TabsImport.importPackageFile] — aangeroepen vanuit
/// [TabsNotifier.openFileByPath] voor een `.ocideck`/zip via "Openen" — naar een
/// [OpenResult], en legt waar mogelijk de [OpenFailure] vast zodat de schil
/// dezelfde gerichte melding toont als bij een losse markdown-open. `null`
/// betekent: afgehandeld (geopend, geblokkeerd met alarm, of wachtwoord
/// afgebroken); dan valt er niets te melden.
OpenResult _packageOpenResult(Ref ref, bool alive, ImportFailure? failure) =>
    switch (failure) {
      null => OpenResult.opened,
      ImportFailure.needsPassword ||
      ImportFailure.encryptedCancelled => OpenResult.passwordCancelled,
      ImportFailure.tooLarge || ImportFailure.limitExceeded =>
        _openFailureResult(ref, alive, OpenFailure.tooLarge),
      ImportFailure.corrupt => _openFailureResult(
        ref,
        alive,
        OpenFailure.corrupt,
      ),
      ImportFailure.unsupported => _openFailureResult(
        ref,
        alive,
        OpenFailure.notPresentation,
      ),
      ImportFailure.network => _openFailureResult(
        ref,
        alive,
        OpenFailure.unreadable,
      ),
    };

/// Een zojuist geopend bestand blijkt elders een byte-identieke kopie te
/// hebben. De shell toont hierop een snackbar met opruim-ingang (zelfde
/// luister-patroon als [importSecurityAlarmProvider]).
class DuplicateCopyNotice {
  final String openedPath;
  final String copyPath;
  const DuplicateCopyNotice({required this.openedPath, required this.copyPath});
}

final duplicateCopyNoticeProvider = StateProvider<DuplicateCopyNotice?>(
  (ref) => null,
);

/// One-shot signal that a deck carrying Informatieveiligheid slide types was
/// just opened (see [Deck.hasSecuritySlides]). The shell listens on this and —
/// only when the module is off — offers a one-time "enable the module" banner
/// (pure discovery; the slides render regardless). Set once per open by
/// [TabsNotifier._maybePromptSecurityModule], then reset to null once handled,
/// mirroring [importSecurityAlarmProvider].
class SecurityModulePrompt {
  /// Het tabblad waarin het deck werd geopend. De melding hoort bij dít
  /// tabblad: zodra de gebruiker wisselt of het deck sluit, gaat hij weg — een
  /// blijvende balk over een presentatie die niet meer in beeld is, is een
  /// leugen over wat er open staat.
  ///
  /// Dit is het enige dat het signaal draagt. Wélke slide de melding aanwijst
  /// wordt niet hier vastgelegd maar bij elke klik opnieuw uit het levende deck
  /// gelezen: de gebruiker mag intussen slides verwijderen of verplaatsen, en
  /// een index van een paar seconden geleden wijst dan iets anders aan (of
  /// niets meer). Zie `_showSecuritySlide` in de shell.
  final int tabId;

  /// A non-const constructor on purpose: each open must produce a *distinct*
  /// instance so a back-to-back second open still notifies listeners (two const
  /// instances would be identical and be swallowed as "no change").
  SecurityModulePrompt({required this.tabId});
}

final securityModulePromptProvider = StateProvider<SecurityModulePrompt?>(
  (ref) => null,
);

/// One-shot signal that a deck carrying Procesverbetering slide types was
/// just opened (see [Deck.hasImprovementSlides]). Same shape as
/// [securityModulePromptProvider] (PROCESS_IMPROVEMENT.md Phase 0).
class ImprovementModulePrompt {
  final int tabId;

  ImprovementModulePrompt({required this.tabId});
}

final improvementModulePromptProvider = StateProvider<ImprovementModulePrompt?>(
  (ref) => null,
);

/// Grafieken waarvan het gekoppelde databestand niet gelezen of niet geschreven
/// kon worden: ontbrekend, onleesbaar, buiten de projectmap, of intussen buiten
/// de app gewijzigd.
///
/// Bij het openen tekent zo'n grafiek leeg, en dat ziet er precies uit als een
/// grafiek zonder cijfers. Bij het opslaan is het erger: de markdown draagt dan
/// alleen nog de verwijzing, dus de cijfers staan enkel nog in dit venster. In
/// beide gevallen is het probleem onzichtbaar tenzij we het zeggen. Zelfde
/// eenmalige signaalvorm als [securityModulePromptProvider]: de state-laag zet
/// hem, de shell toont hem en wist hem.
class ChartDataWarning {
  /// De `source`-paden die het niet haalden.
  final List<String> sources;

  /// Of dit een opslag betrof. De twee gevallen vragen een andere tekst — bij
  /// lezen blijft de grafiek leeg, bij schrijven zijn de cijfers nergens
  /// vastgelegd — en dat verschil bepaalt wat de gebruiker moet doen.
  final bool whileSaving;

  /// Niet-const, net als [SecurityModulePrompt]: twee identieke const-instanties
  /// zouden bij een tweede open als "geen wijziging" worden weggeslikt.
  ChartDataWarning(this.sources, {this.whileSaving = false});
}

/// Welke lagen naast het deck niet zijn ingelezen omdat ze te groot waren.
///
/// Eigen kanaal en niet dat van de grafiekdata: de tekst is anders, en het gaat
/// hier over werk van de gebruiker zélf (strepen, notities) in plaats van over
/// een ontbrekend databestand. Het bestand op schijf is niet aangeraakt, dus dit
/// is te herstellen — maar alleen als iemand het te weten komt.
class SidecarSkippedWarning {
  /// De lagen, met de namen die de leeskant gebruikt (`ink`, `user-notes`, …).
  final List<String> layers;

  /// Niet-const, om dezelfde reden als [ChartDataWarning].
  SidecarSkippedWarning(this.layers);
}

final sidecarSkippedProvider = StateProvider<SidecarSkippedWarning?>(
  (ref) => null,
);

final chartDataWarningProvider = StateProvider<ChartDataWarning?>(
  (ref) => null,
);

/// Zet wat het openen te melden had door naar de schil.
///
/// Top-level en geen methode: het raakt geen enkel veld van [TabsNotifier], en
/// die klasse zit tegen zijn plafond. Twee kanalen, bewust gescheiden — een
/// ontbrekend grafiekbestand vraagt iets anders van de gebruiker dan een laag
/// die te groot was.
void _reportOpenOutcome(Ref ref, DeckOpenResult outcome) {
  if (outcome.warnings.isNotEmpty) {
    ref.read(chartDataWarningProvider.notifier).state = ChartDataWarning(
      outcome.warnings,
    );
  }
  if (outcome.skippedSidecars.isNotEmpty) {
    ref.read(sidecarSkippedProvider.notifier).state = SidecarSkippedWarning(
      outcome.skippedSidecars,
    );
  }
}
