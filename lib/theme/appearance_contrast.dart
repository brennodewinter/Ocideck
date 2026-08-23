import 'package:material_ui/material_ui.dart';

import '../models/settings.dart';
import '../utils/color_contrast.dart';
import 'app_theme.dart';

/// Een paar kleuren uit een app-uiterlijkprofiel dat leesbaar moet zijn.
///
/// De namen beschrijven wat de gebruiker ziet, niet welk veld het is: de helft
/// van deze paren bestaat niet als veld maar wordt in [AppTheme.fromProfile]
/// afgeleid, en juist die helft ging in #744 stuk.
enum AppearanceContrastPair {
  /// Gewone tekst op een kaart of in een dialoog.
  bodyOnSurface,

  /// Gewone tekst op het scherm eromheen.
  bodyOnBackground,

  /// De gedempte tweede regel (onderschriften, hints).
  mutedOnSurface,

  /// De zijbalk: pictogrammen en labels op het paneel.
  panelTextOnPanel,

  /// De titel in de bovenbalk, op de hoofdkleur van het profiel.
  appBarTitleOnBar,

  /// Tekstknoppen en links.
  textButtonOnSurface,

  /// De vulling van een aangevinkt vakje, een schakelaar, de tekstcursor.
  interactiveOnSurface,

  /// Het vinkje óp die vulling — dit toont de stand zelf.
  tickOnInteractive,

  /// Het label op de primaire (gevulde) knop.
  primaryButtonLabel,
}

/// Eén gemeten paar: wat het haalt en wat het had moeten halen.
@immutable
class AppearanceContrastFinding {
  final AppearanceContrastPair pair;
  final Color foreground;
  final Color background;
  final double ratio;

  /// De lat voor dít paar. 4,5:1 voor alles wat tekst is (WCAG 1.4.3), 3:1 voor
  /// een grafisch onderdeel zoals de vulling van een vakje (WCAG 1.4.11).
  final double threshold;

  const AppearanceContrastFinding({
    required this.pair,
    required this.foreground,
    required this.background,
    required this.ratio,
    required this.threshold,
  });

  bool get passes => ratio >= threshold;
}

/// Meet elk paar uit [profile] dat leesbaar moet zijn.
///
/// **Meet het gebouwde thema, niet de velden van het profiel.** Dat is het punt
/// van deze functie. Vier van de negen paren bestaan niet als veld: de voorgrond
/// van een tekstknop, de interactiekleur, het vinkje daarop en het label van de
/// primaire knop worden in [AppTheme.fromProfile] afgeleid — en dáár zat #744.
/// Een controle die alleen de acht kleurvelden naast elkaar legt, had die fout
/// niet gezien en zou hem ook nu niet zien.
///
/// Dezelfde reden dat `test/app_theme_contrast_test.dart` deze functie gebruikt
/// in plaats van zijn eigen som: twee rekensommen over dezelfde vraag lopen uit
/// elkaar, en dan bewaakt de ene niet meer wat de andere toont.
List<AppearanceContrastFinding> appearanceContrastFindings(
  AppAppearanceProfile profile,
) {
  final theme = AppTheme.fromProfile(profile);
  final scheme = theme.colorScheme;
  final palette = AppPalette.of(theme);
  final findings = <AppearanceContrastFinding>[];

  void measure(
    AppearanceContrastPair pair,
    Color? foreground,
    Color? background, {
    double threshold = kWcagAaNormalText,
  }) {
    if (foreground == null || background == null) return;
    findings.add(
      AppearanceContrastFinding(
        pair: pair,
        foreground: foreground,
        background: background,
        ratio: contrastRatio(foreground, background),
        threshold: threshold,
      ),
    );
  }

  final body = theme.textTheme.bodyMedium?.color;
  measure(AppearanceContrastPair.bodyOnSurface, body, scheme.surface);
  measure(
    AppearanceContrastPair.bodyOnBackground,
    body,
    theme.scaffoldBackgroundColor,
  );
  measure(
    AppearanceContrastPair.mutedOnSurface,
    palette.mutedText,
    scheme.surface,
  );
  measure(
    AppearanceContrastPair.panelTextOnPanel,
    palette.panelText,
    palette.panel,
  );
  measure(
    AppearanceContrastPair.appBarTitleOnBar,
    theme.appBarTheme.foregroundColor,
    theme.appBarTheme.backgroundColor,
  );
  measure(
    AppearanceContrastPair.textButtonOnSurface,
    _foregroundOf(theme.textButtonTheme.style),
    scheme.surface,
  );

  // 3:1 en niet 4,5: een aangevinkt vakje is een grafisch onderdeel. Het vinkje
  // erop is dat níét — dat is de stand zelf, en die valt onder de tekstlat.
  measure(
    AppearanceContrastPair.interactiveOnSurface,
    scheme.primary,
    scheme.surface,
    threshold: kWcagAaLargeText,
  );
  measure(
    AppearanceContrastPair.tickOnInteractive,
    scheme.onPrimary,
    scheme.primary,
  );

  final buttonStyle = theme.elevatedButtonTheme.style;
  measure(
    AppearanceContrastPair.primaryButtonLabel,
    _foregroundOf(buttonStyle),
    _backgroundOf(buttonStyle),
  );

  return findings;
}

/// Wat er in de bewerker gemeld moet worden: alleen de paren die zakken.
List<AppearanceContrastFinding> appearanceContrastProblems(
  AppAppearanceProfile profile,
) => appearanceContrastFindings(profile).where((f) => !f.passes).toList();

Color? _foregroundOf(ButtonStyle? style) =>
    style?.foregroundColor?.resolve(<WidgetState>{});

Color? _backgroundOf(ButtonStyle? style) =>
    style?.backgroundColor?.resolve(<WidgetState>{});
