// Keuze-menudia (#1162): de vorm waarin de blokken op de dia staan.
//
// Puur gegeven, geen Flutter — de modellaag mag de widgetlaag niet importeren.
// Net als bij de tijdlijn reizen de opties mee als extra `_class`-tokens naast
// het basistoken `menu`, zodat een indeling round-trippt zonder JSON-blok en het
// bestand leesbaar blijft.

/// Hoe de blokken van een keuze-menudia over de dia verdeeld staan.
enum MenuLayout {
  /// Raster van kaarten: de meeste blokken op één dia.
  grid,

  /// Onder elkaar, één brede kaart per regel — rustig en goed leesbaar.
  list,

  /// In een ring om het midden van de dia; oogt als een keuzewiel.
  circle,
}

/// De `_class`-tokens die de indeling coderen. `grid` is de standaard en
/// schrijft niets weg: bestaande menudia's veranderen zo geen byte.
List<String> menuClassTokens(MenuLayout layout) => [
  if (layout == MenuLayout.list) 'menu-list',
  if (layout == MenuLayout.circle) 'menu-circle',
];

/// Alle optietokens die dit diatype begrijpt (voor het klasse-filter bij het
/// lezen en de woordenlijst van de structuurcontrole). Zonder het basistoken
/// `menu`. `menu-grid` staat erbij omdat een handgeschreven deck de standaard
/// expliciet mag noemen.
const Set<String> menuOptionTokens = {'menu-grid', 'menu-list', 'menu-circle'};

bool isMenuOptionToken(String token) => menuOptionTokens.contains(token);

/// Lees de indeling uit de klassetokens; onbekend of afwezig = [MenuLayout.grid],
/// zodat een oud deck (en een deck met een token uit een nieuwere versie) blijft
/// tonen in plaats van te breken.
MenuLayout menuLayoutFromTokens(Iterable<String> tokens) {
  if (tokens.contains('menu-list')) return MenuLayout.list;
  if (tokens.contains('menu-circle')) return MenuLayout.circle;
  return MenuLayout.grid;
}
