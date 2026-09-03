import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../collab/collab.dart' show CollabSession;
import '../models/asset_origin.dart';
import '../models/chart.dart';
import '../models/deck.dart';
import '../models/improvement_y01.dart';
import '../models/markdown_document.dart';
import '../models/settings.dart';
import '../models/seal_record.dart';
import '../models/slide.dart';
import '../models/storage_origin.dart';
import '../services/annotation_codec.dart';
import '../services/classification_enforcement_policy.dart';
import '../services/duplicate_service.dart';
import '../services/document_integrity.dart';
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
import 'document_provider.dart';
import 'editor_provider.dart';
import 'settings_provider.dart';
import 'asset_rights_module_provider.dart';
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
part 'tabs_provider_recovery.dart';

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
  final Map<int, StreamSubscription<Object?>> _subs = {};

  /// Laatst ge-autosavede deck per tab (op identiteit): het deck is immutable,
  /// dus zolang het object hetzelfde is, is er niets gewijzigd en kan de tick
  /// de volledige serialisatie + schrijfbeurt overslaan.
  final Map<int, Deck> _lastAutosavedDeck = {};
  final Map<int, String?> _lastAutosavedMarkdownDraft = {};

  /// Laatst weggeschreven documentbron per tabblad, zodat een tick die niets
  /// nieuws vindt de schrijfbeurt overslaat — de documenttegenhanger van
  /// [_lastAutosavedDeck].
  final Map<int, String> _lastAutosavedDocument = {};

  /// Duplicaat-melding maximaal één keer per paar per sessie, anders wordt
  /// elke her-open van hetzelfde bestand een herhaalde snackbar.
  final Set<String> _noticedDuplicatePairs = {};
  final DuplicateService _duplicates = DuplicateService();
  Timer? _autosaveTimer;
  int _nextId = 0;

  /// State voor part-extensies; `state` zelf is protected binnen deze klasse.
  TabsState get currentState => state;

  set _replacementState(TabsState value) => state = value;

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
      // Documenttabbladen kennen (nog) geen mem:-assets; hun bron is één string.
      final dn = tab.deckNotifierOrNull;
      if (dn == null || !dn.mounted) continue;
      dn.collectLiveMemoryAssetPaths(live);
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
    // #1953: een schrijffout naar de herstelmap mag niet stil blijven. De
    // eerste fout in een sessie meldt zich één keer in de UI.
    _recovery.onWriteError = (_) {
      if (mounted) _ref.read(recoveryWriteErrorProvider.notifier).state = true;
    };
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
    _lastAutosavedMarkdownDraft.remove(tab.id);
    _lastAutosavedDocument.remove(tab.id);
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
      content: DeckTabContent(deckNotifier, EditorNotifier()),
    );
    _subs[id] = deckNotifier.stream.listen((st) {
      if (!mounted) return;
      // Zodra een tabblad is opgeslagen (schoon), het herstelbestand wissen.
      // Schrijven gebeurt gebufferd door de periodieke autosave-tick.
      if (!(st.isOpen && (st.isDirty || _markdownDraftFor(tab) != null))) {
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
      // Een documenttabblad bewaart zijn eigen momentopname (byte-getrouwe bron,
      // geen deck-sidecars), zodat een crash óók niet-opgeslagen documenten
      // teruggeeft — net als een presentatie.
      final doc = tab.documentNotifier;
      if (doc != null) {
        _autosaveDocument(tab, doc, _recovery, _lastAutosavedDocument);
        continue;
      }
      // Zie TabInfo.label: een tab kan kortstondig een al-gedisposede
      // notifier dragen; die heeft niets meer te autosaven.
      final dn = tab.deckNotifierOrNull;
      if (dn == null || !dn.mounted) continue;
      final st = dn.currentState;
      if (st.isOpen) {
        final deck = st.deck!;
        final editor = tab.editorNotifier.currentState;
        final markdownDraft = _markdownDraftFor(tab);
        if (!st.isDirty && markdownDraft == null) continue;
        if (identical(_lastAutosavedDeck[tab.id], deck) &&
            _lastAutosavedMarkdownDraft[tab.id] == markdownDraft) {
          continue;
        }
        _recovery.save(
          _deckRecoverySnapshot(tab, st, dn, editor, markdownDraft),
        );
        _lastAutosavedDeck[tab.id] = deck;
        _lastAutosavedMarkdownDraft[tab.id] = markdownDraft;
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
      // Een document *ís* zijn bron: geen deck-parse, geen sidecars. Byte-getrouw
      // terug in een documenttabblad, gemarkeerd als (nog) niet opgeslagen.
      if (snap.kind == MarkdownKind.document) {
        // Fail-closed: een herstelbestand is dezelfde klasse invoer als een
        // bestand — bytes die later HTML/PDF/LaTeX worden. Een gewijzigd of
        // vervangen herstelbestand (crash, gedeelde machine, malware in de
        // gebruikersmap) mag de poort niet omzeilen die `openDocumentDetailed`
        // wél opzet. Zie #1643.
        final findings = MarkdownSafetyScanner.scan(snap.markdown);
        if (findings.isNotEmpty) {
          logWarning(
            'restoreRecovered: documentmomentopname geweigerd — uitvoerbare '
            'inhoud (${findings.length} bevinding(en))',
            snap.filePath,
          );
          if (mounted) {
            _ref
                .read(importSecurityAlarmProvider.notifier)
                .state = ImportSecurityAlarm(
              path: snap.filePath ?? snap.label,
              findings: findings,
            );
          }
          unreadable++;
          continue;
        }
        final tab = _createDocumentTab(
          MarkdownDocument.parse(snap.markdown),
          filePath: snap.filePath,
          recoveryId: snap.id,
        );
        tab.documentNotifier!.markDirty();
        restored.add(tab);
        continue;
      }
      final deck = _deckFromRecoverySnapshot(snap, _md);
      if (deck == null) {
        // Niet weggooien. `parseDeck` vangt zijn eigen fouten af juist omdát hij
        // in de praktijk struikelt, en een crash ín de parser is een van de
        // waarschijnlijkere redenen dat deze momentopname er überhaupt ligt.
        // Eerst wissen en dan pas kijken of het lukte, betekende dat één klik op
        // "Herstellen" het enige exemplaar van andermans avond opruimde.
        unreadable++;
        logWarning('restoreRecovered: momentopname onleesbaar', snap.filePath);
        continue;
      }
      // Hergebruik de sleutel van de momentopname. Het bestand dat er al ligt ís
      // daarmee meteen de herstelkopie van dit tabblad, in plaats van dat het
      // wordt weggegooid en de nieuwe pas bij de volgende autosave-tik ontstaat.
      // Dat gat duurde tot [_autosaveInterval] — en juist in die seconden crasht
      // een app die zojuist opnieuw dezelfde inhoud heeft geopend.
      final tab = _createTab(recoveryId: snap.id);
      tab.deckNotifier.loadDeck(deck, filePath: snap.filePath);
      tab.deckNotifier.markDirty(); // herstelde inhoud is nog niet opgeslagen
      _applyRecoveredMarkdownDraft(tab, snap, deck);
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
    TlpLevel tlp = TlpLevel.none,
    List<Slide>? slides,
    String improvementFramework = '',
    String improvementY01 = '',
    ImprovementY01Metric? improvementY01Metric,
  }) {
    final tab = state.current;
    if (tab == null) return;
    tab.deckNotifier.newDeck(
      title,
      tlp: tlp,
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
    TlpLevel tlp = TlpLevel.none,
    List<Slide>? slides,
    String improvementFramework = '',
    String improvementY01 = '',
    ImprovementY01Metric? improvementY01Metric,
    String? projectPath,
  }) {
    final tab = _createTab();
    tab.deckNotifier.newDeck(
      title,
      tlp: tlp,
      slides: slides,
      improvementFramework: improvementFramework,
      improvementY01: improvementY01,
      improvementY01Metric: improvementY01Metric,
      projectPath: projectPath,
    );
    tab.editorNotifier.select(0);
    final newTabs = [...state.tabs, tab];
    state = state.copyWith(tabs: newTabs, selectedIndex: newTabs.length - 1);
  }

  /// Open een bestandskiezer en laad de keuze.
  ///
  /// Loopt door het volledige [openFileByPath]: veiligheidsscan,
  /// dubbele-open-detectie, grafiekdata-waarschuwingen én de router die een
  /// niet-marp `.md` als plat document opent i.p.v. het stil te weigeren.
  Future<void> openFile({String? initialDirectory}) async {
    final path = await _file.pickMarkdownFile(
      initialDirectory: initialDirectory,
    );
    if (path == null) return;
    await openFileByPath(path);
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
    final existing = _indexOfOpenPath(this, path);
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
      // Geen Marp-deck? Router, geen muur (DOCUMENT_MODE.md §2): open als document.
      if (outcome.failure == OpenFailure.notPresentation) {
        return _openAsDocument(path);
      }
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

  /// Open [path] als plat document in een nieuw tabblad (deck-pad gaf
  /// `notPresentation`: veilig, maar geen Marp-deck).
  Future<OpenResult> _openAsDocument(String path) async {
    final result = await _file.openDocumentDetailed(path);
    if (!mounted) return OpenResult.unreadable;
    final document = result.document;
    if (document == null) {
      return _openFailureResult(_ref, mounted, result.failure);
    }
    _placeDocumentTab(document, filePath: path);
    await _settings.addRecentFile(path, kind: MarkdownKind.document);
    return OpenResult.opened;
  }

  /// Maak een nieuw, leeg document in een nieuw tabblad. Nog niet op schijf:
  /// het eerste Cmd/Ctrl+S valt terug op 'Opslaan als…' (kiest dan een pad).
  /// Spiegel van [newDeckInNewTab] voor de documentmodus.
  void newDocument() {
    _placeDocumentTab(MarkdownDocument.parse(''));
  }

  /// Open [source] als plat document in een NIEUW tabblad — een kopie, nog
  /// zonder bestandspad. Voor de conversie presentatie → document
  /// (DOCUMENT_MODE.md §11.3): het originele deck blijft ongemoeid, en er reist
  /// geen zegel mee — een document kent er geen. [projectPath] draagt de map
  /// van het originele deck mee, zodat afbeeldingsverwijzingen blijven
  /// werken (#1646).
  void newDocumentFromMarkdown(String source, {String? projectPath}) {
    _placeDocumentTab(MarkdownDocument.parse(source), projectPath: projectPath);
  }

  /// Bouwt een documenttabblad rond [document] en zet het naast de bestaande
  /// (geselecteerd). Een verse [DocumentNotifier] met een herstelabonnement dat
  /// de kopie wist zodra het tabblad schoon is — gedeeld door het openen van een
  /// `.md` en het maken van een nieuw document.
  void _placeDocumentTab(
    MarkdownDocument document, {
    String? filePath,
    String? projectPath,
  }) {
    final tab = _createDocumentTab(
      document,
      filePath: filePath,
      projectPath: projectPath,
    );
    state = state.copyWith(
      tabs: [...state.tabs, tab],
      selectedIndex: state.tabs.length,
    );
  }

  /// Bouwt (zonder te plaatsen) een documenttabblad met zijn herstelabonnement
  /// dat de kopie wist zodra het tabblad schoon is. [recoveryId] hergebruikt de
  /// sleutel van een bestaande herstelkopie (zie [restoreRecovered]); zonder
  /// krijgt het tabblad een verse. De deck-tegenhanger is [_createTab].
  TabInfo _createDocumentTab(
    MarkdownDocument document, {
    String? filePath,
    String? recoveryId,
    String? projectPath,
  }) {
    final id = _nextId++;
    final key = recoveryId ?? _uuid.v4();
    final notifier = DocumentNotifier()
      ..loadDocument(document, filePath: filePath, projectPath: projectPath);
    _subs[id] = notifier.stream.listen((st) {
      if (!mounted) return;
      if (!(st.isOpen && st.isDirty)) _recovery.discard(key);
      state = state.copyWith(tabs: List.from(state.tabs));
    });
    return TabInfo(
      id: id,
      recoveryId: key,
      content: DocumentTabContent(notifier),
    );
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
    // Hergebruik alleen een leeg *presentatie*-tabblad; een leeg documenttabblad
    // (mogelijk zodra nieuw-document bestaat) is een andere soort en zou op de
    // compat-getter gooien.
    if (current != null &&
        !current.isOpen &&
        current.deckNotifierOrNull != null) {
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

  /// Open een deck (of plat document) uit in-memory bytes — het open-pad voor
  /// web, waar de file-picker, drag-drop én URL-import geen pad maar inhoud
  /// aanleveren. Een `.ocideck`/zip-pakket wordt volledig in het geheugen
  /// uitgepakt ([_openPackageFromBytes]); platte markdown gaat door dezelfde
  /// fail-closed security-gate als [openFileByPath]. Er is geen TOCTOU-gat,
  /// want gescand en geparsed wordt exact dezelfde in-memory string. Ontbreekt
  /// `marp: true`, dan routeert deze methode — net als [openFileByPath] —
  /// door naar [newDocumentFromMarkdown] i.p.v. het stil te weigeren (#1637).
  /// Het tabblad krijgt geen bestandspad, dus opslaan wordt een download.
  /// [name] labelt het importalarm en de logregels (bestandsnaam of URL).
  Future<OpenResult> openDeckFromBytes(
    Uint8List bytes,
    String name, {
    String? remoteOrigin,
  }) async {
    _clearOpenFailure(_ref, mounted);
    if (FileService.looksLikeZipBytes(bytes)) {
      return _openPackageFromBytes(
        this,
        bytes,
        name,
        remoteOrigin: remoteOrigin,
      );
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
    if (deck == null) {
      // Geen Marp-deck? Router, geen muur — spiegelt [openFileByPath]: een
      // plat `.md` zonder `marp: true` openen als document i.p.v. het stil te
      // weigeren (#1637). De veiligheidsscan is al gepasseerd in
      // [_gateAndParseContent] (anders was dit [OpenResult.blocked]).
      if (gated.failure == OpenResult.notAPresentation) {
        if (!mounted) return OpenResult.unreadable;
        newDocumentFromMarkdown(raw);
        return OpenResult.opened;
      }
      return gated.failure;
    }
    if (!mounted) return OpenResult.unreadable;
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

  /// Selecteer een bestaand tabblad; ongeldige indices veranderen niets.
  void selectTab(int index) => _selectTab(this, index);

  /// Sluit een tabblad en ruim daarna alle niet meer gebruikte webassets op.
  void closeTab(int index) => _closeTab(this, index);
}

void _selectTab(TabsNotifier notifier, int index) {
  final current = notifier.currentState;
  if (index >= 0 && index < current.tabs.length) {
    notifier._replacementState = current.copyWith(selectedIndex: index);
  }
}

void _closeTab(TabsNotifier notifier, int index) {
  final current = notifier.currentState;
  if (current.tabs.length == 1) {
    final tab = current.tabs.first;
    notifier._recovery.discard(tab.recoveryId);
    // Het enige overblijvende tabblad wordt gereset (niet verwijderd), zodat de
    // app altijd één tabblad houdt. Een presentatie reset via closeDeck(); een
    // documenttabblad heeft geen deckNotifier en gooit daarop, dus routeer op
    // soort (#1636).
    switch (tab.content) {
      case DeckTabContent(:final deckNotifier):
        deckNotifier.closeDeck();
      case DocumentTabContent(:final documentNotifier):
        documentNotifier.closeDocument();
    }
    notifier.refreshTabs();
    notifier.sweepWebAssets();
    return;
  }
  final tab = current.tabs[index];
  notifier._recovery.discard(tab.recoveryId);
  notifier._disposeTab(tab);
  final newTabs = List<TabInfo>.from(current.tabs)..removeAt(index);
  final newSelected = index >= newTabs.length ? newTabs.length - 1 : index;
  notifier._replacementState = current.copyWith(
    tabs: newTabs,
    selectedIndex: newSelected,
  );
  notifier.sweepWebAssets();
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
/// Index van het tabblad waarin het bestand met [path] al open is, of `null`.
/// Vergelijkt genormaliseerde absolute paden zodat een relatief pad en het
/// volledige pad naar hetzelfde bestand hetzelfde tabblad raken. Top-level (leest
/// via de publieke `currentState`) om de klassenratchet te ontlasten.
int? _indexOfOpenPath(TabsNotifier n, String path) {
  final target = p.canonicalize(path);
  final tabs = n.currentState.tabs;
  for (var i = 0; i < tabs.length; i++) {
    // Soort-agnostisch: een al open document telt net zo goed mee als een deck.
    final open = tabs[i].openFilePath;
    if (open != null && open.isNotEmpty && p.canonicalize(open) == target) {
      return i;
    }
  }
  return null;
}

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

/// De ingestelde thuismap die bij de laatste import onbereikbaar bleek (bv. een
/// niet-aangekoppeld of alleen-lezen volume), of null. Het importpad valt in dat
/// geval terug op de documentenmap zodat de presentatie tóch opent
/// ([TabsImport._importDestDir]); de shell leest dit en meldt de terugval
/// niet-blokkerend, dan terug op null — zelfde patroon als
/// [duplicateCopyNoticeProvider].
final importHomeUnavailableProvider = StateProvider<String?>((ref) => null);

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

/// Het zegel van een geopend deck klopt niet meer met de inhoud — het deck is
/// bewerkt ná het verzegelen. Read-only waarschuwing: het deck mag nog steeds
/// openen, maar de gebruiker moet weten dat het zegel niet meer geldig is.
class SealTamperWarning {
  /// Niet-const, om dezelfde reden als [ChartDataWarning].
  SealTamperWarning();
}

final sealTamperWarningProvider = StateProvider<SealTamperWarning?>(
  (ref) => null,
);

final chartDataWarningProvider = StateProvider<ChartDataWarning?>(
  (ref) => null,
);

/// #1953: het crashherstel kon zijn snapshot niet naar schijf schrijven. Eén
/// keer per sessie (of per herstel na een geslaagde schrijfbeurt) — niet elke
/// 25 s herhalen. De schil luistert en toont een snackbar.
final recoveryWriteErrorProvider = StateProvider<bool>((ref) => false);

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
  if (outcome.integrity == IntegrityStatus.changed) {
    ref.read(sealTamperWarningProvider.notifier).state = SealTamperWarning();
  }
}
