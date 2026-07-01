import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/annotation.dart';
import '../models/deck.dart';
import '../models/settings.dart';
import '../models/slide.dart';
import '../services/annotation_codec.dart';
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
import '../utils/log.dart';
import '../utils/page_scoped_notes.dart';
import 'settings_provider.dart';

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
  );
});

// ── Deck state ───────────────────────────────────────────────────────────────

class DeckState {
  final Deck? deck;
  final bool isDirty;
  final String? filePath;
  final String? error;

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
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      revision: revision ?? this.revision,
    );
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

  void newDeck(String title, {String theme = 'ocideck'}) {
    final deck = Deck(
      title: title,
      theme: theme,
      themeProfile: _file.currentThemeProfile,
      slides: [Slide.create(SlideType.title).copyWith(title: title)],
    );
    _clearHistory();
    state = DeckState(deck: deck, isDirty: true);
  }

  /// Load a deck that was already parsed (used by the tab manager). Styling is
  /// not taken from the deck/markdown but from the active style profile, so an
  /// opened or recovered deck always picks up the current look.
  void loadDeck(Deck deck, {String? filePath}) {
    final resolvedDeck = deck.copyWith(
      themeProfile: _file.activeProfileFor(projectPath: deck.projectPath),
    );
    _clearHistory();
    state = DeckState(deck: resolvedDeck, filePath: filePath, isDirty: false);
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
      if (state.filePath != null) {
        return await _saveToPath(state.filePath!);
      } else {
        return await saveAs(initialDirectory: initialDirectory);
      }
    } finally {
      _saving = false;
    }
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

  /// Splitst de bulletslide op [index] in tweeën: het maximale aantal bullets
  /// dat op natuurlijke grootte op één slide past blijft staan, de rest verhuist
  /// naar een nieuwe slide erna. Doet niets als de slide geen (genoeg) bullets
  /// heeft om te splitsen.
  void splitSlide(int index) {
    final deck = state.deck;
    if (deck == null || index < 0 || index >= deck.slides.length) return;
    final split = _splitSlide(deck.slides[index], deck.themeProfile.fontFamily);
    if (split == null) return;
    final slides = List<Slide>.from(deck.slides);
    slides[index] = split.first;
    slides.insert(index + 1, split.second);
    // De huidige slide krijgt nieuwe inhoud, dus forceer een editor-refresh.
    _mutate(deck.copyWith(slides: slides), bumpRevision: true);
  }

  /// Bepaalt hoe de bulletslide [slide] in tweeën valt, of `null` als dat niet
  /// kan (geen bullettype, of te weinig bullets om te splitsen).
  ({Slide first, Slide second})? _splitSlide(Slide slide, String font) {
    // Slide 1 houdt het optimum: niet meer dan wat op natuurlijke grootte past
    // én niet meer dan de leesbaarheidsdrempel, zodat de overgebleven slide niet
    // opnieuw te vol is. Past de hele kolom al binnen het optimum (de slide is
    // niet te vol), dan splitsen we netjes doormidden — de gebruiker koos er
    // immers bewust voor om in tweeën te knippen. Resultaat ligt altijd in
    // [1, len-1] zodat beide helften minstens één bullet houden.
    int keepFor(int fit, int len, int limit) {
      if (len < 2) return len; // niets te verplaatsen in deze kolom
      var keep = fit < limit ? fit : limit;
      if (keep >= len) keep = len ~/ 2;
      return keep < 1 ? 1 : (keep > len - 1 ? len - 1 : keep);
    }

    switch (slide.type) {
      case SlideType.bullets:
      case SlideType.bulletsImage:
        final bullets = slide.bullets;
        if (bullets.length < 2) return null;
        final counts = bulletFitCounts(slide: slide, font: font);
        // Checklists houden hun ruimere optimum aan (consistent met de
        // waarschuwingsdrempel), zodat een lijst van 12 niet onnodig krimpt.
        final limit = slide.listStyle == ListStyle.checklist
            ? kChecklistBulletWarningCount
            : kSingleColumnBulletWarningCount;
        final at = keepFor(counts.left, bullets.length, limit);
        return (
          first: slide.copyWith(bullets: bullets.sublist(0, at)),
          second: Slide.duplicate(slide).copyWith(bullets: bullets.sublist(at)),
        );
      case SlideType.twoBullets:
        final left = slide.bullets;
        final right = slide.bullets2;
        if (left.length < 2 && right.length < 2) return null;
        final counts = bulletFitCounts(slide: slide, font: font);
        const perColumn = kTwoColumnBulletWarningCount ~/ 2;
        final leftAt = keepFor(counts.left, left.length, perColumn);
        final rightAt = keepFor(counts.right, right.length, perColumn);
        return (
          first: slide.copyWith(
            bullets: left.sublist(0, leftAt),
            bullets2: right.sublist(0, rightAt),
          ),
          second: Slide.duplicate(slide).copyWith(
            bullets: left.sublist(leftAt),
            bullets2: right.sublist(rightAt),
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

  void updateSlide(int index, Slide updated) {
    final deck = state.deck;
    if (deck == null || index < 0 || index >= deck.slides.length) return;
    final slides = List<Slide>.from(deck.slides);
    slides[index] = updated;
    // Snel typen op dezelfde slide telt als één ongedaan-maken-stap. Sleutel op
    // de stabiele slide-id, niet de index: na verwijderen/herordenen mag een
    // bewerking op een ándere slide (zelfde index) niet meecoalescen.
    _mutate(deck.copyWith(slides: slides), coalesceKey: 'slide:${updated.id}');
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

  /// Vink in één keer alle checklist-items in de hele presentatie uit (bijv.
  /// om een ingevulde checklist opnieuw te kunnen aflopen). Eén
  /// ongedaan-maken-stap. No-op wanneer er niets is aangevinkt.
  void clearAllChecklists() {
    final deck = state.deck;
    if (deck == null) return;
    String uncheck(String bullet) => checklistItemChecked(bullet)
        ? checklistBullet(
            level: bulletLevel(bullet),
            text: checklistItemText(bullet),
            checked: false,
          )
        : bullet;
    var changed = false;
    final slides = <Slide>[];
    for (final s in deck.slides) {
      if (s.bullets.any(checklistItemChecked) ||
          s.bullets2.any(checklistItemChecked)) {
        changed = true;
        slides.add(
          s.copyWith(
            bullets: [for (final b in s.bullets) uncheck(b)],
            bullets2: [for (final b in s.bullets2) uncheck(b)],
          ),
        );
      } else {
        slides.add(s);
      }
    }
    // Bump de revisie zodat de editor van de geselecteerde slide remount en de
    // uitgevinkte checkboxen ook in het invoerpaneel toont (niet alleen in de
    // slidepreview).
    if (changed) {
      _mutate(deck.copyWith(slides: slides), bumpRevision: true);
    }
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
      ),
      coalesceKey: 'info',
    );
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

  String generateMarkdown() {
    final deck = state.deck;
    // Inline linked chart data so a markdown round-trip (toggle, recovery
    // snapshot) keeps the chart's points. Saving to disk still writes the
    // source-only form (see FileService._writeProject), so the .md stays clean.
    return deck != null ? _md.generateDeck(deck, inlineChartData: true) : '';
  }

  /// Returns false if parsing fails (content is preserved).
  bool applyMarkdown(String markdown) {
    final parsed = _md.parseDeck(markdown, filePath: state.filePath);
    if (parsed == null) return false;
    // The markdown carries only content; keep the deck's current styling rather
    // than resetting it to the default profile the parser returns.
    final current = state.deck;
    var deck = current == null
        ? parsed
        : parsed.copyWith(themeProfile: current.themeProfile);
    if (current != null && current.userNotes.isNotEmpty) {
      final encoded = UserNotesCodec.encode(current.slides, current.userNotes);
      final remapped = encoded != null
          ? UserNotesCodec.decode(encoded, deck.slides)
          : const <String, String>{};
      deck = deck.copyWith(userNotes: remapped);
    }
    // Annotations (ink layers) live outside the markdown; without re-anchoring
    // them to the new slides a markdown toggle would wipe the drawings, and a
    // subsequent save would delete their sidecar — permanent data loss.
    if (current != null && current.annotations.isNotEmpty) {
      final encoded = AnnotationCodec.encode(
        current.slides,
        current.annotations,
      );
      final remapped = encoded != null
          ? AnnotationCodec.decode(encoded, deck.slides)
          : const <String, List<InkStroke>>{};
      deck = deck.copyWith(annotations: remapped);
    }
    _mutate(deck); // discrete stap → ook ongedaan te maken
    return true;
  }

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
  void _mutate(Deck deck, {String? coalesceKey, bool bumpRevision = false}) {
    final previous = state.deck;
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
