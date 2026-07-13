import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/annotation.dart';
import '../../models/deck.dart';
import '../../models/question.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../models/timeline.dart';
import '../../services/markdown_service.dart';
import '../../services/mermaid_render_service.dart';
import '../../services/finding_context_score.dart';
import '../../services/slide_layout_metrics.dart';
import '../../utils/url_launcher_util.dart';
import '../slides/slide_preview.dart';
import 'annotation_overlay.dart';

/// Channel the audience (beamer) window listens on for updates from the
/// presenter (laptop) window.
const audienceChannel = WindowMethodChannel(
  'ocideck/audience',
  mode: ChannelMode.unidirectional,
);

/// Channel the presenter window listens on; the audience window uses it to
/// forward navigation (clicks on the beamer) and audio-complete events.
const presenterChannel = WindowMethodChannel(
  'ocideck/presenter',
  mode: ChannelMode.unidirectional,
);

/// True wanneer een 'update'-bericht met [seq] ouder is dan het laatst
/// verwerkte nummer [lastSeq]. Berichten zonder nummer (oudere presenter)
/// worden altijd verwerkt.
bool isStaleUpdateSeq(int? seq, int lastSeq) => seq != null && seq <= lastSeq;

/// The app that runs inside the secondary (beamer) window. It only renders the
/// current slide fullscreen; the presenter window drives it via [audienceChannel].
class AudienceWindowApp extends StatefulWidget {
  final Map<String, dynamic> args;

  const AudienceWindowApp({super.key, required this.args});

  @override
  State<AudienceWindowApp> createState() => _AudienceWindowAppState();
}

class _AudienceWindowAppState extends State<AudienceWindowApp> {
  List<Slide> _slides = const [];
  ThemeProfile _theme = const ThemeProfile();
  CockpitColorScheme _scheme = CockpitColorScheme.standard;
  TlpLevel _tlp = TlpLevel.none;
  String _organization = '';
  bool _showClassificationWatermark = false;
  bool _allowRemoteMedia = false;
  String? _projectPath;
  int _index = 0;
  int _richTextPage = 0;
  int _timelineStep = 0;
  int _blank = 0; // 0 = none, 1 = black, 2 = white
  // Hoogst verwerkte 'update'-sequencenummer; oudere berichten worden genegeerd.
  int _lastUpdateSeq = -1;

  // Annotation layer, keyed by slide index (the beamer has no stable ids).
  final Map<int, List<InkStroke>> _ink = {};
  int? _laserIndex;
  Offset? _laserPoint;
  // The stroke the presenter is drawing right now, mirrored live until it
  // commits (then it arrives as a normal stroke over the 'ink' channel).
  int? _activeIndex;
  InkStroke? _activeStroke;

  // Live question state pushed by the presenter, plus the slide index it
  // belongs to (so it never leaks onto another slide).
  QuestionView? _questionView;
  int _questionIndex = -1;

  @override
  void initState() {
    super.initState();
    final markdown = widget.args['markdown'] as String? ?? '';
    _projectPath = widget.args['projectPath'] as String?;
    _index = (widget.args['index'] as num?)?.toInt() ?? 0;
    final deck = MarkdownService().parseDeck(markdown);
    _slides = deck?.slides ?? const [];
    _theme = deck?.themeProfile ?? const ThemeProfile();
    final schemeJson = widget.args['cockpitColorScheme'];
    if (schemeJson is Map) {
      _scheme = CockpitColorScheme.fromJson(
        Map<String, Object?>.from(schemeJson),
      );
    }
    _tlp = deck?.tlp ?? TlpLevel.none;
    _organization = deck?.organization ?? '';
    _showClassificationWatermark =
        widget.args['classificationWatermarkEnabled'] as bool? ?? false;
    _allowRemoteMedia = widget.args['allowRemoteMedia'] as bool? ?? false;
    // Pre-existing strokes passed at creation, keyed by index.
    final ink = widget.args['ink'];
    if (ink is Map) {
      ink.forEach((k, v) {
        final i = int.tryParse('$k');
        if (i != null && v is List) _ink[i] = decodeStrokes(v);
      });
    }
    audienceChannel.setMethodCallHandler(_onPresenterCall);
  }

