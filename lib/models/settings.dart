import 'privacy_disposition.dart';
import 'privacy_finding.dart';
import '../services/privacy/privacy_regions.dart';
import 'ai_settings.dart';
import 'libreplan_settings.dart';
import 'chart.dart' show normalizeChartColor;
import 'checklist_template.dart';
import 'library_folder.dart';
import 'page_size.dart';
import 'recent_file.dart';
import 'storage_connection.dart';
import 'git_settings.dart';
import 's3_settings.dart';
import 'webdav_settings.dart';
import 'matrix_settings.dart';

export 'ai_settings.dart';
export 'libreplan_settings.dart';
export 'checklist_template.dart';
export 'library_folder.dart';
export 'recent_file.dart';
export 'git_settings.dart';
export 's3_settings.dart';
export 'webdav_settings.dart';

part 'parts/app_appearance_profile.dart';
part 'parts/cockpit_color_scheme.dart';
part 'parts/app_settings.dart';

/// Glyph used for unordered (bullet) list markers. [dot] is the classic
/// typographic bullet; [paw] swaps in a small cat-paw drawn in the accent
/// colour (OciDeck's mascot). The theme picks a default; a slide may override
/// it (see `Slide.bulletMarkerOverride`).
enum BulletMarker { dot, paw }

/// Shared activation/animation duration (ms) that animated slide types
/// (timeline, cockpit) inherit from the theme when a slide sets no own value.
/// One knob drives both so a timeline builds up over the same span as a
/// cockpit. The ceiling matches the per-type maxima (30s); a slide that wants
/// different pacing overrides it (see `Slide.timelineAnimationMs` /
/// `CockpitSpec.animationDurationMs`, both nullable = inherit this).
const int kThemeDefaultAnimationDurationMs = 2000;
const int kThemeMinAnimationDurationMs = 400;
const int kThemeMaxAnimationDurationMs = 30000;

/// Clamp a stored/edited theme animation duration into the allowed range.
int clampThemeAnimationDuration(int ms) =>
    ms.clamp(kThemeMinAnimationDurationMs, kThemeMaxAnimationDurationMs);

/// De basislettergrootte van een document, in typografische punten — de maat
/// waarin de gewone tekst staat, en waar de koppen, de noten en de
/// tijdlijnkaartjes zich naar verhouden. Dezelfde eenheid als de PDF: een punt
/// is 1/72 duim.
///
/// Alleen voor documenten. Een dia schaalt haar tekst naar het 16:9-kader en
/// heeft dus geen vaste maat; een blad heeft er wel een, en dat is precies wat
/// hier ontbrak: je kon een documentstijl kiezen zonder te kunnen zeggen hoe
/// groot de letter erin was.
///
/// De ondergrens is de kleinste maat die op papier nog leest, de bovengrens de
/// grootste waarbij een A4 nog een alinea draagt in plaats van een zin.
const double kDocumentDefaultBodyFontSize = 11.0;
const double kDocumentMinBodyFontSize = 9.0;
const double kDocumentMaxBodyFontSize = 28.0;

/// CSS-pixels per typografisch punt. De pagina-meetkunde van het document
/// staat op 96 dpi (`kPxPerMm` in de paginaweergave); een punt is 1/72 duim.
/// Zonder deze factor is een body van 11 pt op het scherm 11 CSS-pixels — een
/// derde kleiner dan dezelfde 11 pt in de PDF, en dat is hoe het blad op het
/// scherm kleiner las dan op papier (#1947).
const double kCssPxPerPoint = 96 / 72;

/// Klem een opgeslagen of bewerkte documentlettergrootte binnen het bereik.
double clampDocumentBodyFontSize(double pt) =>
    pt.clamp(kDocumentMinBodyFontSize, kDocumentMaxBodyFontSize);

/// Zet de opgeslagen puntmaat om naar CSS-pixels, zodat scherm, schrijfvlak
/// en HTML-export dezelfde fysieke letter tonen als de PDF.
double documentBodyFontSizeToCssPx(double pt) =>
    clampDocumentBodyFontSize(pt) * kCssPxPerPoint;

