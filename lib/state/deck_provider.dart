import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/annotation.dart';
import '../models/checklist_spec.dart';
import '../models/deck.dart';
import '../models/deck_template.dart';
import '../models/document_signature.dart';
import '../models/scope_matrix_spec.dart';
import '../models/settings.dart';
import '../models/slide.dart';
import '../services/ai_alt_text_cleanup.dart';
import '../services/annotation_codec.dart';
import '../services/bullet_pagination.dart';
import '../services/checklist_templates.dart';
import '../services/document_integrity.dart';
import '../services/finding_context_score.dart';
import '../services/finding_numbering.dart';
import '../services/scope_coverage.dart';
import '../services/file_service.dart';
import '../services/image_service.dart';
import '../services/markdown_service.dart';
import '../services/slide_layout_metrics.dart';
import '../services/slide_quality_analyzer.dart'
    show
        kChecklistBulletWarningCount,
        kSingleColumnBulletWarningCount,
        kTwoColumnBulletWarningCount;
import '../services/user_notes_codec.dart';
import '../platform/platform_features.dart';
import '../utils/log.dart';
import '../utils/page_scoped_notes.dart';
import 'settings_provider.dart';

part 'deck_provider_markdown.dart';
part 'deck_provider_ai.dart';
part 'deck_provider_miauw.dart';
part 'deck_provider_checklist.dart';
part 'deck_provider_auto.dart';

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

  /// Telt alleen op bij undo/redo. De editor gebruikt dit om zijn
  /// tekstvelden te verversen wanneer een wijziging op dezelfde slide wordt
  /// teruggedraaid (de velden synchroniseren anders alleen op slide-id).
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
bool canSplitSlide(Slide slide) {
  switch (slide.type) {
    case SlideType.bullets:
    case SlideType.bulletsImage:
      return slide.bullets.length >= 2;
    case SlideType.twoBullets:
      return slide.bullets.length >= 2 || slide.bullets2.length >= 2;
    default:
      return false;
  }
}

