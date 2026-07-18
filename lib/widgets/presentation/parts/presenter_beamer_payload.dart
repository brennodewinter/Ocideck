// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Split out for navigability; all imports live in the main library file.
part of '../fullscreen_presenter.dart';

/// The self-contained markdown payload for the audience window: the slides,
/// the style profile and the TLP level in one string.
///
/// This payload never touches disk, so everything the beamer cannot look up for
/// itself has to travel inside it. That is why the style profile is inlined —
/// the audience window has no other way to learn the deck's styling — and, for
/// the same reason, why chart data is. A chart that links its data through
/// `source` would otherwise arrive as a bare relative reference the beamer
/// cannot resolve, and render as an empty plot.
String buildBeamerMarkdown({
  required List<Slide> slides,
  required String? projectPath,
  required ThemeProfile themeProfile,
  TlpLevel tlp = TlpLevel.none,
  String organization = '',
  String reportLanguage = '',
}) => MarkdownService().generateDeck(
  Deck(
    title: 'Presentatie',
    slides: slides,
    projectPath: projectPath,
    themeProfile: themeProfile,
    tlp: tlp,
    organization: organization,
    language: reportLanguage,
  ),
  inlineStyleProfile: true,
  inlineChartData: true,
);
