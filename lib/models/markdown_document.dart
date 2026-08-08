import '../utils/document_front_matter.dart';
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

  /// De inhoud zonder het leidende YAML-frontmatter-blok. De editor bewerkt en
  /// toont dít — de frontmatter draagt alleen de stijl en wordt niet als tekst
  /// getoond. Altijd geldt `frontMatter + body == source`.
  String get body => documentBody(source);

  /// Het verbatim frontmatter-blok (of `''`) dat de stijl draagt.
  String get frontMatter => splitDocumentFrontMatter(source).block;

  /// De gekozen documentstijl: de naam van een stijlprofiel uit de `theme:`-
  /// sleutel in de frontmatter, of `null` bij een platte `.md` zonder stijl.
  String? get styleName => documentStyleName(source);

  /// Een nieuw document met dezelfde frontmatter maar een vervangen body. De
  /// stijl blijft staan; alleen de inhoud verandert.
  MarkdownDocument withBody(String nextBody) =>
      withSource(frontMatter + nextBody);

  /// Een nieuw document met de stijl gezet op [name] (of verwijderd bij `null`).
  /// Byte-chirurgisch: een platte `.md` zonder stijl blijft byte-identiek als je
  /// stijl zet en weer wist (zie [withDocumentStyleName]).
  MarkdownDocument withStyleName(String? name) =>
      withSource(withDocumentStyleName(source, name));

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
