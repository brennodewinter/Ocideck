/// De soort van een Markdown-bestand dat OciDeck beheert.
///
/// [presentation] is een Marp/OciDeck-deck: zijn front matter draagt `marp: true`
/// (de deck-serialiser schrijft dat altijd). [document] is een gewoon,
/// doorlopend Markdown-document zonder die markering — een plat `.md` dat elke
/// Markdown-lezer opent (zie `docs/design/DOCUMENT_MODE.md`).
///
/// De soort wordt nooit als een eigen sleutel op schijf gezet: hij volgt uit de
/// *afwezigheid* van `marp: true`, zodat een plat bestand plat blijft. Deze enum
/// draagt de soort alleen dóór de app heen (de recente-lijst, straks de
/// tabbladen); de detectie zelf leunt op de bestaande
/// `MarkdownService.sniffFrontmatter` — er komt geen tweede mechanisme bij.
enum MarkdownKind { presentation, document }

extension MarkdownKindX on MarkdownKind {
  bool get isDocument => this == MarkdownKind.document;
  bool get isPresentation => this == MarkdownKind.presentation;

  /// Stabiele sleutel voor opslag (de recente-lijst in prefs).
  String get key => switch (this) {
    MarkdownKind.presentation => 'presentation',
    MarkdownKind.document => 'document',
  };

  /// Leest een sleutel terug; een onbekende of ontbrekende waarde valt terug op
  /// [MarkdownKind.presentation] — elk bestaand recente-item is een deck, dus
  /// dat is de veilige, achterwaarts compatibele standaard.
  static MarkdownKind fromKey(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'document' => MarkdownKind.document,
        _ => MarkdownKind.presentation,
      };
}
