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

  /// Korte omschrijving — de `requirement:` uit de bron, één zin over wat de
  /// app moet doen. Leeg wanneer de bron er geen geeft.
  ///
  /// Vroeger was er ook een [isPlaceholder]-vlag: driekwart van MASWE was toen
  /// nog concept. Bij de herbouw medio 2026 heeft OWASP alle 78 zwakheden
  /// uitgeschreven, en daarmee verviel het onderscheid.
  final String description;
}
