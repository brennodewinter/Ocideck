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
  /// Of de app-chrome in donkere modus staat. Wordt in [OciDeckApp.build]
  /// gelijkgezet aan het gekozen app-appearance-profiel (`appearance.isDark`),
  /// zodat de mode-afhankelijke tokens hieronder meeschakelen met het thema.
  static bool isDark = false;

  /// Kies [light] of [dark] afhankelijk van [isDark]. Mode-afhankelijke tokens
  /// zijn getters (niet const), dus een `const`-context die zo'n token gebruikt
  /// moet z'n `const` laten vallen.
  static Color _m(Color light, Color dark) => isDark ? dark : light;

  // Brand colours
  static const navy = Color(0xFF1C2B47);
  static const teal = Color(0xFF2E7D64);
  static const accent = Color(0xFF2563EB);
  static Color get surface =>
      _m(const Color(0xFFF8F9FA), const Color(0xFF14161B));

  /// Wit "papier"-oppervlak voor editor-chrome (toolbars, panelen, dialogen).
  /// In donkere modus een donker oppervlak. NIET gebruiken voor slide-inhoud —
  /// een slide is een vast wit canvas en blijft `Colors.white`.
  static Color get paper => _m(Colors.white, const Color(0xFF181B21));

  static const panelBg = Color(0xFF1E2028);
  static const panelFg = Color(0xFFE2E8F0);

  // Het slate-palet (Tailwind-tinten) van de editor-UI. Mode-afhankelijk: in
  // donkere modus keert de licht/donker-oriëntatie om (50 = donkerste
  // oppervlak, 800 = lichtste tekst), zodat bestaande usages meeschakelen.
  static Color get slate50 =>
      _m(const Color(0xFFF8FAFC), const Color(0xFF1C1F26));
  static Color get slate100 =>
      _m(const Color(0xFFF1F5F9), const Color(0xFF232730));
  static Color get slate200 =>
      _m(const Color(0xFFE2E8F0), const Color(0xFF2C313B));
  static Color get slate300 =>
      _m(const Color(0xFFCBD5E1), const Color(0xFF3A4150));
  static Color get slate400 =>
      _m(const Color(0xFF94A3B8), const Color(0xFF8B95A6));
  static Color get slate500 =>
      _m(const Color(0xFF64748B), const Color(0xFFAAB4C4));
  static Color get slate600 =>
      _m(const Color(0xFF475569), const Color(0xFFC6CEDA));
  static Color get slate700 =>
      _m(const Color(0xFF334155), const Color(0xFFDCE2EC));
  static Color get slate800 =>
      _m(const Color(0xFF1E293B), const Color(0xFFE8ECF3));
  static const blue400 = Color(0xFF60A5FA);
  static const blue500 = Color(0xFF3B82F6);

  // Neutraal grijs (Tailwind gray-schaal; kilter dan slate).
  static Color get gray100 =>
      _m(const Color(0xFFF3F4F6), const Color(0xFF222429));
  static Color get gray300 =>
      _m(const Color(0xFFD1D5DB), const Color(0xFF3A3D44));
  static Color get gray400 =>
      _m(const Color(0xFF9CA3AF), const Color(0xFF9CA3AF));
  static Color get gray500 =>
      _m(const Color(0xFF6B7280), const Color(0xFFAAB0BA));
  static Color get gray700 =>
      _m(const Color(0xFF374151), const Color(0xFFCED3DB));
  static Color get gray900 =>
      _m(const Color(0xFF111827), const Color(0xFFE8ECF3));

  // GitHub-flavoured neutralen (mermaid/markdown-previews).
  static Color get ghSurface =>
      _m(const Color(0xFFF6F8FA), const Color(0xFF20242B));
  static Color get ghBorder =>
      _m(const Color(0xFFE1E4E8), const Color(0xFF2C313B));
  static Color get ghInk =>
      _m(const Color(0xFF24292E), const Color(0xFFDCE2EC));

  /// Primaire inkt-kleur voor tekst (slate900-achtig; licht in donkere modus).
  static Color get ink => _m(const Color(0xFF0F172A), const Color(0xFFE8ECF3));

  // Amber-schaal (generiek — waarschuwingen, markeringen, notitie-accent).
  static const amber500 = Color(0xFFF59E0B);
  static const amber600 = Color(0xFFD97706);
  static const amber700 = Color(0xFFB45309);
  static const amberVivid = Color(0xFFFFCC00);

  // ── Semantische status-kleuren (achtergrond + voorgrond) ──────────────────
  // Gebruikt door o.a. het kwaliteitspaneel en per-slide controls. Eén plek
  // i.p.v. tientallen verspreide Color(0xFF…)-literals; ook de basis voor een
  // latere donkere modus.
  static Color get successBg =>
      _m(const Color(0xFFECFDF5), const Color(0xFF10281F));
  static Color get successBgSoft =>
      _m(const Color(0xFFA7F3D0), const Color(0xFF14503B));
  static Color get successFg =>
      _m(const Color(0xFF047857), const Color(0xFF6EE7B7));
  static const success600 = Color(0xFF2E7D32);
  static const success700 = Color(0xFF15803D);
  static const success800 = Color(0xFF166534);
  static const successSoft = Color(0xFF7DD3A7);
  static Color get warningBg =>
      _m(const Color(0xFFFEF3C7), const Color(0xFF2E2410));
  static Color get warningBgSoft =>
      _m(const Color(0xFFFDE68A), const Color(0xFF4A3A12));
  static Color get warningFg =>
      _m(const Color(0xFF92400E), const Color(0xFFFCD34D));
  static Color get dangerBg =>
      _m(const Color(0xFFFEE2E2), const Color(0xFF2E1616));
  static Color get dangerBgSoft =>
      _m(const Color(0xFFFECACA), const Color(0xFF4A1E1E));
  static Color get dangerFg =>
      _m(const Color(0xFFD32F2F), const Color(0xFFF87171));
  static const danger500 = Color(0xFFEF4444);
  static const danger600 = Color(0xFFDC2626);
  static const danger700 = Color(0xFFB91C1C);
  static const danger800 = Color(0xFFC62828);
  static const dangerPlain = Color(0xFFCC0000);

  // ── Checklist-status (MIAUW tri-state, PENTEST_MIAUW §3.2) ─────────────────
  // Deterministische const-tokens voor de status-chips zodat een checklist
  // identiek rendert in de preview én in een export-isolate. P1-THEME verhuist
  // deze naar het beveiligings-ThemeProfile.
  static const checklistTested = Color(0xFF15803D); // green 700
  static const checklistAnomaly = Color(0xFFB91C1C); // red 700
  static const checklistNotTestable = Color(0xFFB45309); // amber 700
  static const checklistNotTested = Color(0xFF64748B); // slate 500
  static Color get infoBg =>
      _m(const Color(0xFFEFF6FF), const Color(0xFF15202E));

  /// Lichtblauwe accent-tint (info-state controls).
  static Color get infoSurface =>
      _m(const Color(0xFFF0F9FF), const Color(0xFF14202B));

  /// Blauwe accent-tint (bijv. CSV-koppeling in de grafiek-editor).
  static const infoAccent = Color(0xFF0369A1);

  // ── Sprekersnotities-accent (amber) ───────────────────────────────────────
  // Icoon/accent/focus gebruiken de generieke amber-schaal (amber700/600/500).
  static Color get notesBg =>
      _m(const Color(0xFFFFFBEB), const Color(0xFF2A2410));
  static const notesBorder = Color(0xFFFCD34D);
  static Color get notesText =>
      _m(const Color(0xFF78350F), const Color(0xFFF5D9A8));
  static Color get notesCodeBg =>
      _m(const Color(0xFFFFF7ED), const Color(0xFF241D12));

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
        // In donkere modus is [primary] donker (onleesbaar op donker); gebruik
        // dan de lichte tekstkleur.
        style: OutlinedButton.styleFrom(
          foregroundColor: profile.isDark ? text : primary,
        ),
      ),
      extensions: [
        AppPalette(panel: panel, panelText: panelText, mutedText: muted),
      ],
    );
  }

  static ThemeData get light => fromProfile(AppAppearanceProfile.basic);
}
