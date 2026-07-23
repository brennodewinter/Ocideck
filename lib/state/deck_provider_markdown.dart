part of 'deck_provider.dart';

/// Markdown-modus: de hele presentatie of één slide als Marp-markdown
/// genereren en weer inlezen. Losgetrokken uit [DeckNotifier] om het
/// hoofdbestand onder de regellimiet te houden; als extension in dezelfde
/// library houdt het toegang tot `_md`, `_mutate` en `currentState`.
extension DeckNotifierMarkdown on DeckNotifier {
  String generateMarkdown() {
    final deck = currentState.deck;
    // Inline linked chart data so a markdown round-trip (toggle, recovery
    // snapshot) keeps the chart's points. Saving to disk still writes the
    // source-only form (see FileService._writeProject), so the .md stays clean.
    return deck != null ? _md.generateDeck(deck, inlineChartData: true) : '';
  }

  /// De markdown van één slide (zonder front matter), voor de per-slide
  /// markdown-weergave in het rechterpaneel. Inline chart-data zodat een
  /// round-trip de grafiekpunten behoudt, net als [generateMarkdown].
  String generateSlideMarkdown(int index) {
    final deck = currentState.deck;
    if (deck == null || index < 0 || index >= deck.slides.length) return '';
    return _md.generateSlide(
      deck.slides[index],
      themeProfile: deck.themeProfile,
      inlineChartData: true,
    );
  }

  /// Returns false if parsing fails (content is preserved).
  bool applyMarkdown(String markdown) {
    final parsed = _md.parseDeck(markdown, filePath: currentState.filePath);
    if (parsed == null) return false;
    // The markdown carries only content; keep the deck's current styling rather
    // than resetting it to the default profile the parser returns.
    final current = currentState.deck;
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
    // De MIAUW-dispositie staat sinds 0.1.0 niet meer in de markdown (ze ligt
    // in de `.miauw.json`-sidecar). Zonder dit zou één keer schakelen naar de
    // markdown-weergave de uitsluitingen en klantbevestigingen wissen, en de
    // eerstvolgende opslag die sidecar met ze erin.
    //
    // Hetzelfde geldt sindsdien voor het zegel en de handtekening
    // (`.seal.json`). Een verzegeld deck komt hier niet eens langs — [_mutate]
    // weigert elke bewerking — maar een handtekening die op de akkoorddia is
    // opgesteld en nog niet verzegeld, wél. Zonder deze regel was die na één
    // keer schakelen weg, en de eerstvolgende opslag had de sidecar erbij
    // opgeruimd. De bestandshash reist mee om dezelfde reden dat hij bestaat:
    // hij hoort bij het bestand op schijf, niet bij de tekst in de editor.
    if (current != null) {
      deck = SealRecord.of(current)
          .applyTo(deck)
          .copyWith(
            miauw: current.miauw,
            fileHash: current.fileHash,
          );
    }
    _mutate(deck); // discrete stap → ook ongedaan te maken
    return true;
  }

  /// Vervang de slide op [index] door de geparste markdown [markdown]. Het
  /// fragment draagt alleen slide-inhoud (geen front matter); [MarkdownService]
  /// leest een kop-loze body prima in. Voegt de gebruiker `---`-scheidingen toe,
  /// dan splitst dit de slide in meerdere. Returns false als parsen faalt
  /// (de inhoud blijft dan behouden). Notities en annotaties worden — net als
  /// bij [applyMarkdown] — op inhoud/positie her-ankerd naar de nieuwe slides.
  bool applySlideMarkdown(int index, String markdown) {
    final current = currentState.deck;
    if (current == null || index < 0 || index >= current.slides.length) {
      return false;
    }
    // Een leeg fragment parseert wél naar een (lege) slide; behandel het als
    // geen-wijziging zodat een per ongeluk leeggemaakt buffer de slide niet wist.
    if (markdown.trim().isEmpty) return false;
    final parsed = _md.parseDeck(markdown, filePath: currentState.filePath);
    if (parsed == null || parsed.slides.isEmpty) return false;
    final slides = [...current.slides]
      ..replaceRange(index, index + 1, parsed.slides);
    var deck = current.copyWith(slides: slides);
    if (current.userNotes.isNotEmpty) {
      final encoded = UserNotesCodec.encode(current.slides, current.userNotes);
      final remapped = encoded != null
          ? UserNotesCodec.decode(encoded, deck.slides)
          : const <String, String>{};
      deck = deck.copyWith(userNotes: remapped);
    }
    if (current.annotations.isNotEmpty) {
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
}
