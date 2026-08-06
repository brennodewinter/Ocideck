import 'markdown_kind.dart';
import 'markdown_outline.dart';
import 'markdown_source_document.dart';

/// Een doorlopend Markdown-document dat OciDeck bewerkt en byte-getrouw op
/// schijf bewaart als een plat `.md` (zie `docs/design/DOCUMENT_MODE.md`).
///
/// Anders dan een `Deck`, dat de Markdown deconstruéért tot getypeerde slides en
/// die terugschrijft (dus verliest wat het niet kan voorstellen), *ís* een
/// document de bron zelf: [toMarkdown] geeft exact de bytes terug die erin
/// gingen — geen `marp:`-kop, geen dia-scheiding, geen normalisatie. Het leunt
/// op [MarkdownSourceDocument], dat de bron verbatim vasthoudt en er alleen
/// structurele bereiken en een koppenoverzicht uit afleidt (voor navigatie en
/// blok-bewerkingen) zonder ook maar één byte te wijzigen.
class MarkdownDocument {
  const MarkdownDocument._(this._source);

  final MarkdownSourceDocument _source;

  /// Leest een document uit de ruwe bytes van een `.md`. Normaliseert niets:
  /// regeleindes, onzichtbare tekens en een ontbrekende slot-newline blijven
  /// exact staan.
  factory MarkdownDocument.parse(String source) =>
      MarkdownDocument._(MarkdownSourceDocument.parse(source));

  /// De soort is per definitie [MarkdownKind.document]; een presentatie loopt
  /// via `Deck`. Bedoeld voor plekken die generiek over een geopend bestand
  /// redeneren (tabblad, recente-lijst).
  MarkdownKind get kind => MarkdownKind.document;

  /// De ruwe bron, byte-identiek aan wat is ingelezen.
  String get source => _source.source;

  /// Wat naar schijf gaat: exact de bron. Nooit her-serialiseren — dat is de
  /// rode lijn die een plat document plat en maximaal uitwisselbaar houdt.
  String toMarkdown() => _source.source;

  /// De koppenstructuur (voor de Overzicht-rail), afgeleid zonder te reparsen.
  List<MarkdownOutlineEntry> get outline => _source.outline;

  /// Het onderliggende bronmodel, voor blok-precieze bewerkingen (bv. één tabel
  /// of grafiek vervangen zonder de rest aan te raken).
  MarkdownSourceDocument get sourceDocument => _source;

  bool get isEmpty => _source.source.isEmpty;

  /// Vervangt de hele inhoud — bijvoorbeeld na een bewerking in de editor — en
  /// levert een nieuw document op. De identiteit van ongewijzigde blokken blijft
  /// behouden, zodat cursor- en selectiestand niet nodeloos verspringen.
  MarkdownDocument withSource(String next) =>
      MarkdownDocument._(_source.reparse(next));
}