// ── DeckNotifier ─────────────────────────────────────────────────────────────

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

  /// Snelle, opeenvolgende bewerkingen (zoals typen) worden samengevoegd tot
  /// één ongedaan-maken-stap zolang ze dezelfde [_lastCoalesceKey] delen en
  /// binnen dit tijdvenster vallen.
  static const _coalesceWindow = Duration(milliseconds: 700);
  DateTime? _lastMutationAt;
  String? _lastCoalesceKey;

  DeckNotifier(this._md, this._file) : super(const DeckState());

  DeckState get currentState => state;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void _clearHistory() {
    _undoStack.clear();
    _redoStack.clear();
    _lastMutationAt = null;
    _lastCoalesceKey = null;
  }

  /// Start a fresh deck. With a [template] the deck opens with that template's
  /// example slides (the first is always a title slide carrying [title]);
  /// without one it is the classic single title slide.
  void newDeck(
    String title, {
    String theme = 'ocideck',
    DeckTemplate? template,
  }) {
    final deck = Deck(
      title: title,
      theme: theme,
      themeProfile: _file.currentThemeProfile,
      slides:
          template?.buildSlides(title) ??
          [Slide.create(SlideType.title).copyWith(title: title)],
    );
    _clearHistory();
    state = DeckState(deck: deck, isDirty: true);
  }

  /// Load a deck that was already parsed (used by the tab manager). Styling is
  /// not taken from the deck/markdown but from the active style profile, so an
  /// opened or recovered deck always picks up the current look.
  void loadDeck(Deck deck, {String? filePath, String? remoteOrigin}) {
    final resolvedDeck = deck.copyWith(
      themeProfile: _file.activeProfileFor(projectPath: deck.projectPath),
    );
    _clearHistory();
    state = DeckState(
      deck: resolvedDeck,
      filePath: filePath,
      remoteOrigin: remoteOrigin,
      isDirty: false,
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
    // Reject a second concurrent save rather than interleaving two writes to
    // the same file. A dropped trigger is harmless — the deck is still dirty.
    if (_saving) return false;
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
    }
  }

  /// Web-opslagpad: start een browserdownload van de deck-markdown. Het deck
  /// wordt daarna als schoon gemarkeerd — het bestand is aan de gebruiker
  /// overhandigd; verdere wijzigingen maken het gewoon weer dirty. [filePath]
  /// blijft null, zodat elke volgende save opnieuw een download start; de
  /// gedownloade bestandsnaam onthouden we wél voor de statusbalk.
  bool _saveAsDownload() {
    final deck = state.deck;
    if (deck == null) return false;
    final name = _file.downloadDeckAsFile(deck);
    if (name == null) {
      state = state.copyWith(error: 'Opslaan als download mislukt.');
      return false;
    }
    state = state.copyWith(isDirty: false, downloadName: name);
    return true;
  }

  Future<bool> saveAs({String? initialDirectory}) async {
    final deck = state.deck;
    if (deck == null) return false;
    final String? path;
    try {
      path = await _file.saveDeckAs(deck, initialDirectory: initialDirectory);
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
    if (reopened == null) {
      logWarning('DeckNotifier.saveAs: saved file could not be re-read', path);
      state = state.copyWith(
        deck: deck,
        filePath: path,
        isDirty: false,
        error:
            'Opgeslagen, maar het bestand kon niet opnieuw worden gelezen:\n$path',
      );
    } else {
      state = state.copyWith(deck: reopened, filePath: path, isDirty: false);
    }
    return true;
  }

  Future<bool> _saveToPath(String path) async {
    final deck = state.deck;
    if (deck == null) return false;
    final Deck savedDeck;
    try {
      savedDeck = await _file.saveDeck(deck, path);
    } catch (e, s) {
      logError('DeckNotifier._saveToPath: write deck', e, s);
      // Keep isDirty so the work still counts as unsaved.
      state = state.copyWith(error: 'Opslaan mislukt:\n$path\n$e');
      return false;
    }
    state = state.copyWith(deck: savedDeck, isDirty: false);
    return true;
  }

  void closeDeck() {
    _clearHistory();
    state = const DeckState();
  }

  // ── Slide operations ───────────────────────────────────────────────────────

  void addSlide(SlideType type, {int? afterIndex}) {
    final deck = state.deck;
    if (deck == null) return;
    final slides = List<Slide>.from(deck.slides);
    final at = afterIndex != null ? afterIndex + 1 : slides.length;
    slides.insert(at, Slide.create(type));
    _mutate(deck.copyWith(slides: slides));
  }

  void removeSlide(int index) {
    final deck = state.deck;
    if (deck == null ||
        deck.slides.length <= 1 ||
        index < 0 ||
        index >= deck.slides.length) {
      return;
    }
    final slides = List<Slide>.from(deck.slides)..removeAt(index);
    _mutate(deck.copyWith(slides: slides));
  }

  /// Verwijder meerdere slides tegelijk (bulk-actie). Houdt altijd minstens één
  /// slide over.
  void removeSlides(Set<int> indices) {
    final deck = state.deck;
    if (deck == null || indices.isEmpty) return;
    final keep = [
      for (var i = 0; i < deck.slides.length; i++)
        if (!indices.contains(i)) deck.slides[i],
    ];
    if (keep.isEmpty || keep.length == deck.slides.length) return;
    _mutate(deck.copyWith(slides: keep));
  }

  /// Zet de "overslaan"-status van meerdere slides ineens (bulk-actie).
  void setSkippedForSlides(Set<int> indices, bool skipped) {
    final deck = state.deck;
    if (deck == null || indices.isEmpty) return;
    final changed = indices.any(
      (i) =>
          i >= 0 && i < deck.slides.length && deck.slides[i].skipped != skipped,
    );
    if (!changed) return;
    final slides = [
      for (var i = 0; i < deck.slides.length; i++)
        indices.contains(i)
            ? deck.slides[i].copyWith(skipped: skipped)
            : deck.slides[i],
    ];
    _mutate(deck.copyWith(slides: slides));
  }

  /// Insert [newSlides] after [afterIndex] (or at the end when null).
  /// Each slide is duplicated so it gets a fresh id and is fully detached
  /// from its source presentation. Returns the index of the first inserted
  /// slide, or -1 when nothing was inserted.
  int insertSlides(List<Slide> newSlides, {int? afterIndex}) {
    final deck = state.deck;
    if (deck == null || newSlides.isEmpty) return -1;
    final slides = List<Slide>.from(deck.slides);
    final at = afterIndex != null ? afterIndex + 1 : slides.length;
    final clamped = at.clamp(0, slides.length);
    slides.insertAll(clamped, newSlides.map(Slide.duplicate));
    _mutate(deck.copyWith(slides: slides), bumpRevision: newSlides.length > 1);
    return clamped;
  }

  void duplicateSlide(int index) {
    final deck = state.deck;
    if (deck == null || index < 0 || index >= deck.slides.length) return;
    final slides = List<Slide>.from(deck.slides);
    slides.insert(index + 1, Slide.duplicate(slides[index]));
    _mutate(deck.copyWith(slides: slides));
  }

  /// Splitst de bulletslide op [index] in zoveel gelijkmatige pagina's als nodig
  /// zodat geen enkele nog overvol is; de vervolgpagina's komen er direct achter.
  /// Doet niets als de slide geen (genoeg) bullets heeft om te splitsen.
  void splitSlide(int index) {
    final deck = state.deck;
    if (deck == null || index < 0 || index >= deck.slides.length) return;
    final pages = _splitSlide(deck.slides[index], deck.themeProfile.fontFamily);
    if (pages == null) return;
    final slides = List<Slide>.from(deck.slides)
      ..removeAt(index)
      ..insertAll(index, pages);
    // De huidige slide krijgt nieuwe inhoud, dus forceer een editor-refresh.
    _mutate(deck.copyWith(slides: slides), bumpRevision: true);
  }

  /// Verdeelt de bulletslide [slide] over gelijkmatige pagina's die elk binnen
  /// het optimum blijven (het kleinste van wat op ware grootte past en de
  /// leesbaarheidsdrempel), of `null` als splitsen niet kan. Splitpunten vallen
  /// op groepsgrenzen zodat geen tussenkop losraakt van zijn bullets. De eerste
  /// pagina erft type/afbeelding en de continuesSplit-vlag van [slide] (want
  /// [Slide.duplicate] kopieert imagePath/-caption/-size); elke vervolgpagina is
  /// een continuation die de fontgrootte deelt.
  List<Slide>? _splitSlide(Slide slide, String font) {
    List<Slide> build(List<(List<String>, List<String>)> pages) => [
      for (var i = 0; i < pages.length; i++)
        (i == 0 ? slide : Slide.duplicate(slide)).copyWith(
          bullets: pages[i].$1,
          bullets2: pages[i].$2,
          continuesSplit: i == 0 ? slide.continuesSplit : true,
        ),
    ];
    switch (slide.type) {
      case SlideType.bullets:
      case SlideType.bulletsImage:
        if (slide.bullets.length < 2) return null;
        // Checklists houden hun ruimere optimum aan (consistent met de
        // waarschuwingsdrempel), zodat een lijst van 12 niet onnodig krimpt.
        final limit = slide.listStyle == ListStyle.checklist
            ? kChecklistBulletWarningCount
            : kSingleColumnBulletWarningCount;
        final fit = bulletFitCounts(slide: slide, font: font).left;
        return build([
          for (final p in paginateBulletsToFit(
            slide.bullets,
            bulletPageCap(fit, limit),
          ))
            (p, const <String>[]),
        ]);
      case SlideType.twoBullets:
        if (slide.bullets.length < 2 && slide.bullets2.length < 2) return null;
        const perColumn = kTwoColumnBulletWarningCount ~/ 2;
        final counts = bulletFitCounts(slide: slide, font: font);
        return build(
          paginateTwoColumnsToFit(
            slide.bullets,
            bulletPageCap(counts.left, perColumn),
            slide.bullets2,
            bulletPageCap(counts.right, perColumn),
          ),
        );
      default:
        return null;
    }
  }

  /// Knip de videoslide op [index] op tijdstip [atMs]: het huidige segment
  /// `[start, eind]` wordt `[start, atMs]` op deze slide, en een nieuwe slide
  /// erna toont `[atMs, eind]` van dezelfde bron (opnieuw knipbaar). Doet niets
  /// als de slide geen video heeft of als het knippunt buiten het segment valt.
  void splitVideoSlide(int index, int atMs) {
    final deck = state.deck;
    if (deck == null || index < 0 || index >= deck.slides.length) return;
    final slide = deck.slides[index];
    if (slide.type != SlideType.video || slide.videoPath.isEmpty) return;
    final start = slide.videoStartMs;
    final end = slide.videoEndMs; // 0 = natuurlijk einde
    // Het knippunt moet strikt binnen het huidige segment liggen.
    if (atMs <= start) return;
    if (end > 0 && atMs >= end) return;
    final first = slide.copyWith(videoEndMs: atMs);
    final second = Slide.duplicate(
      slide,
    ).copyWith(videoStartMs: atMs, videoEndMs: end);
    final slides = List<Slide>.from(deck.slides);
    slides[index] = first;
    slides.insert(index + 1, second);
    _mutate(deck.copyWith(slides: slides));
  }

  // newIndex from onReorderItem is pre-adjusted (no -1 needed)
  void reorderSlides(int oldIndex, int newIndex) {
    final deck = state.deck;
    if (deck == null) return;
    final slides = List<Slide>.from(deck.slides);
    final slide = slides.removeAt(oldIndex);
    slides.insert(newIndex, slide);
    _mutate(deck.copyWith(slides: slides));
  }

  /// Verplaats de geselecteerde slides als één aaneengesloten blok (in hun
  /// oorspronkelijke volgorde) naar de drop-plek. [oldIndex]/[newIndex] komen van
  /// `onReorderItem` (voor-gecorrigeerd, net als bij [reorderSlides]). Bij minder
  /// dan twee geselecteerde slides valt dit terug op een gewone enkel-slide-move.
  /// Geeft de nieuwe startindex van het blok, of -1 als er niets te doen is.
  ///
  /// De drop-plek wordt verankerd op slide-**id** i.p.v. index: we zoeken de
  /// eerste niet-blok-slide op of na [newIndex] en zetten het blok daar vóór. Zo
  /// blijft de plaatsing correct ongeacht hoeveel geselecteerde slides boven de
  /// drop stonden.
  int moveSlides(Set<int> selection, int oldIndex, int newIndex) {
    final deck = state.deck;
    if (deck == null) return -1;
    final n = deck.slides.length;
    final sel = selection.where((i) => i >= 0 && i < n).toList()..sort();
    if (sel.length < 2) {
      reorderSlides(oldIndex, newIndex);
      return newIndex;
    }

    final slides = List<Slide>.from(deck.slides);
    final block = [for (final i in sel) slides[i]];
    final blockIds = {for (final s in block) s.id};

    // Anker = eerste niet-blok-slide op/na de drop in de lijst zonder de
    // gesleepte slide (newIndex is in die coördinaten voor-gecorrigeerd).
    final withoutOld = List<Slide>.from(slides)..removeAt(oldIndex);
    String? anchorId;
    for (var k = newIndex; k < withoutOld.length; k++) {
      if (!blockIds.contains(withoutOld[k].id)) {
        anchorId = withoutOld[k].id;
        break;
      }
    }

    final selSet = sel.toSet();
    final reduced = [
      for (var i = 0; i < n; i++)
        if (!selSet.contains(i)) slides[i],
    ];
    final insertAt = anchorId == null
        ? reduced.length
        : reduced.indexWhere((s) => s.id == anchorId).clamp(0, reduced.length);
    reduced.insertAll(insertAt, block);
    _mutate(deck.copyWith(slides: reduced), bumpRevision: true);
    return insertAt;
  }

  /// [bumpRevision] dwingt een editor-remount af; nodig wanneer de wijziging
  /// niet uit de editor zelf komt (zoals een kwaliteits-quick-fix) en de
  /// tekstvelden de nieuwe slide-inhoud moeten laden.
  void updateSlide(int index, Slide updated, {bool bumpRevision = false}) {
    final deck = state.deck;
    if (deck == null || index < 0 || index >= deck.slides.length) return;
    final slides = List<Slide>.from(deck.slides);
    slides[index] = updated;
    // Snel typen op dezelfde slide telt als één ongedaan-maken-stap. Sleutel op
    // de stabiele slide-id, niet de index: na verwijderen/herordenen mag een
    // bewerking op een ándere slide (zelfde index) niet meecoalescen.
    _mutate(
      deck.copyWith(slides: slides),
      coalesceKey: bumpRevision ? null : 'slide:${updated.id}',
      bumpRevision: bumpRevision,
    );
  }

  /// Zet de "overslaan"-status van een slide aan/uit. Overgeslagen slides
  /// worden weggelaten bij presenteren en exporteren.
  void toggleSkip(int index) {
    final deck = state.deck;
    if (deck == null || index < 0 || index >= deck.slides.length) return;
    final slides = List<Slide>.from(deck.slides);
    slides[index] = slides[index].copyWith(skipped: !slides[index].skipped);
    _mutate(deck.copyWith(slides: slides));
  }

  /// Hoeveel slides momenteel overgeslagen worden.
  int get skippedCount =>
      state.deck?.slides.where((s) => s.skipped).length ?? 0;

  /// Zet in één keer alle "overslaan"-markeringen uit (bijv. nadat je de
  /// presentatie hebt gegeven). No-op wanneer er niets overgeslagen wordt.
  void clearAllSkips() {
    final deck = state.deck;
    if (deck == null || !deck.slides.any((s) => s.skipped)) return;
    final slides = [
      for (final s in deck.slides) s.skipped ? s.copyWith(skipped: false) : s,
    ];
    _mutate(deck.copyWith(slides: slides));
  }

  /// Hoeveel checklist-items in de hele presentatie momenteel afgevinkt zijn.
  int get checkedChecklistCount {
    final deck = state.deck;
    if (deck == null) return 0;
    var total = 0;
    for (final s in deck.slides) {
      total += s.bullets.where(checklistItemChecked).length;
      total += s.bullets2.where(checklistItemChecked).length;
    }
    return total;
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
        tlp: tlp,
        presentationTargetSeconds: presentationTargetSeconds,
        showRehearsalSummary: showRehearsalSummary,
        playOnly: playOnly,
      ),
      coalesceKey: 'info',
    );
  }

  /// Documentintegriteit (§8 A1): rond het deck af en verzegel het. Berekent een
  /// SHA-512-zegel over de inhoud (met de optionele [signature] eronder), zet de
  /// vergrendeling en het zegel, en wist de ongedaan-maken-historie zodat het
  /// afronden in de app niet terug te draaien is (bewust eenrichtingsverkeer).
  /// Doet niets wanneer het deck al verzegeld is.
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

  /// Update the (separate) annotation layer. Kept out of the undo/redo history
  /// and the content revision so drawing while presenting stays lightweight;
  /// marks the deck dirty so the strokes get saved to the sidecar.
  void setAnnotations(Map<String, List<InkStroke>> annotations) {
    final deck = state.deck;
    if (deck == null) return;
    state = state.copyWith(deck: deck.copyWith(annotations: annotations));
    if (!state.isDirty) state = state.copyWith(isDirty: true);
  }

  /// Update the (separate) user-notes layer. Kept out of undo/redo history;
  /// marks the deck dirty so notes get saved to the sidecar.
  void setUserNotes(Map<String, String> notes) {
    final deck = state.deck;
    if (deck == null) return;
    final cleaned = <String, String>{};
    for (final entry in notes.entries) {
      final text = entry.value.trim();
      if (text.isNotEmpty) cleaned[entry.key] = text;
    }
    state = state.copyWith(deck: deck.copyWith(userNotes: cleaned));
    if (!state.isDirty) state = state.copyWith(isDirty: true);
  }

  void setUserNoteForSlide(
    String slideId,
    String text, {
    int pageIndex = 0,
    bool multiPage = false,
  }) {
    final deck = state.deck;
    if (deck == null) return;
    final next = Map<String, String>.from(deck.userNotes);
    final trimmed = text.trim();
    final key = userNoteStorageKey(slideId, pageIndex, multiPage: multiPage);
    if (trimmed.isEmpty) {
      next.remove(key);
      if (multiPage && pageIndex == 0) next.remove(slideId);
    } else {
      next[key] = trimmed;
      if (multiPage && pageIndex == 0) next.remove(slideId);
    }
    setUserNotes(next);
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
