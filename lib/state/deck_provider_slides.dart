part of 'deck_provider.dart';

/// `part of` extensie met de dia-bewerkingen (toevoegen, verwijderen, dupliceren,
/// splitsen, herordenen), zodat de hoofdnotifier onder het regelplafond blijft.
/// Als extensie in dezelfde library houdt het toegang tot `_mutate` en de
/// deckstand; die laatste via [DeckNotifier.currentState], want `state` is
/// protected op de notifier zelf.
extension DeckNotifierSlides on DeckNotifier {
  /// Voegt een slide toe ná [afterIndex] (of achteraan als die null is).
  ///
  /// [afterIndex] komt van de selectie in het editorpaneel, en die kan achterlopen
  /// op het deck: na ongedaan maken is de lijst korter terwijl de selectie nog op
  /// de oude plek staat. De panelen klemmen dat voor de wéérgave, maar de acties
  /// lazen de rauwe index — en een `insert` voorbij het einde gooit een
  /// RangeError. Klemmen dus, net als [insertSlides] en [removeSlide] al deden.
  void addSlide(SlideType type, {int? afterIndex}) {
    final deck = currentState.deck;
    if (deck == null) return;
    final slides = List<Slide>.from(deck.slides);
    final at = afterIndex != null
        ? (afterIndex + 1).clamp(0, slides.length)
        : slides.length;
    slides.insert(at, Slide.create(type));
    _mutate(deck.copyWith(slides: slides));
  }

  void removeSlide(int index) {
    final deck = currentState.deck;
    if (deck == null ||
        deck.slides.length <= 1 ||
        index < 0 ||
        index >= deck.slides.length) {
      return;
    }
    final slides = List<Slide>.from(deck.slides)..removeAt(index);
    _mutate(deck.copyWith(slides: slides));
    onSweepWebAssets?.call();
  }

  /// Verwijder meerdere slides tegelijk (bulk-actie). Houdt altijd minstens één
  /// slide over.
  void removeSlides(Set<int> indices) {
    final deck = currentState.deck;
    if (deck == null || indices.isEmpty) return;
    final keep = [
      for (var i = 0; i < deck.slides.length; i++)
        if (!indices.contains(i)) deck.slides[i],
    ];
    if (keep.isEmpty || keep.length == deck.slides.length) return;
    _mutate(deck.copyWith(slides: keep));
    onSweepWebAssets?.call();
  }

  /// Zet de "overslaan"-status van meerdere slides ineens (bulk-actie).
  void setSkippedForSlides(Set<int> indices, bool skipped) {
    final deck = currentState.deck;
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
    final deck = currentState.deck;
    if (deck == null || newSlides.isEmpty) return -1;
    final slides = List<Slide>.from(deck.slides);
    final at = afterIndex != null ? afterIndex + 1 : slides.length;
    final clamped = at.clamp(0, slides.length);
    slides.insertAll(clamped, newSlides.map(Slide.duplicate));
    _mutate(deck.copyWith(slides: slides), bumpRevision: newSlides.length > 1);
    return clamped;
  }

  void duplicateSlide(int index) {
    final deck = currentState.deck;
    if (deck == null || index < 0 || index >= deck.slides.length) return;
    final slides = List<Slide>.from(deck.slides);
    slides.insert(index + 1, Slide.duplicate(slides[index]));
    _mutate(deck.copyWith(slides: slides));
  }

  /// Splitst de bulletslide op [index] in pagina's van hooguit de leesbaarheids-
  /// drempel, met de overgebleven bullets op een laatste, kortere pagina; de
  /// vervolgpagina's komen er direct achter. Doet niets als de slide geen
  /// (genoeg) bullets heeft om te splitsen.
  void splitSlide(int index) {
    final deck = currentState.deck;
    if (deck == null || index < 0 || index >= deck.slides.length) return;
    final pages = splitBulletSlidePages(deck.slides[index]);
    if (pages == null) return;
    final slides = List<Slide>.from(deck.slides)
      ..removeAt(index)
      ..insertAll(index, pages);
    // De huidige slide krijgt nieuwe inhoud, dus forceer een editor-refresh.
    _mutate(deck.copyWith(slides: slides), bumpRevision: true);
  }

