import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';
import '../../models/annotation.dart';
import '../../models/deck.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../services/markdown_service.dart';
import '../../services/rehearsal_controller.dart';
import '../../utils/log.dart';
import '../../utils/url_launcher_util.dart';
import '../../l10n/app_localizations.dart';
import '../slides/inline_markdown.dart';
import '../slides/slide_preview.dart';
import 'annotation_overlay.dart';
import 'audience_window.dart';
import 'rehearsal_summary.dart';

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

/// Blanco-schermstand tijdens het presenteren (zoals B/W in PowerPoint).
enum _Blank { none, black, white }

class FullscreenPresenter extends StatefulWidget {
  final List<Slide> slides;
  final String? projectPath;
  final ThemeProfile themeProfile;
  final int initialIndex;
  final TlpLevel tlp;

  /// Optionele doeltijd voor de aftelling/oefenklok. Null = geen aftelling.
  /// Sessie-only; live aanpasbaar in de presenter (toets K).
  final Duration? targetDuration;

  /// When set, this presenter drives a separate audience (beamer) window: the
  /// laptop shows the presenter view, the slide goes to [audience]. Null
  /// for the classic single-screen mode.
  final AudienceWindowHandle? audience;

  /// Annotation layer keyed by [Slide.id], and a callback to persist changes
  /// made while presenting back to the deck.
  final Map<String, List<InkStroke>> initialAnnotations;
  final void Function(Map<String, List<InkStroke>>)? onAnnotationsChanged;
  final ValueChanged<Slide>? onSlideChanged;

  const FullscreenPresenter({
    super.key,
    required this.slides,
    required this.projectPath,
    required this.themeProfile,
    required this.initialIndex,
    this.tlp = TlpLevel.none,
    this.targetDuration,
    this.audience,
    this.initialAnnotations = const {},
    this.onAnnotationsChanged,
    this.onSlideChanged,
  });

  /// Entry point used by the app: pick dual-screen mode when a second display is
  /// available on desktop, otherwise the single-window presenter. Any failure
  /// to open the second window falls back to single-window mode.
  static Future<void> present(
    BuildContext context, {
    required List<Slide> slides,
    required String? projectPath,
    required ThemeProfile themeProfile,
    required int initialIndex,
    TlpLevel tlp = TlpLevel.none,
    Duration? targetDuration,
    Map<String, List<InkStroke>> annotations = const {},
    void Function(Map<String, List<InkStroke>>)? onAnnotationsChanged,
    ValueChanged<Slide>? onSlideChanged,
  }) async {
    var displayCount = 0;
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      try {
        final displays = await screenRetriever.getAllDisplays();
        displayCount = displays.length;
      } catch (e) {
        logWarning('FullscreenPresenter.present: display detection failed', e);
        displayCount = 0;
      }
    }
    final dual = shouldUseDualScreen(
      isMacOS: Platform.isMacOS,
      isWindows: Platform.isWindows,
      isLinux: Platform.isLinux,
      displayCount: displayCount,
    );
    if (!context.mounted) return;
    if (dual) {
      await showDualScreen(
        context,
        slides: slides,
        projectPath: projectPath,
        themeProfile: themeProfile,
        initialIndex: initialIndex,
        tlp: tlp,
        targetDuration: targetDuration,
        annotations: annotations,
        onAnnotationsChanged: onAnnotationsChanged,
        onSlideChanged: onSlideChanged,
      );
    } else {
      await show(
        context,
        slides: slides,
        projectPath: projectPath,
        themeProfile: themeProfile,
        initialIndex: initialIndex,
        tlp: tlp,
        targetDuration: targetDuration,
        annotations: annotations,
        onAnnotationsChanged: onAnnotationsChanged,
        onSlideChanged: onSlideChanged,
      );
    }
  }

  static Future<void> show(
    BuildContext context, {
    required List<Slide> slides,
    required String? projectPath,
    required ThemeProfile themeProfile,
    required int initialIndex,
    TlpLevel tlp = TlpLevel.none,
    Duration? targetDuration,
    Map<String, List<InkStroke>> annotations = const {},
    void Function(Map<String, List<InkStroke>>)? onAnnotationsChanged,
    ValueChanged<Slide>? onSlideChanged,
  }) async {
    final hadWakeLock = await _wakeLockEnabled();
    await _enableWakeLock();
    try {
      await windowManager.setFullScreen(true);
      if (context.mounted) {
        await Navigator.push(
          context,
          PageRouteBuilder(
            opaque: true,
            pageBuilder: (context, anim, anim2) => FullscreenPresenter(
              slides: slides,
              projectPath: projectPath,
              themeProfile: themeProfile,
              initialIndex: initialIndex,
              tlp: tlp,
              targetDuration: targetDuration,
              initialAnnotations: annotations,
              onAnnotationsChanged: onAnnotationsChanged,
              onSlideChanged: onSlideChanged,
            ),
            transitionsBuilder: (context, animation, secondary, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 200),
          ),
        );
      }
    } finally {
      await _restoreWakeLock(hadWakeLock);
    }
  }

  /// Dual-screen mode: open a borderless audience window on the beamer showing
  /// the slide, and run the presenter view (current/next/notes/timer) in the
  /// main window on the laptop. The two windows stay in sync over method
  /// channels. Falls back to [show] if the second window can't be created.
  static Future<void> showDualScreen(
    BuildContext context, {
    required List<Slide> slides,
    required String? projectPath,
    required ThemeProfile themeProfile,
    required int initialIndex,
    TlpLevel tlp = TlpLevel.none,
    Duration? targetDuration,
    Map<String, List<InkStroke>> annotations = const {},
    void Function(Map<String, List<InkStroke>>)? onAnnotationsChanged,
    ValueChanged<Slide>? onSlideChanged,
  }) async {
    // A self-contained markdown deck is the payload for the audience window; it
    // carries the slides, the style profile and the TLP level in one string.
    // This payload never touches disk, so it inlines the style profile — the
    // beamer has no other way to learn the deck's styling.
    final markdown = MarkdownService().generateDeck(
      Deck(
        title: 'Presentatie',
        slides: slides,
        projectPath: projectPath,
        themeProfile: themeProfile,
        tlp: tlp,
      ),
      inlineStyleProfile: true,
    );
    // Pre-existing annotations re-keyed by index so the beamer shows them
    // immediately (the audience window has no stable slide ids of its own).
    final inkByIndex = <String, dynamic>{};
    for (var i = 0; i < slides.length; i++) {
      final strokes = annotations[slides[i].id];
      if (strokes != null && strokes.isNotEmpty) {
        inkByIndex['$i'] = encodeStrokes(strokes);
      }
    }
    final argument = jsonEncode({
      'markdown': markdown,
      'projectPath': projectPath,
      'index': initialIndex,
      'ink': inkByIndex,
    });

    WindowController? audience;
    AudienceWindowHandle? audienceHandle;
    try {
      audience = await WindowController.create(
        WindowConfiguration(arguments: argument, hiddenAtLaunch: true),
      );
      audienceHandle = AudienceWindowHandle(audience);
      await audience.show();
      await audience.coverScreen(external: true);
    } catch (e) {
      logError(
        'FullscreenPresenter.showDualScreen: audience window setup failed',
        e,
      );
      if (audienceHandle != null) {
        await audienceHandle.close();
      }
      audience = null;
      audienceHandle = null;
    }

    if (audience == null || audienceHandle == null) {
      if (context.mounted) {
        await show(
          context,
          slides: slides,
          projectPath: projectPath,
          themeProfile: themeProfile,
          initialIndex: initialIndex,
          tlp: tlp,
          annotations: annotations,
          onAnnotationsChanged: onAnnotationsChanged,
          onSlideChanged: onSlideChanged,
        );
      }
      return;
    }

    final hadWakeLock = await _wakeLockEnabled();
    await _enableWakeLock();
    try {
      if (context.mounted) {
        await Navigator.push(
          context,
          PageRouteBuilder(
            opaque: true,
            pageBuilder: (context, anim, anim2) => FullscreenPresenter(
              slides: slides,
              projectPath: projectPath,
              themeProfile: themeProfile,
              initialIndex: initialIndex,
              tlp: tlp,
              audience: audienceHandle,
              initialAnnotations: annotations,
              onAnnotationsChanged: onAnnotationsChanged,
              onSlideChanged: onSlideChanged,
            ),
            transitionsBuilder: (context, animation, secondary, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 200),
          ),
        );
      }
    } finally {
      await _restoreWakeLock(hadWakeLock);
      // Make sure the audience window is gone even if exit didn't close it.
      await audienceHandle.close();
    }
  }

  @override
  State<FullscreenPresenter> createState() => _FullscreenPresenterState();
}

