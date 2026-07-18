/// Eén test uit de OWASP MASTG-index: het stabiele id (`MASTG-TEST-0326`), de
/// canonieke Engelse [title], het [platform] waarvoor hij geldt, de
/// MASVS-[category] waar hij onder valt en de MASWE-zwakheid die hij verifieert.
///
/// Gebruikt door `MastgCatalog` om een `checklist`-slide te vullen met de
/// testlijst van de standaard, zoals [WstgTest] dat voor het web doet.
///
/// De MASTG is in v2.0.0 herbouwd tot een machineleesbare verzameling
/// componenten met stabiele id's. Dat is precies wat een checklist nodig heeft,
/// en de reden dat het bundelen van de *index* volstaat: de inhoud van elke
/// test blijft op mas.owasp.org staan, waar hij ook onderhouden wordt.
class MastgTest {
  const MastgTest({
    required this.id,
    required this.title,
    required this.platform,
    required this.category,
    required this.weakness,
  });

  /// Stabiel MASTG-id, bv. `MASTG-TEST-0326`.
  final String id;

  /// Canonieke Engelse titel.
  final String title;

  /// `android`, `ios` of `network`.
  final String platform;

  /// MASVS-categorie, bv. `MASVS-AUTH`.
  final String category;

  /// De MASWE-zwakheid die deze test verifieert, bv. `MASWE-0045`. Leeg wanneer
  /// de bron er geen noemt.
  final String weakness;
}
