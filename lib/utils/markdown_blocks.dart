/// De gedeelde ` ```chart `-fence van de documentmodus.
///
/// Hij woont hier — in `utils/`, dat zowel widgets als services mogen importeren
/// — zodat het editor-scherm (de fence vervangen bij bewerken), `MarpHtmlService`
/// (de fence omzetten naar inline-SVG in de HTML-export) en de grafiek-hydratie
/// (de externe data terug in de fence vouwen) naar exact dezelfde blokken wijzen.
/// Voorheen droeg elk een byte-getrouwe kopie van deze regex.
///
/// GFM-tabellen wonen bewust *niet* hier maar in `services/markdown_table_codec.dart`:
/// dat is de app-brede tabelcodec (per-kolomuitlijning, meerregelige cellen via
/// `<br>`), die de documentmodus sinds de office-tabellen deelt met de
/// rapportagedia's, de import en het klembord.
library;

/// De fence van één ` ```chart `-blok; de kale spec-tekst staat in groep 1.
/// Dezelfde vorm die de editor vervangt, de export omzet en de hydratie invult —
/// zodat ze naar exact dezelfde blokken wijzen.
final RegExp chartFencePattern = RegExp(
  r'```chart[ \t]*\n([\s\S]*?)\n```',
  multiLine: true,
);
