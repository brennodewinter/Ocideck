import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../../platform/platform_features.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';
import '../../models/annotation.dart';
import '../../models/deck.dart';
import '../../models/question.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../models/timeline.dart';
import '../../services/markdown_service.dart';
import '../../services/mermaid_render_service.dart';
import '../../services/rehearsal_controller.dart';
import '../../services/rich_text_layout.dart';
import '../../services/slide_layout_metrics.dart';
import '../../utils/log.dart';
import '../../utils/page_scoped_notes.dart';
import '../../utils/project_path.dart';
import '../../utils/url_launcher_util.dart';
import '../../l10n/app_localizations.dart';
import '../slides/inline_markdown.dart';
import '../slides/slide_preview.dart';
import '../markdown_notes_editor.dart';
import 'annotation_overlay.dart';
import 'audience_window.dart';
import 'rehearsal_summary.dart';

part 'parts/presenter_questions.dart';
part 'parts/presenter_table.dart';
part 'parts/presenter_ink.dart';
part 'parts/presenter_playback.dart';
part 'parts/presenter_displays.dart';
part 'parts/presenter_navigation.dart';
part 'parts/presenter_keys.dart';
part 'parts/presenter_notes.dart';
part 'parts/presenter_overlays.dart';

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

/// Tick-interval (ms) voor de vraag-timer. Top-level zodat de presenter-
/// onderdelen die over `part`-bestanden zijn verdeeld erbij kunnen.
const _questionTickMs = 100;

