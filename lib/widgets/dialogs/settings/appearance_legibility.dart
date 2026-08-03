import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/settings.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/appearance_contrast.dart';

/// Een miniatuur van de app in [profile].
///
/// **Het bouwt het échte thema en rendert daarin.** Dat is niet netheid maar de
/// hele reden dat dit ding er staat: hiervóór schilderde het voorbeeld zijn
/// eigen kleuren met een hulpje dat zwart of wit koos op luminantie. De app doet
/// dat niet — die gebruikt `panelTextColor` voor de baltitel en een berekende
/// voorgrond voor de knop. Het voorbeeld liet dus een leesbare balk zien waar de
/// app een onleesbare rendert: het vleide precies het profiel dat een
/// waarschuwing verdiende (#750).
///
/// En het toont de onderdelen die in #744 stukgingen — een selectievakje, een
/// schakelaar, een tekstknop. Het oude voorbeeld liet alleen de rollen zien die
/// het goed deed.
class AppearancePreview extends StatelessWidget {
  final AppAppearanceProfile profile;

  const AppearancePreview({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.fromProfile(profile);
    final palette = AppPalette.of(theme);
    return Theme(
      data: theme,
      // Vaste tekstschaal: dit is een miniatuur met een vast pixelontwerp (hoogte
      // 148), geen interface die met de leesbaarheidsinstelling meegroeit. Zonder
      // deze grens liep het voorbeeld bij 200% interface-tekst buiten zijn eigen
      // kader — de knoppen en de balktekst zwollen op tot de rij overliep. Het
      // toont hóe het profiel oogt, niet hoe groot de interface staat.
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        // Een plaatje, geen bedieningspaneel: de knoppen staan er om te tónen hoe
        // ze eruitzien. Ze wél inschakelen (`onChanged` niet null) is nodig om ze
        // in hun actieve kleur te krijgen; IgnorePointer houdt ze stil.
        child: IgnorePointer(
          child: Container(
            height: 148,
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: palette.panel),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _bar(context, theme),
                Expanded(child: _body(context, theme, palette)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bar(BuildContext context, ThemeData theme) => Container(
    height: 30,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    color: theme.appBarTheme.backgroundColor,
    alignment: Alignment.centerLeft,
    child: Text(
      context.l10n.d('OciDeck'),
      style: TextStyle(
        color: theme.appBarTheme.foregroundColor,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _body(BuildContext context, ThemeData theme, AppPalette palette) =>
      Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 52,
              color: palette.panel,
              alignment: Alignment.center,
              child: Icon(Icons.slideshow_outlined, color: palette.panelText),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                color: theme.colorScheme.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Text(
                      context.l10n.d('Voorbeeldtekst'),
                      style: TextStyle(
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                    _controls(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  /// De rollen die #744 blootlegde: het aangevinkte vakje (vulling én vinkje),
  /// de schakelaar, de tekstknop en de gevulde knop.
  ///
  /// In een [FittedBox] omdat dit een miniatuur met een vaste breedte is: de vier
  /// bedieningen naast elkaar passen bij een smal voorbeeldkader net niet, en een
  /// plaatje krimpt liever in zijn geheel dan dat het overloopt of afkapt.
  Widget _controls(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 24,
          width: 24,
          child: Checkbox(
            value: true,
            visualDensity: VisualDensity.compact,
            onChanged: (_) {},
          ),
        ),
        const SizedBox(width: 4),
        Transform.scale(
          scale: 0.7,
          child: Switch(value: true, onChanged: (_) {}),
        ),
        const SizedBox(width: 16),
        TextButton(
          onPressed: () {},
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: const Size(0, 28),
          ),
          child: Text(context.l10n.d('Meer')),
        ),
        const SizedBox(width: 4),
        ElevatedButton(
          onPressed: () {},
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            minimumSize: const Size(0, 28),
            textStyle: const TextStyle(fontSize: 12),
          ),
          child: Text(context.l10n.d('Knop')),
        ),
      ],
    ),
  );
}

/// De leesbaarheidsmeting onder het voorbeeld.
///
/// Waarom dit er is: de toetsen uit #744 dekken de drie ingebouwde profielen.
/// Wie hier zelf kleuren kiest, kan precies dezelfde fout terugbouwen — een
/// donker accent in een donker profiel — en niets zei daar iets over.
///
/// Waarschuwen en niet tegenhouden: het is de app van de gebruiker, en de weg
/// terug is één kleur. Blokkeren past bij een export, die de deur uit gaat.
class AppearanceLegibility extends StatelessWidget {
  final AppAppearanceProfile profile;

  const AppearanceLegibility({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final problems = appearanceContrastProblems(profile);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.slate300),
        borderRadius: BorderRadius.circular(6),
        color: AppTheme.paper,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                problems.isEmpty
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_outlined,
                size: 16,
                color: problems.isEmpty
                    ? AppTheme.successFg
                    : AppTheme.warningFg,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.d('Leesbaarheid van dit profiel'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (problems.isEmpty)
            Text(
              l10n.d('Alle onderdelen halen de norm.'),
              style: const TextStyle(fontSize: 11),
            )
          else
            for (final finding in problems) _row(context, finding),
          const SizedBox(height: 8),
          // De instelbare "Minimale contrastverhouding" bij Algemeen gaat over
          // de dia's van de gebruiker. Deze lat is vast: de app zijn eigen
          // ondergrens laten verlagen is iets anders dan de gebruiker zijn eigen
          // dek laten beoordelen.
          Text(
            l10n.d(
              'Deze verhoudingen gaan over de app zelf, niet over je dia\'s.',
            ),
            style: TextStyle(fontSize: 10, color: AppTheme.slate500),
          ),
        ],
      ),
    );
  }

  /// Eén zakkend paar: waar het over gaat, wat het haalt, en wat het moest
  /// halen. Geen zin eromheen — het label plus twee getallen leest sneller, en
  /// scheelt een geïnterpoleerde bronstring in 31 talen.
  Widget _row(BuildContext context, AppearanceContrastFinding finding) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dot(context, finding.background),
          const SizedBox(width: 4),
          _dot(context, finding.foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _label(context, finding.pair),
              style: const TextStyle(fontSize: 11),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${finding.ratio.toStringAsFixed(1)} : 1',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.warningFg,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '≥ ${finding.threshold.toStringAsFixed(1)} : 1',
            style: TextStyle(fontSize: 11, color: AppTheme.slate500),
          ),
        ],
      ),
    );
  }

