// De eigen-identiteitslijst.
//
// De grootste praktische vals-positieven-bron van de hele scanner is de auteur
// zelf: zijn naam op de titelslide, zijn e-mailadres in de footer, zijn
// telefoonnummer op de contactslide. Dat zijn geen bevindingen — dat is de
// afzender. Zonder deze lijst vuurt vrijwel élk deck onterecht, en wel op de ene
// slide die er altijd in zit.
//
// Het is bewust een lijst en geen slimmigheid. Een heuristiek die probeert te
// raden wie de auteur is (uit de frontmatter, uit het OS-account) zit er soms
// naast, en dan onderdrukt hij juist wél een echte bevinding. Een expliciete
// lijst zit er nooit naast: hij bevat precies wat de gebruiker erin heeft gezet.

/// Normaliseert een waarde voor vergelijking: kleine letters, geen spaties,
/// streepjes of punten in getallen.
String _normalise(String raw) =>
    raw.trim().toLowerCase().replaceAll(RegExp(r'[\s()\-]'), '');

/// De eigen gegevens van de gebruiker: namen, e-mailadressen, telefoonnummers,
/// organisatiedomeinen. Eén per regel.
class OwnIdentity {
  final List<String> entries;

  const OwnIdentity(this.entries);

  static const empty = OwnIdentity([]);

  /// Uit het vrije tekstveld in de instellingen: één opgave per regel, lege
  /// regels weg.
  factory OwnIdentity.fromLines(String text) => OwnIdentity([
    for (final line in text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ]);

  String toLines() => entries.join('\n');

  bool get isEmpty => entries.isEmpty;

  /// Hoort deze gevonden waarde bij de gebruiker zelf?
  ///
  /// Twee manieren, allebei exact:
  ///
  ///   * een exacte match na normalisatie — `Brenno@dewinter.com` dekt
  ///     `brenno@dewinter.com`, maar niet het adres van een collega;
  ///   * een domeinopgave dekt elk adres eronder — `politie.nl` dekt
  ///     `j.jansen@politie.nl` en `pers@woordvoering.politie.nl`, zodat een
  ///     organisatie niet elke collega hoeft op te sommen.
  ///
  /// Bewust **geen** losse substring-match. Die zou `politie.nl` ook
  /// `j.jansen@nietpolitie.nl` laten dekken — een adres van een heel andere
  /// organisatie, stilletjes onderdrukt. Wie zich hierin vergist, onderdrukt een
  /// échte bevinding, en dat is precies het soort fout dat je niet merkt.
  bool covers(String value) {
    if (entries.isEmpty) return false;
    final needle = _normalise(value);
    if (needle.isEmpty) return false;

    for (final entry in entries) {
      final own = _normalise(
        entry.startsWith('@') ? entry.substring(1) : entry,
      );
      if (own.isEmpty) continue;
      if (needle == own) return true;

      // Een domeinopgave (geen apenstaartje, wel een punt) dekt elk adres
      // eronder. De grens is een punt of een apenstaartje — `nietpolitie.nl`
      // eindigt weliswaar op `politie.nl`, maar niet op `.politie.nl`.
      if (!own.contains('@') && own.contains('.')) {
        if (needle.endsWith('@$own') || needle.endsWith('.$own')) return true;
      }
    }
    return false;
  }
}
