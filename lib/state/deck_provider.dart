import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/annotation.dart';
import '../models/asset_origin.dart';
import '../models/checklist_spec.dart';
import '../models/deck.dart';
import '../models/provenance_signature.dart';
import '../models/improvement_y01.dart';
import '../models/document_signature.dart';
import '../models/scope_matrix_spec.dart';
import '../models/settings.dart';
import '../models/seal_record.dart';
import '../models/slide.dart';
import '../models/used_tool.dart';
import '../services/ai_alt_text_cleanup.dart';
import '../services/annotation_codec.dart';
import '../services/checklist_templates.dart';
import '../services/document_integrity.dart';
import '../services/rich_text_chapters.dart';
import '../services/finding_context_score.dart';
import '../services/finding_numbering.dart';
import '../models/chart.dart';
import '../services/management_system_artefacts.dart';
import '../services/management_system_progress.dart';
import '../services/menu_blocks.dart';
import '../services/scope_coverage.dart';
import '../services/slide_anchors.dart';
import '../services/file_service.dart';
import '../services/image_service.dart';
import '../services/markdown_service.dart';
import '../services/quality_autofix.dart';
import '../services/user_notes_codec.dart';
import '../platform/platform_features.dart';
import '../utils/bullet_fixes.dart';
import '../utils/table_pagination.dart';
import '../utils/log.dart';
import '../utils/page_scoped_notes.dart';
import 'settings_provider.dart';
import '../services/privacy/dismissal_codec.dart';

part 'deck_provider_markdown.dart';
part 'deck_provider_ai.dart';
part 'deck_provider_miauw.dart';
part 'deck_provider_checklist.dart';
part 'deck_provider_managementsysteem.dart';
part 'deck_provider_auto.dart';
part 'deck_provider_slides.dart';

// ── Service providers ────────────────────────────────────────────────────────

final markdownServiceProvider = Provider<MarkdownService>(
  (_) => MarkdownService(),
);
final imageServiceProvider = Provider<ImageService>((ref) {
  return ImageService(
    languageCode: () => ref.read(settingsProvider).languageCode,
  );
});
final fileServiceProvider = Provider<FileService>((ref) {
  return FileService(
    ref.read(markdownServiceProvider),
    ref.read(imageServiceProvider),
    () => ref.read(settingsProvider).themeProfile,
    languageCode: () => ref.read(settingsProvider).languageCode,
    homeDirectory: () => ref.read(settingsProvider).homeDirectory,
    libraryPaths: () => ref.read(settingsProvider).libraryPaths,
  );
});

// ── Deck state ───────────────────────────────────────────────────────────────

class DeckState {
  final Deck? deck;
  final bool isDirty;
  final String? filePath;
  final String? error;

  /// Op web (geen schrijfbaar bestandssysteem) is opslaan een download; de
  /// browser geeft geen pad terug. We onthouden hier de bestandsnaam die we
  /// lieten downloaden, zodat de statusbalk die kan tonen i.p.v. "nog niet
  /// opgeslagen". Op desktop blijft dit null en telt [filePath].
  final String? downloadName;

  /// Gezet wanneer dit deck via de web-URL-import/`?deck=`-deeplink van een
  /// externe URL is opgehaald (niet van schijf gekozen). De statusbalk toont
  /// dan een privacy-badge: het openen van zo'n link heeft die externe server
  /// benaderd. Null voor lokaal geopende/nieuwe decks.
  final String? remoteOrigin;

  /// Of er een ongedaan-maken- resp. opnieuw-uitvoeren-stap beschikbaar is.
  /// Onderdeel van de state zodat de toolbarknoppen vanzelf mee-enabelen.
  final bool canUndo;
  final bool canRedo;

  /// De editor gebruikt dit om zijn tekstvelden te verversen wanneer de inhoud
  /// van de huidige slide buiten die velden om verandert; ze synchroniseren
  /// anders alleen op slide-id. Telt op bij undo/redo en bij
  /// [DeckNotifier.refreshEditorFields].
  final int revision;

  const DeckState({
    this.deck,
    this.isDirty = false,
    this.filePath,
    this.error,
    this.downloadName,
    this.remoteOrigin,
    this.canUndo = false,
    this.canRedo = false,
    this.revision = 0,
  });

  bool get hasUnsavedChanges => isDirty;
  bool get isOpen => deck != null;

