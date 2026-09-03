import 'app_theme.dart';
import '../models/settings.dart';
import '../utils/bundled_asset.dart';

/// The bundled brand marks, each paired with the variant for a dark surface.
///
/// All three are line art in dark ink, so on the dark app chrome they either
/// vanish or — worse — announce themselves. `ocideck-logo.png` carried its white
/// plate baked in as fully opaque pixels: every corner is `#FFFFFF` at alpha
/// 255, roughly 89% of the image is white, and at 200px on the welcome screen
/// that read as a bright rectangle rather than a logo (#735).
///
/// A tint cannot fix that, because the plate and the drawing are the same
/// pixels. The dark variants are therefore a second file: the same drawing with
/// a genuinely transparent background and the ink lifted to the dark value of
/// [AppTheme.ink]. Keeping the alpha channel as the drawing's coverage is what
/// makes them land correctly on *any* surface, not just the one built-in dark
/// profile — a user-made profile picks its own background.
///
/// Not every mark needs an entry. `ocideck-logo-eu.png` only ever sits on the
/// EU-blue settings sidebar and the navy "about" banner, surfaces that are dark
/// in *both* modes, and its EU-yellow ink already reads there; it stays a plain
/// `Image.asset`.
enum BrandLogo {
  ociDeck(
    'assets/images/ocideck-logo.png',
    'assets/images/ocideck-logo-dark.png',
  ),
  libreKat(
    'assets/images/librekat-logo.png',
    'assets/images/librekat-logo-dark.png',
  ),
  vigilis(
    'assets/images/vigilis-logo.png',
    'assets/images/vigilis-logo-dark.png',
  );

  const BrandLogo(this.lightAsset, this.darkAsset);

  /// The mark as drawn for a light surface — dark ink.
  final String lightAsset;

  /// The same mark for a dark surface — transparent background, light ink.
  final String darkAsset;

  /// The asset key for the mode the app chrome is in right now.
  ///
  /// Reads the [AppTheme.isDark] static rather than a `BuildContext`, like
  /// every other mode-dependent token: the tree rebuilds when the appearance
  /// profile changes, so there is nothing to listen to here that the theme does
  /// not already carry.
  String get assetKey => AppTheme.isDark ? darkAsset : lightAsset;

  /// De asset-sleutel voor een oppervlak met de gegeven [surfaceLuminance].
  ///
  /// In tegenstelling tot [assetKey] (die de app-chrome-modus leest), kiest dit
  /// op basis van de daadwerkelijke dia-achtergrond (#1931).
  String effectiveAssetKey(double surfaceLuminance) =>
      surfaceLuminance < 0.5 ? darkAsset : lightAsset;

  /// Vindt het gebundelde merk-logo wiens lichte asset-sleutel [key] is, of
  /// `null` als het geen gebundeld merk is.
  static BrandLogo? forAssetKey(String key) {
    for (final logo in BrandLogo.values) {
      if (logo.lightAsset == key) return logo;
    }
    return null;
  }
}

/// Resolves the effective logo path for a slide with the profile's background
/// color (#1931). For bundled brand logos, selects the dark variant
/// automatically when the background is dark. For custom logos, uses
/// [ThemeProfile.logoDarkPath] if set. Falls back to the light logo.
String? effectiveSlideLogoPath(ThemeProfile profile) {
  final path = profile.logoPath;
  if (path == null || path.trim().isEmpty) return null;
  final bg = AppTheme.parseHexColor(profile.slideBackgroundColor);
  if (bg.computeLuminance() >= 0.5) return path;
  if (isBundledAssetPath(path)) {
    final brand = BrandLogo.forAssetKey(bundledAssetKey(path));
    if (brand != null) return 'asset:${brand.darkAsset}';
  }
  final darkPath = profile.logoDarkPath;
  if (darkPath != null && darkPath.trim().isNotEmpty) return darkPath;
  return path;
}
