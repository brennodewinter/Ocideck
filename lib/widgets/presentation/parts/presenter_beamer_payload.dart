// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Split out for navigability; all imports live in the main library file.
part of '../fullscreen_presenter.dart';

typedef _AudienceSyncSnapshot = ({
  int index,
  int blank,
  int richTextPage,
  int stepIndex,
  int menuCategory,
  double timelineView,
  int timedPhase,
  int countdown,
});

void _syncPresenterAudience(
  _FullscreenPresenterState state, {
  bool force = false,
}) {
  if (state.widget.audience?.controller == null) return;
  final snapshot = (
    index: state._index,
    blank: state._blankCode,
    richTextPage: state._richTextPage,
    stepIndex: state._stepIndex,
    menuCategory: state._menuCategory,
    timelineView: state._timelineSync.controller.fraction,
    timedPhase: state.widget.presentationTiming.enabled
        ? state._timedSession.phase.index
        : -1,
    countdown: state._timedSession.countdown,
  );
  final indexChanged = state._audienceSync.indexChanged(snapshot);
  if (!state._audienceSync.begin(snapshot, force: force)) return;
  audienceChannel
      .invokeMethod('update', {
        'seq': state._audienceSync.nextSequence,
        'index': snapshot.index,
        'blank': snapshot.blank,
        'richTextPage': snapshot.richTextPage,
        'stepIndex': snapshot.stepIndex,
        'menuCategory': snapshot.menuCategory,
        'timelineView': snapshot.timelineView,
        'timedPhase': snapshot.timedPhase,
        'countdown': snapshot.countdown,
      })
      .then<void>((_) => state._audienceSync.delivered())
      .catchError((Object error) {
        logWarning('FullscreenPresenter: audience window sync failed', error);
        if (state.mounted) {
          state._audienceSync.failed(
            snapshot,
            error,
            () => state._syncAudience(),
          );
        }
        return null;
      });
  if (!indexChanged) return;
  state._chartHover.setLocal(null);
  state._chartHover.setExternal(null);
  state._pushInk();
}

/// Houdt verzendstatus en een begrensde snelle herkansing voor de beamer bij.
///
/// De presentator blijft hierdoor alleen verantwoordelijk voor zijn huidige
/// toestand. Transportboekhouding hoort niet in die al grote widget state.
class _AudienceSyncTracker {
  _AudienceSyncSnapshot? _last;
  Timer? _retry;
  bool _retrying = false;
  int _sequence = 0;

  int get nextSequence => ++_sequence;

  bool indexChanged(_AudienceSyncSnapshot snapshot) =>
      snapshot.index != _last?.index;

  bool begin(_AudienceSyncSnapshot snapshot, {required bool force}) {
    if (!force && snapshot == _last) return false;
    // Optimistisch onthouden voorkomt dubbel zenden bij twee builds terwijl
    // dezelfde method-channel-aanroep nog onderweg is.
    _last = snapshot;
    return true;
  }

  void delivered() => _retrying = false;

  void invalidate() => _last = null;

  void failed(
    _AudienceSyncSnapshot snapshot,
    Object error,
    VoidCallback retry,
  ) {
    // Trek alleen deze mislukte snapshot terug. Een nieuwere toestand kan
    // intussen al onderweg of afgeleverd zijn.
    if (_last != snapshot) return;
    _last = null;
    final retryable =
        error is WindowChannelException &&
        const {
          'CHANNEL_UNREGISTERED',
          'CHANNEL_NOT_FOUND',
        }.contains(error.code);
    if (!retryable || _retrying) return;
    _retrying = true;
    _retry?.cancel();
    _retry = Timer(const Duration(milliseconds: 100), retry);
  }

  void dispose() => _retry?.cancel();
}