  DeckState copyWith({
    Deck? deck,
    bool? isDirty,
    String? filePath,
    String? error,
    String? downloadName,
    String? remoteOrigin,
    bool? canUndo,
    bool? canRedo,
    int? revision,
    bool clearError = false,
    bool clearFilePath = false,
  }) {
    return DeckState(
      deck: deck ?? this.deck,
      isDirty: isDirty ?? this.isDirty,
      filePath: clearFilePath ? null : (filePath ?? this.filePath),
      error: clearError ? null : (error ?? this.error),
      downloadName: downloadName ?? this.downloadName,
      remoteOrigin: remoteOrigin ?? this.remoteOrigin,
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      revision: revision ?? this.revision,
    );
  }
}

/// Whether [DeckNotifier.splitSlide] would actually split [slide]: a bullet
/// slide type with at least two bullets to divide. Mirrors the guards in
/// `_splitSlide`, so the UI can offer a "split" action exactly when it works.
///
/// Welke types doorlopende bullets tonen staat in de registry naast de enum
/// ([SlideTypeMeta.bulletColumns]) en niet meer als uitgeschreven lijst hier:
/// een nieuw bullettype is dan overal tegelijk splitsbaar, in plaats van in de
/// paneelknop wel en in de slidestrook niet.
bool canSplitSlide(Slide slide) => switch (slide.type.bulletColumns) {
  BulletColumns.none => false,
  BulletColumns.one => slide.bullets.length >= 2,
  BulletColumns.two => slide.bullets.length >= 2 || slide.bullets2.length >= 2,
};

// ── DeckNotifier ─────────────────────────────────────────────────────────────

/// Holds the deck currently being edited, and is the only thing allowed to
/// change it.
///
/// Every mutation goes through a method here rather than through a slide
/// object, and that is deliberate: **undo/redo is built on whole-deck snapshots
/// taken at this boundary.** A caller that reaches around this class and edits
/// a [Slide] in place produces a change the user cannot undo, and a preview
/// that does not repaint.
///
/// `revision` increments on every accepted change and is what the editor
/// column watches to rebuild after an undo — it is not a document version and
/// never reaches disk.
///
/// Saving is not here: this class marks the deck dirty and [FileService] writes
/// it, driven by the tab layer. The class is split across
/// `deck_provider_*.dart` by subject (slides, markdown, checklist, MIAUW, AI,
/// auto); those are the same class.
class DeckNotifier extends StateNotifier<DeckState> {
  final MarkdownService _md;
  final FileService _file;

  /// Snapshots van eerdere/latere deck-versies voor ongedaan maken/opnieuw.
  /// Decks zijn immutable (copyWith), dus dit zijn goedkope referenties.
  final List<Deck> _undoStack = [];
  final List<Deck> _redoStack = [];
  static const _maxHistory = 80;

  /// Guards against two save triggers (the toolbar, status bar and several
  /// Cmd/Ctrl+S key bindings all call [save]) writing the same file at once.
  bool _saving = false;

  /// #1952: een tweede Cmd/Ctrl+S tijdens een lopende opslag werd stilletjes
  /// genegeerd. Nu onthouden we hem en slaan opnieuw op nadat de eerste klaar
  /// is — maar alleen als het tabblad nog vuil is (de eerste opslag kan al
  /// schoon hebben gemaakt, of de gebruiker kan ondertussen hebben getypt).
  bool _saveQueued = false;

  /// Snelle, opeenvolgende bewerkingen (zoals typen) worden samengevoegd tot
  /// één ongedaan-maken-stap zolang ze dezelfde [_lastCoalesceKey] delen en
  /// binnen dit tijdvenster vallen.
  static const _coalesceWindow = Duration(milliseconds: 700);
  DateTime? _lastMutationAt;
  String? _lastCoalesceKey;

  DeckNotifier(this._md, this._file) : super(const DeckState());

  /// Idempotent: gedeelde eigendom (TabsNotifier houdt de notifier, de
  /// ProviderScope disposet 'm) maakt een dubbele dispose mogelijk. #1478 nam
  /// de trigger weg; deze no-op vangt elke resterende teardown-race fail-safe af.
  @override
  void dispose() {
    if (mounted) super.dispose();
  }

  DeckState get currentState => state;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Laat de editorvelden hun inhoud opnieuw uit het deck lezen.
  ///
  /// Die velden cachen in eigen [TextEditingController]s en verversen alleen
  /// wanneer [DeckState.revision] verandert. Een wijziging die búiten de editor
  /// om binnenkomt — live een tabelcel bijwerken of een checklist afvinken
  /// tijdens het presenteren — laat ze dus op de oude tekst staan. Erger dan
  /// verwarrend: de eerstvolgende toetsaanslag in zo'n veld schrijft de hele
  /// gecachete inhoud terug en draait de live bewerking stil terug.
  ///
  /// Het deck zelf blijft ongemoeid, dus dit is geen mutatie: geen
  /// ongedaan-stap, geen coalescing, geen 'gewijzigd'-vlag.
  void refreshEditorFields() {
    state = state.copyWith(revision: state.revision + 1);
  }

