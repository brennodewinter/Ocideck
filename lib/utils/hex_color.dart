/// De `RRGGBB`-vorm van een profielkleur: zonder hekje, in hoofdletters.
///
/// Profielkleuren zijn `#RRGGBB`-tekst, maar exportformaten willen de kleur
/// anders: OOXML (`w:color`, `w:shd`) zonder hekje, ODF (`fo:color`) mét
/// hekje. Deze omzetting staat één keer hier; de DOCX- en ODT-export
/// gebruiken hem allebei.
///
/// Acht tekens betekent dat de doorzichtigheid vooraan staat (`#AARRGGBB`) —
/// die kennen de documentformaten niet op tekst, dus alleen de kleur telt.
/// Een waarde die geen zes hex-cijfers oplevert wordt `000000`: een kleur
/// die op het papier-wit van een export altijd leesbaar is.
String hexRgbTriplet(String color) {
  final cleaned = color.trim().replaceFirst('#', '');
  final rgb = cleaned.length > 6
      ? cleaned.substring(cleaned.length - 6)
      : cleaned;
  if (!RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(rgb)) return '000000';
  return rgb.toUpperCase();
}
