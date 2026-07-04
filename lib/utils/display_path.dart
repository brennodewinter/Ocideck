import 'package:path/path.dart' as p;

/// Leesbare vindplaats van een bestand voor open-lijsten (recente
/// presentaties, zoekresultaten): de mág, niet het hele pad — de bestandsnaam
/// staat er als titel al boven. Volledige paden zijn in een smalle lijst
/// onbruikbaar: de gemeenschappelijke prefix eet de ruimte op en juist het
/// onderscheidende einde valt door de ellipsis weg. Toon het volledige pad in
/// een tooltip; deze functie levert de korte vorm:
///
/// - onder de thuismap voor presentaties → `OciDeck › Proefpresentatie (2)`
///   (de mapnaam van de thuismap als anker, dan het relatieve pad);
/// - anders onder de OS-thuismap → `~/Vigilis/Presentaties`;
/// - anders het volledige mappad.
String displayFolder(String filePath, {String? homeDir, String? osHome}) {
  final dir = p.normalize(p.dirname(filePath));

  if (homeDir != null && homeDir.trim().isNotEmpty) {
    final home = p.normalize(homeDir);
    if (p.equals(dir, home) || p.isWithin(home, dir)) {
      final anchor = p.basename(home);
      if (p.equals(dir, home)) return anchor;
      final rel = p.split(p.relative(dir, from: home)).join(' › ');
      return '$anchor › $rel';
    }
  }

  if (osHome != null && osHome.trim().isNotEmpty) {
    final home = p.normalize(osHome);
    if (p.equals(dir, home)) return '~';
    if (p.isWithin(home, dir)) {
      return p.join('~', p.relative(dir, from: home));
    }
  }

  return dir;
}
