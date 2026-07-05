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

  // Het slate/blue-palet (Tailwind-tinten) van de editor-UI. Deze waarden
  // stonden tot 90× hardcoded verspreid door lib/widgets/; via deze consts
  // raakt een paletwijziging één plek in plaats van tientallen bestanden.
  static const slate50 = Color(0xFFF8FAFC);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate300 = Color(0xFFCBD5E1);
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
  static const slate600 = Color(0xFF475569);
  static const slate700 = Color(0xFF334155);
  static const slate800 = Color(0xFF1E293B);
  static const blue400 = Color(0xFF60A5FA);
  static const blue500 = Color(0xFF3B82F6);

  // Neutraal grijs (Tailwind gray-schaal; kilter dan slate).
  static const gray100 = Color(0xFFF3F4F6);
  static const gray300 = Color(0xFFD1D5DB);
  static const gray400 = Color(0xFF9CA3AF);
  static const gray500 = Color(0xFF6B7280);
  static const gray700 = Color(0xFF374151);
  static const gray900 = Color(0xFF111827);

  // GitHub-flavoured neutralen (mermaid/markdown-previews).
  static const ghSurface = Color(0xFFF6F8FA);
  static const ghBorder = Color(0xFFE1E4E8);
  static const ghInk = Color(0xFF24292E);

  /// Primaire inkt-kleur voor tekst (slate900-achtig).
  static const ink = Color(0xFF0F172A);

  // Amber-schaal (generiek — waarschuwingen, markeringen, notitie-accent).
  static const amber500 = Color(0xFFF59E0B);
  static const amber600 = Color(0xFFD97706);
  static const amber700 = Color(0xFFB45309);
  static const amberVivid = Color(0xFFFFCC00);

  // ── Semantische status-kleuren (achtergrond + voorgrond) ──────────────────
  // Gebruikt door o.a. het kwaliteitspaneel en per-slide controls. Eén plek
  // i.p.v. tientallen verspreide Color(0xFF…)-literals; ook de basis voor een
  // latere donkere modus.
  static const successBg = Color(0xFFECFDF5);
  static const successBgSoft = Color(0xFFA7F3D0);
  static const successFg = Color(0xFF047857);
  static const success600 = Color(0xFF2E7D32);
  static const success700 = Color(0xFF15803D);
  static const success800 = Color(0xFF166534);
  static const successSoft = Color(0xFF7DD3A7);
  static const warningBg = Color(0xFFFEF3C7);
  static const warningBgSoft = Color(0xFFFDE68A);
  static const warningFg = Color(0xFF92400E);
  static const dangerBg = Color(0xFFFEE2E2);
  static const dangerBgSoft = Color(0xFFFECACA);
  static const dangerFg = Color(0xFFD32F2F); // Material red 700
  static const danger500 = Color(0xFFEF4444);
  static const danger600 = Color(0xFFDC2626);
  static const danger700 = Color(0xFFB91C1C);
  static const danger800 = Color(0xFFC62828);
  static const dangerPlain = Color(0xFFCC0000);
  static const infoBg = Color(0xFFEFF6FF);

  /// Lichtblauwe accent-tint (info-state controls).
  static const infoSurface = Color(0xFFF0F9FF);

  /// Blauwe accent-tint (bijv. CSV-koppeling in de grafiek-editor).
  static const infoAccent = Color(0xFF0369A1);

  // ── Sprekersnotities-accent (amber) ───────────────────────────────────────
  // Icoon/accent/focus gebruiken de generieke amber-schaal (amber700/600/500).
  static const notesBg = Color(0xFFFFFBEB);
  static const notesBorder = Color(0xFFFCD34D);
  static const notesText = Color(0xFF78350F);
  static const notesCodeBg = Color(0xFFFFF7ED);

  // ── Gebruikersnotities-accent (blauw; tegenhanger van de amber notities) ───
  // De achtergrond en code-achtergrond delen [infoBg].
  static const userNotesBorder = Color(0xFFBFDBFE);
  static const userNotesBorderFocus = Color(0xFF93C5FD);
  static const userNotesAccent = Color(0xFF1D4ED8);
  static const userNotesText = Color(0xFF1E3A8A);

  // ── Donkere slate-ramp (thumbnails, dark editor-chrome, preview-panel) ─────
  static const darkSlate900 = Color(0xFF1B1E25);
  static const darkSlate800 = Color(0xFF252830);
  static const darkSlate700 = Color(0xFF2A2F3B);
  static const darkSlate600 = Color(0xFF3A3F4B);
  static const darkSlate500 = Color(0xFF4A4F5B);
  static const darkNeutral = Color(0xFF242424);

  // ── Goud/brons-accent (o.a. LibreKAT-thema, badges) ───────────────────────
  static const gold = Color(0xFFD4A24E);
  static const goldDark = Color(0xFF8A6D3B);
  static const goldSoft = Color(0xFFE3C281);
  static const goldSoft2 = Color(0xFFE2C08D);

  // ── Pale blauw / blauwgrijs (dialogen, media-badges) ───────────────────────
  static const paleBlue = Color(0xFF93B8F8);
  static const paleBlue2 = Color(0xFF8BB8FF);
  static const blueGray = Color(0xFFB6C2D2);
  static const blueGray2 = Color(0xFFB0BEC5);
  static const navySoft = Color(0xFF273A60);
  static const iceBlue = Color(0xFFE9EEF5);
  static const iceBlue2 = Color(0xFFEEF2F7);

  // ── Overig ─────────────────────────────────────────────────────────────────
  static const cyan = Color(0xFF1AB7EA);
  static const coral = Color(0xFFE5746E);
  static const forestDark = Color(0xFF10231C);
  static const nearWhite = Color(0xFFFAFBFC);
  static const warnSurface = Color(0xFFFFF9E6);
  static const gray550 = Color(0xFF888888);
  static const darkInk = Color(0xFF1A1A1A);

  // ── Alpha-overlays (ARGB met alpha; schaduwen/tinten) ──────────────────────
  static const shadow10 = Color(0x1A000000);
  static const shadow20 = Color(0x33000000);
  static const inkOverlay = Color(0x330F172A);
  static const tealOverlay = Color(0x332E7D64);
  static const goldOverlay = Color(0x33B8860B);
  static const accentOverlay = Color(0xCC2563EB);
  static const goldDarkOverlay = Color(0xCC8A6D3B);

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