@visibleForTesting
bool shouldUseDualScreen({
  required bool isMacOS,
  required bool isWindows,
  required bool isLinux,
  required int displayCount,
}) {
  return (isMacOS || isWindows || isLinux) && displayCount >= 2;
}

@visibleForTesting
bool autoAdvanceWaitsForMedia(Slide slide) {
  final autoplayVideo =
      slide.type == SlideType.video &&
      slide.videoPath.isNotEmpty &&
      slide.videoAutoplay;
  final autoplayAudio = slide.audioPath.isNotEmpty && slide.audioAutoplay;
  return autoplayVideo || autoplayAudio;
}

Future<bool> _wakeLockEnabled() async {
  try {
    return await WakelockPlus.enabled;
  } catch (e) {
    logWarning('fullscreen_presenter._wakeLockEnabled: query failed', e);
    return false;
  }
}

Future<void> _enableWakeLock() async {
  try {
    await WakelockPlus.enable();
  } catch (e) {
    logWarning('fullscreen_presenter._enableWakeLock: enable failed', e);
    // Best-effort: unsupported platforms should not interrupt presenting.
  }
}

Future<void> _restoreWakeLock(bool enabledBeforePresentation) async {
  try {
    if (enabledBeforePresentation) {
      await WakelockPlus.enable();
    } else {
      await WakelockPlus.disable();
    }
  } catch (e) {
    logWarning('fullscreen_presenter._restoreWakeLock: restore failed', e);
    // Best-effort cleanup.
  }
}

class _FullscreenPresenterState extends State<FullscreenPresenter> {
  late int _index;
  late FocusNode _focusNode;
  Timer? _advanceTimer;
  Timer? _clockTimer;
  double _progress = 0; // 0..1 voor de voortgangsbalk

  /// Presenter view (notities, klok, volgende slide) vs. publieksweergave.
  bool _presenterView = false;

  /// Blanco scherm (zwart/wit) tijdens het presenteren.
  _Blank _blank = _Blank.none;

  /// Rasteroverzicht van alle slides om snel te springen.
  bool _gridOpen = false;

  /// Gemarkeerde positie in het raster (los van de getoonde slide) plus de
  /// huidige kolom-/rijmaat, nodig om met de pijltjes te navigeren en mee te
  /// scrollen.
  int _gridCursor = 0;
  int _gridCols = 3;
  double _gridRowExtent = 220;
  final ScrollController _gridScroll = ScrollController();

  /// Oefenklok: verstreken tijd, aftelling en per-slide-tijd. Sessie-only,
  /// puur meten (geen pacing). Resetbaar met R.
  late RehearsalController _rehearsal;

  /// Getypte cijfers om naar een slidenummer te springen (leeg = niet actief).
  String _typed = '';
  Timer? _typedTimer;

  /// Doeltijd-invoermodus (toets K): cijfers worden als MMSS gelezen i.p.v. als
  /// slidenummer. [_targetTyped] houdt de invoer tot Enter/Esc.
  bool _targetInput = false;
  String _targetTyped = '';

  /// Sneltoets-overzicht (cheatsheet) zichtbaar.
  bool _helpOpen = false;

  /// Automatische modus: slides wisselen vanzelf (op tijd of na audio). Staat
  /// standaard aan zodat ingestelde tijdwissels meteen werken; met A te pauzeren.
  bool _autoPlay = true;

  /// Herhaling: na de laatste slide terug naar de eerste (anders blijft de
  /// laatste slide staan). Met L te wisselen.
  bool _loop = false;

  /// Wissel ná het afspelen van autoplay-media i.p.v. op de tijdwissel.
  /// Met M te wisselen.
  bool _advanceOnMediaEnd = true;

  /// Known displays for moving the fullscreen presentation window. This is not
  /// a second presenter window; it keeps the current output movable between
  /// screens with S or the presenter-view button.
  List<Display> _displays = const [];
  int _displayIndex = 0;

  /// True when this presenter drives a separate audience (beamer) window.
  bool get _dual => widget.audience != null;

  /// Last (index, blank) pushed to the audience window, to avoid redundant sends.
  int? _lastSentIndex;
  int? _lastSentBlank;

  // ── Annotatielaag ─────────────────────────────────────────────────────────
  /// Strokes per slide, keyed by [Slide.id] (stable within the session).
  late Map<String, List<InkStroke>> _ink;

  /// Active annotation tool, or null when annotation is off.
  InkTool? _tool;
  int _inkColor = 0xFFEF4444; // rood
  static const _penWidth = 0.004;
  static const _highlighterWidth = 0.022;
  DateTime _lastLaserSent = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastInkLiveSent = DateTime.fromMillisecondsSinceEpoch(0);

  double get _toolWidth =>
      _tool == InkTool.highlighter ? _highlighterWidth : _penWidth;

