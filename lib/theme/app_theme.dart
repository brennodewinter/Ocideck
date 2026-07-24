import 'package:flutter/material.dart';
import '../models/settings.dart';

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color panel;
  final Color panelText;
  final Color mutedText;

  /// The ink for a link, a list marker or a small accent icon — anything that
  /// must be *read* rather than merely seen.
  ///
  /// Not `colorScheme.primary`, which is where these used to come from. A
  /// profile's primary colour is a brand colour, and a dark profile's brand
  /// colour is dark: the built-in *Donker* profile puts `#111827` on a `#1E293B`
  /// surface, which is 1.21:1 — gone (#744). In light mode primary *is* the
  /// right ink (14:1), so this follows the same rule the outlined button
  /// already used: the profile's text colour when dark, its primary when light.
  ///
  /// `secondary` was the obvious alternative and is wrong: in the *Europa*
  /// profile the accent is EU yellow, which on that profile's white surface is
  /// no better than the problem being fixed.
  final Color accentInk;

  const AppPalette({
    required this.panel,
    required this.panelText,
    required this.mutedText,
    required this.accentInk,
  });

  /// The palette [theme] carries, or one derived from it.
  ///
  /// `theme.extension<AppPalette>()!` is what the app-owned widgets used, and it
  /// is a trap outside the app: a bare `MaterialApp` in a test or a preview has
  /// no extension, and the `!` turns a missing accent colour into a crash. The
  /// derived fallback keeps the *rule* rather than the values — light ink on a
  /// dark theme, the primary on a light one — so a widget lifted out of the app
  /// still renders legibly instead of not at all.
  static AppPalette of(ThemeData theme) =>
      theme.extension<AppPalette>() ??
      AppPalette(
        panel: theme.colorScheme.surfaceContainerHighest,
        panelText: theme.colorScheme.onSurface,
        mutedText: theme.colorScheme.onSurfaceVariant,
        accentInk: theme.brightness == Brightness.dark
            ? theme.colorScheme.onSurface
            : theme.colorScheme.primary,
      );

  @override
  AppPalette copyWith({
    Color? panel,
    Color? panelText,
    Color? mutedText,
    Color? accentInk,
  }) {
    return AppPalette(
      panel: panel ?? this.panel,
      panelText: panelText ?? this.panelText,
      mutedText: mutedText ?? this.mutedText,
      accentInk: accentInk ?? this.accentInk,
    );
  }

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      panel: Color.lerp(panel, other.panel, t)!,
      panelText: Color.lerp(panelText, other.panelText, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
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
  // De lichte kant is bewust de diepe rode en niet #D32F2F: dit token staat
  // vaak op een tint van zichzelf (de scorecard-chip vult met 12%), en daar
  // zakte de lichtere variant naar 4,2:1 — onder AA, terwijl het juist de
  // alarmkleur is (#606).
  static Color get dangerFg =>
      _m(const Color(0xFFB91C1C), const Color(0xFFF87171));
  static const danger500 = Color(0xFFEF4444);
  static const danger600 = Color(0xFFDC2626);
  static const danger700 = Color(0xFFB91C1C);
  static const danger800 = Color(0xFFC62828);

  // ── Merkkleuren als tékst, mode-afhankelijk (#606) ────────────────────────
  //
  // [accent], [navy] en [teal] zijn merkkleuren en blijven const: ze vullen
  // vlakken, kleuren randen en verlopen, en een deel ervan rendert in een
  // headless export-isolate waar de app-modus niet bestaat. Meebewegen zou daar
  // twee verschillende PDF's opleveren van hetzelfde deck (PENTEST_MIAUW §11).
  //
  // Als *tekst of icoon* op het app-oppervlak halen ze de AA-lat niet zodra dat
  // oppervlak donker is: #2563EB komt daar op 3,3:1, #1C2B47 verdwijnt zo goed
  // als helemaal. Vandaar deze drie: dezelfde rol, maar geschikt voor de modus
  // waarin ze gelezen worden. De lichte varianten zijn iets dieper dan de
  // merkkleur zelf, zodat ook op wit de 4,5:1 gehaald wordt.
  //
  // Gebruik deze in de interface (dialogen, editors, panelen, de schil).
  // Gebruik de const-merkkleuren in wat een dia wordt.
  static Color get accentFg =>
      _m(const Color(0xFF1D4ED8), const Color(0xFF8AB4F8));
  static Color get brandFg =>
      _m(const Color(0xFF1C2B47), const Color(0xFFC7D2E4));
  static Color get tealFg =>
      _m(const Color(0xFF1F6B55), const Color(0xFF7FD8BE));

  // ── Dia-inkt: de grijstinten zoals ze op een dia gelezen worden ───────────
  //
  // Een dia is een wit vlak, altijd, in beide app-thema's. De grijzen hierboven
  // (`slate200`…`slate700`) volgen wél het thema, en dat is voor de interface
  // precies goed — maar op een dia is het rampzalig: in donkere modus werd
  // `slate700` op wit 1,3:1 en `slate500` 2,1:1, dus de tekst van een checklist,
  // een scope-matrix en een bevindingenoverzicht verdween zo goed als helemaal
  // (#606).
  //
  // Erger nog dan onleesbaar: het week af van de export. De HTML-export schrijft
  // de lichte waarden, altijd, want die draait zonder thema. Het exportdialoog
  // belooft "de export gebruikt exact de weergave uit de editor", en in donkere
  // modus was dat onwaar.
  //
  // Dit zijn dus dezelfde waarden als de lichte kant van de slate-schaal, maar
  // `const`: ze horen niet te bewegen. Zelfde regel als bij de ernstkleuren —
  // wat op een dia landt, volgt het thema niet.
  static const slideInk = Color(0xFF334155); // slate700-licht
  static const slideInkMuted = Color(0xFF475569); // slate600-licht
  static const slideInkSoft = Color(0xFF64748B); // slate500-licht
  static const slideInkFaint = Color(0xFF94A3B8); // slate400-licht
  static const slideRule = Color(0xFFCBD5E1); // slate300-licht
  static const slideRuleSoft = Color(0xFFE2E8F0); // slate200-licht

  // ── Bevinding-ernst (FIRST CVSS-banden) ───────────────────────────────────
  // Deterministische const-tokens zodat een `finding` identiek rendert in de
  // on-screen preview én in een headless export-isolate (PENTEST_MIAUW §11).
  // P1-THEME verhuist deze naar het beveiligings-ThemeProfile.
  static const severityCritical = Color(0xFFB91C1C); // red 700
  static const severityHigh = Color(0xFFEA580C); // orange 600
  static const severityMedium = Color(0xFFD97706); // amber 600
  static const severityLow = Color(0xFF15803D); // green 700
  static const severityNone = Color(0xFF475569); // slate 600
  // ── Checklist-status (MIAUW tri-state, PENTEST_MIAUW §3.2) ─────────────────
  // Deterministische const-tokens voor de status-chips zodat een checklist
  // identiek rendert in de preview én in een export-isolate. P1-THEME verhuist
  // deze naar het beveiligings-ThemeProfile.
  static const checklistTested = Color(0xFF15803D); // green 700
  static const checklistAnomaly = Color(0xFFB91C1C); // red 700
  static const checklistNotTestable = Color(0xFFB45309); // amber 700
  static const checklistNotTested = Color(0xFF64748B); // slate 500
  // ── Scope-matrix-status (PENTEST_MIAUW §4.4) ──────────────────────────────
  // Deterministische const-tokens voor de coverage-chips, export-isolate-veilig.
  // P1-THEME verhuist deze naar het beveiligings-ThemeProfile.
  static const scopeTested = Color(0xFF15803D); // green 700
  static const scopeDeviation = Color(0xFFB45309); // amber 700
  static const scopeUnreachable = Color(0xFFB91C1C); // red 700
  static const scopeNotTested = Color(0xFF64748B); // slate 500
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
  // Kop en tekst volgen het thema, net als de amber-tegenhanger `notesText` al
  // deed. Ze stonden vast op de lichte blauwen: op het donkere paneel haalde de
  // kop 2,4:1 en de tekst 1,7:1 — de kop was daarmee zwakker dan zijn eigen
  // ondertitel eronder, een omgekeerde hiërarchie in zijn eigen blok (#606).
  static Color get userNotesAccent =>
      _m(const Color(0xFF1D4ED8), const Color(0xFF8AB4F8));
  static Color get userNotesText =>
      _m(const Color(0xFF1E3A8A), const Color(0xFFC7DBFB));

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

  // ── Badges op een slide-thumbnail ─────────────────────────────────────────
  // Doorzichtig genoeg om de slide eronder te laten zien, dekkend genoeg om het
  // icoon leesbaar te houden op elke achtergrond. Zie `slide_badge_tone.dart`
  // voor wanneer welke geldt.
  static const badgeErrorOverlay = Color(0xCCD32F2F);
  static const badgeWarningOverlay = Color(0xCCB45309);

  /// Gevonden, maar wij zijn er zelf niet zeker van.
  static const badgeHintOverlay = Color(0xCC64748B);

  /// Gevonden, en de auteur heeft gezegd dat het zo hoort. Duidelijk grijzer dan
  /// [badgeHintOverlay], zodat "ik twijfel" en "jij hebt beslist" niet op elkaar
  /// lijken.
  static const badgeAcceptedOverlay = Color(0xB3475569);

  // ── Weggeredigeerde media ─────────────────────────────────────────────────
  // Deze twee volgen de themastand *niet*, en dat is de bedoeling. Ze spreken
  // dezelfde taal als de `█`-blokken van de tekstredactie: een zwart vlak zegt
  // "hier stond iets, en het is er bewust uit". Zou dat vlak in een licht thema
  // lichtgrijs worden, dan leest het als een lege plek — precies de verwarring
  // die de redactie moet wegnemen.

  /// De inkt van het redactievlak. Niet volledig `0xFF000000`: absoluut zwart
  /// leest op een donkere dia als een gat in het scherm.
  static const redactionInk = Color(0xFF111111);

  /// Het icoon en het bijschrift óp dat vlak. Licht genoeg om leesbaar te zijn,
  /// gedempt genoeg om niet met echte inhoud te worden verward.
  static const redactionMark = Color(0xFF9AA3AE);

  /// Leest een hexkleur (`#RRGGBB`, `RRGGBB` of `AARRGGBB`) en geeft altijd
  /// een kleur terug: bij onleesbare invoer komt [fallback] eruit.
  ///
  /// Dit is de enige plek waar die vertaling hoort te staan. Wie juist wil
  /// wéten dat de invoer niet deugde, neemt `tryParseHexColor` uit
  /// `utils/color_contrast.dart`; die is strenger en geeft `null`.
  static Color parseHexColor(String hex, {Color fallback = Colors.white}) {
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse(
      cleaned.length == 6 ? 'FF$cleaned' : cleaned,
      radix: 16,
    );
    return value == null ? fallback : Color(value);
  }

  /// De kleur waarmee Material zijn interactieve onderdelen schildert: de
  /// vulling van een aangevinkt selectievakje, de duim van een schakelaar, de
  /// tekstcursor, de focusring, de actieve schuifbalk.
  ///
  /// Dat is een ándere rol dan die van [primary] in een profiel, en daar zat de
  /// fout (#744). `profile.primaryColor` is de **merk- en balkkleur** —
  /// `appBarTheme` schildert de bovenbalk ermee — en die hoort in een donker
  /// profiel juist donker te zijn (`#111827`). Material kreeg dezelfde waarde
  /// als `ColorScheme.primary` en gebruikte hem dan als accent, wat in donkere
  /// modus twee onmogelijkheden opleverde:
  ///
  ///   * `primary` op `surface` = 1,21:1 — de tekstcursor was weg;
  ///   * `onPrimary` (`#122F60`) op `primary` = **1,35:1** — het vinkje in een
  ///     aangevinkt vakje was onzichtbaar op zijn eigen vulling, dus het vakje
  ///     toonde zijn stand niet.
  ///
  /// Het profiel simpelweg een lichte `primaryColor` geven repareert dat niet
  /// maar verplaatst het: dan wordt de bovenbalk licht. De twee rollen moeten
  /// uit elkaar, en het profiel heeft de tweede al — [accentColor], dat de
  /// focusrand en de primaire knop ook al gebruiken.
  ///
  /// Alleen in donkere modus. In een licht profiel ís de merkkleur de goede
  /// accentkleur (14,1:1 bij Basic), en omschakelen zou de lichte modus
  /// onnodig verkleuren.
  static Color _interactiveColor(
    AppAppearanceProfile profile,
    Color primary,
    Color accentColor,
  ) => profile.isDark ? accentColor : primary;

  /// Zwart of wit op [fill] — welke van de twee er het best op leest.
  ///
  /// Puur een som over [fill] zelf. Hier stond een regel die óók naar de
  /// helderheid van het thema keek (`brightness == light && luminance > 0.6 ?
  /// zwart : wit`), en die dwong in donkere modus altijd wit af — ook op het
  /// lichte accent `#60A5FA` van het profiel Donker. Dat is 2,54:1, en het is
  /// het label van de opslaan-knop. Welk thema eromheen staat verandert niets
  /// aan wat er óp een gevulde knop leesbaar is (#750).
  static Color _labelOn(Color fill) =>
      fill.computeLuminance() > 0.179 ? Colors.black : Colors.white;

  static ThemeData fromProfile(AppAppearanceProfile profile) {
    final primary = parseHexColor(profile.primaryColor, fallback: navy);
    final accentColor = parseHexColor(profile.accentColor, fallback: accent);
    final background = parseHexColor(
      profile.backgroundColor,
      fallback: surface,
    );
    final surfaceColor = parseHexColor(profile.surfaceColor);
    final text = parseHexColor(
      profile.textColor,
      fallback: const Color(0xFF1E293B),
    );
    final muted = parseHexColor(
      profile.mutedTextColor,
      fallback: const Color(0xFF64748B),
    );
    final panel = parseHexColor(profile.panelColor, fallback: panelBg);
    final panelText = parseHexColor(profile.panelTextColor, fallback: panelFg);
    final brightness = profile.isDark ? Brightness.dark : Brightness.light;

    final interactive = _interactiveColor(profile, primary, accentColor);

    final scheme = ColorScheme.fromSeed(
      // De kiem blijft de mérkkleur: die bepaalt de hele harmonie van het
      // schema (containers, outlines, onPrimary). Alleen de rol `primary` komt
      // er niet meer uit.
      seedColor: primary,
      brightness: brightness,
      primary: interactive,
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
      // Er stond er geen, en zonder deze regel neemt Flutter
      // `colorScheme.primary` voor de cursor. Dat is precies de kleur die
      // hierboven de bálkkleur bleek te zijn: in donkere modus stond de cursor
      // op 1,21:1 tegen de vulling van het veld — in een tekstverwerker weet je
      // dan niet waar je typt. Nu expliciet, en aan dezelfde rol gekoppeld als
      // de rest van de interactie.
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: interactive,
        selectionColor: interactive.withValues(alpha: 0.35),
        selectionHandleColor: interactive,
      ),
      inputDecorationTheme: _inputDecorationTheme(scheme, muted, accentColor),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: _labelOn(accentColor),
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
      // Dezelfde regel, en hij ontbrak hier. Material geeft een TextButton
      // standaard [primary] als voorgrond, dus elke tekstknop en elke link in
      // de app stond in donkere modus op 1,21:1 — terwijl de omlijnde knop
      // ernaast, door de regel hierboven, gewoon leesbaar was (#744).
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: profile.isDark ? text : primary,
        ),
      ),
      extensions: [
        AppPalette(
          panel: panel,
          panelText: panelText,
          mutedText: muted,
          accentInk: profile.isDark ? text : primary,
        ),
      ],
    );
  }

  static ThemeData get light => fromProfile(AppAppearanceProfile.basic);
}