  /// Aangeroepen wanneer een `mem:`-asset (webversie) niet meer nodig hóéft te
  /// zijn: na het verwijderen van dia's en na het opslaan. [TabsNotifier] hangt
  /// hier de sweep aan — die is de enige die alle tabbladen én het klembord
  /// overziet, dus deze notifier weet zelf niet welke assets weg mogen; hij
  /// meldt alleen dát het moment daar is.
  void Function()? onSweepWebAssets;

  /// Aangeroepen na een opslag waarbij één of meer grafieken hun cijfers niet in
  /// hun databestand kwijt konden. Die cijfers staan dan nergens meer: de
  /// markdown draagt alleen nog de verwijzing.
  ///
  /// Zelfde constructie als [onSweepWebAssets] — deze notifier heeft geen `Ref`,
  /// en [TabsNotifier] wel; die zet er [chartDataWarningProvider] mee, waarna de
  /// shell het meldt.
  void Function(List<String> sources)? onChartDataWarnings;

  /// Elk `mem:`-pad dat dit tabblad nog terug kan halen: de huidige dia's plus
  /// alles in de ongedaan-/opnieuw-stapel. Een verwijderde dia leeft in de
  /// ongedaan-stapel voort, dus zijn afbeelding mag pas weg als die stap dat ook
  /// is. Het logo van elk van die deck-versies telt mee.
  void collectLiveMemoryAssetPaths(Set<String> into) {
    for (final deck in [
      if (state.deck != null) state.deck!,
      ..._undoStack,
      ..._redoStack,
    ]) {
      into.addAll(deckMemoryAssetPaths(deck));
    }
  }

  void _clearHistory() {
    _undoStack.clear();
    _redoStack.clear();
    _lastMutationAt = null;
    _lastCoalesceKey = null;
  }

  /// Start a fresh deck. [slides] may provide pre-built template content;
  /// otherwise this creates the classic single title slide.
  void newDeck(
    String title, {
    String theme = 'ocideck',
    TlpLevel tlp = TlpLevel.none,
    List<Slide>? slides,
    String improvementFramework = '',
    String improvementY01 = '',
    ImprovementY01Metric? improvementY01Metric,
    String? projectPath,
  }) {
    final y01 =
        improvementY01Metric ??
        (improvementY01.isEmpty
            ? ImprovementY01Metric.empty
            : ImprovementY01Metric(name: improvementY01));
    final deck = Deck(
      title: title,
      theme: theme,
      tlp: tlp,
      themeProfile: _file.currentThemeProfile,
      improvementFramework: improvementFramework,
      improvementY01Metric: y01,
      slides: slides ?? [Slide.create(SlideType.title).copyWith(title: title)],
      projectPath: projectPath,
    );
    _clearHistory();
    state = DeckState(deck: deck, isDirty: true);
  }

  /// Load a deck that was already parsed (used by the tab manager). Styling is
  /// not taken from the deck/markdown but from the active style profile, so an
  /// opened or recovered deck always picks up the current look.
  void loadDeck(
    Deck deck, {
    String? filePath,
    String? remoteOrigin,
    bool isDirty = false,
  }) {
    final resolvedDeck = deck.copyWith(
      themeProfile: _file.activeProfileFor(projectPath: deck.projectPath),
    );
    _clearHistory();
    state = DeckState(
      deck: resolvedDeck,
      filePath: filePath,
      remoteOrigin: remoteOrigin,
      isDirty: isDirty,
    );
  }

  Future<void> openDeck({String? initialDirectory}) async {
    final path = await _file.pickMarkdownFile(
      initialDirectory: initialDirectory,
    );
    if (path == null) return;
    final deck = await _file.openDeck(path);
    if (deck == null) {
      state = state.copyWith(error: 'Kon presentatie niet openen:\n$path');
      return;
    }
    _clearHistory();
    state = DeckState(deck: deck, filePath: path, isDirty: false);
  }