/// Op welke breedte je in de visuele documentmodus schrijft.
///
/// Drie standen, omdat er drie verschillende dingen zijn die je aan het doen
/// bent. [page] is de tekstbreedte van het vel: dan valt een pagina-einde op
/// het scherm waar het op papier valt, en alleen in deze stand betekenen de
/// streepjeslijnen iets. [column] is een rustige leesbreedte uit de
/// instellingen, voor wie schrijft zonder aan de bladzijde te denken. [full]
/// gebruikt het hele venster, voor een brede tabel of een tweede scherm.
enum DocumentEditorWidth { page, column, full }

/// De randstijl van een tabel in een document of presentatie. Huisstijl die
/// voor álle tabellen geldt — zie `ThemeProfile.tableBorderStyle`.
enum TableBorderStyle {
  /// Dunne horizontale lijnen tussen rijen (booktabs-stijl): geen verticale
  /// randen, alleen een lijn onder de kop en onder de laatste rij.
  lined,

  /// Volledig omkaderd: elke cel krijgt een rand aan alle zijden.
  boxed,

  /// Geen randen: de tabel leunt op witruimte en kopvulling.
  none,
}

class ThemeProfile {
  final String name;
  final String slideBackgroundColor;
  final String textColor;
  final String accentColor;
  final String checklistCheckedColor;
  final String checklistUncheckedColor;
  final bool checklistStrikeThrough;

  /// Default marker glyph; a slide can override it.
  final BulletMarker bulletMarker;
  final String tableTextColor;
  final String tableHeaderTextColor;
  final String tableHeaderBackgroundColor;

  /// Tabelstijl — huisstijl die voor alle tabellen in documenten en slides
  /// geldt (feature 5). Zebrastrepen kleuren elke tweede body-rij (de tweede,
  /// vierde, … — `tbody tr:nth-child(even)` in de HTML-export, dezelfde rijen
  /// in de Flutter-weergave) met
  /// [tableZebraColor]; [tableBorderStyle] bepaalt de randvorm; [tableBorderColor]
  /// is de randkleur (standaard lichtgrijs); [tableCellPaddingPx] is de
  /// celopvulling in px (CSS) / logical pixels (Flutter); [tableAccentHeaderBorder]
  /// trekt een accentkleurige onderrand onder de koprij.
  final bool tableZebraStriped;
  final String tableZebraColor;
  final TableBorderStyle tableBorderStyle;
  final String tableBorderColor;
  final double tableCellPaddingPx;
  final bool tableAccentHeaderBorder;

  final String titleBackgroundColor;
  final String titleTextColor;
  final String sectionBackgroundColor;

  /// Colours for code (broncode) slides.
  final String codeBackgroundColor;
  final String codeTextColor;

  /// When false, code is shown monochrome in [codeTextColor].
  final bool codeHighlightSyntax;

  final String codeFontFamily;
  final String? logoPath;
  final String logoPosition;
  final int logoSize;

  /// Donkere variant van het logo, gekozen op donkere dia-achtergronden (#1931).
  /// `null` betekent: geen donkere variant. Gebundelde merk-logo's kiezen
  /// automatisch via [BrandLogo.effectiveAssetKey] en hebben dit veld niet nodig.
  final String? logoDarkPath;

  /// Documenten delen standaard het presentatielogo; `null` deelt en leeg zet het uit.
  final String? documentLogoPath;
  final String documentLogoPosition;
  final int? documentLogoSize;
  final double documentBodyFontSize;
  final String documentHeaderText;
  final String documentFooterText;

  /// De kleur van de koppen ván een document. `null` houdt de verdeling die er
  /// altijd was: een hoofdstukkop volgt de tekstkleur, een subkop het accent.
  /// Wie hem zet, krijgt één kopkleur voor alle niveaus — het geval waarvoor
  /// hij bestaat is een rapport met rustige broodtekst en koppen in de
  /// huisstijlkleur, en dat kon met de bestaande velden niet.
  final String? documentHeadingColor;
  final String? documentBandTextColor;
  final String? documentBandBackgroundColor;
  final bool documentShowPageNumbers;

