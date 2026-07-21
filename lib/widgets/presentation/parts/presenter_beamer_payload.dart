// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Split out for navigability; all imports live in the main library file.
part of '../fullscreen_presenter.dart';

/// The markdown payload for the audience window: the slides and the TLP level.
///
/// This payload never touches disk, so everything the beamer cannot look up for
/// itself has to travel with it. Chart data is therefore inlined: a chart that
/// links its data through `source` would otherwise arrive as a bare relative
/// reference the beamer cannot resolve, and render as an empty plot.
///
/// De styling reist er náást mee, niet erin. Ze stond tot 0.1.0 als base64 in
/// de front matter van deze payload, en dat was het laatste stukje base64 dat
/// de markdown-generator kon produceren. Het profiel hoort niet in een
/// document dat een teksteditor moet kunnen lezen; de boodschap naar het
/// tweede venster is een JSON-envelop en heeft er al een veld voor
/// ([beamerStyleProfileKey]).
String buildBeamerMarkdown({
  required List<Slide> slides,
  required String? projectPath,
  TlpLevel tlp = TlpLevel.none,
  String organization = '',
  String reportLanguage = '',
}) => MarkdownService().generateDeck(
  Deck(
    title: 'Presentatie',
    slides: slides,
    projectPath: projectPath,
    tlp: tlp,
    organization: organization,
    language: reportLanguage,
  ),
  inlineChartData: true,
);
