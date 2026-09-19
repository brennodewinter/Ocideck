// Welke aangeboden letter een vreemde lettertypenaam vervangt.
//
// Een geïmporteerd Word- of LibreOffice-document vraagt om een letter die
// OciDeck meestal niet kan tonen: `Aptos`, `Cambria`, `Neue Haas Grotesk`. De
// naam zelf bewaren we in het profiel (`preferredFontFamily`), zodat een export
// hem weer kan noemen; op het scherm moet er intussen íéts staan dat in de
// buurt komt. Dat "in de buurt" is hier bewust grof: schreef, schreefloos of
// vaste breedte. Fijner onderscheid (humanistisch, geometrisch, grotesk) zou
// een tabel van honderden namen vragen en op het scherm nauwelijks winnen —
// de lezer ziet het verschil tussen een schreef en een schreefloze letter, niet
// tussen twee schreefloze.
//
// Headless en zonder Flutter: dezelfde tabel dient de import, de PDF-export
// (die alleen de klasse kan zetten) en het instellingenvenster.

import '../models/settings.dart';

/// De grove klasse van een lettertype.
enum FontClass { sans, serif, mono }

/// Schreefletters die een kantoorpakket doorgaans schrijft. Kleingeschreven,
/// want de vergelijking is dat ook; een naam matcht ook als hij met een van
/// deze begint (`Garamond Premier Pro`, `Times New Roman Bold`).
const _serifFamilies = [
  'eb garamond',
  'garamond',
  'georgia',
  'times',
  'cambria',
  'lora',
  'merriweather',
  'playfair',
  'baskerville',
  'book antiqua',
  'bookman',
  'palatino',
  'constantia',
  // Niet kaal `century`: Century Gothic is schreefloos.
  'century schoolbook',
  'new century schoolbook',
  'didot',
  'bodoni',
  'minion',
  'caslon',
  'charter',
  'crimson',
  'libre baskerville',
  'liberation serif',
  'dejavu serif',
  'noto serif',
  'source serif',
  'pt serif',
  'roboto serif',
  'roboto slab',
  'rockwell',
  'perpetua',
  'sabon',
  'utopia',
  'literata',
  'spectral',
  'serif',
];

/// Letters met vaste breedte.
const _monoFamilies = [
  'courier',
  'consolas',
  'menlo',
  'monaco',
  'cascadia',
  'fira code',
  'fira mono',
  'source code',
  'jetbrains mono',
  'roboto mono',
  'liberation mono',
  'dejavu sans mono',
  'noto sans mono',
  'noto mono',
  'lucida console',
  'ubuntu mono',
  'ibm plex mono',
  'inconsolata',
  'hack',
  'monospace',
];

/// Bepaalt de grove klasse van een lettertypenaam. Onbekend is schreefloos:
/// dat is wat een kantoorpakket sinds jaren standaard schrijft (Calibri,
/// Aptos, Liberation Sans) en wat op het scherm het minst opvalt als het
/// misgaat.
FontClass classifyFontFamily(String name) {
  final key = name.trim().toLowerCase();
  if (key.isEmpty) return FontClass.sans;
  for (final mono in _monoFamilies) {
    if (key == mono || key.startsWith('$mono ')) return FontClass.mono;
  }
  for (final serif in _serifFamilies) {
    if (key == serif || key.startsWith('$serif ')) return FontClass.serif;
  }
  return FontClass.sans;
}

/// Buren die dichterbij liggen dan de klasse-terugval. Aptos is de opvolger
/// van Calibri in hetzelfde humanistische register; Helvetica ís Helvetica
/// Neue min de nieuwe sneden; Liberation Sans en Arimo zijn metrisch gelijk aan
/// Arial. Sleutel kleingeschreven; een naam die ermee begint telt ook.
const _closeStandIns = {
  'aptos': 'Calibri',
  'carlito': 'Calibri',
  'helvetica': 'Helvetica Neue',
  'liberation sans': 'Arial',
  'arimo': 'Arial',
  'tahoma': 'Verdana',
  'liberation serif': 'Times New Roman',
  'tinos': 'Times New Roman',
  'liberation mono': 'Courier New',
  'cousine': 'Courier New',
};

/// De aangeboden letter die [name] op het scherm vervangt.
///
/// Een exacte treffer in [AppSettings.availableFonts] blijft zichzelf
/// (hoofdletterongevoelig, en `Calibri Light` telt als `Calibri`: de dikte is
/// geen ander lettertype). Dan een bekende buur ([_closeStandIns]). Anders
/// beslist de klasse: een schreefletter wordt EB Garamond — gebundeld, dus op
/// elk platform en op het web identiek —, een vaste-breedteletter Courier New,
/// en al het andere Arial, de ene schreefloze letter die elk systeem onder die
/// naam kent of eronder vertaalt.
String nearestAvailableFont(String name) {
  final exact = _exactAvailableFont(name);
  if (exact != null) return exact;
  final key = name.trim().toLowerCase();
  for (final entry in _closeStandIns.entries) {
    if (key == entry.key || key.startsWith('${entry.key} ')) {
      return entry.value;
    }
  }
  return switch (classifyFontFamily(name)) {
    FontClass.serif => 'EB Garamond',
    FontClass.mono => 'Courier New',
    FontClass.sans => 'Arial',
  };
}

/// De aangeboden letter waarvan [name] een dikte of variant is, of `null`.
String? _exactAvailableFont(String name) {
  final key = name.trim().toLowerCase();
  if (key.isEmpty) return null;
  for (final font in AppSettings.availableFonts) {
    final candidate = font.toLowerCase();
    if (key == candidate) return font;
    // `Calibri Light`, `Segoe UI Semibold`, `Arial Narrow`: een variant van
    // een letter die we hebben, is dichterbij dan een klasse-terugval.
    if (key.startsWith('$candidate ')) return font;
  }
  return null;
}