/// Cijfer (gewoon of numpad) → karakter, of null bij andere toetsen.
/// Top-level zodat de toets-afhandeling in een `part`-bestand erbij kan.
final Map<LogicalKeyboardKey, String> _digits = {
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

class FullscreenPresenter extends StatefulWidget {
  final List<Slide> slides;
  final String? projectPath;
  final ThemeProfile themeProfile;
  final CockpitColorScheme cockpitColorScheme;
  final int initialIndex;
  final TlpLevel tlp;
  final String organization;
  final bool showClassificationWatermark;

  /// Of online media (URL-video's/-afbeeldingen en YouTube/Vimeo-embeds) live
  /// geladen mag worden tijdens presenteren. Komt uit de instelling
  /// `allowRemoteMedia` (fail-closed: standaard uit).
  final bool allowRemoteMedia;

  /// Optionele doeltijd voor de aftelling/oefenklok. Null = geen aftelling.
  /// Sessie-only; live aanpasbaar in de presenter (toets K).
  final Duration? targetDuration;

  /// Of het oefenoverzicht (bestede tijd per slide) na afloop verschijnt. De
  /// tijd wordt altijd gemeten; dit schakelt enkel het eindscherm. Komt uit de
  /// instelling `showRehearsalSummary` (standaard aan).
  final bool showRehearsalSummary;

  /// When set, this presenter drives a separate audience (beamer) window: the
  /// laptop shows the presenter view, the slide goes to [audience]. Null
  /// for the classic single-screen mode.
  final AudienceWindowHandle? audience;

  /// Annotation layer keyed by [Slide.id], and a callback to persist changes
  /// made while presenting back to the deck.
  final Map<String, List<InkStroke>> initialAnnotations;
  final void Function(Map<String, List<InkStroke>>)? onAnnotationsChanged;
  final ValueChanged<Slide>? onSlideChanged;

  /// Recipient/course notes keyed by [Slide.id]; never shown on the audience
  /// display unless the presenter toggles the local notes panel (Ctrl+N).
  final Map<String, String> initialUserNotes;
  final void Function(Map<String, String>)? onUserNotesChanged;

  const FullscreenPresenter({
    super.key,
    required this.slides,
    required this.projectPath,
    required this.themeProfile,
    this.cockpitColorScheme = CockpitColorScheme.standard,
    required this.initialIndex,
    this.tlp = TlpLevel.none,
    this.organization = '',
    this.showClassificationWatermark = false,
    this.allowRemoteMedia = false,
    this.targetDuration,
    this.showRehearsalSummary = true,
    this.audience,
    this.initialAnnotations = const {},
    this.onAnnotationsChanged,
    this.onSlideChanged,
    this.initialUserNotes = const {},
    this.onUserNotesChanged,
  });

  /// Entry point used by the app: pick dual-screen mode when a second display is
  /// available on desktop, otherwise the single-window presenter. Any failure
  /// to open the second window falls back to single-window mode.
  static Future<void> present(
    BuildContext context, {
    required List<Slide> slides,
    required String? projectPath,
    required ThemeProfile themeProfile,
    CockpitColorScheme cockpitColorScheme = CockpitColorScheme.standard,
    required int initialIndex,
    TlpLevel tlp = TlpLevel.none,
    String organization = '',
    bool showClassificationWatermark = false,
    bool allowRemoteMedia = false,
    Duration? targetDuration,
    bool showRehearsalSummary = true,
    Map<String, List<InkStroke>> annotations = const {},
    void Function(Map<String, List<InkStroke>>)? onAnnotationsChanged,
    ValueChanged<Slide>? onSlideChanged,
    Map<String, String> initialUserNotes = const {},
    void Function(Map<String, String>)? onUserNotesChanged,
  }) async {
    var displayCount = 0;
    if (supportsDualScreenPresenter) {
      try {
        final displays = await screenRetriever.getAllDisplays();
        displayCount = displays.length;
      } catch (e) {
        logWarning('FullscreenPresenter.present: display detection failed', e);
        displayCount = 0;
      }
    }
    final dual = shouldUseDualScreen(
      isDesktopNative: supportsDualScreenPresenter,
      displayCount: displayCount,
    );
    if (!context.mounted) return;
    if (dual) {
      await showDualScreen(
        context,
        slides: slides,
        projectPath: projectPath,
        themeProfile: themeProfile,
        cockpitColorScheme: cockpitColorScheme,
        initialIndex: initialIndex,
        tlp: tlp,
        organization: organization,
        showClassificationWatermark: showClassificationWatermark,
        allowRemoteMedia: allowRemoteMedia,
        targetDuration: targetDuration,
        showRehearsalSummary: showRehearsalSummary,
        annotations: annotations,
        onAnnotationsChanged: onAnnotationsChanged,
        onSlideChanged: onSlideChanged,
        initialUserNotes: initialUserNotes,
        onUserNotesChanged: onUserNotesChanged,
      );
    } else {
      await show(
        context,
        slides: slides,
        projectPath: projectPath,
        themeProfile: themeProfile,
        cockpitColorScheme: cockpitColorScheme,
        initialIndex: initialIndex,
        tlp: tlp,
        organization: organization,
        showClassificationWatermark: showClassificationWatermark,
        allowRemoteMedia: allowRemoteMedia,
        targetDuration: targetDuration,
        showRehearsalSummary: showRehearsalSummary,
        annotations: annotations,
        onAnnotationsChanged: onAnnotationsChanged,
        onSlideChanged: onSlideChanged,
        initialUserNotes: initialUserNotes,
        onUserNotesChanged: onUserNotesChanged,
      );
    }
  }

  static Future<void> show(
    BuildContext context, {
    required List<Slide> slides,
    required String? projectPath,
    required ThemeProfile themeProfile,
    CockpitColorScheme cockpitColorScheme = CockpitColorScheme.standard,
    required int initialIndex,
    TlpLevel tlp = TlpLevel.none,
    String organization = '',
    bool showClassificationWatermark = false,
    bool allowRemoteMedia = false,
    Duration? targetDuration,
    bool showRehearsalSummary = true,
    Map<String, List<InkStroke>> annotations = const {},
    void Function(Map<String, List<InkStroke>>)? onAnnotationsChanged,
    ValueChanged<Slide>? onSlideChanged,
    Map<String, String> initialUserNotes = const {},
    void Function(Map<String, String>)? onUserNotesChanged,
  }) async {
    final hadWakeLock = await _wakeLockEnabled();
    await _enableWakeLock();
    try {
      await windowManager.setFullScreen(true);
      if (context.mounted) {
        await Navigator.push(
          context,
          PageRouteBuilder<void>(
            opaque: true,
            pageBuilder: (context, anim, anim2) => FullscreenPresenter(
              slides: slides,
              projectPath: projectPath,
              themeProfile: themeProfile,
              cockpitColorScheme: cockpitColorScheme,
              initialIndex: initialIndex,
              tlp: tlp,
              organization: organization,
              showClassificationWatermark: showClassificationWatermark,
              allowRemoteMedia: allowRemoteMedia,
              targetDuration: targetDuration,
              showRehearsalSummary: showRehearsalSummary,
              initialAnnotations: annotations,
              onAnnotationsChanged: onAnnotationsChanged,
              onSlideChanged: onSlideChanged,
              initialUserNotes: initialUserNotes,
              onUserNotesChanged: onUserNotesChanged,
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
    CockpitColorScheme cockpitColorScheme = CockpitColorScheme.standard,
    required int initialIndex,
    TlpLevel tlp = TlpLevel.none,
    String organization = '',
    bool showClassificationWatermark = false,
    bool allowRemoteMedia = false,
    Duration? targetDuration,
    bool showRehearsalSummary = true,
    Map<String, List<InkStroke>> annotations = const {},
    void Function(Map<String, List<InkStroke>>)? onAnnotationsChanged,
    ValueChanged<Slide>? onSlideChanged,
    Map<String, String> initialUserNotes = const {},
    void Function(Map<String, String>)? onUserNotesChanged,
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
        organization: organization,
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
      'classificationWatermarkEnabled': showClassificationWatermark,
      'allowRemoteMedia': allowRemoteMedia,
      // The cockpit colour scheme is styling, so it travels with the transient
      // beamer payload (like the inlined style profile) rather than the deck.
      'cockpitColorScheme': cockpitColorScheme.toJson(),
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
          cockpitColorScheme: cockpitColorScheme,
          initialIndex: initialIndex,
          tlp: tlp,
          organization: organization,
          showClassificationWatermark: showClassificationWatermark,
          allowRemoteMedia: allowRemoteMedia,
          showRehearsalSummary: showRehearsalSummary,
          annotations: annotations,
          onAnnotationsChanged: onAnnotationsChanged,
          onSlideChanged: onSlideChanged,
          initialUserNotes: initialUserNotes,
          onUserNotesChanged: onUserNotesChanged,
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
          PageRouteBuilder<void>(
            opaque: true,
            pageBuilder: (context, anim, anim2) => FullscreenPresenter(
              slides: slides,
              projectPath: projectPath,
              themeProfile: themeProfile,
              cockpitColorScheme: cockpitColorScheme,
              initialIndex: initialIndex,
              tlp: tlp,
              organization: organization,
              showClassificationWatermark: showClassificationWatermark,
              allowRemoteMedia: allowRemoteMedia,
              showRehearsalSummary: showRehearsalSummary,
              audience: audienceHandle,
              initialAnnotations: annotations,
              onAnnotationsChanged: onAnnotationsChanged,
              onSlideChanged: onSlideChanged,
              initialUserNotes: initialUserNotes,
              onUserNotesChanged: onUserNotesChanged,
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
  required bool isDesktopNative,
  required int displayCount,
}) {
  return isDesktopNative && displayCount >= 2;
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

  /// Gebruikersnotities-paneel (ontvanger/cursist); standaard uit.
  bool _userNotesMode = false;
  NotesEditorMode _userNotesEditorMode = NotesEditorMode.markdown;
  late Map<String, String> _userNotes;
  TextEditingController? _userNoteCtrl;
  late final FocusNode _userNotesFocusNode;

  /// Live tabelbewerking op een tabeldia (toets E).
  bool _tableEditMode = false;
  int? _tableEditRow;
  int? _tableEditCol;

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

  /// Last (index, blank, richTextPage) pushed to the audience window.
  int? _lastSentIndex;
  int? _lastSentBlank;
  int? _lastSentRichTextPage;
  int? _lastSentTimelineStep;

  /// Pagina binnen een rich-text slide (0-gebaseerd).
  int _richTextPage = 0;

  /// Aantal reeds onthulde extra gebeurtenissen op een tijdlijn-slide in
  /// stap-voor-stap-modus (0 = alleen de eerste gebeurtenis getoond). Net als
  /// [_richTextPage] is dit sessie-only en wordt het naar de beamer gepusht.
  int _timelineStep = 0;

  // ── Vraag-slides (sessie-only, niet naar .md) ─────────────────────────────
  /// Live toestand per vraag-slide, gekeyd op [Slide.id]. De presenter is de
  /// bron van waarheid; het wordt naar het publieksvenster gepusht.
  final Map<String, QuestionView> _questionViews = {};

  /// Countdown-timer van de actieve vraag (null = geen).
  Timer? _questionTimer;

  /// Welke slide-index als "getoond" is verwerkt (voorkomt dubbel rollen).
  int _shownIndex = -1;

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

  /// Rebuild helper for the presenter's `part` extensions. Extension methods
  /// cannot call the protected [State.setState] directly, so they route through
  /// this; behaviour is identical to calling `setState` inside the class.
  void _rebuild(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _rehearsal = RehearsalController(target: widget.targetDuration);
    _focusNode = FocusNode();
    _userNotesFocusNode = FocusNode();
    _ink = {
      for (final e in widget.initialAnnotations.entries)
        e.key: List<InkStroke>.from(e.value),
    };
    _userNotes = Map<String, String>.from(widget.initialUserNotes);
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
            await _exit();
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
          case 'answerSelected':
            final args = Map<String, dynamic>.from(call.arguments as Map);
            _onAnswerSelected(
              (args['optionIndex'] as num?)?.toInt() ?? 0,
              slideIndex: (args['slideIndex'] as num?)?.toInt(),
            );
          case 'answerSubmit':
            final args = Map<String, dynamic>.from(call.arguments as Map);
            _onAnswerSubmit(slideIndex: (args['slideIndex'] as num?)?.toInt());
        }
        return null;
      });
    }
    // Tik elke seconde, maar herbouw alleen in presenter view (klok/teller).
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_presenterView) setState(() {});
      if (_userNotesMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _userNotesFocusNode.requestFocus();
        });
      }
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
    _questionTimer?.cancel();
    _gridScroll.dispose();
    _focusNode.dispose();
    _userNotesFocusNode.dispose();
    _userNoteCtrl?.dispose();
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
    if (_index == _lastSentIndex &&
        blank == _lastSentBlank &&
        _richTextPage == _lastSentRichTextPage &&
        _timelineStep == _lastSentTimelineStep) {
      return;
    }
    final indexChanged = _index != _lastSentIndex;
    _lastSentIndex = _index;
    _lastSentBlank = blank;
    _lastSentRichTextPage = _richTextPage;
    _lastSentTimelineStep = _timelineStep;
    audienceChannel
        .invokeMethod('update', {
          'index': _index,
          'blank': blank,
          'richTextPage': _richTextPage,
          'timelineStep': _timelineStep,
        })
        .catchError((Object e) {
          // Audience-window sync is best-effort, but a fully silent failure
          // left the beamer out of sync with no trace; make it observable.
          logWarning('FullscreenPresenter: audience window sync failed', e);
          return null;
        });
    if (indexChanged) _pushInk();
  }

  // ── Vraag-slides ───────────────────────────────────────────────────────────

  /// Wordt aangeroepen als de getoonde slide wijzigt. Start een verse
  /// vraagronde of toont de reeds-beantwoorde toestand. Idempotent: meerdere
  /// keren aanroepen voor dezelfde index doet niets.
  void _onSlideShown() {
    if (_index == _shownIndex) return;
    _shownIndex = _index;
    _questionTimer?.cancel();
    final slide = _currentSlide;
    if (slide.type != SlideType.question) {
      _pushQuestion(); // wist de vraag-overlay op het publieksvenster
      return;
    }
    final existing = _questionViews[slide.id];
    if (existing != null && existing.passed) {
      _pushQuestion();
      return;
    }
    _startQuestionRound(slide);
  }

  RichTextLayoutPlan? _richTextPlanFor(Slide slide) {
    if (!slideUsesRichText(slide)) return null;
    const w = kReferenceSlideWidth;
    final split = slide.type == SlideType.bulletsImage;
    final hPad = split ? w * 0.038 : w * 0.07;
    final imgFraction = split
        ? ((slide.imageSize > 0 ? slide.imageSize / 100.0 : 0.40).clamp(
            0.1,
            0.70,
          ))
        : 0.0;
    final contentW = split
        ? (w - imgFraction * w - hPad * 2).clamp(w * 0.12, w)
        : w - hPad * 2;
    final contentH = w * 9 / 16 - (split ? w * 0.042 * 2 : w * 0.05 * 2);
    return planRichTextForSlide(
      slide: slide,
      profile: widget.themeProfile,
      w: w,
      availW: contentW,
      availH: contentH,
      font: widget.themeProfile.fontFamily,
      splitWithImage: split,
    );
  }

  int _richTextPageCountFor(Slide slide) =>
      _richTextPlanFor(slide)?.pageCount ?? 1;

  bool _userNotesMultiPage(Slide slide) => _richTextPageCountFor(slide) > 1;

  String _userNoteKeyFor(Slide slide) => userNoteStorageKey(
    slide.id,
    _richTextPage,
    multiPage: _userNotesMultiPage(slide),
  );

  String _userNoteTextFor(Slide slide) =>
      userNoteForPage(
        _userNotes,
        slide.id,
        _richTextPage,
        multiPage: _userNotesMultiPage(slide),
      ) ??
      '';

  void _setRichTextPage(int page) {
    _persistUserNoteFromController();
    setState(() => _richTextPage = page);
    _loadUserNoteIntoController();
    _syncAudience();
  }

  // ── Tijdlijn stap-voor-stap ──────────────────────────────────────────────

  /// True wanneer [slide] zijn gebeurtenissen klik-voor-klik onthult.
  bool _slideUsesTimelineSteps(Slide slide) =>
      slide.type == SlideType.timeline &&
      slide.timelineReveal == TimelineReveal.steps;

  int _timelineEventCountFor(Slide slide) =>
      parseTimelineEvents(slide.bullets).length;

  /// Hoeveel gebeurtenissen nu zichtbaar moeten zijn, of null als de slide niet
  /// in stapmodus staat (dan toont de tijdlijn alles / tekent zichzelf in).
  /// Stap 0 toont al de eerste gebeurtenis, zodat de slide nooit leeg opent.
  int? _timelineRevealedFor(Slide slide) {
    if (!_slideUsesTimelineSteps(slide)) return null;
    final n = _timelineEventCountFor(slide);
    if (n <= 0) return 0;
    return (_timelineStep + 1).clamp(1, n);
  }

  /// True zolang er nog een volgende gebeurtenis te onthullen valt op de huidige
  /// tijdlijn-slide (dan houdt een klik je op de slide).
  bool get _timelineHasMoreSteps {
    final slide = _currentSlide;
    if (!_slideUsesTimelineSteps(slide)) return false;
    return _timelineStep < _timelineEventCountFor(slide) - 1;
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
          .catchError((Object e) {
            // Audience-window sync is best-effort, but a fully silent failure
            // left the beamer out of sync with no trace; make it observable.
            logWarning('FullscreenPresenter: audience window sync failed', e);
            return null;
          });
    }
  }

  Slide get _currentSlide =>
      widget.slides[_index.clamp(0, widget.slides.length - 1)];

  // ── Annotatielaag ─────────────────────────────────────────────────────────

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
    // Tijd wordt altijd gemeten; deze schakelaar bepaalt enkel of het
    // eindscherm verschijnt (uit = stille modus, bv. bij een echte presentatie).
    if (!widget.showRehearsalSummary) return;
    if (!mounted || !_rehearsal.hasMeaningfulData) return;
    final run = _rehearsal.finish();
    await showRehearsalSummary(context, run: run, slides: widget.slides);
  }

  // ── Formatters ─────────────────────────────────────────────────────────────

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
            if (_tableEditMode)
              Positioned(
                left: 0,
                right: 0,
                top: 20,
                child: Center(child: _buildTableEditBanner()),
              ),
            // Subtiel potlood-icoon op tabeldia's: gedimd wanneer bewerken uit
            // staat, opgelicht wanneer het aan staat. Klikken schakelt het net
            // als de E-toets, zodat je ook met muis/clicker kunt bewerken.
            if (_currentSlideTableEditable &&
                !_helpOpen &&
                !_gridOpen &&
                !_userNotesMode &&
                !_targetInput &&
                _blank == _Blank.none)
              Positioned(top: 20, right: 20, child: _buildTableEditToggle()),
            if (_userNotesMode) ...[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _userNotesFocusNode.requestFocus(),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.45),
                  ),
                ),
              ),
              _buildUserNotesOverlay(),
            ],
            const MermaidRenderHostLayer(),
          ],
        ),
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
                  cockpitColorScheme: widget.cockpitColorScheme,
                  onLinkTap: openExternalUrl,
                  slideNumber: _index + 1,
                  slideCount: widget.slides.length,
                  richTextPage: _richTextPage,
                  showRichTextPageControls:
                      (_richTextPlanFor(slide)?.pageCount ?? 1) > 1,
                  onRichTextPageChanged:
                      (_richTextPlanFor(slide)?.pageCount ?? 1) > 1
                      ? (page) => _setRichTextPage(page)
                      : null,
                  timelineRevealedCount: _timelineRevealedFor(slide),
                  tlp: widget.tlp,
                  organization: widget.organization,
                  showClassificationWatermark:
                      widget.showClassificationWatermark,
                  presentationMode: true,
                  onChecklistItemToggle: (column, itemIndex) =>
                      _toggleChecklistItem(
                        slideIndex: _index,
                        column: column,
                        itemIndex: itemIndex,
                      ),
                  questionView: _currentQuestionView,
                  onAnswerSelected: (i) => _onAnswerSelected(i),
                  onAnswerSubmit: () => _onAnswerSubmit(),
                  tableEditMode:
                      _tableEditMode && slide.type == SlideType.table,
                  tableEditRow: _tableEditRow,
                  tableEditCol: _tableEditCol,
                  onTableCellSelected: (row, col) => _selectTableCell(row, col),
                  onTableCellChanged: (row, col, value) => _updateTableCell(
                    slideIndex: _index,
                    row: row,
                    col: col,
                    value: value,
                  ),
                  // Tijdens het presenteren speelt media en starten audio/video
                  // vanzelf; het media-einde stuurt auto-advance aan. In dual-
                  // schermmodus speelt de media op het beamervenster, niet hier,
                  // anders zou het geluid dubbel klinken.
                  enableMedia: !_dual,
                  autoplayMedia: !_dual,
                  allowRemoteMedia: widget.allowRemoteMedia,
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
                  tool: _tableEditMode ? null : _tool,
                  color: _inkColor,
                  width: _toolWidth,
                  interactive: !_tableEditMode,
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
      onTap: _tableEditMode ? null : _next,
      onSecondaryTap: _tableEditMode ? null : _prev,
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
                      onTap: _tableEditMode ? null : _next,
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
                              cockpitColorScheme: widget.cockpitColorScheme,
                              tlp: widget.tlp,
                              organization: widget.organization,
                              showClassificationWatermark:
                                  widget.showClassificationWatermark,
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

  // ── Rasteroverzicht (snel naar een slide springen) ───────────────────────
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
