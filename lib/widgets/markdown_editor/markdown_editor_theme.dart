import '../reader/document_markdown_view.dart'
    show kDocumentBodyFontSize, kDocumentBodyLineHeight;
import 'package:material_ui/material_ui.dart';
import '../../models/settings.dart';
import '../../theme/app_theme.dart';

/// Readable editor chrome independent of slide/panel background colors.
class MarkdownEditorTheme {
  final Color surface;
  final Color text;
  final Color hint;
  final Color link;
  final Color heading;
  final Color subheading;
  final Color codeBackground;
  final Color toolbarIcon;
  final Color accent;
  final Color border;
  final double fontSize;
  final double lineHeight;
  final String? fontFamily;
  final ThemeProfile? profile;

  /// Tekstkleur van een blokcitaat — los van [text], want een citaat staat
  /// een tint lager dan de alinea. Alleen gezet door [documentSurface]; de
  /// notitiepanelen hebben geen citaten en vallen terug op [text].
  final Color quoteText;

  /// Achtergrondkleur van een blokcitaat. Alleen gezet door [documentSurface].
  final Color quoteBg;

  /// De gekleurde balk links van een blokcitaat. Alleen gezet door
  /// [documentSurface]; elders gelijk aan [accent].
  final Color quoteBar;

  /// Tekstkleur in een codeblok — los van [text], want een profiel kan een
  /// eigen code-inkt kiezen. Alleen gezet door [documentSurface].
  final Color codeText;

  const MarkdownEditorTheme({
    required this.surface,
    required this.text,
    required this.hint,
    required this.link,
    required this.heading,
    required this.subheading,
    required this.codeBackground,
    required this.toolbarIcon,
    required this.accent,
    required this.border,
    this.fontSize = 14,
    this.lineHeight = 1.5,
    this.fontFamily,
    this.profile,
    this.documentTypography = false,
    this.quoteText = Colors.transparent,
    this.quoteBg = Colors.transparent,
    this.quoteBar = Colors.transparent,
    this.codeText = Colors.transparent,
  });

  /// Schrijf je op een pagina, dan schrijf je in de lettermaten van die
  /// pagina. De documentmodus zet dit aan; dan neemt het schrijfvlak de
  /// typografie van de documentweergave over — dezelfde lettergrootte,
  /// regelafstand, kopmaten en blokafstanden.
  ///
  /// Dat is geen smaakkwestie maar rekenwerk: de pagina-einden in de
  /// schrijfstand worden gemeten aan wat er staat, en met kleinere letters
  /// paste er ruim een kwart te veel op een vel. De lijn stond dan wel op een
  /// blokgrens, maar op de verkeerde.
  final bool documentTypography;

  TextStyle get bodyStyle => TextStyle(
    fontFamily: fontFamily,
    fontSize: fontSize,
    height: lineHeight,
    color: text,
  );

  TextStyle get hintStyle => bodyStyle.copyWith(color: hint);

  /// Het vlakje achter **inline** `code` in het schrijfvlak.
  ///
  /// Los van [codeBackground] — dat is het paneel van een codeblok. Zie
  /// [AppTheme.inlineCodeBackground] voor waarom die twee uit elkaar horen: in
  /// een alinea werd het codeblok-vlak een zwart blokje met de alineakleur erin.
  /// Dat de documentweergave dezelfde som doet, is het hele punt — de twee
  /// weergaven van dezelfde tekst horen er gelijk uit te zien (#1567).
  Color get inlineCodeBackground => AppTheme.inlineCodeBackground(text);

  TextStyle get markdownStyle => bodyStyle.copyWith(
    fontFamily: 'monospace',
    fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
    fontSize: fontSize - 0.5,
  );

  /// Editor for the slide edit panel (speaker / user notes blocks).
  ///
  /// De achtergrond volgt het thema. Hij stond vast op `Colors.white`, en dat
  /// was in donkere modus een wit vlak middenin een donkere interface: de
  /// gebalkte werkbalk boven het notitieveld. De tekst en de iconen komen
  /// mode-afhankelijk binnen (`notesText`/`userNotesText`, licht in donkere
  /// modus), dus ze landden bijna onzichtbaar op dat witte vlak — de tekst op
  /// 1,1:1, de iconen op 1,3:1 (#821). Met `paper` — dezelfde tint als de
  /// `fillColor` van het veld eronder — leest de lichte tekst op ~15:1 en de
  /// werkbalk hoort weer bij de rest.
  factory MarkdownEditorTheme.editorPanel({
    required Color text,
    required Color link,
    required Color accent,
    required Color codeBackground,
    required Color border,
    double fontSize = 12,
  }) {
    return MarkdownEditorTheme(
      surface: AppTheme.paper,
      text: text,
      hint: text.withValues(alpha: 0.45),
      link: link,
      heading: text,
      subheading: text,
      codeBackground: codeBackground,
      toolbarIcon: text.withValues(alpha: 0.75),
      accent: accent,
      border: border,
      fontSize: fontSize,
    );
  }

