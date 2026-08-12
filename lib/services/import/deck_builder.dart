import '../../models/deck.dart';
import '../../models/slide.dart';
import '../markdown_safety.dart';
import '../web_asset_store.dart';
import 'import_loss.dart';
import 'models/slide_failure_policy.dart';
import 'models/source_deck.dart';
import 'pipeline/problem_slide.dart';
import 'pipeline/slide_classifier.dart';
import 'pipeline/unconverted_tracker.dart';
import 'slide_factory.dart';

export 'slide_factory.dart' show kImportedBulletLimit, kImportedTableRowLimit;

/// The outcome of building an OciDeck [Deck] from a classified source deck: the
/// deck itself plus the [ProblemSlide]s that carried real (non-salvaged) loss,
/// which the UI surfaces for a per-slide decision.
class BuiltDeck {
  const BuiltDeck({
    required this.deck,
    required this.problemSlides,
    this.safetyFindings = const [],
  });

  final Deck deck;
  final List<ProblemSlide> problemSlides;

  /// De uitkomst van de fail-closed backstop: uitvoerbare inhoud die na het
  /// bouwen tóch in het gegenereerde `.md` bleef staan (#876). Leeg = veilig.
  /// Niet-leeg betekent dat de import geweigerd hoort te worden — de importbouw
  /// neutraliseert brontekst, maar de definitieve serialisatie wordt hier nog
  /// eens door dezelfde poort gehaald die ook een vreemd bestand bij het openen
  /// tegenhoudt, zodat een geïmporteerd deck niet alsnog geweigerd wordt bij het
  /// heropenen.
  final List<MarkdownSafetyFinding> safetyFindings;
}

/// Turns a format-neutral [SourceDeck] plus its per-slide [ClassifiedSlide]s
/// into a real OciDeck [Deck] built on the actual `Slide`/`Deck` model.
///
/// This is Keiko's writer replaced on OciDeck's own object model: instead of
/// emitting Marp Markdown, it constructs `Slide` objects via
/// [Slide.create] + [Slide.copyWith] and lets the existing
/// `MarkdownService`/`FileService` serialise them. Nothing here writes Markdown
/// text for a structured slide — only free-Markdown note/salvage bodies, which
/// are genuinely free text.
///
/// De verantwoordelijkheden zijn gesplitst (#878): het bouwen van de echte
/// `Slide`-objecten en het materialiseren van afbeeldingen zit in
/// [SlideFactory], de verliesanalyse in `import_loss.dart`. [DeckBuilder] is de
/// orkestrator die per dia het [SlideFailurePolicy]-beleid bepaalt en die
/// collaborators aanroept.
///
/// ## Image materialisation
///
/// Each [SourceImage] carries raw [SourceImage.bytes]. Rather than Keiko's
/// shared `images/<sha256>` scheme, the builder hands the bytes to
/// [WebAssetStore.put], which returns a `mem:` path, and stores that path in the
/// slide's `imagePath`. When [FileService.saveDeck] later runs,
/// `ImageService.copyImagesToProject` materialises every `mem:` path into the
/// deck's own `images/` folder with content-based de-dup
/// (`resolveAssetDestinationForBytes`) — the exact route a remote (`mem:`) deck
/// already takes on save. So the bytes travel with the deck, land per-deck, and
/// de-dup on save without this layer touching the filesystem (web-safe).
///
/// Identical images are de-duped up front too: the same bytes (by SHA-256) reuse
/// one `mem:` path, so a logo repeated on ten slides becomes one store entry and
/// materialises once — de-dup by content, but through the idiomatic filename,
/// not a `<sha256>.<ext>` name.
class DeckBuilder {
  /// Bouwt een deck; [translate] vertaalt de notitietekst die in het document
  /// van de gebruiker belandt.
  ///
  /// De naad zit op de bouwer en niet in elke methodesignatuur: de service
  /// maakt één [DeckBuilder] met `l10n.d` erin, en alles wat een notitiedia
  /// schrijft gebruikt dezelfde functie. Zonder een UI (een test, een
  /// opdrachtregel) is het [identityTranslator] en blijft de tekst Nederlands.
  /// De keuze om híer te vertalen en niet bij het tonen is bewust: de
  /// notitiedia is inhoud die in het `.md` wordt opgeslagen (#806) — zie
  /// [UnconvertedTracker].
  DeckBuilder({this.translate = identityTranslator})
    : _factory = SlideFactory(translate);

