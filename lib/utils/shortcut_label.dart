import '../l10n/app_localizations.dart';

/// De sneltoetsaanduiding zoals de gebruiker hem leest: `Ctrl/Cmd+S`.
///
/// Een sneltoets is deels tekst en deels identifier, en die scheiding is de hele
/// reden dat deze functie bestaat. De toets zelf — `S`, `Z`, `F` — hangt aan een
/// `LogicalKeyboardKey` in de bindings en verandert niet met de taal: wie de
/// letter vertaalt, beschrijft een toets die niet werkt. De modificatietoets
/// verandert wél. Een Duits toetsenbord draagt `Strg` in plaats van `Ctrl` en
/// `Umschalt` in plaats van `Shift`, en de bestaande vertalingen deden dat al
/// (`Rückgängig (Strg/Cmd+Z)`). Alleen dat deel loopt dus door `d()`.
///
/// Zo kost een nieuwe sneltoets géén 31 vertalingen: de twee vertaalbare woorden
/// staan één keer in het systeem, en de aanduiding wordt hier samengesteld.
/// `+` en de plaatsing van de modificatietoets vóór de toets zijn notatie, geen
/// taal — geen van de 32 talen schrijft dat anders.
String shortcutLabel(AppLocalizations l10n, String key, {bool shift = false}) {
  final modifiers = shift
      ? '${l10n.d('Ctrl/Cmd')}+${l10n.d('Shift')}'
      : l10n.d('Ctrl/Cmd');
  return '$modifiers+$key';
}

/// Een menu-item of tooltip met zijn sneltoets erachter:
/// `Opslaan  (Ctrl/Cmd+S)`.
///
/// [dutchLabel] is de Nederlandse bronstring en gaat hier door `d()`. Dat is
/// bewust: het houdt het label en zijn sneltoets in één aanroep bij elkaar, en
/// de vertaalpoort ziet de literal op de aanroepplaats nog steeds — hij staat op
/// de parameter van een functie die er `d()` op doet, precies de indirecte vorm
/// die tool/check_hardcoded_text.dart volgt.
String labelWithShortcut(
  AppLocalizations l10n,
  String dutchLabel,
  String key, {
  bool shift = false,
}) =>
    '${l10n.d(dutchLabel)}  '
    '(${shortcutLabel(l10n, key, shift: shift)})';