  Future<bool> save({String? initialDirectory}) async {
    // Wijs een tweede gelijktijdige opslag af — twee schrijfbeurten door
    // elkaar is erger — maar onthoud hem: ná de eerste opslag opnieuw
    // proberen als het tabblad nog vuil is (#1952).
    if (_saving) {
      _saveQueued = true;
      return false;
    }
    _saving = true;
    try {
      // Web kent geen schrijfbaar bestandssysteem: opslaan is daar de
      // gegenereerde markdown als bestand laten downloaden.
      if (!supportsLocalProjectFolders) return _saveAsDownload();
      if (state.filePath != null) {
        return await _saveToPath(state.filePath!);
      } else {
        return await saveAs(initialDirectory: initialDirectory);
      }
    } finally {
      _saving = false;
      if (_saveQueued) {
        _saveQueued = false;
        // ponytail: unawaited — de aanroeper van de eerste save heeft zijn
        // resultaat al; de herhaling is een gunst, geen belofte aan hem.
        if (state.isDirty) unawaited(save(initialDirectory: initialDirectory));
      }
    }
  }

  /// Web-opslagpad: start een browserdownload van de deck-markdown. Het deck
  /// wordt daarna als schoon gemarkeerd — het bestand is aan de gebruiker
  /// overhandigd; verdere wijzigingen maken het gewoon weer dirty. [filePath]
  /// blijft null, zodat elke volgende save opnieuw een download start; de
  /// gedownloade bestandsnaam onthouden we wél voor de statusbalk.
  ///
  /// #1954: een deck met `mem:`-afbeeldingen reist niet mee in een kale `.md`.
  /// Het tabblad vuil houden na zo'n download, zodat de waarschuwing bij de
  /// volgende save opnieuw komt en de afsluitlus opnieuw vraagt — anders denkt
  /// de gebruiker dat hij opgeslagen heeft, sluit de tab, en is het beeld kwijt.
  bool _saveAsDownload() {
    final deck = state.deck;
    if (deck == null) return false;
    final name = _file.downloadDeckAsFile(deck);
    if (name == null) {
      state = state.copyWith(error: 'Opslaan als download mislukt.');
      return false;
    }
    final carriesMemAssets = deckCarriesMemoryAssets(deck);
    state = state.copyWith(isDirty: carriesMemAssets, downloadName: name);
    // Opslaan is een natuurlijk opschoonmoment: een afbeelding die is vervangen
    // laat zijn oude mem:-bytes achter zonder dat er een dia is verwijderd.
    // Bij mem:-assets niet vegen: die zijn nu juist nog nodig.
    if (!carriesMemAssets) onSweepWebAssets?.call();
    return true;
  }

  Future<bool> saveAs({String? initialDirectory}) async {
    final deck = state.deck;
    if (deck == null) return false;
    final undoLenBefore = _undoStack.length;
    final String? path;
    var incomplete = false;
    try {
      final written = await _file.saveDeckAsDetailed(
        deck,
        initialDirectory: initialDirectory,
      );
      path = written.path;
      incomplete = _reportChartWarnings(written.chartWarnings);
    } catch (e, s) {
      logError('DeckNotifier.saveAs: write deck', e, s);
      // Keep isDirty so the work still counts as unsaved.
      state = state.copyWith(error: 'Opslaan mislukt:\n$e');
      return false;
    }
    if (path == null) return false; // user cancelled the picker
    // The write succeeded; re-read to pick up the normalised on-disk form. If
    // that read fails the data is still safely persisted, so keep the in-memory
    // deck and mark it clean, but surface the anomaly instead of hiding it.
    // Not "trusted": once it is on disk it could have been changed, so the
    // re-read is scanned like any other open. Our own decks are clean data and
    // pass; only a tampered file on disk would be refused — which is correct.
    final reopened = await _file.openDeck(path);
    // Dezelfde race als in [_saveToPath], nu over twee wachtpunten: nieuwer
    // getypt werk blijft staan en blijft vuil.
    //
    // De identity-check (`identical`) is te streng: een state-vervanging die
    // geen inhoudswijziging is (bv. een copyWith voor themeProfile) maakt hem
    // false, waarna het deck onterecht vuil blijft. We vangen dat af door ook
    // naar de undo-stapel te kijken: is die niet gegroeid, dan was er geen
    // echte bewerking (#1473).
    final deckChanged = !identical(state.deck, deck);
    final userEdited = deckChanged && _undoStack.length > undoLenBefore;
    final settled = userEdited ? state.deck : (reopened ?? deck);
    if (reopened == null) {
      logWarning('DeckNotifier.saveAs: saved file could not be re-read', path);
      state = state.copyWith(
        deck: settled,
        filePath: path,
        isDirty: userEdited || incomplete,
        error:
            'Opgeslagen, maar het bestand kon niet opnieuw worden gelezen:\n$path',
      );
    } else {
      state = state.copyWith(
        deck: settled,
        filePath: path,
        isDirty: userEdited || incomplete,
      );
    }
    return true;
  }