/// Owns the timeline viewport and its throttled audience transport.
///
/// Keeping this session-only concern outside [_FullscreenPresenterState] means
/// navigation only says "reset"; it does not also carry channel bookkeeping.
class _TimelineViewSync {
  _TimelineViewSync(this.audience, this.index) {
    controller.addListener(_broadcast);
  }

  final AudienceWindowHandle? audience;
  final int Function() index;
  final TimelineViewController controller = TimelineViewController();
  double? _lastSent;

  void reset() {
    _lastSent = null;
    controller.setFraction(0);
    _broadcast();
  }

  void _broadcast() {
    if (audience?.controller == null) return;
    final fraction = controller.fraction;
    if (_lastSent != null && (fraction - _lastSent!).abs() < 0.005) return;
    _lastSent = fraction;
    audienceChannel
        .invokeMethod('timelineView', {'index': index(), 'fraction': fraction})
        .catchError((Object e) {
          logWarning('FullscreenPresenter: timeline view sync failed', e);
          return null;
        });
  }

  void dispose() {
    controller.removeListener(_broadcast);
    controller.dispose();
  }
}

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
  // Het profiel staat óók in het Deck: zonder logoPath schrijft de serialisator
  // nooit `no-logo`, en zou het publieksvenster de per-dia logo-opt-out
  // verliezen terwijl de presentator hem wel toepast (#2172).
  required ThemeProfile themeProfile,
  TlpLevel tlp = TlpLevel.none,
  String organization = '',
  String reportLanguage = '',
  ImprovementY01Metric improvementY01 = ImprovementY01Metric.empty,
}) => MarkdownService().generateDeck(
  Deck(
    title: 'Presentatie',
    slides: slides,
    projectPath: projectPath,
    themeProfile: themeProfile,
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

  /// Listener op [_chartHover]: deelt de eigen hover met het publieksvenster.
  /// Leest alleen [ChartHoverController.local] — een van de beamer ontvangen
  /// hover (extern) verandert `local` niet, dus wordt hij niet teruggekaatst.
  void _broadcastChartHover() {
    final hover = _chartHover.local;
    final seq = _chartHoverStream.nextFor(hover);
    if (seq == null) return;
    _sendChartHover(
      audience: widget.audience,
      hover: hover,
      index: _index,
      sequence: seq,
    );
  }

  /// Een 'chartHover' van het beamervenster: toon dezelfde markering op de
  /// presenter-dia, mits het venster nog op onze dia staat (een late hover mag
  /// nooit op een andere dia belanden).
  void _applyBeamerChartHover(Object? arguments) {
    final args = Map<String, dynamic>.from(arguments as Map);
    if (!_chartHoverStream.accept((args['seq'] as num?)?.toInt())) return;
    if ((args['index'] as num?)?.toInt() == _index) {
      _chartHover.setExternal(ChartHover.fromJson(args['hover']));
    }
  }
}

/// Stuurt de huidige lokale grafiek-hover naar het publieksvenster (#930-stijl,
/// naast [_sendMermaidView]). Alleen bij een echte wijziging: de hover verspringt
/// pas als de aanwijzer een andere reeks/punt/taartpunt raakt, dus is geen
/// tijd-throttle nodig. De index reist mee zodat het venster een late hover
/// nooit op een andere dia zet.
/// [sequence] maakt een snelle hover A -> B -> weg bestand tegen berichten die
/// door de vensterbrug buiten volgorde aankomen. Top-level, net als
/// [_sendMermaidView].
void _sendChartHover({
  required AudienceWindowHandle? audience,
  required ChartHover? hover,
  required int index,
  required int sequence,
}) {
  if (audience?.controller == null) return;
  audienceChannel
      .invokeMethod('chartHover', {
        'seq': sequence,
        'index': index,
        'hover': hover?.toJson(),
      })
      .catchError((Object e) {
        logWarning('FullscreenPresenter: chart hover sync failed', e);
        return null;
      });
}

String _dualWindowArguments({
  required List<Slide> slides,
  required String? projectPath,
  required int initialIndex,
  required TlpLevel tlp,
  required String organization,
  required String reportLanguage,
  required ImprovementY01Metric improvementY01,
  required Map<String, List<InkStroke>> annotations,
  required bool showClassificationWatermark,
  required bool allowRemoteMedia,
  required ThemeProfile themeProfile,
  required MarpStyle marpStyle,
  required CockpitColorScheme cockpitColorScheme,
}) => _audienceWindowArguments(
  markdown: buildBeamerMarkdown(
    slides: slides,
    projectPath: projectPath,
    themeProfile: themeProfile,
    tlp: tlp,
    organization: organization,
    reportLanguage: reportLanguage,
    improvementY01: improvementY01,
  ),
  projectPath: projectPath,
  initialIndex: initialIndex,
  inkByIndex: FullscreenPresenter._annotationsBySlideIndex(slides, annotations),
  showClassificationWatermark: showClassificationWatermark,
  allowRemoteMedia: allowRemoteMedia,
  themeProfile: themeProfile,
  marpStyle: marpStyle,
  cockpitColorScheme: cockpitColorScheme,
);

Future<String?> _runDualPresenter(
  BuildContext context, {
  required AudienceWindowHandle audienceHandle,
  required List<Slide> slides,
  required String? projectPath,
  required ThemeProfile themeProfile,
  required MarpStyle marpStyle,
  required CockpitColorScheme cockpitColorScheme,
  required int initialIndex,
  required TlpLevel tlp,
  required String organization,
  required String reportLanguage,
  required bool showClassificationWatermark,
  required bool allowRemoteMedia,
  required Duration? targetDuration,
  required bool showRehearsalSummary,
  required bool playOnly,
  required PresentationTimingConfig presentationTiming,
  required bool rehearsalMode,
  required Map<String, List<InkStroke>> annotations,
  required void Function(Map<String, List<InkStroke>>)? onAnnotationsChanged,
  required ValueChanged<Slide>? onSlideChanged,
  required ValueChanged<String>? onSlideSplit,
  required ValueChanged<Slide>? onSessionEdit,
  required Future<void> Function(PlaybackReport report)? onPlaybackFinished,
  required Map<String, String> initialUserNotes,
  required void Function(Map<String, String>)? onUserNotesChanged,
  required ImprovementY01Metric improvementY01,
}) async {
  final hadWakeLock = await _wakeLockEnabled();
  await _enableWakeLock();
  try {
    if (!context.mounted) return null;
    return await Navigator.push<String>(
      context,
      PageRouteBuilder<String>(
        opaque: true,
        pageBuilder: (context, anim, anim2) => FullscreenPresenter(
          slides: slides,
          projectPath: projectPath,
          themeProfile: themeProfile,
          marpStyle: marpStyle,
          cockpitColorScheme: cockpitColorScheme,
          initialIndex: initialIndex,
          tlp: tlp,
          organization: organization,
          reportLanguage: reportLanguage,
          showClassificationWatermark: showClassificationWatermark,
          allowRemoteMedia: allowRemoteMedia,
          targetDuration: targetDuration,
          showRehearsalSummary: showRehearsalSummary,
          playOnly: playOnly,
          presentationTiming: presentationTiming,
          rehearsalMode: rehearsalMode,
          audience: audienceHandle,
          initialAnnotations: annotations,
          onAnnotationsChanged: onAnnotationsChanged,
          onSlideChanged: onSlideChanged,
          onSlideSplit: onSlideSplit,
          onSessionEdit: onSessionEdit,
          onPlaybackFinished: onPlaybackFinished,
          initialUserNotes: initialUserNotes,
          onUserNotesChanged: onUserNotesChanged,
          improvementY01: improvementY01,
        ),
        transitionsBuilder: (context, animation, secondary, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );
  } finally {
    await _restoreWakeLock(hadWakeLock);
    await audienceHandle.close();
  }
}