  final String fontFamily;

  /// Vrije footertekst onderaan elke slide; ondersteunt tokens.
  final String footerText;

  /// Toon pagina/totaal rechtsonder op elke slide.
  final bool footerShowPageNumbers;
  final String footerPosition;

  /// Optionele afsluitslide bij presenteren en exporteren.
  final bool closingSlideEnabled;
  final String closingSlideMarkdown;

  final int animationDurationMs;

  /// Severity-kleuren voor bevindingen (Critical→Informational).
  final String severityCriticalColor;
  final String severityHighColor;
  final String severityMediumColor;
  final String severityLowColor;
  final String severityNoneColor;

  const ThemeProfile({
    this.name = 'Standaard',
    this.slideBackgroundColor = '#FFFFFF',
    this.textColor = '#222222',
    this.accentColor = '#2E7D64',
    this.checklistCheckedColor = '#2E7D64',
    this.checklistUncheckedColor = '#64748B',
    this.checklistStrikeThrough = true,
    this.bulletMarker = BulletMarker.dot,
    String? tableTextColor,
    this.tableHeaderTextColor = '#FFFFFF',
    String? tableHeaderBackgroundColor,
    this.tableZebraStriped = false,
    String? tableZebraColor,
    this.tableBorderStyle = TableBorderStyle.boxed,
    String? tableBorderColor,
    this.tableCellPaddingPx = 8.0,
    this.tableAccentHeaderBorder = false,
    this.titleBackgroundColor = '#1C2B47',
    this.titleTextColor = '#FFFFFF',
    this.sectionBackgroundColor = '#2E7D64',
    this.codeBackgroundColor = '#282C34',
    this.codeTextColor = '#ABB2BF',
    this.codeHighlightSyntax = true,
    this.codeFontFamily = 'monospace',
    this.logoPath,
    this.logoPosition = 'bottom-right',
    this.logoSize = 96,
    this.logoDarkPath,
    this.documentLogoPath,
    this.documentLogoPosition = 'top-right',
    this.documentLogoSize,
    this.documentBodyFontSize = kDocumentDefaultBodyFontSize,
    this.documentHeaderText = '',
    this.documentFooterText = '',
    this.documentHeadingColor,
    this.documentBandTextColor,
    this.documentBandBackgroundColor,
    this.documentShowPageNumbers = false,
    this.fontFamily = 'Arial',
    this.footerText = '',
    this.footerShowPageNumbers = false,
    this.footerPosition = 'right',
    this.closingSlideEnabled = false,
    this.closingSlideMarkdown = '# Bedankt\n\nVragen?',
    this.animationDurationMs = kThemeDefaultAnimationDurationMs,
    this.severityCriticalColor = '#B91C1C',
    this.severityHighColor = '#EA580C',
    this.severityMediumColor = '#D97706',
    this.severityLowColor = '#15803D',
    this.severityNoneColor = '#475569',
  }) : tableTextColor = tableTextColor ?? textColor,
       tableHeaderBackgroundColor = tableHeaderBackgroundColor ?? accentColor,
       tableZebraColor = tableZebraColor ?? '#F1F5F9',
       tableBorderColor = tableBorderColor ?? '#CBD5E1';

  static const logoPositions = [
    'top-left',
    'top-right',
    'bottom-left',
    'bottom-right',
  ];

  static const footerPositions = ['left', 'center', 'right'];

