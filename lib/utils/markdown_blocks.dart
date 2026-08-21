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

/// Een geopende CommonMark-fence, gedeeld door documentweergave en bridge.
class MarkdownFence {
  final String marker;
  final int length;
  final String language;

  const MarkdownFence(this.marker, this.length, this.language);

  bool closes(String trimmed) =>
      RegExp('^${RegExp.escape(marker)}{$length,}[ \\t]*\$').hasMatch(trimmed);
}

/// Ontleedt het hek en het eerste woord van de info-string.
MarkdownFence? markdownFenceOpen(String trimmed) {
  final match = RegExp(r'^(`{3,}|~{3,})[ \t]*(\S*)').firstMatch(trimmed);
  if (match == null) return null;
  final run = match.group(1)!;
  return MarkdownFence(run[0], run.length, match.group(2)!.toLowerCase());
}

/// De fence van één ` ```chart `-blok; de kale spec-tekst staat in groep 1.
/// Dezelfde vorm die de editor vervangt, de export omzet en de hydratie invult —
/// zodat ze naar exact dezelfde blokken wijzen.
final RegExp chartFencePattern = RegExp(
  r'```chart[ \t]*\n([\s\S]*?)\n```',
  multiLine: true,
);

/// Alt-tekst voor `![…](…)`: een bijschrift met `[`/`]` gestript, zodat de
/// markdown-syntaxis van de afbeeldingsverwijzing heel blijft. Een blokhaak in
/// een bijschrift zou de link anders vroegtijdig afsluiten en de rest van de
/// regel als tekst laten staan.
String markdownImageAlt(String caption) =>
    caption.replaceAll('[', '').replaceAll(']', '');