  /// Vertaalt één Nederlandse bronstring; zie [ImportTextTranslator].
  final ImportTextTranslator translate;

  /// Eén [SlideFactory] per deck: de mem-path-cache erin moet over alle dia's
  /// van dít deck consistent blijven, en [build] wordt één keer per import
  /// aangeroepen.
  final SlideFactory _factory;

  /// Build an OciDeck [Deck] from [sourceDeck] and its [classified] slides
  /// (aligned by order). [title] becomes the deck title.
  BuiltDeck build(
    SourceDeck sourceDeck,
    List<ClassifiedSlide> classified, {
    required String title,
    Map<int, SlideFailurePolicy> policies = const {},
  }) => WebAssetStore.atomic(
    () => _build(sourceDeck, classified, title: title, policies: policies),
  );

  BuiltDeck _build(
    SourceDeck sourceDeck,
    List<ClassifiedSlide> classified, {
    required String title,
    required Map<int, SlideFailurePolicy> policies,
  }) {
    final slides = <Slide>[];
    final problemSlides = <ProblemSlide>[];

    for (final c in classified) {
      final issues = conversionIssuesFor(c);
      final realLoss = issues.where((i) => !i.isSalvaged).toList();

      // Het beleid geldt alleen voor een dia met écht verlies. Een dia die
      // schoon converteert laat je met rust, ook als de gebruiker "overslaan"
      // als algemene voorkeur koos — anders gooit één keuze zijn hele deck weg.
      final policy = realLoss.isEmpty
          ? SlideFailurePolicy.bestEffort
          : (policies[c.source.index] ?? SlideFailurePolicy.bestEffort);
      final effective =
          policy == SlideFailurePolicy.imageOnly && c.source.images.isEmpty
          // Een afbeeldingsdia zonder afbeelding is niets; dan is overslaan
          // eerlijker dan een lege dia.
          ? SlideFailurePolicy.skip
          : policy;

      var slideAdded = false;
      switch (effective) {
        case SlideFailurePolicy.bestEffort:
          slides.add(_factory.buildSlide(c));
          slideAdded = true;
        case SlideFailurePolicy.imageOnly:
          slides.add(_factory.imageOnlySlide(c.source));
          slideAdded = true;
        case SlideFailurePolicy.skip:
          break;
      }

      if (issues.isNotEmpty) {
        if (slideAdded) {
          // Zet de niet-overgenomen inhoud in de notities van de dia zelf, niet
          // op een aparte notitiedia. De gebruiker ziet direct wat wegviel bij
          // de dia waar het bij hoort, in het notitiepaneel van de editor.
          final noteText = UnconvertedTracker.buildNoteBody(
            c.source.index + 1,
            issues,
            heading: _factory.headingFor(effective, c.source.index + 1),
            translate: translate,
          );
          final last = slides.removeLast();
          slides.add(last.copyWith(notes: noteText));
        } else {
          // De dia werd overgeslagen — er is niets om aan vast te hangen, dus
          // behoud de aparte notitiedia.
          slides.add(
            _factory.noteSlide(
              c.source.index + 1,
              issues,
              heading: _factory.headingFor(effective, c.source.index + 1),
            ),
          );
        }
      }
      if (realLoss.isNotEmpty) {
        problemSlides.add(problemSlide(c.source, realLoss));
      }
    }

    if (sourceDeck.issues.isNotEmpty) {
      slides.add(_factory.deckNoteSlide(sourceDeck.issues));
    }

    final deck = Deck(title: title, author: sourceDeck.author, slides: slides);
    return BuiltDeck(deck: deck, problemSlides: problemSlides);
  }

  /// De probleemdia's van [classified], zónder een deck te bouwen.
  ///
  /// Het beslismoment valt tússen classificeren en bouwen: de gebruiker moet
  /// kunnen kiezen wát er met een dia gebeurt vóórdat die dia er is. Dit is
  /// dezelfde verliesberekening als [build] doet, maar zonder dia's te
  /// construeren of afbeeldingen te materialiseren — vragen mag niet duurder
  /// zijn dan doen.
  List<ProblemSlide> analyse(List<ClassifiedSlide> classified) => [
    for (final c in classified)
      if (conversionIssuesFor(c).where((i) => !i.isSalvaged).toList()
          case final realLoss when realLoss.isNotEmpty)
        problemSlide(c.source, realLoss),
  ];
}
