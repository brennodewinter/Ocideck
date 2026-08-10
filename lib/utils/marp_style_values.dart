/// Marp-stijlwaarden die Flutter en HTML exact hetzelfde moeten uitleggen.
library;

/// Hoogstens zoveel afbeeldingsfilters worden tijdens één render toegepast.
///
/// De bronlijst blijft intact voor round-trips; alleen de dure renderlaag is
/// begrensd.
const int kMaxRenderedMarpImageFilters = 32;

/// Geeft een veilige, genormaliseerde Marp-kleur of `null`.
///
/// Beide renderers gebruiken bewust dezelfde kleine CSS-subset: #rgb,
/// #rrggbb, #rrggbbaa en de hieronder genoemde kleuren. Zo kan HTML geen
/// kleurvorm accepteren die Flutter vervolgens anders of helemaal niet toont.
String? normalizeMarpColor(String source) {
  final value = source.trim().toLowerCase();
  if (value.isEmpty) return null;
  if (RegExp(r'^#[0-9a-f]{6}(?:[0-9a-f]{2})?$').hasMatch(value)) return value;
  final short = RegExp(r'^#([0-9a-f])([0-9a-f])([0-9a-f])$').firstMatch(value);
  if (short != null) {
    final r = short.group(1)!;
    final g = short.group(2)!;
    final b = short.group(3)!;
    return '#$r$r$g$g$b$b';
  }
  return _namedMarpColors[value];
}

const _namedMarpColors = <String, String>{
  'black': '#000000',
  'blue': '#0000ff',
  'cyan': '#00ffff',
  'gray': '#808080',
  'green': '#008000',
  'grey': '#808080',
  'lime': '#00ff00',
  'magenta': '#ff00ff',
  'maroon': '#800000',
  'navy': '#000080',
  'olive': '#808000',
  'orange': '#ffa500',
  'purple': '#800080',
  'red': '#ff0000',
  'silver': '#c0c0c0',
  'teal': '#008080',
  'transparent': '#00000000',
  'white': '#ffffff',
  'yellow': '#ffff00',
};