/// Het uiterlijk van elk invoerveld in de app: een *outlined* tekstveld zoals
/// Material 3 dat bedoelt — een rand, en geen vulling.
///
/// Los van [AppTheme.fromProfile] omdat het daar niet paste: die methode kwam
/// er met dit blok erin over de 150 regels van `check_method_length`.
InputDecorationTheme _inputDecorationTheme(
  ColorScheme scheme,
  Color muted,
  Color accentColor,
) {
  // De rand doet hier al het werk, dus die moet het ook kunnen dragen:
  // `outline` en niet `outlineVariant`. Die laatste haalde 1,58–1,92:1 tegen de
  // achtergrond waar het veld op staat, `outline` haalt 4,18–5,61:1 — over de
  // 3:1 die WCAG 1.4.11 voor de grens van een bedieningselement vraagt, en de
  // rol die Material 3 hier zelf voorschrijft. Bewaakt door
  // `test/input_field_border_test.dart`.
  final rand = OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: BorderSide(color: scheme.outline),
  );

  return InputDecorationTheme(
    // Geen vulling. Een zwevend label staat half boven de bovenrand van het
    // veld en half erin; met een vulling loopt er dus altijd een kleurovergang
    // dwars door de letters, want de gap van een [OutlineInputBorder]
    // onderbreekt alleen de lijn en niet het vlak. In het lichte profiel viel
    // dat niet op (#F4F7FC tegen #FFFFFF), in het donkere las het als een
    // afgesneden onderste letterhelft: #0F172A tegen #1E293B (#811). Zonder
    // vulling neemt het veld over waar het op staat, en dan is er niets om
    // doorheen te lopen.
    filled: false,
    // Een tip moet er als een tip uitzien. Zonder deze regel erft `hintText` de
    // gewone tekstkleur, en dan is een leeg veld met een voorbeeldwaarde niet
    // te onderscheiden van een ingevuld veld. Dat kostte een scorecard-dia: het
    // formulier oogde gevuld, de dia renderde wit, en dat bleek pas op de
    // beamer. Bewaakt door `test/input_hint_contrast_test.dart`.
    //
    // `muted` en niet `scheme.onSurfaceVariant`: die laatste ligt maar 0,04
    // luminantie van de gewone tekstkleur af — een verschil dat je met een
    // kleurenkiezer ziet en met het oog niet.
    hintStyle: TextStyle(color: muted),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: rand,
    enabledBorder: rand,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: accentColor, width: 1.5),
    ),
  );
}
