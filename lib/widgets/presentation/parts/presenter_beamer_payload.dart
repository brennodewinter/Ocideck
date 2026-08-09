// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Split out for navigability; all imports live in the main library file.
part of '../fullscreen_presenter.dart';

/// Guards teardown of the secondary audience window so native close is only
/// invoked once (double-close on Linux can crash the embedder).
@visibleForTesting
class AudienceWindowHandle {
  AudienceWindowHandle(
    this.controller, {
    Future<void> Function(WindowController controller)? closeImpl,
  }) : _closeImpl = closeImpl ?? ((c) => c.close());

  final WindowController controller;
  final Future<void> Function(WindowController controller) _closeImpl;
  bool _closed = false;

  bool get isClosed => _closed;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _closeImpl(controller);
    } catch (e) {
      logWarning('AudienceWindowHandle.close: audience window', e);
    }
  }
}

String _audienceWindowArguments({
  required String markdown,
  required String? projectPath,
  required int initialIndex,
  required Map<String, dynamic> inkByIndex,
  required bool showClassificationWatermark,
  required bool allowRemoteMedia,
  required ThemeProfile themeProfile,
  required MarpStyle marpStyle,
  required CockpitColorScheme cockpitColorScheme,
}) => jsonEncode({
  'markdown': markdown,
  'projectPath': projectPath,
  'index': initialIndex,
  'ink': inkByIndex,
  'classificationWatermarkEnabled': showClassificationWatermark,
  'allowRemoteMedia': allowRemoteMedia,
  // Styling travels beside the readable Markdown because the audience window
  // has no other source for the active profiles.
  beamerStyleProfileKey: themeProfile.toJson(),
  'marpStyle': marpStyle.toJson(),
  'cockpitColorScheme': cockpitColorScheme.toJson(),
});

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
  ImprovementY01Metric improvementY01 = ImprovementY01Metric.empty,
}) => MarkdownService().generateDeck(
  Deck(
    title: 'Presentatie',
    slides: slides,
    projectPath: projectPath,
    tlp: tlp,
    organization: organization,
    language: reportLanguage,
    improvementY01Metric: improvementY01,
  ),
  inlineChartData: true,
);

/// Mermaid-kijkstand delen met het publieksvenster. Hoort bij [_sendMermaidView]
/// hierboven; als extension op [_FullscreenPresenterState] omdat het de
/// presentertoestand leest die in het hoofdbestand leeft.
extension _PresenterMermaidBroadcast on _FullscreenPresenterState {
  /// Listener op [_mermaidView]: deelt de kijkstand met het publieksvenster en
  /// onthoudt de laatst verzonden waarde voor de throttle. Zie [_sendMermaidView].
  void _broadcastMermaidView() {
    _lastSentMermaidView = _sendMermaidView(
      audience: widget.audience,
      controller: _mermaidView,
      index: _index,
      lastSent: _lastSentMermaidView,
    );
  }
}