  /// Ingebouwd LibreKAT-profiel: de huisstijl (EU-blauw op wit, EB Garamond,
  /// gebundeld logo) die als standaard wordt uitgerold. Het logo is een
  /// `asset:`-pad zodat het op elk platform — ook web — rendert en mee kan in
  /// pakket-exports.
  static const libreKat = ThemeProfile(
    name: 'LibreKAT',
    slideBackgroundColor: '#FFFFFF',
    textColor: '#003399',
    accentColor: '#003399',
    checklistCheckedColor: '#003399',
    checklistUncheckedColor: '#DC2626',
    checklistStrikeThrough: true,
    bulletMarker: BulletMarker.dot,
    tableTextColor: '#003399',
    tableHeaderTextColor: '#FFCC00',
    tableHeaderBackgroundColor: '#003399',
    titleBackgroundColor: '#FFFFFF',
    titleTextColor: '#003399',
    sectionBackgroundColor: '#FFFFFF',
    codeBackgroundColor: '#111827',
    codeTextColor: '#2E7D64',
    codeHighlightSyntax: true,
    codeFontFamily: 'monospace',
    logoPath: 'asset:assets/images/librekat-logo.png',
    logoPosition: 'bottom-left',
    logoSize: 96,
    fontFamily: 'EB Garamond',
  );

  /// Ingebouwd beveiligingsprofiel voor pentest-/MIAUW-rapporten (PENTEST_MIAUW
  /// §11): een strakke, zakelijke look — leesbare lichte pagina's met een
  /// donkere slate-titelbalk en een rood accent dat de beveiligingscontext
  /// signaleert. De severity-tokens blijven op de FIRST-standaardpalet, zodat
  /// bevindingskaarten meteen de vertrouwde bandkleuren tonen.
  static const security = ThemeProfile(
    name: 'Security',
    slideBackgroundColor: '#FFFFFF',
    textColor: '#1E293B',
    accentColor: '#B91C1C',
    checklistCheckedColor: '#15803D',
    checklistUncheckedColor: '#64748B',
    checklistStrikeThrough: true,
    bulletMarker: BulletMarker.dot,
    tableTextColor: '#1E293B',
    tableHeaderTextColor: '#FFFFFF',
    tableHeaderBackgroundColor: '#0F172A',
    titleBackgroundColor: '#0F172A',
    titleTextColor: '#FFFFFF',
    sectionBackgroundColor: '#B91C1C',
    codeBackgroundColor: '#0F172A',
    codeTextColor: '#E2E8F0',
    codeHighlightSyntax: true,
    codeFontFamily: 'monospace',
    fontFamily: 'Arial',
  );

  /// Ingebouwd Vigilis-profiel: sober zwart op wit, met het gele merkaccent.
  /// De bestaande semantische kleurvelden dragen de documentstijl én de
  /// presentatie-opmaak; er is bewust geen tweede, documentspecifiek formaat.
  static const vigilis = ThemeProfile(
    name: 'Vigilis',
    slideBackgroundColor: '#FFFFFF',
    textColor: '#111318',
    accentColor: '#FFB800',
    checklistCheckedColor: '#15803D',
    checklistUncheckedColor: '#64748B',
    checklistStrikeThrough: true,
    bulletMarker: BulletMarker.dot,
    tableTextColor: '#111318',
    tableHeaderTextColor: '#FFFFFF',
    tableHeaderBackgroundColor: '#111318',
    titleBackgroundColor: '#111318',
    titleTextColor: '#FFFFFF',
    // De sectiedia tekent `titleTextColor` op deze achtergrond, en dat wit
    // haalde op het merkgeel 1,73 — onleesbaar (#1818). Het geel kan hier niet
    // blijven zolang de sectie zijn tekstkleur deelt met de titeldia, en die
    // moet wit blijven voor de bijna-zwarte titelachtergrond hierboven. Het
    // merkaccent zelf blijft ongemoeid: `accentColor` is nog steeds #FFB800.
    sectionBackgroundColor: '#111318',
    codeBackgroundColor: '#111318',
    codeTextColor: '#F8FAFC',
    codeHighlightSyntax: true,
    codeFontFamily: 'monospace',
    logoPath: 'asset:assets/images/vigilis-logo.png',
    logoPosition: 'top-right',
    logoSize: 112,
    fontFamily: 'Arial',
    footerText: 'Vigilis',
    footerShowPageNumbers: true,
    documentLogoPosition: 'top-right',
    documentHeaderText: 'Bestuurlijk rapport',
    documentFooterText: 'Vigilis · Vertrouwelijk',
    documentShowPageNumbers: true,
  );