  /// Meld grafieken die hun cijfers niet naar hun databestand kwijt konden.
  /// Alleen wanneer er iets te melden is — een lege lijst is het normale geval.
  /// Geeft terug of er waarschuwingen waren (#1950: dan blijft het tabblad vuil).
  bool _reportChartWarnings(List<String> sources) {
    if (sources.isNotEmpty) onChartDataWarnings?.call(sources);
    return sources.isNotEmpty;
  }

  Future<bool> _saveToPath(String path) async {
    final deck = state.deck;
    if (deck == null) return false;
    final undoLenBefore = _undoStack.length;
    final Deck savedDeck;
    var incomplete = false;
    try {
      final written = await _file.saveDeckDetailed(deck, path);
      savedDeck = written.deck;
      incomplete = _reportChartWarnings(written.chartWarnings);
    } catch (e, s) {
      logError('DeckNotifier._saveToPath: write deck', e, s);
      // Keep isDirty so the work still counts as unsaved.
      state = state.copyWith(error: 'Opslaan mislukt:\n$path\n$e');
      return false;
    }
    // Doorgetypt tijdens het schrijven? Dan is [state.deck] nieuwer dan wat er
    // zojuist op schijf belandde. Terugzetten gooit dat werk stil weg, en
    // "schoon" melden wist ook de herstelkopie — het bestaat dan nergens meer.
    //
    // De identity-check is te streng voor state-vervangingen die geen
    // inhoudswijziging zijn (bv. copyWith voor themeProfile); we vergelijken
    // ook de undo-stapel (#1473).
    final deckChanged = !identical(state.deck, deck);
    final userEdited = deckChanged && _undoStack.length > undoLenBefore;
    if (userEdited) return true;
    state = state.copyWith(deck: savedDeck, isDirty: incomplete);
    return true;
  }

  void closeDeck() {
    _clearHistory();
    state = const DeckState();
  }

  // ── Zoeken & vervangen ─────────────────────────────────────────────────────

  /// Tel hoe vaak [query] in alle tekstvelden van de presentatie voorkomt.
  int countMatches(String query, {bool caseSensitive = false}) {
    final deck = state.deck;
    if (deck == null || query.isEmpty) return 0;
    final pattern = _searchPattern(query, caseSensitive);
    var total = 0;
    for (final slide in deck.slides) {
      for (final field in _searchableFields(slide)) {
        total += pattern.allMatches(field).length;
      }
    }
    return total;
  }

  /// Vervang alle voorkomens van [query] door [replacement] in elke slide.
  /// Geeft het aantal vervangingen terug; één ongedaan-maken-stap.
  int replaceAll(
    String query,
    String replacement, {
    bool caseSensitive = false,
  }) {
    final deck = state.deck;
    if (deck == null || query.isEmpty) return 0;
    final pattern = _searchPattern(query, caseSensitive);

    var total = 0;
    String sub(String s) {
      if (s.isEmpty) return s;
      total += pattern.allMatches(s).length;
      return s.replaceAll(pattern, replacement);
    }

    final slides = [
      for (final s in deck.slides)
        s.copyWith(
          title: sub(s.title),
          subtitle: sub(s.subtitle),
          bullets: [for (final b in s.bullets) sub(b)],
          bullets2: [for (final b in s.bullets2) sub(b)],
          columnTitle1: sub(s.columnTitle1),
          columnTitle2: sub(s.columnTitle2),
          quote: sub(s.quote),
          quoteAuthor: sub(s.quoteAuthor),
          customMarkdown: sub(s.customMarkdown),
          imageCaption: sub(s.imageCaption),
          imageCaption2: sub(s.imageCaption2),
          notes: sub(s.notes),
          tableRows: [
            for (final row in s.tableRows) [for (final c in row) sub(c)],
          ],
        ),
    ];

    if (total > 0) _mutate(deck.copyWith(slides: slides));
    return total;
  }

  /// Alle doorzoekbare tekstvelden van een slide.
  Iterable<String> _searchableFields(Slide s) => [
    s.title,
    s.subtitle,
    ...s.bullets,
    ...s.bullets2,
    s.columnTitle1,
    s.columnTitle2,
    s.quote,
    s.quoteAuthor,
    s.customMarkdown,
    s.imageCaption,
    s.imageCaption2,
    s.notes,
    for (final row in s.tableRows) ...row,
  ];

  /// Zoekpatroon dat letterlijke tekst matcht (hoofdletter-(on)gevoelig).
  Pattern _searchPattern(String query, bool caseSensitive) {
    return caseSensitive
        ? query
        : RegExp(RegExp.escape(query), caseSensitive: false);
  }