  /// Editor chrome derived entirely from the active [ColorScheme], so the
  /// word-processor honours the app theme instead of a hard-coded palette.
  ///
  /// The writing sheet is [ColorScheme.surfaceContainerLowest] and its text is
  /// [ColorScheme.onSurface] — a pair Material guarantees to contrast, in light
  /// and dark and under a custom appearance profile alike. It sits a tone apart
  /// from the dialog's own [ColorScheme.surface] so the page stays visible as a
  /// distinct writing area.
  factory MarkdownEditorTheme.documentSurface({
    required ColorScheme scheme,
    double fontSize = 15,
    String? fontFamily,
    ThemeProfile? profile,
    bool documentTypography = false,
  }) {
    final paper = profile == null
        ? scheme.surfaceContainerLowest
        : AppTheme.parseHexColor(profile.slideBackgroundColor);
    final text = profile == null
        ? scheme.onSurface
        : AppTheme.parseHexColor(profile.textColor);
    final accent = profile == null
        ? scheme.primary
        : AppTheme.parseHexColor(profile.accentColor);
    // De kopkleuren volgen het profiel: een documentstijl die een eigen
    // kopkleur kiest krijgt die op élk kopniveau, net als in de lezer en de
    // export. Zonder profiel valt h1 terug op de tekstkleur en h2+ op het
    // accent — dezelfde verdeling als [_Theme] in document_markdown_blocks.
    final headingColor = profile == null
        ? text
        : AppTheme.parseHexColor(profile.effectiveDocumentHeadingColor);
    final subheadingColor = profile == null
        ? accent
        : AppTheme.parseHexColor(profile.effectiveDocumentSubheadingColor);
    return MarkdownEditorTheme(
      surface: paper,
      text: text,
      hint: text.withValues(alpha: 0.62),
      link: accent,
      heading: headingColor,
      subheading: subheadingColor,
      // Het codeblok-vlak matcht de lezer: surfaceContainerHighest op 60%
      // zonder profiel, de profielkleur met. Eerder stond hier
      // surfaceContainerHigh zonder alpha — een andere tint dan de weergave.
      codeBackground: profile == null
          ? scheme.surfaceContainerHighest.withValues(alpha: 0.6)
          : AppTheme.parseHexColor(profile.codeBackgroundColor),
      toolbarIcon: text.withValues(alpha: 0.72),
      accent: accent,
      border: profile == null
          ? scheme.outlineVariant
          : text.withValues(alpha: 0.22),
      // Met documenttypografie gelden de maten van de documentweergave, zodat
      // schrijven en drukken dezelfde hoogte opleveren — inclusief de
      // basislettergrootte van de gekozen documentstijl. Zonder die laatste
      // schreef je in de standaardmaat en drukte je in een andere, en dan valt
      // de pagina-eindlijn op de verkeerde regel.
      fontSize: documentTypography
          ? documentBodyFontSizeToCssPx(
              profile?.documentBodyFontSize ?? kDocumentBodyFontSize,
            )
          : fontSize,
      lineHeight: documentTypography ? kDocumentBodyLineHeight : 1.5,
      // Het lettertype van de gekozen documentstijl; `null` = het app-lettertype
      // (dan leest een plat document precies als voorheen).
      fontFamily: fontFamily,
      profile: profile,
      documentTypography: documentTypography,
      // Citaten: de balk en de achtergrond volgen het accent, de tekst staat
      // een tint lager — dezelfde keuze als [_Theme] in de lezer.
      quoteText: profile == null ? scheme.onSurfaceVariant : text,
      quoteBg: profile == null
          ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
          : accent.withValues(alpha: 0.10),
      quoteBar: accent,
      // Code-inkt: een profiel kan een eigen kleur kiezen, anders de
      // tekstkleur — net als in de lezer.
      codeText: profile?.codeTextColor == null
          ? scheme.onSurface
          : AppTheme.parseHexColor(profile!.codeTextColor, fallback: text),
    );
  }

  /// Contrasting surface for notes inside a themed presenter overlay.
  factory MarkdownEditorTheme.presenterOverlay({
    required Color panelBackground,
    required Color panelText,
    required Color accent,
    String? fontFamily,
  }) {
    final darkPanel = panelBackground.computeLuminance() < 0.45;
    return MarkdownEditorTheme(
      surface: darkPanel ? AppTheme.darkNeutral : Colors.white,
      text: darkPanel ? AppTheme.gray100 : AppTheme.slate800,
      hint: darkPanel ? AppTheme.gray400 : AppTheme.slate400,
      link: accent,
      heading: panelText,
      subheading: panelText,
      codeBackground: darkPanel ? AppTheme.gray700 : AppTheme.slate100,
      toolbarIcon: darkPanel ? AppTheme.gray300 : AppTheme.slate500,
      accent: accent,
      border: panelText.withValues(alpha: 0.2),
      fontSize: 15,
      fontFamily: fontFamily,
    );
  }
}

/// Geeft document-embeds hetzelfde profiel als de omliggende WYSIWYG-editor.
/// Alleen de documentfactory zet een profiel; notities bij presentaties blijven
/// daardoor het sobere app-thema gebruiken.
class DocumentStyleScope extends InheritedWidget {
  const DocumentStyleScope({
    super.key,
    required this.profile,
    required super.child,
  });

  final ThemeProfile? profile;

  static ThemeProfile? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DocumentStyleScope>()?.profile;

  @override
  bool updateShouldNotify(DocumentStyleScope oldWidget) =>
      profile != oldWidget.profile;
}