  /// Ingebouwde stijlprofielen voor een verse installatie: LibreKAT voorop
  /// (en dus de standaardselectie), met het neutrale 'Standaard' en het
  /// beveiligingsprofiel ernaast. Bestaande installaties behouden hun eigen
  /// opgeslagen profielenlijst.
  static const builtIns = [libreKat, ThemeProfile(), security, vigilis];

  ThemeProfile copyWith({
    String? name,
    String? slideBackgroundColor,
    String? textColor,
    String? accentColor,
    String? checklistCheckedColor,
    String? checklistUncheckedColor,
    bool? checklistStrikeThrough,
    BulletMarker? bulletMarker,
    String? tableTextColor,
    String? tableHeaderTextColor,
    String? tableHeaderBackgroundColor,
    bool? tableZebraStriped,
    String? tableZebraColor,
    TableBorderStyle? tableBorderStyle,
    String? tableBorderColor,
    double? tableCellPaddingPx,
    bool? tableAccentHeaderBorder,
    String? titleBackgroundColor,
    String? titleTextColor,
    String? sectionBackgroundColor,
    String? codeBackgroundColor,
    String? codeTextColor,
    bool? codeHighlightSyntax,
    String? codeFontFamily,
    String? logoPath,
    String? logoPosition,
    int? logoSize,
    String? logoDarkPath,
    String? documentLogoPath,
    String? documentLogoPosition,
    int? documentLogoSize,
    double? documentBodyFontSize,
    String? documentHeaderText,
    String? documentFooterText,
    String? documentHeadingColor,
    String? documentBandTextColor,
    String? documentBandBackgroundColor,
    bool? documentShowPageNumbers,
    String? fontFamily,
    String? footerText,
    bool? footerShowPageNumbers,
    String? footerPosition,
    bool? closingSlideEnabled,
    String? closingSlideMarkdown,
    int? animationDurationMs,
    String? severityCriticalColor,
    String? severityHighColor,
    String? severityMediumColor,
    String? severityLowColor,
    String? severityNoneColor,
    bool clearLogo = false,
    bool clearLogoDark = false,
    bool clearDocumentLogoOverride = false,
  }) {
    return ThemeProfile(
      name: name ?? this.name,
      slideBackgroundColor: slideBackgroundColor ?? this.slideBackgroundColor,
      textColor: textColor ?? this.textColor,
      accentColor: accentColor ?? this.accentColor,
      checklistCheckedColor:
          checklistCheckedColor ?? this.checklistCheckedColor,
      checklistUncheckedColor:
          checklistUncheckedColor ?? this.checklistUncheckedColor,
      checklistStrikeThrough:
          checklistStrikeThrough ?? this.checklistStrikeThrough,
      bulletMarker: bulletMarker ?? this.bulletMarker,
      tableTextColor: tableTextColor ?? this.tableTextColor,
      tableHeaderTextColor: tableHeaderTextColor ?? this.tableHeaderTextColor,
      tableHeaderBackgroundColor:
          tableHeaderBackgroundColor ?? this.tableHeaderBackgroundColor,
      tableZebraStriped: tableZebraStriped ?? this.tableZebraStriped,
      tableZebraColor: tableZebraColor ?? this.tableZebraColor,
      tableBorderStyle: tableBorderStyle ?? this.tableBorderStyle,
      tableBorderColor: tableBorderColor ?? this.tableBorderColor,
      tableCellPaddingPx: tableCellPaddingPx ?? this.tableCellPaddingPx,
      tableAccentHeaderBorder:
          tableAccentHeaderBorder ?? this.tableAccentHeaderBorder,
      titleBackgroundColor: titleBackgroundColor ?? this.titleBackgroundColor,
      titleTextColor: titleTextColor ?? this.titleTextColor,
      sectionBackgroundColor:
          sectionBackgroundColor ?? this.sectionBackgroundColor,
      codeBackgroundColor: codeBackgroundColor ?? this.codeBackgroundColor,
      codeTextColor: codeTextColor ?? this.codeTextColor,
      codeHighlightSyntax: codeHighlightSyntax ?? this.codeHighlightSyntax,
      codeFontFamily: codeFontFamily ?? this.codeFontFamily,
      logoPath: clearLogo ? null : (logoPath ?? this.logoPath),
      logoPosition: logoPosition ?? this.logoPosition,
      logoSize: logoSize ?? this.logoSize,
      logoDarkPath: clearLogoDark ? null : (logoDarkPath ?? this.logoDarkPath),
      documentLogoPath: clearDocumentLogoOverride
          ? null
          : (documentLogoPath ?? this.documentLogoPath),
      documentLogoPosition: documentLogoPosition ?? this.documentLogoPosition,
      documentLogoSize: documentLogoSize ?? this.documentLogoSize,
      documentBodyFontSize: documentBodyFontSize ?? this.documentBodyFontSize,
      documentHeaderText: documentHeaderText ?? this.documentHeaderText,
      documentFooterText: documentFooterText ?? this.documentFooterText,
      documentHeadingColor: documentHeadingColor ?? this.documentHeadingColor,
      documentBandTextColor:
          documentBandTextColor ?? this.documentBandTextColor,
      documentBandBackgroundColor:
          documentBandBackgroundColor ?? this.documentBandBackgroundColor,
      documentShowPageNumbers:
          documentShowPageNumbers ?? this.documentShowPageNumbers,
      fontFamily: fontFamily ?? this.fontFamily,
      footerText: footerText ?? this.footerText,
      footerShowPageNumbers:
          footerShowPageNumbers ?? this.footerShowPageNumbers,
      footerPosition: footerPosition ?? this.footerPosition,
      closingSlideEnabled: closingSlideEnabled ?? this.closingSlideEnabled,
      closingSlideMarkdown: closingSlideMarkdown ?? this.closingSlideMarkdown,
      animationDurationMs: animationDurationMs ?? this.animationDurationMs,
      severityCriticalColor:
          severityCriticalColor ?? this.severityCriticalColor,
      severityHighColor: severityHighColor ?? this.severityHighColor,
      severityMediumColor: severityMediumColor ?? this.severityMediumColor,
      severityLowColor: severityLowColor ?? this.severityLowColor,
      severityNoneColor: severityNoneColor ?? this.severityNoneColor,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'slideBackgroundColor': slideBackgroundColor,
      'name': name,
      'textColor': textColor,
      'accentColor': accentColor,
      'checklistCheckedColor': checklistCheckedColor,
      'checklistUncheckedColor': checklistUncheckedColor,
      'checklistStrikeThrough': checklistStrikeThrough,
      'bulletMarker': bulletMarker.name,
      'tableTextColor': tableTextColor,
      'tableHeaderTextColor': tableHeaderTextColor,
      'tableHeaderBackgroundColor': tableHeaderBackgroundColor,
      'tableZebraStriped': tableZebraStriped,
      'tableZebraColor': tableZebraColor,
      'tableBorderStyle': tableBorderStyle.name,
      'tableBorderColor': tableBorderColor,
      'tableCellPaddingPx': tableCellPaddingPx,
      'tableAccentHeaderBorder': tableAccentHeaderBorder,
      'titleBackgroundColor': titleBackgroundColor,
      'titleTextColor': titleTextColor,
      'sectionBackgroundColor': sectionBackgroundColor,
      'codeBackgroundColor': codeBackgroundColor,
      'codeTextColor': codeTextColor,
      'codeHighlightSyntax': codeHighlightSyntax,
      'codeFontFamily': codeFontFamily,
      'logoPath': logoPath,
      'logoPosition': logoPosition,
      'logoSize': logoSize,
      'logoDarkPath': logoDarkPath,
      'documentLogoPath': documentLogoPath,
      'documentLogoPosition': documentLogoPosition,
      'documentLogoSize': documentLogoSize,
      'documentBodyFontSize': documentBodyFontSize,
      'documentHeaderText': documentHeaderText,
      'documentFooterText': documentFooterText,
      'documentHeadingColor': documentHeadingColor,
      'documentBandTextColor': documentBandTextColor,
      'documentBandBackgroundColor': documentBandBackgroundColor,
      'documentShowPageNumbers': documentShowPageNumbers,
      'fontFamily': fontFamily,
      'footerText': footerText,
      'footerShowPageNumbers': footerShowPageNumbers,
      'footerPosition': footerPosition,
      'closingSlideEnabled': closingSlideEnabled,
      'closingSlideMarkdown': closingSlideMarkdown,
      'animationDurationMs': animationDurationMs,
      'severityCriticalColor': severityCriticalColor,
      'severityHighColor': severityHighColor,
      'severityMediumColor': severityMediumColor,
      'severityLowColor': severityLowColor,
      'severityNoneColor': severityNoneColor,
    };
  }