  /// De twee kleuren die vergeleken zijn, naast elkaar. Zonder deze stippen is
  /// een verhouding een getal zonder aanwijzing welke kiezer eronder zit.
  Widget _dot(BuildContext context, Color color) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
  );

  String _label(BuildContext context, AppearanceContrastPair pair) {
    final l10n = context.l10n;
    return switch (pair) {
      AppearanceContrastPair.bodyOnSurface => l10n.d(
        'Tekst op kaarten en dialogen',
      ),
      AppearanceContrastPair.bodyOnBackground => l10n.d(
        'Tekst op de schermachtergrond',
      ),
      AppearanceContrastPair.mutedOnSurface => l10n.d('Gedempte tekst'),
      AppearanceContrastPair.panelTextOnPanel => l10n.d(
        'Tekst en pictogrammen in de zijbalk',
      ),
      AppearanceContrastPair.appBarTitleOnBar => l10n.d(
        'Titel in de bovenbalk',
      ),
      AppearanceContrastPair.textButtonOnSurface => l10n.d(
        'Tekstknoppen en links',
      ),
      AppearanceContrastPair.interactiveOnSurface => l10n.d(
        'Selectievakjes, schakelaars en de tekstcursor',
      ),
      AppearanceContrastPair.tickOnInteractive => l10n.d(
        'Het vinkje in een aangevinkt vakje',
      ),
      AppearanceContrastPair.primaryButtonLabel => l10n.d(
        'Label op de primaire knop',
      ),
    };
  }
}