  @override
  void dispose() {
    audienceChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<dynamic> _onPresenterCall(MethodCall call) async {
    switch (call.method) {
      case 'update':
        final m = Map<String, dynamic>.from(call.arguments as Map);
        if (!mounted) return null;
        // Verwerp verouderde updates: aanroepen komen niet gegarandeerd in
        // volgorde binnen, en bij snel navigeren mag een oudere slide een
        // nieuwere nooit overschrijven.
        final seq = (m['seq'] as num?)?.toInt();
        if (isStaleUpdateSeq(seq, _lastUpdateSeq)) return null;
        if (seq != null) _lastUpdateSeq = seq;
        setState(() {
          _index = (m['index'] as num?)?.toInt() ?? _index;
          _richTextPage = (m['richTextPage'] as num?)?.toInt() ?? 0;
          _timelineStep = (m['timelineStep'] as num?)?.toInt() ?? 0;
          _blank = (m['blank'] as num?)?.toInt() ?? 0;
          _laserPoint = null; // laser never carries over to another slide
          _activeStroke = null; // nor does an in-progress stroke
          // Drop a stale question overlay when moving to a different slide. If a
          // 'question' message for this index already arrived (either order),
          // _questionIndex matches and the overlay is kept.
          if (_questionIndex != _index) _questionView = null;
        });
      case 'question':
        final m = Map<String, dynamic>.from(call.arguments as Map);
        if (!mounted) return null;
        final i = (m['index'] as num?)?.toInt() ?? _index;
        final raw = m['view'];
        setState(() {
          _questionIndex = i;
          _questionView = raw is Map
              ? QuestionView.fromJson(Map<String, dynamic>.from(raw))
              : null;
        });
      case 'ink':
        final m = Map<String, dynamic>.from(call.arguments as Map);
        final i = (m['index'] as num?)?.toInt();
        if (i == null || !mounted) return null;
        setState(
          () => _ink[i] = decodeStrokes((m['strokes'] as List?) ?? const []),
        );
      case 'inkLive':
        final m = Map<String, dynamic>.from(call.arguments as Map);
        final i = (m['index'] as num?)?.toInt();
        final s = m['stroke'];
        if (!mounted) return null;
        setState(() {
          _activeIndex = i;
          _activeStroke = s == null
              ? null
              : InkStroke.fromJson(Map<String, dynamic>.from(s as Map));
        });
      case 'laser':
        final m = Map<String, dynamic>.from(call.arguments as Map);
        final i = (m['index'] as num?)?.toInt();
        final pt = m['point'] as List?;
        if (!mounted) return null;
        setState(() {
          _laserIndex = i;
          _laserPoint = pt == null
              ? null
              : Offset((pt[0] as num).toDouble(), (pt[1] as num).toDouble());
        });
      case 'checklistUpdate':
        final m = Map<String, dynamic>.from(call.arguments as Map);
        final i = (m['slideIndex'] as num?)?.toInt();
        if (i == null || i < 0 || i >= _slides.length || !mounted) return null;
        setState(() {
          _slides[i] = _slides[i].copyWith(
            bullets: List<String>.from(m['bullets'] as List? ?? const []),
            bullets2: List<String>.from(m['bullets2'] as List? ?? const []),
          );
        });
      case 'tableUpdate':
        final m = Map<String, dynamic>.from(call.arguments as Map);
        final i = (m['slideIndex'] as num?)?.toInt();
        if (i == null || i < 0 || i >= _slides.length || !mounted) return null;
        final raw = m['tableRows'] as List?;
        if (raw == null) return null;
        final rows = raw
            .map(
              (row) => List<String>.from(
                (row as List).map((cell) => cell.toString()),
              ),
            )
            .toList();
        setState(() {
          _slides[i] = _slides[i].copyWith(tableRows: rows);
        });
    }
    return null;
  }

  void _send(String method, [Object? arguments]) {
    // Best-effort: the presenter may already be gone.
    presenterChannel.invokeMethod(method, arguments).catchError((_) => null);
  }

  /// Reveal count for a timeline in step mode, mirroring the presenter so the
  /// beamer stays in sync; null when the slide isn't a stepping timeline.
  int? _timelineRevealedFor(Slide slide) {
    if (slide.type != SlideType.timeline ||
        slide.timelineReveal != TimelineReveal.steps) {
      return null;
    }
    final n = parseTimelineEvents(slide.bullets).length;
    if (n <= 0) return 0;
    return (_timelineStep + 1).clamp(1, n);
  }

  /// Cmd+W / Ctrl+W op het beamervenster vraagt de presenter de presentatie af
  /// te sluiten (die ruimt dit venster daarna op). Overige toetsen laten we
  /// door, zodat het beamervenster verder geen sneltoetsen opslokt.
  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    if ((keys.isMetaPressed || keys.isControlPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyW) {
      _send('exit');
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          autofocus: true,
          onKeyEvent: _handleKey,
          child: Stack(children: [_body(), const MermaidRenderHostLayer()]),
        ),
      ),
    );
  }

  Widget _body() {
    if (_slides.isEmpty) return const SizedBox.shrink();
    if (_blank != 0) {
      return Container(color: _blank == 2 ? Colors.white : Colors.black);
    }
    final slide = _slides[_index.clamp(0, _slides.length - 1)];
    return GestureDetector(
      onTap: () => _send('next'),
      onSecondaryTap: () => _send('prev'),
      child: SizedBox.expand(child: _canvas(slide)),
    );
  }

  /// A 16:9 slide letterboxed to fit the screen, mirroring the presenter's view.
  Widget _canvas(Slide slide) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        const ratio = 16.0 / 9.0;
        double slideW, slideH;
        if (w / h > ratio) {
          slideH = h;
          slideW = h * ratio;
        } else {
          slideW = w;
          slideH = w / ratio;
        }
        return Center(
          child: SizedBox(
            width: slideW,
            height: slideH,
            child: Stack(
              fit: StackFit.expand,
              children: [
                SlidePreviewWidget(
                  slide: slide,
                  projectPath: _projectPath,
                  themeProfile: _theme,
                  cockpitColorScheme: _scheme,
                  onLinkTap: openExternalUrl,
                  slideNumber: _index + 1,
                  slideCount: _slides.length,
                  numberStart: numberedListStartFor(_slides, _index),
                  scopeCia: deckScopeCiaIndex(_slides),
                  fitScaleOverride: sharedSplitFitScale(
                    _slides,
                    _index,
                    _theme,
                    _theme.fontFamily,
                  ),
                  richTextPage: _richTextPage,
                  showRichTextPageControls: false,
                  timelineRevealedCount: _timelineRevealedFor(slide),
                  tlp: _tlp,
                  organization: _organization,
                  showClassificationWatermark: _showClassificationWatermark,
                  presentationMode: true,
                  onChecklistItemToggle: (column, itemIndex) =>
                      _send('checklistToggle', {
                        'slideIndex': _index,
                        'column': column,
                        'itemIndex': itemIndex,
                      }),
                  questionView: _questionIndex == _index ? _questionView : null,
                  onAnswerSelected: (i) => _send('answerSelected', {
                    'slideIndex': _index,
                    'optionIndex': i,
                  }),
                  onAnswerSubmit: () =>
                      _send('answerSubmit', {'slideIndex': _index}),
                  enableMedia: true,
                  autoplayMedia: true,
                  allowRemoteMedia: _allowRemoteMedia,
                  // Media finishing on the beamer drives auto-advance.
                  onAudioComplete: () => _send('mediaComplete', {
                    'index': _index,
                    'kind': 'audio',
                  }),
                  onVideoComplete: () => _send('mediaComplete', {
                    'index': _index,
                    'kind': 'video',
                  }),
                ),
                AnnotationLayer(
                  strokes: [
                    ...?_ink[_index],
                    // The live in-progress stroke renders just like a committed
                    // one, so the audience sees the line grow as it's drawn.
                    if (_activeStroke != null && _activeIndex == _index)
                      _activeStroke!,
                  ],
                  interactive: false,
                  laserPoint: _laserIndex == _index ? _laserPoint : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