  /// Houdt profielkleuren veilig voor interpolatie in HTML en CSS.
  static String _color(Object? value, String fallback) =>
      normalizeChartColor(value is String ? value : null) ?? fallback;

  /// Whitelists a font family against the offered set; an unknown value can
  /// break out of the `font-family:'…'` declaration, so reject it.
  static String _font(Object? value, List<String> allowed, String fallback) =>
      value is String && allowed.contains(value) ? value : fallback;

  factory ThemeProfile.fromJson(Map<String, Object?> json) {
    return ThemeProfile(
      slideBackgroundColor: _color(json['slideBackgroundColor'], '#FFFFFF'),
      name: json['name'] as String? ?? 'Standaard',
      textColor: _color(json['textColor'], '#222222'),
      accentColor: _color(json['accentColor'], '#2E7D64'),
      checklistCheckedColor: _color(
        json['checklistCheckedColor'] ?? json['accentColor'],
        '#2E7D64',
      ),
      checklistUncheckedColor: _color(
        json['checklistUncheckedColor'],
        '#64748B',
      ),
      checklistStrikeThrough: json['checklistStrikeThrough'] as bool? ?? true,
      bulletMarker: BulletMarker.values.firstWhere(
        (m) => m.name == json['bulletMarker'],
        orElse: () => BulletMarker.dot,
      ),
      tableTextColor: _color(
        json['tableTextColor'] ?? json['textColor'],
        '#222222',
      ),
      tableHeaderTextColor: _color(json['tableHeaderTextColor'], '#FFFFFF'),
      tableHeaderBackgroundColor: _color(
        json['tableHeaderBackgroundColor'] ?? json['accentColor'],
        '#2E7D64',
      ),
      tableZebraStriped: json['tableZebraStriped'] as bool? ?? false,
      tableZebraColor: _color(json['tableZebraColor'], '#F1F5F9'),
      tableBorderStyle: TableBorderStyle.values.firstWhere(
        (s) => s.name == json['tableBorderStyle'],
        orElse: () => TableBorderStyle.boxed,
      ),
      tableBorderColor: _color(json['tableBorderColor'], '#CBD5E1'),
      tableCellPaddingPx:
          (json['tableCellPaddingPx'] as num?)?.toDouble() ?? 8.0,
      tableAccentHeaderBorder:
          json['tableAccentHeaderBorder'] as bool? ?? false,
      titleBackgroundColor: _color(json['titleBackgroundColor'], '#1C2B47'),
      titleTextColor: _color(json['titleTextColor'], '#FFFFFF'),
      sectionBackgroundColor: _color(json['sectionBackgroundColor'], '#2E7D64'),
      codeBackgroundColor: _color(json['codeBackgroundColor'], '#282C34'),
      codeTextColor: _color(json['codeTextColor'], '#ABB2BF'),
      codeHighlightSyntax: json['codeHighlightSyntax'] as bool? ?? true,
      codeFontFamily: _font(
        json['codeFontFamily'],
        AppSettings.codeFonts,
        'monospace',
      ),
      logoPath: json['logoPath'] as String?,
      logoPosition: json['logoPosition'] as String? ?? 'bottom-right',
      logoSize: (json['logoSize'] as num?)?.round() ?? 96,
      logoDarkPath: json['logoDarkPath'] as String?,
      documentLogoPath: json['documentLogoPath'] as String?,
      documentLogoPosition:
          json['documentLogoPosition'] as String? ?? 'top-right',
      documentLogoSize: (json['documentLogoSize'] as num?)?.round().clamp(
        32,
        480,
      ),
      documentBodyFontSize: clampDocumentBodyFontSize(
        (json['documentBodyFontSize'] as num?)?.toDouble() ??
            kDocumentDefaultBodyFontSize,
      ),
      documentHeaderText: json['documentHeaderText'] as String? ?? '',
      documentFooterText: json['documentFooterText'] as String? ?? '',
      documentHeadingColor: json['documentHeadingColor'] == null
          ? null
          : _color(json['documentHeadingColor'], '#222222'),
      documentBandTextColor: json['documentBandTextColor'] == null
          ? null
          : _color(json['documentBandTextColor'], '#222222'),
      documentBandBackgroundColor: json['documentBandBackgroundColor'] == null
          ? null
          : _color(json['documentBandBackgroundColor'], '#FFFFFF'),
      documentShowPageNumbers:
          json['documentShowPageNumbers'] as bool? ?? false,
      fontFamily: _font(
        json['fontFamily'],
        AppSettings.availableFonts,
        'Arial',
      ),
      footerText: json['footerText'] as String? ?? '',
      footerShowPageNumbers: json['footerShowPageNumbers'] as bool? ?? false,
      footerPosition: json['footerPosition'] as String? ?? 'right',
      closingSlideEnabled: json['closingSlideEnabled'] as bool? ?? false,
      closingSlideMarkdown:
          json['closingSlideMarkdown'] as String? ?? '# Bedankt\n\nVragen?',
      animationDurationMs: clampThemeAnimationDuration(
        (json['animationDurationMs'] as num?)?.round() ??
            kThemeDefaultAnimationDurationMs,
      ),
      severityCriticalColor: _color(json['severityCriticalColor'], '#B91C1C'),
      severityHighColor: _color(json['severityHighColor'], '#EA580C'),
      severityMediumColor: _color(json['severityMediumColor'], '#D97706'),
      severityLowColor: _color(json['severityLowColor'], '#15803D'),
      severityNoneColor: _color(json['severityNoneColor'], '#475569'),
    );
  }

