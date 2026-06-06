import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/deck.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../services/markdown_service.dart';
import '../../utils/url_launcher_util.dart';
import '../slides/slide_preview.dart';

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
  TlpLevel _tlp = TlpLevel.none;
  String? _projectPath;
  int _index = 0;
  int _blank = 0; // 0 = none, 1 = black, 2 = white

  @override
  void initState() {
    super.initState();
    final markdown = widget.args['markdown'] as String? ?? '';
    _projectPath = widget.args['projectPath'] as String?;
    _index = (widget.args['index'] as num?)?.toInt() ?? 0;
    final deck = MarkdownService().parseDeck(markdown);
    _slides = deck?.slides ?? const [];
    _theme = deck?.themeProfile ?? const ThemeProfile();
    _tlp = deck?.tlp ?? TlpLevel.none;
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
        setState(() {
          _index = (m['index'] as num?)?.toInt() ?? _index;
          _blank = (m['blank'] as num?)?.toInt() ?? 0;
        });
      case 'close':
        try {
          final self = await WindowController.fromCurrentEngine();
          await self.close();
        } catch (_) {}
    }
    return null;
  }

  void _send(String method) {
    // Best-effort: the presenter may already be gone.
    presenterChannel.invokeMethod(method).catchError((_) => null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(backgroundColor: Colors.black, body: _body()),
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
            child: SlidePreviewWidget(
              slide: slide,
              projectPath: _projectPath,
              themeProfile: _theme,
              onLinkTap: openExternalUrl,
              slideNumber: _index + 1,
              slideCount: _slides.length,
              tlp: _tlp,
              enableMedia: true,
              autoplayMedia: true,
              // Audio finishing on the beamer drives the presenter's auto-advance.
              onAudioComplete: () => _send('audioComplete'),
            ),
          ),
        );
      },
    );
  }
}