  void updateMeta({String? title, String? theme, bool? paginate}) {
    final deck = state.deck;
    if (deck == null) return;
    _mutate(
      deck.copyWith(title: title, theme: theme, paginate: paginate),
      coalesceKey: 'meta',
    );
  }

  void updateInfo({
    String? title,
    String? author,
    String? organization,
    String? version,
    String? date,
    String? description,
    String? keywords,
    String? language,
    List<String>? standardsUsed,
    List<UsedTool>? toolsUsed,
    TlpLevel? tlp,
    int? presentationTargetSeconds,
    bool? showRehearsalSummary,
    bool? playOnly,
  }) {
    final deck = state.deck;
    if (deck == null) return;
    _mutate(
      deck.copyWith(
        title: title,
        author: author,
        organization: organization,
        version: version,
        date: date,
        description: description,
        keywords: keywords,
        language: language,
        standardsUsed: standardsUsed,
        toolsUsed: toolsUsed,
        tlp: tlp,
        presentationTargetSeconds: presentationTargetSeconds,
        showRehearsalSummary: showRehearsalSummary,
        playOnly: playOnly,
      ),
      coalesceKey: 'info',
    );
  }

  /// Documentintegriteit (§8 A1): rond het deck af en verzegel het. Zet de
  /// vergrendeling, de optionele [signature] en het moment van verzegelen, en
  /// wist de ongedaan-maken-historie zodat het afronden in de app niet terug te
  /// draaien is (bewust eenrichtingsverkeer). Doet niets wanneer het deck al
  /// verzegeld is.
  ///
  /// De hash zelf ontstaat pas bij het opslaan: die gaat over de bytes van de
  /// `.md`, en die bestaan hier nog niet. Tot dat moment meldt het zegel zich
  /// als [IntegrityStatus.notVerifiable] — de aanroepende schermen slaan daarom
  /// meteen op, of zeggen dat het moet gebeuren.
  void finalizeAndSeal({DocumentSignature? signature}) {
    final deck = state.deck;
    if (deck == null || deck.finalized) return;
    // AI_ASSIST §16.3: refuse to seal while any AI-drafted field is unreviewed,
    // so the EIS 1.6 attestation always covers human-verified text. The UI
    // pre-checks it (see [slidesBlockingSeal]); this is the authoritative guard.
    if (deckHasUnreviewedAiMarkers(deck)) return;
    final sealed = DocumentIntegrity(_md).seal(deck, signature: signature);
    _clearHistory();
    state = state.copyWith(deck: sealed, isDirty: true);
  }

  /// Attach the owner's cryptographic provenance [signature] to the sealed deck
  /// (COLLABORATION Phase 2 "Blok C"). Marks the deck dirty so the next save
  /// writes it into `<name>.seal.json`; the signature is over the *saved*
  /// `sealHash`, so the caller signs only a saved, finalised deck. Passing null
  /// clears it.
  void applyProvenance(ProvenanceSignature? signature) {
    final deck = state.deck;
    if (deck == null) return;
    state = state.copyWith(
      deck: deck.copyWith(
        provenance: signature,
        clearProvenance: signature == null,
      ),
      isDirty: true,
    );
  }

  /// The 1-based slide numbers whose unreviewed AI-assist markers currently
  /// block sealing (empty = sealing is allowed). Used by the finalise UI to
  /// explain the block instead of silently doing nothing.
  List<int> get slidesBlockingSeal {
    final deck = state.deck;
    return deck == null ? const [] : slidesWithUnreviewedAiMarkers(deck);
  }

  /// Set the deck-level visual signature draft (authored on the `signOff` slide,
  /// §8 A1). Goes through [_mutate], so it is undoable and — like every edit —
  /// blocked once the deck is finalised. Clearing to an empty signature removes
  /// it from the front matter.
  void setSignature(DocumentSignature signature) {
    final deck = state.deck;
    if (deck == null) return;
    _mutate(
      deck.copyWith(
        signature: signature.isEmpty ? null : signature,
        clearSignature: signature.isEmpty,
      ),
    );
  }

  /// De integriteitsstatus van het open deck (niet-verzegeld / intact /
  /// gewijzigd-na-afronden). Herberekent de hash en vergelijkt met het zegel.
  IntegrityStatus get integrityStatus {
    final deck = state.deck;
    if (deck == null) return IntegrityStatus.notSealed;
    return DocumentIntegrity(_md).verify(deck);
  }

  void updateThemeProfile(ThemeProfile profile) {
    final deck = state.deck;
    if (deck == null) return;
    _mutate(
      deck.copyWith(
        themeProfile: _file.resolveThemeProfile(
          profile,
          projectPath: deck.projectPath,
        ),
      ),
    );
  }