  String? get effectiveDocumentLogoPath => documentLogoPath ?? logoPath;
  int get effectiveDocumentLogoSize =>
      (documentLogoSize ?? logoSize).clamp(32, 480);

  /// Hoeveel groter of kleiner de documenttekst staat dan de standaardmaat.
  ///
  /// Eén verhouding, want alles op een blad hangt aan dezelfde maat: een kop is
  /// een veelvoud van de bodytekst, een noot een breukdeel ervan. Zouden ze elk
  /// hun eigen maat krijgen, dan liep de verhouding scheef zodra iemand de
  /// bodytekst verzette — en dat zie je pas op papier.
  double get documentFontScale =>
      clampDocumentBodyFontSize(documentBodyFontSize) /
      kDocumentDefaultBodyFontSize;

  /// De bodymaat in CSS-pixels — wat de weergave, het schrijfvlak en de
  /// HTML-export zetten. De PDF leest [documentBodyFontSize] rechtstreeks als
  /// punten: zonder deze omzetting is 11 pt op het scherm 11 px (#1947).
  double get documentBodyFontSizeCssPx =>
      documentBodyFontSizeToCssPx(documentBodyFontSize);

  /// De kopkleur van een document, met de oude verdeling als terugval: een
  /// hoofdstukkop volgt de tekstkleur, een subkop het accent. Zo verandert er
  /// niets aan een profiel dat de kleur niet zet.
  String get effectiveDocumentHeadingColor => documentHeadingColor ?? textColor;
  String get effectiveDocumentSubheadingColor =>
      documentHeadingColor ?? accentColor;

  String get effectiveDocumentBandTextColor =>
      documentBandTextColor ?? textColor;
  String get effectiveDocumentBandBackgroundColor =>
      documentBandBackgroundColor ?? slideBackgroundColor;
}