  /// Werkt alle automatisch én veilig oplosbare kwaliteitsproblemen in één keer
  /// weg (#915), met steeds de meest veilige oplossing: te volle dia's splitsen,
  /// meerzins-bullets opknippen, meegesleepte pagina's losmaken. Nooit wordt
  /// inhoud van een dia gehaald; wat menselijk oordeel vraagt blijft staan.
  ///
  /// Eén mutatie, dus één ongedaan-stap — wie de knop per ongeluk raakt draait
  /// alles met één keer terug. Geeft terug hoeveel structurele fixes zijn
  /// toegepast (0 = niets automatisch op te lossen; het deck blijft dan gelijk).
  int fixAllStructuralIssues() {
    final deck = currentState.deck;
    if (deck == null) return 0;
    final result = fixAllStructuralQualityIssues(deck);
    if (result.applied == 0) return 0;
    _mutate(result.deck, bumpRevision: true);
    return result.applied;
  }

  /// Knipt de vrije-tekstslide op [index] op zijn `#`-koppen: één dia per
  /// hoofdstuk, met de kop als titel. Doet niets als er niets te knippen valt.
  ///
  /// Eén mutatie, dus één keer ongedaan maken zet alles terug. Dat is de
  /// voorwaarde om dit als knop aan te durven bieden: wie het per ongeluk
  /// aanklikt op een lang document is niet twintig dia's aan het terugvoegen.
  void splitIntoChapters(int index) {
    final deck = currentState.deck;
    if (deck == null || index < 0 || index >= deck.slides.length) return;
    final chapters = splitRichTextIntoChapters(deck.slides[index]);
    if (chapters.length <= 1) return;
    final slides = List<Slide>.from(deck.slides)
      ..removeAt(index)
      ..insertAll(index, chapters);
    // De huidige slide krijgt nieuwe inhoud, dus forceer een editor-refresh.
    _mutate(deck.copyWith(slides: slides), bumpRevision: true);
  }

  /// Haalt de slide op [index] uit de split-run waar hij in zit: de reeks wordt
  /// er vóór én erna afgeknipt, zodat deze slide op zichzelf staat en de rest
  /// van de reeks weer op eigen grootte rendert.
  ///
  /// De tegenhanger van [splitSlide]. Nodig omdat de gedeelde tekstgrootte van
  /// een run het minimum is: één overvolle pagina drukt alle andere pagina's
  /// naar diezelfde grootte. Alleen de vlaggen gaan om — geen tekst verplaatst,
  /// niets samengevoegd, en dus met één stap ongedaan te maken.
  void detachSplitPage(int index) {
    final deck = currentState.deck;
    if (deck == null || index < 0 || index >= deck.slides.length) return;
    final slides = List<Slide>.from(deck.slides);
    // Knip vóór deze slide: hij is geen voortzetting meer.
    var changed = false;
    if (slides[index].continuesSplit) {
      slides[index] = slides[index].copyWith(continuesSplit: false);
      changed = true;
    }
    // En erna: de volgende slide zet de reeks niet op deze voort.
    final next = index + 1;
    if (next < slides.length && slides[next].continuesSplit) {
      slides[next] = slides[next].copyWith(continuesSplit: false);
      changed = true;
    }
    if (!changed) return;
    _mutate(deck.copyWith(slides: slides), bumpRevision: true);
  }

