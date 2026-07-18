/// Eén hulpmiddel dat bij het onderzoek is gebruikt (MIAUW EIS 4.8.2).
///
/// De eis splitst in drieën en die drie zijn precies de velden hier:
/// beschrijving (4.8.2.1), versienummer (4.8.2.2) en een publieke referentie
/// (4.8.2.3). Het versienummer staat er bevroren bij, om dezelfde reden als bij
/// de gebruikte standaarden: een rapport verantwoordt achteraf waarmee is
/// gewerkt, en die tool is inmiddels alweer een paar keer bijgewerkt.
class UsedTool {
  final String name;
  final String version;
  final String url;
  final String description;

  const UsedTool({
    required this.name,
    this.version = '',
    this.url = '',
    this.description = '',
  });

  /// Op één regel: `naam@versie | url | beschrijving`.
  ///
  /// Dezelfde `naam@versie`-vorm als bij de standaarden, zodat er één conventie
  /// te onthouden is. Lege staartvelden worden weggelaten in plaats van als
  /// lege pijpen te blijven staan.
  String format() {
    final head = version.isEmpty ? name : '$name@$version';
    final tail = [url, description];
    while (tail.isNotEmpty && tail.last.trim().isEmpty) {
      tail.removeLast();
    }
    return [head, ...tail].join(' | ');
  }

  /// Leest [format] terug. Geeft null voor een regel zonder naam.
  ///
  /// Tolerant met opzet: dit veld wordt met de hand getypt. Een ontbrekende URL
  /// of beschrijving is geen fout maar een onvolledig ingevuld hulpmiddel, en
  /// dat mag de gebruiker zelf zien in plaats van dat de regel verdwijnt.
  static UsedTool? parse(String line) {
    final parts = line.split('|').map((p) => p.trim()).toList();
    final head = parts.isEmpty ? '' : parts.first;
    if (head.isEmpty) return null;

    final at = head.lastIndexOf('@');
    final name = at <= 0 ? head : head.substring(0, at).trim();
    final version = at <= 0 ? '' : head.substring(at + 1).trim();
    if (name.isEmpty) return null;

    return UsedTool(
      name: name,
      version: version,
      url: parts.length > 1 ? parts[1] : '',
      description: parts.length > 2 ? parts.sublist(2).join(' | ').trim() : '',
    );
  }

  /// Alle regels uit een meerregelig tekstveld, lege regels overgeslagen.
  static List<UsedTool> parseAll(String text) =>
      text.split('\n').map(parse).whereType<UsedTool>().toList();

  /// Niets van de eis is ingevuld behalve de naam — de gebruiker is halverwege.
  bool get isIncomplete =>
      version.isEmpty || url.isEmpty || description.isEmpty;
}

/// De bijlagetabel zoals MIAUW hem vraagt: kopregel plus één rij per hulpmiddel.
///
/// Kolomvolgorde volgt de eisnummering (4.8.2.1 beschrijving, .2 versie,
/// .3 referentie), met de naam ervoor omdat een tabel zonder naam niet te lezen
/// is. De kopteksten komen van de aanroeper zodat ze in de taal van het
/// *rapport* staan en niet in die van de interface.
List<List<String>> toolsAppendixRows(
  List<UsedTool> tools, {
  required String nameHeader,
  required String descriptionHeader,
  required String versionHeader,
  required String referenceHeader,
}) => [
  [nameHeader, descriptionHeader, versionHeader, referenceHeader],
  for (final t in tools) [t.name, t.description, t.version, t.url],
];
