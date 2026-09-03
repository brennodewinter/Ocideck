// Part of the app_shell library — see ../app_shell.dart.
// Split out for navigability; all imports live in the main library file.
part of '../app_shell.dart';

// De gedeelde vormen van het startscherm: één knopvorm, één primaire en één
// secundaire stijl, en de twee losse stukjes voettekst. Ze stonden onderaan
// welcome_screen.dart, tot dat bestand tegen het regelplafond liep
// (`fileSizeBaseline` in tool/check_conventions.dart). Ze horen bij elkaar en
// niet bij één scherm-methode, dus ze verhuizen als groep.

/// De gedeelde knopvorm: een ruimere afronding dan de Material-standaard geeft
/// de startkolom een zachter, verfijnder beeld. Top-level zodat zowel
/// [_WelcomeScreen._startColumn] als de losse [_WelcomeScreen._imageLibraryButton]
/// dezelfde vorm delen zonder de klasse te laten groeien.
const _welcomeButtonShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(10)),
);

/// De primaire acties ('Nieuwe presentatie', 'Nieuw document'): inhoud links
/// uitgelijnd zodat het label op dezelfde linkerlijn valt als de kop en de
/// knoplabels eronder.
ButtonStyle _primaryButtonStyle() => ElevatedButton.styleFrom(
  alignment: Alignment.centerLeft,
  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
  shape: _welcomeButtonShape,
);

/// De secundaire acties (openen, importeren, zoeken…): dezelfde linkeruitlijning
/// en vorm, met de zachtere [ColorScheme.outlineVariant] als rand in plaats van
/// de standaard [ColorScheme.outline] — rustiger tegen het paneel.
ButtonStyle _secondaryButtonStyle(ColorScheme scheme) =>
    OutlinedButton.styleFrom(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      shape: _welcomeButtonShape,
      side: BorderSide(color: scheme.outlineVariant),
    );

/// Een volle-breedte primaire startknop: dezelfde vorm en uitlijning als
/// [_wideSecondaryButton], maar gevuld in de accentkleur. Gedeeld door de twee
/// manieren om te beginnen (presentatie en document), zodat ze er als
/// gelijkwaardige keuzes uitzien. De optionele [subtitle] komt onder het label
/// in kleinere, gedempte tekst — één regel die zegt wat je krijgt, zonder jargon
/// (#1961).
Widget _widePrimaryButton({
  required ButtonStyle style,
  required IconData icon,
  required Widget label,
  required VoidCallback onPressed,
  Widget? subtitle,
}) => SizedBox(
  width: double.infinity,
  child: ElevatedButton.icon(
    style: style,
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: subtitle == null
        ? label
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              label,
              DefaultTextStyle.merge(
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  fontWeight: FontWeight.normal,
                ),
                child: subtitle,
              ),
            ],
          ),
  ),
);

/// Een volle-breedte secundaire startknop met de gedeelde stijl. Losse helper
/// zodat de startkolom de `SizedBox` + `OutlinedButton.icon`-boilerplate niet
/// voor elke knop herhaalt (en onder de methodelengte-ratchet blijft).
Widget _wideSecondaryButton({
  required ButtonStyle style,
  required IconData icon,
  required Widget label,
  required VoidCallback onPressed,
}) => SizedBox(
  width: double.infinity,
  child: OutlinedButton.icon(
    style: style,
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: label,
  ),
);

/// De sponsorvermelding rechtsonder: 'Mogelijk gemaakt door' met het thema-
/// bewuste Vigilis-merk. Klein en gedempt — het is een credit, geen actie.
/// Begrensd op een bescheiden breedte zodat het label bij 200% tekst netjes
/// wikkelt in plaats van de voettekstband te laten overlopen; het merk zelf
/// schaalt niet mee met de tekst (het is een afbeelding), dus de bandhoogte
/// wordt door de tekst bepaald en klemt het logo nooit af.
Widget _madePossibleByVigilis(AppLocalizations l10n, TextStyle style) {
  return ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 220),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            l10n.d('Mogelijk gemaakt door'),
            style: style,
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: 8),
        // Het merk in een vaste breedte wikkelen, zodat een failed asset load
        // (stale build, corrupte installatie) de broken-image placeholder niet
        // in een onbegrensd `Row`-slot kan laten groeien voorbij de
        // `ConstrainedBox(maxWidth: 220)` — dat gaf een RenderFlex-overflow op
        // de voettekst zodra `AssetManifest.bin` ontbrak. `BoxFit.contain` in
        // een beperkte doos schaalt het logo tot zijn natuurlijke 76px en de
        // fout-placeholder blijft binnen de 80×18.
        SizedBox(
          width: 80,
          height: 18,
          child: Image.asset(
            BrandLogo.vigilis.assetKey,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            semanticLabel: l10n.d('Vigilis'),
          ),
        ),
      ],
    ),
  );
}

/// Alleen buiten nl/en zit er een melding op de sjabloonbelofte; in die twee
/// talen komt de tekst kaal terug, zodat er geen leeg zweefvenster ontstaat.
Widget _withTemplateLanguageTooltip(AppLocalizations l10n, Widget child) {
  if (l10n.languageCode == 'nl' || l10n.languageCode == 'en') return child;
  return Tooltip(
    message: l10n.d(
      "De voorbeelddia's van een sjabloon staan in het Engels. Naam en omschrijving volgen je eigen taal; de inhoud pas je na het aanmaken aan.",
    ),
    child: child,
  );
}
