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
import '../models/deck_template.dart';
import '../models/settings.dart';
import '../models/slide.dart';
import '../models/storage_origin.dart';
import '../services/annotation_codec.dart';
import '../services/classification_enforcement_policy.dart';
import '../services/duplicate_service.dart';
import '../services/file_service.dart';
import '../services/git/asset_pool.dart';
import '../services/git/deck_mirror.dart';
import '../services/git/draft_store.dart';
import '../services/git/deck_merge.dart';
import '../services/git/deck_repo_serializer.dart';
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

part 'tabs_provider_import_types.dart';
part 'tabs_provider_tab_info.dart';
part 'tabs_provider_package.dart';
part 'tabs_provider_s3.dart';
part 'tabs_provider_git.dart';
part 'tabs_provider_git_native.dart';
part 'tabs_provider_git_review.dart';

const _uuid = Uuid();

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
            miauw: MiauwCodec.encode(
              deck.miauwWaivers,
              deck.miauwConfirmations,
            ),
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
          deck = deck.copyWith(
            miauwWaivers: d.waivers,
            miauwConfirmations: d.confirmations,
          );
        }
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

  void newDeckInCurrentTab(String title, {DeckTemplate? template}) {
    final tab = state.current;
    if (tab == null) return;
    tab.deckNotifier.newDeck(title, template: template);
    tab.editorNotifier.select(0);
    // Force rebuild by copying state (label may have changed)
    state = state.copyWith(tabs: List.from(state.tabs));
  }

  void newDeckInNewTab(String title, {DeckTemplate? template}) {
    final tab = _createTab();
    tab.deckNotifier.newDeck(title, template: template);
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
    if (outcome.warnings.isNotEmpty) {
      _ref.read(chartDataWarningProvider.notifier).state = ChartDataWarning(
        outcome.warnings,
      );
    }

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
      // A readable file that simply isn't a presentation gets its own result so
      // the UI can say "not a Marp/OciDeck presentation" rather than a generic
      // "couldn't open".
      return outcome.failure == OpenFailure.notPresentation
          ? OpenResult.notAPresentation
          : OpenResult.unreadable;
    }
    // notifier disposed during the await
    if (!mounted) return OpenResult.unreadable;
    if (outcome.warnings.isNotEmpty) {
      _ref.read(chartDataWarningProvider.notifier).state = ChartDataWarning(
        outcome.warnings,
      );
    }
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
    if (FileService.looksLikeZipBytes(bytes)) {
      return _openPackageFromBytes(bytes, name, remoteOrigin: remoteOrigin);
    }
    if (bytes.length > FileService.maxDeckMarkdownBytes) {
      return OpenResult.unreadable;
    }
    final String raw;
    try {
      raw = utf8.decode(bytes);
    } on FormatException catch (e) {
      logWarning('TabsNotifier.openDeckFromBytes: not valid UTF-8', e);
      return OpenResult.unreadable;
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
  /// Retourneert `null` wanneer het pakket is opgehaald én verwerkt — ook als
  /// de veiligheidscontrole de inhoud blokkeert (dan toont de shell het alarm).
  /// Anders de reden waarom het pakket niet kon worden gelezen/uitgepakt.
  Future<ImportFailure?> importPackageFile(
    String zipPath, {
    String? homeDir,
  }) async {
    final dest = await _importDestDir(homeDir);
    final file = File(zipPath);
    if (await file.length() > FileService.maxPackageBytes) {
      return ImportFailure.tooLarge;
    }
    final bytes = await file.readAsBytes();
    final outcome = await _file.importPackageBytesDetailed(
      bytes,
      dest,
      onPassword: packagePasswordResolver,
    );
    final mdPath = outcome.mdPath;
    // Afbreken van de wachtwoordvraag is geen fout: geen melding tonen.
    if (outcome.failure == ImportFailure.encryptedCancelled) return null;
    if (mdPath == null) return outcome.failure;
    final result = await _openImported(mdPath);
    return _importHandled(result) ? null : ImportFailure.unsupported;
  }

  /// Haal een presentatie op via een URL (pakket of platte markdown) en open
  /// het in een tab. Zie [importPackageFile] voor de betekenis van de retour.
  Future<ImportFailure?> importFromUrl(String url, {String? homeDir}) async {
    final dest = await _importDestDir(homeDir);
    final outcome = await _file.importFromUrlDetailed(
      url,
      dest,
      onPassword: packagePasswordResolver,
    );
    final mdPath = outcome.mdPath;
    if (outcome.failure == ImportFailure.encryptedCancelled) return null;
    if (mdPath == null) return outcome.failure;
    final result = await _openImported(mdPath);
    if (result == OpenResult.opened && mounted) {
      // Herkomst voor de wolk-badge in recente presentaties.
      await _settings.setRecentFileOrigin(mdPath, url);
    }
    return _importHandled(result) ? null : ImportFailure.unsupported;
  }

  /// Web-variant van [importFromUrl]: haalt de presentatie in de browser op
  /// (CORS en de pagina-CSP bewaken het verkeer) en opent haar volledig in
  /// het geheugen — een `.ocideck`/zip-pakket wordt daarbij in het geheugen
  /// uitgepakt, met dezelfde omvangslimiet als de desktop-import.
  Future<OpenResult> importFromUrlWeb(String url) async {
    final bytes = await _file.fetchUrlBytes(
      url,
      maxBytes: FileService.maxPackageBytes,
      onConfirmProxy: proxyFallbackConfirm,
    );
    if (bytes == null || !mounted) return OpenResult.unreadable;
    // Zelfde kern als de web-picker en drag-drop: [openDeckFromBytes]. De URL
    // reist mee als [remoteOrigin] zodat de statusbalk de privacy-badge toont:
    // deze presentatie is van buiten het apparaat opgehaald.
    return openDeckFromBytes(bytes, url, remoteOrigin: url);
  }

  /// Gedeelde staart van elke import-flow (pakket/URL/WebDAV): open het
  /// geïmporteerde bestand en ruim de import-artefacten op wanneer dat niet
  /// lukte.
  Future<OpenResult> _openImported(String mdPath) async {
    final result = await openFileByPath(mdPath);
    if (result != OpenResult.opened) await _discardImportArtifacts(mdPath);
    return result;
  }

  /// "Verwerkt" betekent voor de bool-imports: geopend, óf geblokkeerd door de
  /// security-gate (de shell toont dan het alarm) — niet-leesbaar is `false`.
  static bool _importHandled(OpenResult result) =>
      result == OpenResult.opened || result == OpenResult.blocked;

  /// Download [entry] van de WebDAV-bron, haal het door de bestaande
  /// security-gate en open het in een tab. Het tabblad onthoudt zijn herkomst
  /// zodat "Opslaan naar Nextcloud" terug kan schrijven. Een netwerk-/auth-fout
  /// wordt als [WebdavException] doorgegeven aan de aanroeper.
  Future<OpenResult> openFromWebdav(
    WebdavService service,
    WebdavEntry entry, {
    String connectionId = '',
    String? homeDir,
  }) async {
    final dest = await _importDestDir(homeDir);
    final maxBytes = entry.isMarkdown
        ? FileService.maxDeckMarkdownBytes
        : FileService.maxPackageBytes;
    final downloaded = await service.download(
      entry.relativePath,
      maxBytes: maxBytes,
    );
    final bytes = downloaded.bytes;
    if (!mounted) return OpenResult.unreadable;
    final String? mdPath;
    if (entry.isMarkdown) {
      mdPath = await _file.importMarkdownBytes(bytes, dest, entry.name);
    } else {
      final outcome = await _file.importPackageBytesDetailed(
        bytes,
        dest,
        onPassword: packagePasswordResolver,
      );
      if (outcome.failure == ImportFailure.encryptedCancelled) {
        return OpenResult.passwordCancelled;
      }
      mdPath = outcome.mdPath;
    }
    if (mdPath == null) return OpenResult.unreadable;
    final result = await _openImported(mdPath);
    if (result != OpenResult.opened) return result;
    // De zojuist geopende deck zit in het huidige tabblad (zie openFileByPath).
    state.current?.webdavOrigin = WebdavOrigin(
      connectionId: connectionId,
      baseUrl: service.server.baseUrl,
      username: service.server.username,
      remotePath: entry.relativePath,
      // De versie die we nét ophaalden; hierop toetst een latere opslag.
      etag: downloaded.etag,
    );
    // Herkomst voor de wolk-badge in recente presentaties.
    await _settings.setRecentFileOrigin(
      mdPath,
      '${service.server.baseUrl} · ${entry.relativePath}',
    );
    if (mounted) state = state.copyWith(tabs: List.from(state.tabs));
    return OpenResult.opened;
  }

  /// Schrijf het deck van [tab] terug naar de WebDAV-bron op [targetPath]
  /// (relatief aan de wortelmap). Bij [DeckSaveFormat.ocideck] gaat er één
  /// pakketbestand omhoog; bij [DeckSaveFormat.flat] worden de pakket-leden
  /// (`.md` + assetmappen) los geüpload in dezelfde map. Werkt de herkomst van
  /// het tabblad bij. Gooit [WebdavException] bij een netwerk-/auth-fout.
  Future<void> saveToWebdav(
    TabInfo tab,
    WebdavService service, {
    required DeckSaveFormat format,
    required String targetPath,
    String connectionId = '',
    bool overwrite = false,
  }) async {
    final deck = tab.deckNotifier.currentState.deck;
    if (deck == null) return;
    // Alleen terugschrijven naar precies het bestand dat we ophaalden valt te
    // bewaken; voor elk ander doelpad hebben we geen versie om tegen te
    // toetsen, en koos de gebruiker het pad zelf.
    final origin = tab.webdavOrigin;
    final guard =
        (!overwrite &&
            origin != null &&
            origin.matchesServer(service.server) &&
            origin.remotePath == targetPath)
        ? origin.etag
        : null;
    String? savedEtag;
    if (format == DeckSaveFormat.ocideck) {
      final bytes = await _file.buildPackageBytes(deck);
      savedEtag = await service.upload(targetPath, bytes, ifMatch: guard);
    } else {
      final members = await _file.buildPackageMembers(deck);
      final dir = p.posix.dirname(targetPath);
      final mdBase = p.posix.basename(targetPath);
      // Het markdownbestand eerst; zie [saveToS3] voor waarom die volgorde telt.
      final ordered = [
        ...members.entries.where(_isRootMd),
        ...members.entries.where((e) => !_isRootMd(e)),
      ];
      for (final entry in ordered) {
        // Het pakket-markdownbestand heet naar de deck-titel; geef het op de
        // server de naam die de gebruiker koos. Assets behouden hun submap.
        final isRootMd = _isRootMd(entry);
        final remote = isRootMd
            ? p.posix.join(dir, mdBase)
            : p.posix.join(dir, entry.key);
        // Alleen het markdownbestand ís het deck; de assets ernaast hebben we
        // nooit opgehaald, dus daar valt niets te toetsen.
        final etag = await service.upload(
          remote,
          entry.value,
          ifMatch: isRootMd ? guard : null,
        );
        if (isRootMd) savedEtag = etag;
      }
    }
    tab.webdavOrigin = WebdavOrigin(
      // Een leeg id bij opslaan zou de herkomst van een geopend deck wissen;
      // val dan terug op wat er al stond.
      connectionId: connectionId.isEmpty
          ? (tab.webdavOrigin?.connectionId ?? '')
          : connectionId,
      baseUrl: service.server.baseUrl,
      username: service.server.username,
      remotePath: targetPath,
      // Vanaf nu is dít de versie waarop we verder werken. Gaf de server er
      // geen, dan blijft het `null` en is de volgende opslag onbewaakt — dat
      // is zichtbaar zo, en niet een gok die stil de guard uitzet.
      etag: savedEtag,
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

final chartDataWarningProvider = StateProvider<ChartDataWarning?>(
  (ref) => null,
);
