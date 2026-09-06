part of 'slide.dart';

/// Broad grouping a [SlideType] belongs to, used by the add-slide picker to
/// offer category tabs. The picker derives its tabs from the categories that
/// are actually present.
enum SlideCategory {
  general,
  informationSecurity,
  procesverbetering,
  managementsysteem,
  eLearning,
}

/// Hoeveel kolommen doorlopende bullettekst een [SlideType] toont.
enum BulletColumns { none, one, two }

/// The part a slide plays inside a finding group.
enum FindingRole { header, detail, evidence }

enum ListStyle { bullets, numbered, checklist, richText }

/// Native Marp image-column layout for a title slide (#1405).
enum TitleColumnLayout { none, left, right, both }

/// Per-kolomuitlijning uit de GFM-scheidingsrij van een tabel.
enum TableAlign { left, center, right }

extension SlideTypeExtension on SlideType {
  String get label => slideTypeMeta[this]!.label;
  String get marpClass => slideTypeMeta[this]!.marpClass;

  /// True for the bulletsImage split layout (body beside an inline image).
  bool get splitWithImage => slideTypeMeta[this]!.splitWithImage;

  /// True for a title/section heading slide.
  bool get isHeading => slideTypeMeta[this]!.isHeading;

  /// The picker category this type belongs to.
  SlideCategory get category => slideTypeMeta[this]!.category;

  /// Hoeveel kolommen doorlopende bullettekst dit type toont.
  BulletColumns get bulletColumns => slideTypeMeta[this]!.bulletColumns;

  /// True when the type's content lives in [Slide.tableRows] and round-trips
  /// through the shared table writer/reader. See [SlideTypeMeta.backedByTable].
  bool get backedByTable => slideTypeMeta[this]!.backedByTable;

  /// Informatieveiligheid scaffold types (P1-S) whose body is still stored as
  /// free Markdown in [Slide.customMarkdown] and round-trips like a free-Markdown
  /// slide until each type's structured serialiser lands. `checklist` (P1-CHK),
  /// `scopeMatrix` (P1-SCOPE) and `findingsSummary` (P1-SUM) graduated to real
  /// Markdown tables in [Slide.tableRows]; `signOff` (P1-SIGN) stores only an
  /// optional heading (its attestation is deck-level), so all four are excluded
  /// here. Only `finding` (P1-FIND) still uses the scaffold body.
  ///
  /// De drie afgestudeerde types worden aan [backedByTable] herkend in plaats
  /// van bij naam: een nieuw tabelgedragen module-type is dan meteen goed
  /// ingedeeld, in plaats van stil als scaffold-Markdown te worden gelezen.
  bool get usesScaffoldMarkdownBody =>
      category == SlideCategory.informationSecurity &&
      !backedByTable &&
      this != SlideType.signOff;

  /// eLearning types whose body is plain Markdown in [Slide.customMarkdown],
  /// written by `_writeFreeMarkdownSlide` and read back by
  /// `_parsedCustomMarkdown`.
  ///
  /// Dit predicaat bestaat omdat schrijver en lezer hier uit elkaar liepen
  /// (#1999): er wérd een body geschreven, maar het inlezen kende de
  /// eLearning-types niet en gaf een lege `customMarkdown` terug. De dia leek
  /// daardoor gewoon te openen, en de eerstvolgende opslag schreef de tekst van
  /// de auteur weg — zonder melding. Eén gedeelde bron voorkomt dat de twee
  /// kanten opnieuw kunnen verschillen.
  ///
  /// De regel is de categorie, niet een lijst namen, zodat een nieuw
  /// tekstgedragen eLearning-type meteen goed staat. Komt er ooit een
  /// eLearning-type dat zijn inhoud níet als vrije Markdown bewaart — een
  /// tabelgedragen of gestructureerd type — dan hoort het hier expliciet
  /// uitgezonderd te worden, net als bij [usesScaffoldMarkdownBody].
  bool get usesFreeMarkdownBody =>
      category == SlideCategory.eLearning && !backedByTable;
}