  /// Werk een laag bij die naast de markdown leeft: annotaties, notities,
  /// terzijdegelegde bevindingen.
  ///
  /// Alle drie buiten undo/redo — het zijn geen inhoudswijzigingen, en Ctrl+Z
  /// hoort een typefout terug te draaien en niet een tekening of een oordeel.
  /// Wel vuil markeren, anders wordt de sidecar nooit weggeschreven; juist dat
  /// laatste is de stap die je bij een vierde laag zou vergeten.
  void _updateSidecarLayer(Deck Function(Deck) apply) {
    final deck = state.deck;
    if (deck == null) return;
    state = state.copyWith(deck: apply(deck));
    if (!state.isDirty) state = state.copyWith(isDirty: true);
  }

  /// Update the (separate) annotation layer. Kept out of the undo/redo history
  /// and the content revision so drawing while presenting stays lightweight;
  /// marks the deck dirty so the strokes get saved to the sidecar.
  void setAnnotations(Map<String, List<InkStroke>> annotations) =>
      _updateSidecarLayer((d) => d.copyWith(annotations: annotations));

  /// Vervang de terzijdegelegde privacybevindingen (#651). Buiten undo/redo:
  /// Ctrl+Z hoort een typefout terug te draaien, niet een privacy-oordeel —
  /// daarvoor is de terzijdegelegd-lijst met haar eigen ongedaan-maken.
  void setDismissals(DeckDismissals dismissals) =>
      _updateSidecarLayer((d) => d.copyWith(dismissals: dismissals));

  /// Update the (separate) user-notes layer. Kept out of undo/redo history;
  /// marks the deck dirty so notes get saved to the sidecar.
  void setUserNotes(Map<String, String> notes) =>
      _updateSidecarLayer((d) => d.copyWith(userNotes: _nonEmptyNotes(notes)));

  /// Replace the deck with one the collaboration layer produced — a co-author's
  /// change already merged onto the local deck by `collab_session_controller`
  /// (COLLABORATION.md §5.7). Kept out of undo/redo (Ctrl+Z should undo my own
  /// edit, not a collaborator's), but it bumps [DeckState.revision] so the
  /// editor's cached text fields re-read the incoming change, and marks the deck
  /// dirty so it is saved. A no-op when no deck is open.
  void applyCollabDeck(Deck deck) {
    if (state.deck == null) return;
    state = state.copyWith(
      deck: deck,
      isDirty: true,
      revision: state.revision + 1,
    );
  }

  void setUserNoteForSlide(
    String slideId,
    String text, {
    int pageIndex = 0,
    bool multiPage = false,
  }) {
    final deck = state.deck;
    if (deck == null) return;
    setUserNotes(
      _withUserNote(
        deck.userNotes,
        slideId,
        text,
        pageIndex: pageIndex,
        multiPage: multiPage,
      ),
    );
  }

  String? userNoteForSlide(
    String slideId, {
    int pageIndex = 0,
    bool multiPage = false,
  }) => userNoteForPage(
    state.deck?.userNotes ?? const {},
    slideId,
    pageIndex,
    multiPage: multiPage,
  );

  void clearUserNoteForSlide(
    String slideId, {
    int pageIndex = 0,
    bool multiPage = false,
  }) => setUserNoteForSlide(
    slideId,
    '',
    pageIndex: pageIndex,
    multiPage: multiPage,
  );

  // ── Markdown mode ──────────────────────────────────────────────────────────
  // Zie deck_provider_markdown.dart (extension DeckNotifierMarkdown) voor
  // generateMarkdown/generateSlideMarkdown/applyMarkdown/applySlideMarkdown.

  void clearError() => state = state.copyWith(clearError: true);

  /// Markeer de huidige deck als gewijzigd (gebruikt bij herstel na een crash:
  /// het teruggehaalde werk is nog niet opgeslagen).
  void markDirty() {
    if (state.deck != null && !state.isDirty) {
      state = state.copyWith(isDirty: true);
    }
  }

  // ── Ongedaan maken / opnieuw uitvoeren ───────────────────────────────────

  /// Draai de laatste wijziging terug.
  void undo() {
    final deck = state.deck;
    if (deck == null || _undoStack.isEmpty) return;
    _redoStack.add(deck);
    final previous = _undoStack.removeLast();
    // Volgende bewerking begint een verse ongedaan-maken-stap.
    _lastCoalesceKey = null;
    _lastMutationAt = null;
    state = state.copyWith(
      deck: previous,
      isDirty: true,
      canUndo: _undoStack.isNotEmpty,
      canRedo: _redoStack.isNotEmpty,
      revision: state.revision + 1,
    );
  }