  List<InkStroke> get _currentStrokes {
    final id = widget.slides[_index.clamp(0, widget.slides.length - 1)].id;
    return _ink[id] ?? const [];
  }

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _rehearsal = RehearsalController(target: widget.targetDuration);
    _focusNode = FocusNode();
    _ink = {
      for (final e in widget.initialAnnotations.entries)
        e.key: List<InkStroke>.from(e.value),
    };
    if (_dual) {
      // The laptop shows the presenter view; the slide lives on the beamer.
      _presenterView = true;
      // Navigation triggered on the beamer (clicks) and its audio-end events
      // come back over this channel.
      presenterChannel.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'next':
            _next();
          case 'prev':
            _prev();
          case 'exit':
            _exit();
          case 'audioComplete':
            _onMediaCompleted(kind: 'audio');
          case 'mediaComplete':
            final args = Map<String, dynamic>.from(call.arguments as Map);
            _onMediaCompleted(
              index: (args['index'] as num?)?.toInt(),
              kind: args['kind']?.toString(),
            );
          case 'checklistToggle':
            final args = Map<String, dynamic>.from(call.arguments as Map);
            _toggleChecklistItem(
              slideIndex: (args['slideIndex'] as num?)?.toInt() ?? _index,
              column: (args['column'] as num?)?.toInt() ?? 0,
              itemIndex: (args['itemIndex'] as num?)?.toInt() ?? 0,
            );
        }
        return null;
      });
    }
    // Tik elke seconde, maar herbouw alleen in presenter view (klok/teller).
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _presenterView) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _loadDisplays();
      _scheduleAdvance();
    });
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _clockTimer?.cancel();
    _typedTimer?.cancel();
    _gridScroll.dispose();
    _focusNode.dispose();
    if (_dual) presenterChannel.setMethodCallHandler(null);
    super.dispose();
  }

  int get _blankCode =>
      _blank == _Blank.white ? 2 : (_blank == _Blank.black ? 1 : 0);

  /// Mirror the current index/blank state to the audience window when it changed.
  void _syncAudience() {
    final aw = widget.audience?.controller;
    if (aw == null) return;
    final blank = _blankCode;
    if (_index == _lastSentIndex && blank == _lastSentBlank) return;
    final indexChanged = _index != _lastSentIndex;
    _lastSentIndex = _index;
    _lastSentBlank = blank;
    audienceChannel
        .invokeMethod('update', {'index': _index, 'blank': blank})
        .catchError((_) => null);
    // On a slide change, push that slide's strokes so saved/earlier ink shows.
    if (indexChanged) _pushInk();
  }

  void _toggleChecklistItem({
    required int slideIndex,
    required int column,
    required int itemIndex,
  }) {
    if (slideIndex < 0 || slideIndex >= widget.slides.length) return;
    final slide = widget.slides[slideIndex];
    final source = column == 1 ? slide.bullets2 : slide.bullets;
    if (itemIndex < 0 || itemIndex >= source.length) return;
    final updatedItems = List<String>.from(source);
    final item = updatedItems[itemIndex];
    updatedItems[itemIndex] = checklistBullet(
      level: bulletLevel(item),
      text: checklistItemText(item),
      checked: !checklistItemChecked(item),
    );
    final updated = column == 1
        ? slide.copyWith(bullets2: updatedItems)
        : slide.copyWith(bullets: updatedItems);
    setState(() => widget.slides[slideIndex] = updated);
    widget.onSlideChanged?.call(updated);
    if (_dual) {
      audienceChannel
          .invokeMethod('checklistUpdate', {
            'slideIndex': slideIndex,
            'bullets': updated.bullets,
            'bullets2': updated.bullets2,
          })
          .catchError((_) => null);
    }
  }

  // ── Annotatielaag ─────────────────────────────────────────────────────────

  /// Send the current slide's strokes to the beamer (keyed by index there).
  void _pushInk() {
    if (widget.audience == null) return;
    audienceChannel
        .invokeMethod('ink', {
          'index': _index,
          'strokes': encodeStrokes(_currentStrokes),
        })
        .catchError((_) => null);
  }

  void _onStrokesChanged(List<InkStroke> strokes) {
    final id = widget.slides[_index.clamp(0, widget.slides.length - 1)].id;
    setState(() {
      if (strokes.isEmpty) {
        _ink.remove(id);
      } else {
        _ink[id] = strokes;
      }
    });
    widget.onAnnotationsChanged?.call(_ink);
    _pushInk();
  }

  void _onLaserMove(Offset? point) {
    if (widget.audience == null) return;
    final now = DateTime.now();
    // Throttle to keep the channel calm; always send the "gone" (null) event.
    if (point != null &&
        now.difference(_lastLaserSent) < const Duration(milliseconds: 33)) {
      return;
    }
    _lastLaserSent = now;
    audienceChannel
        .invokeMethod('laser', {
          'index': _index,
          'point': point == null ? null : [point.dx, point.dy],
        })
        .catchError((_) => null);
  }

  /// Mirror the stroke that is being drawn right now to the beamer, so the
  /// audience sees a pen/highlighter line appear live instead of only after the
  /// pen lifts. The committed stroke still follows over the 'ink' channel; this
  /// just keeps the in-progress preview in sync for the same slide.
  void _onActiveStroke(InkStroke? stroke) {
    if (widget.audience == null) return;
    final now = DateTime.now();
    // Throttle growth events; always send the "done" (null) event so the
    // beamer drops its live preview the moment the stroke commits.
    if (stroke != null &&
        now.difference(_lastInkLiveSent) < const Duration(milliseconds: 33)) {
      return;
    }
    _lastInkLiveSent = now;
    audienceChannel
        .invokeMethod('inkLive', {'index': _index, 'stroke': stroke?.toJson()})
        .catchError((_) => null);
  }

  /// Select a tool, or toggle it off when it is already active.
  void _setTool(InkTool tool) {
    setState(() => _tool = _tool == tool ? null : tool);
    if (_tool != InkTool.laser) _onLaserMove(null); // hide laser on tool switch
  }

  void _clearCurrentInk() {
    final id = widget.slides[_index.clamp(0, widget.slides.length - 1)].id;
    if (!_ink.containsKey(id)) return;
    setState(() => _ink.remove(id));
    widget.onAnnotationsChanged?.call(_ink);
    _pushInk();
  }

  /// Decode the current slide's images plus its neighbours into the image cache
  /// ahead of time. Because a precached [FileImage] resolves synchronously, the
  /// next slide paints its picture on the very first frame instead of flashing
  /// the black Scaffold behind it while the file decodes — essential for a clean
  /// recording. Best-effort: decode errors are swallowed.
  void _precacheNeighbours() {
    if (!mounted) return;
    final logo = widget.themeProfile.logoPath;
    if (logo != null && logo.isNotEmpty) {
      _precachePath(logo);
    }
    // Current first, then the likely next/previous targets.
    for (final offset in const [0, 1, -1, 2]) {
      final i = _index + offset;
      if (i < 0 || i >= widget.slides.length) continue;
      final slide = widget.slides[i];
      _precachePath(slide.imagePath);
      _precachePath(slide.imagePath2);
    }
  }

  void _precachePath(String path) {
    final resolved = resolveSlideAssetPath(path, widget.projectPath);
    if (resolved == null) return;
    precacheImage(FileImage(File(resolved)), context, onError: (_, _) {});
  }

  void _scheduleAdvance() {
    // Funnel point for every navigation (next/prev/jump/auto) and the initial
    // frame, so neighbour images are always warm before they are shown.
    _precacheNeighbours();
    _advanceTimer?.cancel();
    _advanceTimer = null;
    setState(() => _progress = 0);

    // Auto-modus uit: nooit vanzelf wisselen.
    if (!_autoPlay) return;

    final slide = widget.slides[_index.clamp(0, widget.slides.length - 1)];

    if (_advanceOnMediaEnd && autoAdvanceWaitsForMedia(slide)) return;

    final dur = slide.advanceDuration;
    if (dur <= 0) return;
    // Op de laatste slide alleen doortikken als we herhalen.
    if (_index >= widget.slides.length - 1 && !_loop) return;

    final totalMs = (dur * 1000).round();
    final startTime = DateTime.now();

    // Tick elke 50ms voor een vloeiende voortgangsbalk
    _advanceTimer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      final p = (elapsed / totalMs).clamp(0.0, 1.0);
      setState(() => _progress = p);
      if (elapsed >= totalMs) {
        t.cancel();
        _autoAdvance();
      }
    });
  }

  /// Automatisch doorschakelen (tijd of media-einde): naar de volgende slide,
  /// of bij herhaling vanaf de laatste terug naar de eerste. Zonder herhaling
  /// blijft de laatste slide gewoon staan.
  void _autoAdvance() {
    if (_blank != _Blank.none) return;
    if (_index < widget.slides.length - 1) {
      setState(() => _index++);
      _scheduleAdvance();
    } else if (_loop) {
      setState(() => _index = 0);
      _scheduleAdvance();
    }
  }

  void _onMediaCompleted({int? index, String? kind}) {
    if (index != null && index != _index) return;
    final slide = widget.slides[_index.clamp(0, widget.slides.length - 1)];
    // A video is primary on a video slide. Ignore an attached audio track that
    // happens to finish earlier.
    if (kind == 'audio' &&
        slide.type == SlideType.video &&
        slide.videoPath.isNotEmpty &&
        slide.videoAutoplay) {
      return;
    }
    if (_autoPlay && _advanceOnMediaEnd && autoAdvanceWaitsForMedia(slide)) {
      _autoAdvance();
    }
  }

  void _toggleAutoPlay() {
    setState(() => _autoPlay = !_autoPlay);
    _scheduleAdvance();
  }

  void _toggleLoop() {
    setState(() => _loop = !_loop);
    _scheduleAdvance();
  }

  void _toggleMediaAdvance() {
    setState(() => _advanceOnMediaEnd = !_advanceOnMediaEnd);
    _scheduleAdvance();
  }

  Future<void> _loadDisplays() async {
    try {
      final displays = await screenRetriever.getAllDisplays();
      if (!mounted || displays.isEmpty) return;
      final bounds = await windowManager.getBounds();
      final center = bounds.center;
      final current = displays.indexWhere((d) {
        final p = d.visiblePosition ?? Offset.zero;
        final s = d.visibleSize ?? d.size;
        return Rect.fromLTWH(p.dx, p.dy, s.width, s.height).contains(center);
      });
      setState(() {
        _displays = displays;
        _displayIndex = current < 0 ? 0 : current;
      });
    } catch (e) {
      logWarning(
        '_FullscreenPresenterState._loadDisplays: screen detection failed',
        e,
      );
      // Screen detection is best-effort; presenting should still work.
    }
  }

  Future<void> _moveToDisplay(int index) async {
    if (_displays.length < 2) return;
    final display = _displays[index.clamp(0, _displays.length - 1)];
    final position = display.visiblePosition ?? Offset.zero;
    final size = display.visibleSize ?? display.size;
    try {
      await windowManager.setFullScreen(false);
      await windowManager.setBounds(
        Rect.fromLTWH(position.dx, position.dy, size.width, size.height),
      );
      await windowManager.setFullScreen(true);
      if (mounted) setState(() => _displayIndex = index);
    } catch (e) {
      logError(
        '_FullscreenPresenterState._moveToDisplay: moving window to display failed',
        e,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.d('Kon niet van scherm wisselen.')),
          ),
        );
      }
    }
  }

  Future<void> _cycleDisplay() async {
    if (_displays.isEmpty) await _loadDisplays();
    if (_displays.length < 2) return;
    await _moveToDisplay((_displayIndex + 1) % _displays.length);
  }

  Future<void> _exit() async {
    _advanceTimer?.cancel();
    await _maybeShowRehearsalSummary();
    final aw = widget.audience;
    if (aw != null) {
      // Dual mode: the main window was never put in full screen; just tear down
      // the audience window (once — double-close crashes the Linux embedder).
      await aw.close();
    } else {
      await windowManager.setFullScreen(false);
    }
    if (mounted) Navigator.pop(context);
  }

  /// Toon na afloop de oefenrun-samenvatting, mits er genoeg gemeten is.
  /// Sessie-only: niets wordt opgeslagen.
  Future<void> _maybeShowRehearsalSummary() async {
    if (!mounted || !_rehearsal.hasMeaningfulData) return;
    final run = _rehearsal.finish();
    await showRehearsalSummary(context, run: run, slides: widget.slides);
  }

  /// Meld de slidewissel aan schermlezers (WCAG 4.1.3, statusberichten):
  /// visueel verandert de hele slide, maar zonder aankondiging merkt een
  /// schermlezer-gebruiker de wissel niet op.
  void _announceSlide() {
    final total = widget.slides.length;
    if (total == 0 || !mounted) return;
    final slide = widget.slides[_index.clamp(0, total - 1)];
    final title = stripInlineMarkdown(slide.title).trim();
    SemanticsService.sendAnnouncement(
      View.of(context),
      '${context.l10n.d('Slide')} ${_index + 1}/$total'
      '${title.isEmpty ? '' : ': $title'}',
      TextDirection.ltr,
    );
  }

  void _next() {
    // Eerste toets/klik op een blanco scherm haalt het scherm terug.
    if (_blank != _Blank.none) {
      setState(() => _blank = _Blank.none);
      return;
    }
    if (_index < widget.slides.length - 1) {
      setState(() => _index++);
      _scheduleAdvance();
      _announceSlide();
    }
  }

  void _prev() {
    if (_blank != _Blank.none) {
      setState(() => _blank = _Blank.none);
      return;
    }
    if (_index > 0) {
      setState(() => _index--);
      _scheduleAdvance();
      _announceSlide();
    }
  }

  void _togglePresenterView() {
    setState(() => _presenterView = !_presenterView);
  }

  void _resetTimer() {
    setState(() => _rehearsal.reset());
  }

  /// Open de doeltijd-invoer (toets K): cijfers worden voortaan als MMSS
  /// gelezen. Een lege invoer laat de huidige doeltijd ongemoeid.
  void _beginTargetInput() {
    _clearTyped();
    setState(() {
      _targetInput = true;
      _targetTyped = '';
    });
  }

  void _cancelTargetInput() {
    setState(() {
      _targetInput = false;
      _targetTyped = '';
    });
  }

  /// Lees [_targetTyped] als MMSS en zet de doeltijd. Leeg = ongewijzigd,
  /// nul = aftelling uit.
  void _commitTarget() {
    final raw = _targetTyped;
    setState(() {
      _targetInput = false;
      _targetTyped = '';
    });
    if (raw.isEmpty) return;
    final n = int.tryParse(raw) ?? 0;
    final secs = (n ~/ 100) * 60 + (n % 100);
    setState(
      () => _rehearsal.target = secs <= 0 ? null : Duration(seconds: secs),
    );
  }

  void _toggleHelp() {
    setState(() => _helpOpen = !_helpOpen);
  }

  /// Cijfer (gewoon of numpad) → karakter, of null bij andere toetsen.
  static final Map<LogicalKeyboardKey, String> _digits = {
    LogicalKeyboardKey.digit0: '0',
    LogicalKeyboardKey.digit1: '1',
    LogicalKeyboardKey.digit2: '2',
    LogicalKeyboardKey.digit3: '3',
    LogicalKeyboardKey.digit4: '4',
    LogicalKeyboardKey.digit5: '5',
    LogicalKeyboardKey.digit6: '6',
    LogicalKeyboardKey.digit7: '7',
    LogicalKeyboardKey.digit8: '8',
    LogicalKeyboardKey.digit9: '9',
    LogicalKeyboardKey.numpad0: '0',
    LogicalKeyboardKey.numpad1: '1',
    LogicalKeyboardKey.numpad2: '2',
    LogicalKeyboardKey.numpad3: '3',
    LogicalKeyboardKey.numpad4: '4',
    LogicalKeyboardKey.numpad5: '5',
    LogicalKeyboardKey.numpad6: '6',
    LogicalKeyboardKey.numpad7: '7',
    LogicalKeyboardKey.numpad8: '8',
    LogicalKeyboardKey.numpad9: '9',
  };

  void _appendDigit(String d) {
    setState(() {
      _typed += d;
      if (_typed.length > 4) _typed = _typed.substring(_typed.length - 4);
    });
    _typedTimer?.cancel();
    _typedTimer = Timer(const Duration(milliseconds: 2500), _clearTyped);
  }

  void _clearTyped() {
    _typedTimer?.cancel();
    _typedTimer = null;
    if (_typed.isNotEmpty) setState(() => _typed = '');
  }

  /// Spring naar het getypte slidenummer (1-gebaseerd) en wis de invoer.
  void _commitTyped() {
    final n = int.tryParse(_typed);
    _clearTyped();
    if (n != null) _goTo(n - 1);
  }

  /// Zet het scherm op zwart/wit, of terug naar de slide bij dezelfde toets.
  void _toggleBlank(_Blank target) {
    setState(() {
      _blank = _blank == target ? _Blank.none : target;
      if (_blank != _Blank.none) _gridOpen = false;
    });
  }

  void _toggleGrid() {
    setState(() {
      _gridOpen = !_gridOpen;
      if (_gridOpen) {
        _blank = _Blank.none;
        _gridCursor = _index;
      }
    });
    if (_gridOpen) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollGridToCursor(),
      );
    }
  }

  /// Spring direct naar een slide (vanuit het rasteroverzicht).
  void _jumpTo(int index) {
    setState(() {
      _index = index.clamp(0, widget.slides.length - 1);
      _blank = _Blank.none;
      _gridOpen = false;
    });
    _scheduleAdvance();
    _announceSlide();
  }

  /// Ga rechtstreeks naar slide [index] zonder het raster te openen (Home/End).
  void _goTo(int index) {
    if (_blank != _Blank.none) {
      setState(() => _blank = _Blank.none);
      return;
    }
    final target = index.clamp(0, widget.slides.length - 1);
    if (target == _index) return;
    setState(() => _index = target);
    _scheduleAdvance();
    _announceSlide();
  }

  /// Verplaats de rastercursor en houd 'm in beeld.
  void _moveGridCursor(int delta) {
    setState(() {
      _gridCursor = (_gridCursor + delta).clamp(0, widget.slides.length - 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollGridToCursor());
  }

  void _setGridCursor(int index) {
    setState(() {
      _gridCursor = index.clamp(0, widget.slides.length - 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollGridToCursor());
  }

  /// Scroll het raster zo dat de cursorrij zichtbaar is (met wat context).
  void _scrollGridToCursor() {
    if (!_gridScroll.hasClients) return;
    final row = _gridCols == 0 ? 0 : _gridCursor ~/ _gridCols;
    final target = (row - 1) * _gridRowExtent; // één rij context erboven
    final max = _gridScroll.position.maxScrollExtent;
    _gridScroll.animateTo(
      target.clamp(0.0, max),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    // Sneltoets-overzicht vangt alles: sluiten met ? / H / Esc.
    if (_helpOpen) {
      if (key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.keyH ||
          key == LogicalKeyboardKey.question) {
        setState(() => _helpOpen = false);
      }
      return KeyEventResult.handled;
    }

    // Doeltijd-invoer vangt cijfers/Enter/Esc tot de invoer klaar is.
    if (_targetInput) return _handleTargetKey(key);

    // Terwijl het raster open is, sturen de pijltjes een aparte cursor aan.
    if (_gridOpen) return _handleGridKey(key);

    // Cijfers verzamelen om naar een slidenummer te springen.
    final digit = _digits[key];
    if (digit != null) {
      _appendDigit(digit);
      return KeyEventResult.handled;
    }

    final last = widget.slides.length - 1;
    switch (key) {
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        // Met een getypt nummer: springen; anders gewoon door.
        if (_typed.isNotEmpty) {
          _commitTyped();
        } else {
          _next();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.backspace:
        if (_typed.isNotEmpty) {
          setState(() => _typed = _typed.substring(0, _typed.length - 1));
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyH:
      case LogicalKeyboardKey.question:
        _toggleHelp();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.pageDown:
        _next();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.pageUp:
        _prev();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        _goTo(0);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        _goTo(last);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyP:
        _togglePresenterView();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyR:
        _resetTimer();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyK:
        _beginTargetInput();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyB:
        _toggleBlank(_Blank.black);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyW:
        _toggleBlank(_Blank.white);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyG:
        _toggleGrid();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyA:
        _toggleAutoPlay();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyL:
        _toggleLoop();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyM:
        _toggleMediaAdvance();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyS:
        _cycleDisplay();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyD:
        _setTool(InkTool.pen);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyT:
        _setTool(InkTool.highlighter);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyE:
        _setTool(InkTool.eraser);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyX:
        _setTool(InkTool.laser);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyC:
        _clearCurrentInk();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        // Gelaagd: gereedschap weg, getypt nummer wissen, blanco scherm, afsluiten.
        if (_tool != null) {
          setState(() => _tool = null);
          _onLaserMove(null);
        } else if (_typed.isNotEmpty) {
          _clearTyped();
        } else if (_blank != _Blank.none) {
          setState(() => _blank = _Blank.none);
        } else {
          _exit();
        }
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  /// Toetsen terwijl de doeltijd wordt ingevoerd (MMSS). Alles wordt
  /// opgeslokt zodat losse cijfers niet als slidesprong gelden.
  KeyEventResult _handleTargetKey(LogicalKeyboardKey key) {
    final digit = _digits[key];
    if (digit != null) {
      setState(() {
        _targetTyped += digit;
        if (_targetTyped.length > 4) {
          _targetTyped = _targetTyped.substring(_targetTyped.length - 4);
        }
      });
      return KeyEventResult.handled;
    }
    switch (key) {
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
      case LogicalKeyboardKey.keyK:
        _commitTarget();
      case LogicalKeyboardKey.backspace:
        if (_targetTyped.isNotEmpty) {
          setState(
            () => _targetTyped = _targetTyped.substring(
              0,
              _targetTyped.length - 1,
            ),
          );
        }
      case LogicalKeyboardKey.escape:
        _cancelTargetInput();
      default:
        break;
    }
    return KeyEventResult.handled;
  }

  /// Toetsen terwijl het rasteroverzicht open is.
  KeyEventResult _handleGridKey(LogicalKeyboardKey key) {
    final last = widget.slides.length - 1;
    switch (key) {
      case LogicalKeyboardKey.arrowRight:
        _moveGridCursor(1);
      case LogicalKeyboardKey.arrowLeft:
        _moveGridCursor(-1);
      case LogicalKeyboardKey.arrowDown:
        _moveGridCursor(_gridCols);
      case LogicalKeyboardKey.arrowUp:
        _moveGridCursor(-_gridCols);
      case LogicalKeyboardKey.home:
        _setGridCursor(0);
      case LogicalKeyboardKey.end:
        _setGridCursor(last);
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
      case LogicalKeyboardKey.space:
        _jumpTo(_gridCursor);
      case LogicalKeyboardKey.keyG:
      case LogicalKeyboardKey.escape:
        setState(() => _gridOpen = false);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ── Formatters ─────────────────────────────────────────────────────────────

  String _fmtClock(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _fmtElapsed(Duration d) {
    final mm = (d.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$mm:$ss' : '$mm:$ss';
  }

  /// Resterende tijd, met minteken zodra je over de doeltijd gaat.
  String _fmtRemaining(Duration d) {
    final body = _fmtElapsed(d.abs());
    return d.isNegative ? '-$body' : body;
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.slides.length;
    if (total == 0) {
      _exit();
      return const SizedBox.shrink();
    }

    // Keep the beamer window in step with whatever index/blank we now show.
    _syncAudience();

    // Per-slide-timing: registreer de huidige slide. Idempotent en goedkoop,
    // dus veilig om elke build aan te roepen — vangt álle navigatiepaden.
    final clampedIndex = _index.clamp(0, total - 1);
    _rehearsal.observe(widget.slides[clampedIndex].id, clampedIndex);

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            _presenterView
                ? _buildPresenterView(context)
                : _buildAudienceView(context),
            if (_gridOpen) Positioned.fill(child: _buildGridOverlay()),
            if (_tool != null && !_gridOpen && !_helpOpen)
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Center(child: _buildAnnotationToolbar()),
              ),
            if (_typed.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 60,
                child: Center(child: _buildTypedBadge(total)),
              ),
            if (_targetInput)
              Positioned(
                left: 0,
                right: 0,
                bottom: 60,
                child: Center(child: _buildTargetBadge()),
              ),
            if (_helpOpen) Positioned.fill(child: _buildHelpOverlay()),
          ],
        ),
      ),
    );
  }

  /// Zwevende balk met annotatiegereedschap, kleuren en wissen.
  Widget _buildAnnotationToolbar() {
    const palette = [
      0xFFEF4444, // rood
      0xFFF59E0B, // amber
      0xFF22C55E, // groen
      0xFF3B82F6, // blauw
      0xFFFFFFFF, // wit
      0xFF111111, // zwart
    ];
    Widget toolBtn(InkTool tool, IconData icon, String tip) {
      final active = _tool == tool;
      return Tooltip(
        message: tip,
        child: IconButton(
          onPressed: () => _setTool(tool),
          icon: Icon(icon, size: 20),
          color: active ? const Color(0xFF60A5FA) : Colors.white70,
          style: IconButton.styleFrom(
            backgroundColor: active ? Colors.white10 : Colors.transparent,
          ),
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          toolBtn(InkTool.pen, Icons.edit, 'Pen (D)'),
          toolBtn(InkTool.highlighter, Icons.brush, 'Markeerstift (T)'),
          toolBtn(InkTool.eraser, Icons.cleaning_services_outlined, 'Gum (E)'),
          toolBtn(InkTool.laser, Icons.my_location, 'Laser (X)'),
          const SizedBox(width: 8),
          Container(width: 1, height: 22, color: Colors.white24),
          const SizedBox(width: 8),
          for (final c in palette)
            GestureDetector(
              onTap: () => setState(() => _inkColor = c),
              child: Container(
                width: 20,
                height: 20,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: Color(c),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _inkColor == c ? Colors.white : Colors.white24,
                    width: _inkColor == c ? 2.5 : 1,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
          Container(width: 1, height: 22, color: Colors.white24),
          Tooltip(
            message: context.l10n.d('Wis annotaties (C)'),
            child: IconButton(
              onPressed: _clearCurrentInk,
              icon: const Icon(Icons.delete_outline, size: 20),
              color: Colors.white70,
              visualDensity: VisualDensity.compact,
            ),
          ),
          Tooltip(
            message: context.l10n.d('Stoppen (Esc)'),
            child: IconButton(
              onPressed: () {
                setState(() => _tool = null);
                _onLaserMove(null);
              },
              icon: const Icon(Icons.close, size: 20),
              color: Colors.white70,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  /// Badge met het getypte slidenummer ("→ 12 / 28  · Enter").
  Widget _buildTypedBadge(int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF60A5FA), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.south_east, color: Color(0xFF60A5FA), size: 20),
          const SizedBox(width: 10),
          Text(
            '$_typed / $total',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Enter',
            style: TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
  }

  /// Badge tijdens het invoeren van de doeltijd ("Doeltijd 20:00 · Enter").
  /// Cijfers schuiven van rechts in als MM:SS (zoals een magnetron).
  Widget _buildTargetBadge() {
    final padded = _targetTyped.padLeft(4, '0');
    final preview = '${padded.substring(0, 2)}:${padded.substring(2)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, color: Color(0xFFF59E0B), size: 20),
          const SizedBox(width: 10),
          Text(
            preview,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${context.l10n.d('Doeltijd')} · Enter · 0 = ${context.l10n.d('uit')}',
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ],
      ),
    );
  }

  /// Sneltoets-overzicht (cheatsheet).
  Widget _buildHelpOverlay() {
    final l10n = context.l10n;
    final rows = <(String, String)>[
      ('→ · ${l10n.d('spatie')} · ${l10n.d('klik')}', l10n.d('Volgende slide')),
      ('←', l10n.d('Vorige slide')),
      ('${l10n.d('cijfers')} + Enter', l10n.d('Naar slidenummer')),
      ('Home · End', l10n.d('Eerste · laatste slide')),
      ('G', l10n.d('Slide-overzicht (pijltjes + Enter)')),
      ('P', l10n.d('Presenter view (notities, klok)')),
      ('S', l10n.d('Scherm wisselen (meerdere schermen)')),
      ('B · W', l10n.d('Zwart · wit scherm')),
      ('D · T · E', l10n.d('Pen · markeerstift · gum')),
      ('X · C', l10n.d('Laser · annotaties wissen')),
      ('K', l10n.d('Doeltijd / aftellen instellen (MMSS)')),
      ('R', l10n.d('Tijd & oefenrun resetten')),
      ('A', l10n.d('Automatische modus aan/uit')),
      ('L', l10n.d('Herhalen (loop) aan/uit')),
      ('M', l10n.d('Na media automatisch doorgaan')),
      ('H', l10n.d('Deze legenda')),
      ('Esc', l10n.d('Terug / afsluiten')),
    ];
    return GestureDetector(
      onTap: _toggleHelp,
      child: Container(
        color: Colors.black.withValues(alpha: 0.85),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 460,
            maxHeight: MediaQuery.of(context).size.height - 48,
          ),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFF161616),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2A2A2A)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.keyboard_outlined,
                        color: Colors.white70,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        l10n.d('Toetsenlegenda'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  for (final (keys, desc) in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 150,
                            child: Text(
                              keys,
                              style: const TextStyle(
                                color: Color(0xFF60A5FA),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              desc,
                              style: const TextStyle(
                                color: Color(0xFFE5E5E5),
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      l10n.d('Klik of druk op H / Esc om te sluiten'),
                      style: const TextStyle(
                        color: Colors.white30,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Vol-vlak zwart/wit scherm dat met een klik weer verdwijnt.
  Widget _blankFill() {
    return GestureDetector(
      onTap: () => setState(() => _blank = _Blank.none),
      child: Container(
        color: _blank == _Blank.white ? Colors.white : Colors.black,
      ),
    );
  }

  /// A 16:9 slide sized to fit within the given constraints.
  Widget _slideCanvas(Slide slide) {
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
                  projectPath: widget.projectPath,
                  themeProfile: widget.themeProfile,
                  onLinkTap: openExternalUrl,
                  slideNumber: _index + 1,
                  slideCount: widget.slides.length,
                  tlp: widget.tlp,
                  presentationMode: true,
                  onChecklistItemToggle: (column, itemIndex) =>
                      _toggleChecklistItem(
                        slideIndex: _index,
                        column: column,
                        itemIndex: itemIndex,
                      ),
                  // Tijdens het presenteren speelt media en starten audio/video
                  // vanzelf; het media-einde stuurt auto-advance aan. In dual-
                  // schermmodus speelt de media op het beamervenster, niet hier,
                  // anders zou het geluid dubbel klinken.
                  enableMedia: !_dual,
                  autoplayMedia: !_dual,
                  onAudioComplete: () => _onMediaCompleted(kind: 'audio'),
                  onVideoComplete: () => _onMediaCompleted(kind: 'video'),
                ),
                // Annotatielaag bovenop de dia. Laat klikken door wanneer er
                // geen gereedschap actief is (zodat tikken blijft doorbladeren).
                AnnotationLayer(
                  // Keyed by slide so a slide change (e.g. auto-advance) while a
                  // stroke is in progress resets the layer instead of committing
                  // the half-drawn stroke onto the next slide.
                  key: ValueKey(slide.id),
                  strokes: _currentStrokes,
                  tool: _tool,
                  color: _inkColor,
                  width: _toolWidth,
                  interactive: true,
                  onStrokesChanged: _onStrokesChanged,
                  onLaserMove: _onLaserMove,
                  onActiveStrokeChanged: _onActiveStroke,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Audience view (alleen de slide) ──────────────────────────────────────

  Widget _buildAudienceView(BuildContext context) {
    final total = widget.slides.length;
    final slide = widget.slides[_index.clamp(0, total - 1)];

    // Blanco scherm vult in publieksweergave het hele beeld.
    if (_blank != _Blank.none) return _blankFill();

    return GestureDetector(
      onTap: _next,
      onSecondaryTap: _prev,
      child: SizedBox.expand(child: _slideCanvas(slide)),
    );
  }

  // ── Presenter view (slide + volgende + notities + tijd) ──────────────────

  Widget _buildPresenterView(BuildContext context) {
    final l10n = context.l10n;
    final total = widget.slides.length;
    final slide = widget.slides[_index.clamp(0, total - 1)];
    final hasNext = _index < total - 1;
    final nextSlide = hasNext ? widget.slides[_index + 1] : null;

    return Container(
      color: const Color(0xFF0A0A0A),
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Hoofdgebied: huidige slide ───────────────────────────────────
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionLabel(l10n.d('HUIDIGE SLIDE')),
                const SizedBox(height: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: GestureDetector(
                      onTap: _next,
                      child: Stack(
                        children: [
                          Positioned.fill(child: _slideCanvas(slide)),
                          // Blanco scherm dekt alleen het slidevlak; jouw
                          // notities en klok blijven zichtbaar.
                          if (_blank != _Blank.none)
                            Positioned.fill(child: _blankFill()),
                          if (_progress > 0 && _blank == _Blank.none)
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: LinearProgressIndicator(
                                value: _progress,
                                backgroundColor: Colors.white12,
                                color: Colors.white54,
                                minHeight: 3,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _buildPresenterControls(total),
              ],
            ),
          ),
          const SizedBox(width: 20),

          // ── Zijbalk: klok, volgende slide, notities ─────────────────────
          SizedBox(
            width: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildClockBar(),
                const SizedBox(height: 16),
                _SectionLabel(l10n.d('VOLGENDE')),
                const SizedBox(height: 8),
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: nextSlide != null
                        ? Container(
                            color: Colors.black,
                            child: SlidePreviewWidget(
                              slide: nextSlide,
                              projectPath: widget.projectPath,
                              themeProfile: widget.themeProfile,
                              presentationMode: true,
                            ),
                          )
                        : Container(
                            color: const Color(0xFF161616),
                            alignment: Alignment.center,
                            child: Text(
                              l10n.d('Einde van de presentatie'),
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 13,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                _SectionLabel(l10n.d('NOTITIES')),
                const SizedBox(height: 8),
                Expanded(child: _buildNotes(slide)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Eén tijdwaarde met bijschrift voor de klokbalk.
  Widget _metric(
    String label,
    String value, {
    Color? color,
    CrossAxisAlignment align = CrossAxisAlignment.start,
    double size = 24,
  }) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color ?? Colors.white,
            fontSize: size,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _buildClockBar() {
    final l10n = context.l10n;
    final elapsed = _rehearsal.elapsed;
    final remaining = _rehearsal.remaining;
    final slideElapsed = _rehearsal.currentSlideElapsed;
    final overtime = remaining != null && remaining.isNegative;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF262626)),
      ),
      child: Column(
        children: [
          // Bovenrij: verstreken tijd, knoppen, wandklok.
          Row(
            children: [
              Expanded(
                child: _metric(l10n.d('Verstreken'), _fmtElapsed(elapsed)),
              ),
              Tooltip(
                message: l10n.d('Doeltijd / aftellen (K)'),
                child: IconButton(
                  onPressed: _beginTargetInput,
                  icon: const Icon(Icons.timer_outlined, size: 18),
                  color: Colors.white38,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              Tooltip(
                message: l10n.d('Tijd resetten (R)'),
                child: IconButton(
                  onPressed: _resetTimer,
                  icon: const Icon(Icons.restart_alt, size: 18),
                  color: Colors.white38,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 4),
              _metric(
                l10n.d('Klok'),
                _fmtClock(DateTime.now()),
                color: Colors.white70,
                align: CrossAxisAlignment.end,
              ),
            ],
          ),
          const Divider(height: 18, color: Color(0xFF262626)),
          // Onderrij: aftelling (resterend/over) en tijd op huidige slide.
          Row(
            children: [
              Expanded(
                child: _metric(
                  overtime ? l10n.d('Over de tijd') : l10n.d('Resterend'),
                  remaining == null ? '–:––' : _fmtRemaining(remaining),
                  color: remaining == null
                      ? Colors.white24
                      : (overtime
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF22C55E)),
                  size: 20,
                ),
              ),
              _metric(
                l10n.d('Deze slide'),
                _fmtElapsed(slideElapsed),
                color: Colors.white70,
                align: CrossAxisAlignment.end,
                size: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotes(Slide slide) {
    final l10n = context.l10n;
    final notes = slide.notes.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF262626)),
      ),
      child: notes.isEmpty
          ? Align(
              alignment: Alignment.topLeft,
              child: Text(
                l10n.d('Geen notities voor deze slide.'),
                style: const TextStyle(
                  color: Colors.white30,
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          : SingleChildScrollView(
              child: Text(
                notes,
                style: const TextStyle(
                  color: Color(0xFFE5E5E5),
                  fontSize: 17,
                  height: 1.5,
                ),
              ),
            ),
    );
  }

  Widget _buildPresenterControls(int total) {
    final l10n = context.l10n;
    return Row(
      children: [
        _NavButton(icon: Icons.chevron_left, onTap: _index > 0 ? _prev : null),
        const SizedBox(width: 8),
        _NavButton(
          icon: Icons.chevron_right,
          onTap: _index < total - 1 ? _next : null,
        ),
        if (_displays.length > 1) ...[
          const SizedBox(width: 8),
          Tooltip(
            message: l10n.d('Wissel scherm (S)'),
            child: _NavButton(
              icon: Icons.screen_share_outlined,
              onTap: _cycleDisplay,
            ),
          ),
        ],
        const SizedBox(width: 16),
        Text(
          '${l10n.d('Slide')} ${_index + 1} / $total',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            l10n.d(
              _displays.length > 1
                  ? 'P publiek · H legenda · S scherm · G overzicht · B/W zwart/wit · R tijd · Esc stop'
                  : 'P publiek · H legenda · G overzicht · B/W zwart/wit · R tijd · Esc stop',
            ),
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white24, fontSize: 11),
          ),
        ),
        const SizedBox(width: 12),
        Tooltip(
          message: l10n.d('Afsluiten (Escape)'),
          child: IconButton(
            onPressed: _exit,
            icon: const Icon(Icons.close),
            color: Colors.white,
            style: IconButton.styleFrom(backgroundColor: Colors.black45),
          ),
        ),
      ],
    );
  }

  // ── Rasteroverzicht (snel naar een slide springen) ───────────────────────

  Widget _buildGridOverlay() {
    final l10n = context.l10n;
    final total = widget.slides.length;
    return Container(
      color: Colors.black.withValues(alpha: 0.94),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 12),
              child: Row(
                children: [
                  Text(
                    l10n.d('Slide-overzicht'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${l10n.d('pijltjes + Enter of klik om te springen')} · $total ${l10n.t('slides')}',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  const Spacer(),
                  Tooltip(
                    message: l10n.d('Sluiten (G of Esc)'),
                    child: IconButton(
                      onPressed: _toggleGrid,
                      icon: const Icon(Icons.close),
                      color: Colors.white,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (_, constraints) {
                  // Mik op tegels van ~260px breed, tussen 2 en 6 kolommen.
                  const hPad = 24.0, spacing = 16.0;
                  const aspect = 16 / 10.4; // slide + nummerregel
                  final cols = (constraints.maxWidth ~/ 260).clamp(2, 6);
                  // Maten onthouden voor pijltjesnavigatie + auto-scroll.
                  _gridCols = cols;
                  final tileW =
                      (constraints.maxWidth - hPad * 2 - spacing * (cols - 1)) /
                      cols;
                  _gridRowExtent = tileW / aspect + spacing;
                  return GridView.builder(
                    controller: _gridScroll,
                    padding: const EdgeInsets.fromLTRB(hPad, 0, hPad, 24),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      crossAxisSpacing: spacing,
                      mainAxisSpacing: spacing,
                      childAspectRatio: aspect,
                    ),
                    itemCount: total,
                    itemBuilder: (_, i) => _buildGridTile(i),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridTile(int i) {
    final isCurrent = i == _index; // de slide die nu getoond wordt
    final isCursor = i == _gridCursor; // de toetsenbordcursor

    // Cursor wint qua markering (witte rand + gloed); de huidige slide krijgt
    // anders een accentrand zodat je beide posities ziet.
    final Color borderColor;
    final double borderWidth;
    if (isCursor) {
      borderColor = Colors.white;
      borderWidth = 3;
    } else if (isCurrent) {
      borderColor = const Color(0xFF60A5FA);
      borderWidth = 2;
    } else {
      borderColor = const Color(0xFF3A3A3A);
      borderWidth = 1;
    }

    return GestureDetector(
      onTap: () => _jumpTo(i),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setGridCursor(i),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor, width: borderWidth),
                  boxShadow: isCursor
                      ? [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.25),
                            blurRadius: 16,
                          ),
                        ]
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: SlidePreviewWidget(
                      slide: widget.slides[i],
                      projectPath: widget.projectPath,
                      themeProfile: widget.themeProfile,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${i + 1}',
                  style: TextStyle(
                    color: (isCursor || isCurrent)
                        ? Colors.white
                        : Colors.white54,
                    fontSize: 12,
                    fontWeight: (isCursor || isCurrent)
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
                if (isCurrent) ...[
                  const SizedBox(width: 5),
                  const Icon(
                    Icons.play_arrow_rounded,
                    size: 13,
                    color: Color(0xFF60A5FA),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Kleine helpers ───────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF6B7280),
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _NavButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? const Color(0xFF1F1F1F) : const Color(0xFF141414),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 44,
          height: 36,
          child: Icon(
            icon,
            color: enabled ? Colors.white70 : Colors.white12,
            size: 24,
          ),
        ),
      ),
    );
  }
}