  /// Knip de videoslide op [index] op tijdstip [atMs]: het huidige segment
  /// `[start, eind]` wordt `[start, atMs]` op deze slide, en een nieuwe slide
  /// erna toont `[atMs, eind]` van dezelfde bron (opnieuw knipbaar). Doet niets
  /// als de slide geen video heeft of als het knippunt buiten het segment valt.
  void splitVideoSlide(int index, int atMs) {
    final deck = currentState.deck;
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
    final deck = currentState.deck;
    if (deck == null) return;
    final slides = List<Slide>.from(deck.slides);
    // Zelfde reden als bij [addSlide]: de indices komen uit de UI en kunnen
    // achterlopen op het deck.
    if (oldIndex < 0 || oldIndex >= slides.length) return;
    final slide = slides.removeAt(oldIndex);
    slides.insert(newIndex.clamp(0, slides.length), slide);
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
    final deck = currentState.deck;
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
    final deck = currentState.deck;
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

  /// Zet de dia's met een id in [originalsById] in één ongedaan-stap terug naar
  /// hun oorspronkelijke versie — voor het terugdraaien van session-data-edits
  /// (checklist/tabel) na een presentatie (#1235). Eén `_mutate`, dus één
  /// Ctrl+Z, ongeacht het aantal dia's. Een id die inmiddels verdwenen is
  /// (verwijderde dia) wordt stil genegeerd. bumpRevision dwingt de editor de
  /// teruggedraaide inhoud te tonen.
  void revertSlidesById(Map<String, Slide> originalsById) {
    final deck = currentState.deck;
    if (deck == null || originalsById.isEmpty) return;
    final slides = List<Slide>.from(deck.slides);
    var changed = false;
    for (var i = 0; i < slides.length; i++) {
      final orig = originalsById[slides[i].id];
      if (orig != null && slides[i] != orig) {
        slides[i] = orig;
        changed = true;
      }
    }
    if (!changed) return;
    _mutate(deck.copyWith(slides: slides), bumpRevision: true);
  }

  /// Zet (of wist) de sprong-uit van dia [index] (#1162): naar welke dia de
  /// presentatie na deze springt in plaats van de volgende in bronvolgorde.
  ///
  /// [targetIndex] `null` wist de sprong (terug naar lineair). Anders krijgt de
  /// doeldia zo nodig een uniek, bevroren anker — de gebruiker koos een dia, niet
  /// een anker — en wijst deze dia daarheen. Een sprong naar zichzelf of een
  /// ongeldige index wordt genegeerd. Beide dia's muteren in één stap.
  void setSlideJump(int index, int? targetIndex) {
    final deck = currentState.deck;
    if (deck == null) return;
    final slides = slidesWithJump(deck.slides, index, targetIndex);
    if (slides == null) return;
    _mutate(deck.copyWith(slides: slides), bumpRevision: true);
  }

  /// Laat menublok [blockIndex] van menudia [menuIndex] naar dia [targetIndex]
  /// wijzen (of, bij `null`, nergens) — en ken de doeldia zo nodig een anker toe
  /// (#1162). De gebruiker koos een dia, niet een anker.
  void setMenuBlockTarget(int menuIndex, int blockIndex, int? targetIndex) {
    final deck = currentState.deck;
    if (deck == null) return;
    final slides = slidesWithMenuTarget(
      deck.slides,
      menuIndex,
      blockIndex,
      targetIndex,
    );
    if (slides == null) return;
    _mutate(deck.copyWith(slides: slides), bumpRevision: true);
  }

  /// Zet de "overslaan"-status van een slide aan/uit. Overgeslagen slides
  /// worden weggelaten bij presenteren en exporteren.
  void toggleSkip(int index) {
    final deck = currentState.deck;
    if (deck == null || index < 0 || index >= deck.slides.length) return;
    final slides = List<Slide>.from(deck.slides);
    slides[index] = slides[index].copyWith(skipped: !slides[index].skipped);
    _mutate(deck.copyWith(slides: slides));
  }

  /// Hoeveel slides momenteel overgeslagen worden.
  int get skippedCount =>
      currentState.deck?.slides.where((s) => s.skipped).length ?? 0;

  /// Zet in één keer alle "overslaan"-markeringen uit (bijv. nadat je de
  /// presentatie hebt gegeven). No-op wanneer er niets overgeslagen wordt.
  void clearAllSkips() {
    final deck = currentState.deck;
    if (deck == null || !deck.slides.any((s) => s.skipped)) return;
    final slides = [
      for (final s in deck.slides) s.skipped ? s.copyWith(skipped: false) : s,
    ];
    _mutate(deck.copyWith(slides: slides));
  }

  /// Hoeveel checklist-items in de hele presentatie momenteel afgevinkt zijn.
  int get checkedChecklistCount {
    final deck = currentState.deck;
    if (deck == null) return 0;
    var total = 0;
    for (final s in deck.slides) {
      total += s.bullets.where(checklistItemChecked).length;
      total += s.bullets2.where(checklistItemChecked).length;
    }
    return total;
  }
}