  /// Voer een teruggedraaide wijziging opnieuw uit.
  void redo() {
    final deck = state.deck;
    if (deck == null || _redoStack.isEmpty) return;
    _undoStack.add(deck);
    final next = _redoStack.removeLast();
    _lastCoalesceKey = null;
    _lastMutationAt = null;
    state = state.copyWith(
      deck: next,
      isDirty: true,
      canUndo: _undoStack.isNotEmpty,
      canRedo: _redoStack.isNotEmpty,
      revision: state.revision + 1,
    );
  }

  /// Pas een nieuwe deck-versie toe en bewaar de vorige in de ongedaan-stapel.
  ///
  /// Wanneer [coalesceKey] gelijk is aan die van de vorige bewerking en deze
  /// binnen [_coalesceWindow] valt, wordt geen nieuwe ongedaan-stap aangemaakt
  /// (zodat typen niet per teken een aparte stap oplevert). Een [coalesceKey]
  /// van null markeert een losse, discrete stap.
  ///
  /// Wanneer [bumpRevision] waar is, wordt de inhouds-revisie opgehoogd. Dat
  /// dwingt de editor-subtree (die op `revision` is gesleuteld) om te remounten
  /// en zijn velden opnieuw uit de slide te laden. Nodig bij deck-brede
  /// bewerkingen die de huidige slide aanpassen zonder dat de editor zelf de
  /// bron van de wijziging was (anders blijft de editor de oude, gecachte
  /// waarden tonen).
  void _mutate(
    Deck deck, {
    String? coalesceKey,
    bool bumpRevision = false,
    bool allowFinalized = false,
  }) {
    final previous = state.deck;
    // Read-only lock (§8 A1): a finalised deck rejects edits here (sealing sets
    // state directly via [finalizeAndSeal]); only the post-seal RFC3161
    // timestamp ([allowFinalized]) is exempt — it falls outside the hashed body.
    if (previous != null && previous.finalized && !allowFinalized) return;
    if (previous != null) {
      final now = DateTime.now();
      final canCoalesce =
          coalesceKey != null &&
          coalesceKey == _lastCoalesceKey &&
          _lastMutationAt != null &&
          now.difference(_lastMutationAt!) < _coalesceWindow &&
          _undoStack.isNotEmpty;
      if (!canCoalesce) {
        _undoStack.add(previous);
        if (_undoStack.length > _maxHistory) _undoStack.removeAt(0);
      }
      _lastMutationAt = now;
      _lastCoalesceKey = coalesceKey;
    }
    _redoStack.clear();
    state = state.copyWith(
      deck: deck,
      isDirty: true,
      canUndo: _undoStack.isNotEmpty,
      canRedo: false,
      revision: bumpRevision ? state.revision + 1 : null,
    );
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final deckProvider = StateNotifierProvider<DeckNotifier, DeckState>((ref) {
  return DeckNotifier(
    ref.read(markdownServiceProvider),
    ref.read(fileServiceProvider),
  );
});

/// De notities zonder lege waarden.
///
/// Een leeg gemaakte notitie hoort te verdwijnen en niet als lege string te
/// blijven staan: dan schrijft de codec een sidecar voor niets, en telt "er
/// zijn notities" iets mee dat de lezer niet ziet.
Map<String, String> _nonEmptyNotes(Map<String, String> notes) {
  final cleaned = <String, String>{};
  for (final entry in notes.entries) {
    final text = entry.value.trim();
    if (text.isNotEmpty) cleaned[entry.key] = text;
  }
  return cleaned;
}

/// [notes] met de notitie van één dia gezet of gewist.
///
/// Een leeg gemaakte notitie verdwijnt in plaats van als lege string te blijven
/// staan. Bij een meerpagina-dia gaat de oude sleutel zónder paginanummer óók
/// weg: die is van vóór de paginering en zou anders als spooknotitie blijven
/// bestaan naast de nieuwe.
Map<String, String> _withUserNote(
  Map<String, String> notes,
  String slideId,
  String text, {
  required int pageIndex,
  required bool multiPage,
}) {
  final next = Map<String, String>.from(notes);
  final trimmed = text.trim();
  final key = userNoteStorageKey(slideId, pageIndex, multiPage: multiPage);
  if (trimmed.isEmpty) {
    next.remove(key);
  } else {
    next[key] = trimmed;
  }
  if (multiPage && pageIndex == 0) next.remove(slideId);
  return next;
}
