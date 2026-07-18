/// Eén zwakheid uit de OWASP Mobile Application Security Weakness Enumeration
/// (MASWE) — de mobiele tegenhanger van MITRE's CWE.
///
/// MASTG-tests verwijzen ernaar (`MastgTest.weakness`): een test verifieert een
/// zwakheid. Andersom draagt een zwakheid een [cweIds]-koppeling, waarmee een
/// mobiele bevinding ook in de CWE-taal te leggen valt die OciDeck al bundelt.
class MasweWeakness {
  const MasweWeakness({
    required this.id,
    required this.title,
    required this.category,
    required this.platforms,
    required this.cweIds,
    required this.isPlaceholder,
    this.description = '',
  });

  /// Stabiel MASWE-id, bv. `MASWE-0005`.
  final String id;

  /// Canonieke Engelse titel.
  final String title;

  /// MASVS-categorie, bv. `MASVS-AUTH`.
  final String category;

  /// `android`, `ios` of beide.
  final List<String> platforms;

  /// De CWE-nummers waar deze zwakheid op uitkomt; leeg als de bron er geen
  /// noemt.
  final List<int> cweIds;

  /// OWASP heeft de zwakheid wél benoemd maar de uitleg nog niet geschreven.
  ///
  /// Dit is bewust géén reden om hem weg te laten, en daarin verschilt MASWE
  /// van MASTG. Een MASTG-placeholder belooft een test die niemand kan
  /// uitvoeren; een MASWE-placeholder is een zwakheid die wél is
  /// geïdentificeerd — met id, titel, CWE-koppeling en een conceptomschrijving
  /// — alleen is de toelichtingspagina nog leeg. Ernaar verwijzen in een
  /// bevinding is dus gewoon juist. Wie de uitleg wil, moet weten dat die nog
  /// dun is, en daarvoor staat deze vlag hier.
  final bool isPlaceholder;

  /// Korte omschrijving; bij een placeholder komt die uit het `draft`-blok.
  /// Leeg wanneer de bron er geen geeft.
  final String description;
}
