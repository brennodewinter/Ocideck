import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';
import '../../models/deck.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../services/markdown_service.dart';
import '../../utils/url_launcher_util.dart';
import '../../l10n/app_localizations.dart';
import '../slides/slide_preview.dart';
import 'audience_window.dart';

/// Blanco-schermstand tijdens het presenteren (zoals B/W in PowerPoint).
enum _Blank { none, black, white }

class FullscreenPresenter extends StatefulWidget {
  final List<Slide> slides;
  final String? projectPath;
  final ThemeProfile themeProfile;
  final int initialIndex;
  final TlpLevel tlp;

  /// When set, this presenter drives a separate audience (beamer) window: the
  /// laptop shows the presenter view, the slide goes to [audienceWindow]. Null
  /// for the classic single-screen mode.
  final WindowController? audienceWindow;

  const FullscreenPresenter({
    super.key,
    required this.slides,
    required this.projectPath,
    required this.themeProfile,
    required this.initialIndex,
    this.tlp = TlpLevel.none,
    this.audienceWindow,
  });

  /// Entry point used by the app: pick dual-screen mode when a second display is
  /// available (macOS), otherwise the single-window presenter. Any failure to
  /// open the second window falls back to single-window mode.
  static Future<void> present(
    BuildContext context, {
    required List<Slide> slides,
    required String? projectPath,
    required ThemeProfile themeProfile,
    required int initialIndex,
    TlpLevel tlp = TlpLevel.none,
  }) async {
    var dual = false;
    if (Platform.isMacOS) {
      try {
        final displays = await screenRetriever.getAllDisplays();
        dual = displays.length >= 2;
      } catch (_) {
        dual = false;
      }
    }
    if (!context.mounted) return;
    if (dual) {
      await showDualScreen(
        context,
        slides: slides,
        projectPath: projectPath,
        themeProfile: themeProfile,
        initialIndex: initialIndex,
        tlp: tlp,
      );
    } else {
      await show(
        context,
        slides: slides,
        projectPath: projectPath,
        themeProfile: themeProfile,
        initialIndex: initialIndex,
        tlp: tlp,
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
  }) async {
    // A self-contained markdown deck is the payload for the audience window; it
    // carries the slides, the style profile and the TLP level in one string.
    final markdown = MarkdownService().generateDeck(
      Deck(
        title: 'Presentatie',
        slides: slides,
        projectPath: projectPath,
        themeProfile: themeProfile,
        tlp: tlp,
      ),
    );
    final argument = jsonEncode({
      'markdown': markdown,
      'projectPath': projectPath,
      'index': initialIndex,
    });

    WindowController? audience;
    try {
      audience = await WindowController.create(
        WindowConfiguration(arguments: argument, hiddenAtLaunch: true),
      );
      await audience.coverScreen(external: true);
    } catch (_) {
      audience = null;
    }

    if (audience == null) {
      if (context.mounted) {
        await show(
          context,
          slides: slides,
          projectPath: projectPath,
          themeProfile: themeProfile,
          initialIndex: initialIndex,
          tlp: tlp,
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
              audienceWindow: audience,
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
      audience.close().catchError((_) => null);
    }
  }

  @override
  State<FullscreenPresenter> createState() => _FullscreenPresenterState();
}

Future<bool> _wakeLockEnabled() async {
  try {
    return await WakelockPlus.enabled;
  } catch (_) {
    return false;
  }
}

Future<void> _enableWakeLock() async {
  try {
    await WakelockPlus.enable();
  } catch (_) {
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
  } catch (_) {
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

  /// Starttijd voor de verstreken-tijd-teller (resetbaar met R).
  late DateTime _startTime;

  /// Getypte cijfers om naar een slidenummer te springen (leeg = niet actief).
  String _typed = '';
  Timer? _typedTimer;

  /// Sneltoets-overzicht (cheatsheet) zichtbaar.
  bool _helpOpen = false;

  /// Automatische modus: slides wisselen vanzelf (op tijd of na audio). Staat
  /// standaard aan zodat ingestelde tijdwissels meteen werken; met A te pauzeren.
  bool _autoPlay = true;

  /// Herhaling: na de laatste slide terug naar de eerste (anders blijft de
  /// laatste slide staan). Met L te wisselen.
  bool _loop = false;

  /// Wissel ná het afspelen van de audio op de slide i.p.v. op de tijdwissel.
  /// Met M te wisselen.
  bool _advanceOnAudioEnd = true;

  /// Known displays for moving the fullscreen presentation window. This is not
  /// a second presenter window; it keeps the current output movable between
  /// screens with S or the presenter-view button.
  List<Display> _displays = const [];
  int _displayIndex = 0;

  /// True when this presenter drives a separate audience (beamer) window.
  bool get _dual => widget.audienceWindow != null;

  /// Last (index, blank) pushed to the audience window, to avoid redundant sends.
  int? _lastSentIndex;
  int? _lastSentBlank;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _startTime = DateTime.now();
    _focusNode = FocusNode();
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
            _onAudioCompleted();
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
    final aw = widget.audienceWindow;
    if (aw == null) return;
    final blank = _blankCode;
    if (_index == _lastSentIndex && blank == _lastSentBlank) return;
    _lastSentIndex = _index;
    _lastSentBlank = blank;
    audienceChannel
        .invokeMethod('update', {'index': _index, 'blank': blank})
        .catchError((_) => null);
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

    // Audio-gestuurd: heeft deze slide audio die vanzelf speelt én is de keuze
    // 'na audio doorgaan' actief? Dan wachten we op het audio-einde (de
    // _AudioPlayback meldt zich via onAudioComplete) en zetten we geen timer.
    final audioDriven =
        _advanceOnAudioEnd && slide.audioPath.isNotEmpty && slide.audioAutoplay;
    if (audioDriven) return;

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

  /// Automatisch doorschakelen (tijd of audio-einde): naar de volgende slide,
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

  /// Aangeroepen door de audiospeler zodra de audio op de huidige slide klaar
  /// is. In automatische modus met 'na audio doorgaan' schakelen we dan door.
  void _onAudioCompleted() {
    if (_autoPlay && _advanceOnAudioEnd) _autoAdvance();
  }

  void _toggleAutoPlay() {
    setState(() => _autoPlay = !_autoPlay);
    _scheduleAdvance();
  }

  void _toggleLoop() {
    setState(() => _loop = !_loop);
    _scheduleAdvance();
  }

  void _toggleAudioAdvance() {
    setState(() => _advanceOnAudioEnd = !_advanceOnAudioEnd);
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
    } catch (_) {
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
    } catch (_) {
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
    final aw = widget.audienceWindow;
    if (aw != null) {
      // Dual mode: the main window was never put in full screen; just tear down
      // the audience window.
      audienceChannel.invokeMethod('close').catchError((_) => null);
      aw.close().catchError((_) => null);
    } else {
      await windowManager.setFullScreen(false);
    }
    if (mounted) Navigator.pop(context);
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
    }
  }

  void _togglePresenterView() {
    setState(() => _presenterView = !_presenterView);
  }

  void _resetTimer() {
    setState(() => _startTime = DateTime.now());
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
        _toggleAudioAdvance();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyS:
        _cycleDisplay();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        // Gelaagd: getypt nummer wissen, dan blanco scherm, dan pas afsluiten.
        if (_typed.isNotEmpty) {
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

  @override
  Widget build(BuildContext context) {
    final total = widget.slides.length;
    if (total == 0) {
      _exit();
      return const SizedBox.shrink();
    }

    // Keep the beamer window in step with whatever index/blank we now show.
    _syncAudience();

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
            if (_typed.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 60,
                child: Center(child: _buildTypedBadge(total)),
              ),
            if (_helpOpen) Positioned.fill(child: _buildHelpOverlay()),
          ],
        ),
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
      ('R', l10n.d('Verstreken tijd resetten')),
      ('A', l10n.d('Automatische modus aan/uit')),
      ('L', l10n.d('Herhalen (loop) aan/uit')),
      ('M', l10n.d('Na audio automatisch doorgaan')),
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
            child: SlidePreviewWidget(
              slide: slide,
              projectPath: widget.projectPath,
              themeProfile: widget.themeProfile,
              onLinkTap: openExternalUrl,
              slideNumber: _index + 1,
              slideCount: widget.slides.length,
              tlp: widget.tlp,
              // Tijdens het presenteren speelt media en starten audio/video
              // vanzelf; het audio-einde stuurt de auto-advance aan. In dual-
              // schermmodus speelt de media op het beamervenster, niet hier,
              // anders zou het geluid dubbel klinken.
              enableMedia: !_dual,
              autoplayMedia: !_dual,
              onAudioComplete: _onAudioCompleted,
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

  Widget _buildClockBar() {
    final l10n = context.l10n;
    final elapsed = DateTime.now().difference(_startTime);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF262626)),
      ),
      child: Row(
        children: [
          // Verstreken tijd
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.d('Verstreken'),
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
                const SizedBox(height: 2),
                Text(
                  _fmtElapsed(elapsed),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          // Reset-knop
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
          // Wandklok
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                l10n.d('Klok'),
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
              const SizedBox(height: 2),
              Text(
                _fmtClock(DateTime.now()),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
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
