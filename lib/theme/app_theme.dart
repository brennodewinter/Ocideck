import 'package:flutter/material.dart';
import '../models/settings.dart';

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color panel;
  final Color panelText;
  final Color mutedText;

  const AppPalette({
    required this.panel,
    required this.panelText,
    required this.mutedText,
  });

  @override
  AppPalette copyWith({Color? panel, Color? panelText, Color? mutedText}) {
    return AppPalette(
      panel: panel ?? this.panel,
      panelText: panelText ?? this.panelText,
      mutedText: mutedText ?? this.mutedText,
    );
  }

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      panel: Color.lerp(panel, other.panel, t)!,
      panelText: Color.lerp(panelText, other.panelText, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
    );
  }
}

class AppTheme {
  // Brand colours
  static const navy = Color(0xFF1C2B47);
  static const teal = Color(0xFF2E7D64);
  static const accent = Color(0xFF2563EB);
  static const surface = Color(0xFFF8F9FA);
  static const panelBg = Color(0xFF1E2028);
  static const panelFg = Color(0xFFE2E8F0);

  static Color parseHex(String hex, {Color fallback = Colors.white}) {
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse(
      cleaned.length == 6 ? 'FF$cleaned' : cleaned,
      radix: 16,
    );
    return value == null ? fallback : Color(value);
  }

  static ThemeData fromProfile(AppAppearanceProfile profile) {
    final primary = parseHex(profile.primaryColor, fallback: navy);
    final accentColor = parseHex(profile.accentColor, fallback: accent);
    final background = parseHex(profile.backgroundColor, fallback: surface);
    final surfaceColor = parseHex(profile.surfaceColor);
    final text = parseHex(profile.textColor, fallback: const Color(0xFF1E293B));
    final muted = parseHex(
      profile.mutedTextColor,
      fallback: const Color(0xFF64748B),
    );
    final panel = parseHex(profile.panelColor, fallback: panelBg);
    final panelText = parseHex(profile.panelTextColor, fallback: panelFg);
    final brightness = profile.isDark ? Brightness.dark : Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      primary: primary,
      secondary: accentColor,
      surface: surfaceColor,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      // The interface font from the appearance profile (one of the bundled
      // [AppAppearanceProfile.uiFonts]). Bundled in pubspec.yaml so the CanvasKit
      // web engine never fetches it from fonts.gstatic.com — keeping the web
      // build self-contained under a strict connect-src 'self' CSP.
      fontFamily: profile.fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: surfaceColor,
      cardColor: surfaceColor,
      dialogTheme: DialogThemeData(backgroundColor: surfaceColor),
      textTheme: ThemeData(
        brightness: brightness,
      ).textTheme.apply(bodyColor: text, displayColor: text),
      appBarTheme: AppBarTheme(
        backgroundColor: primary,
        foregroundColor: panelText,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: panelText),
        actionsIconTheme: IconThemeData(color: panelText),
        titleTextStyle: TextStyle(
          color: panelText,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: accentColor, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor:
              scheme.brightness == Brightness.light &&
                  accentColor.computeLuminance() > 0.6
              ? Colors.black
              : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(foregroundColor: primary),
      ),
      extensions: [
        AppPalette(panel: panel, panelText: panelText, mutedText: muted),
      ],
    );
  }

  static ThemeData get light => fromProfile(AppAppearanceProfile.basic);
}
