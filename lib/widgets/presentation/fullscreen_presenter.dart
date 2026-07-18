import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../../platform/platform_features.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, listEquals, visibleForTesting;
import 'package:flutter/material.dart';
import '../../theme/presenter_palette.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart';
import '../../platform/presenter_fullscreen.dart';
import '../../models/annotation.dart';
import '../../models/deck.dart';
import '../../models/question.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../models/timeline.dart';
import '../../services/markdown_service.dart';
import '../../services/privacy/privacy_projection.dart';
import '../../services/mermaid_render_service.dart';
import '../../services/rehearsal_controller.dart';
import '../../services/rich_text_layout.dart';
import '../../services/finding_context_score.dart';
import '../../services/slide_layout_metrics.dart';
import '../../services/web_asset_store.dart';
import '../../utils/bundled_asset.dart';
import '../../utils/image_limits.dart';
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
import '../../theme/app_theme.dart';

part 'parts/presenter_questions.dart';
part 'parts/presenter_table.dart';
part 'parts/presenter_ink.dart';
part 'parts/presenter_playback.dart';
part 'parts/presenter_displays.dart';
part 'parts/presenter_navigation.dart';
part 'parts/presenter_keys.dart';
part 'parts/presenter_notes.dart';
part 'parts/presenter_overlays.dart';
part 'parts/presenter_content.dart';
part 'parts/presenter_views.dart';

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

  /// De taal van het rapport ([Deck.language]); een bevinding toont haar
  /// sectiekoppen daarin (PENTEST_MIAUW §12.3). Leeg = niet vastgelegd.
  final String reportLanguage;
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
    this.reportLanguage = '',
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
  /// Het instappunt dat de app gebruikt. Neemt bewust een [AudienceDeck]:
  /// presenteren is het ontvangende oppervlak bij uitstek — wat hier op het
  /// scherm komt, ziet de zaal. De projectiegrens hoort dus in het typesysteem
  /// te staan en niet in een afspraak. Zie `PrivacyProjection`.
  static Future<void> present(
    BuildContext context, {
    required AudienceDeck audienceDeck,
    CockpitColorScheme cockpitColorScheme = CockpitColorScheme.standard,
    required int initialIndex,
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
    // Alles wat de render nodig heeft, komt uit het geprojecteerde deck.
    final slides = audienceDeck.slides;
    final deck = audienceDeck.deck;
    final projectPath = deck.projectPath;
    final themeProfile = deck.themeProfile;
    final tlp = deck.tlp;
    final organization = deck.organization;
    final reportLanguage = deck.language;

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
        reportLanguage: reportLanguage,
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
        reportLanguage: reportLanguage,
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
    String reportLanguage = '',
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
      // Volledig scherm is best-effort: op web kan de browser weigeren en op
      // een onbekend platform ontbreekt het venster. Nooit blokkerend — de
      // presenter-route wordt hoe dan ook geopend.
      await setPresenterFullscreen(true);
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
              reportLanguage: reportLanguage,
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

  /// The self-contained markdown payload for the audience window: the slides,
  /// the style profile and the TLP level in one string.
  ///
  /// This payload never touches disk, so everything the beamer cannot look up
  /// for itself has to travel inside it. That is why the style profile is
  /// inlined — the audience window has no other way to learn the deck's
  /// styling — and, for the same reason, why chart data is. A chart that links
  /// its data through `source` would otherwise arrive as a bare relative
  /// reference the beamer cannot resolve, and render as an empty plot.
  @visibleForTesting
  static String buildBeamerMarkdown({
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
    String reportLanguage = '',
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
    final markdown = buildBeamerMarkdown(
      slides: slides,
      projectPath: projectPath,
      themeProfile: themeProfile,
      tlp: tlp,
      organization: organization,
      reportLanguage: reportLanguage,
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
          reportLanguage: reportLanguage,
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
              reportLanguage: reportLanguage,
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

  /// Monotone teller op 'update'-berichten: method-channel-aanroepen zijn
  /// fire-and-forget en niet gegarandeerd in volgorde, dus het publieksvenster
  /// negeert berichten met een lager nummer dan het laatst verwerkte.
  int _syncSeq = 0;

  /// Toegang tot de annotatielaag om een streek-in-uitvoering te committen
  /// vóór een slide-/paginawissel.
  final _annotationLayerKey = GlobalKey<AnnotationLayerState>();

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

  /// The [_ink] key for the slide on screen, scoped to its rich-text page so
  /// marks drawn on one page of a paginated text slide don't bleed onto the
  /// next. Page 0 (and every non-paginated slide) keeps the bare slide id.
  String _currentInkKey() {
    final slide = widget.slides[_index.clamp(0, widget.slides.length - 1)];
    final page = slideUsesRichText(slide) ? _richTextPage : 0;
    return annotationKey(slide.id, page);
  }

  List<InkStroke> get _currentStrokes => _ink[_currentInkKey()] ?? const [];

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
          'seq': ++_syncSeq,
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
      await setPresenterFullscreen(false);
    }
    if (mounted) Navigator.pop(context);
  }

  /// Toon na afloop de oefenrun-samenvatting wanneer de deck-schakelaar aan
  /// staat. Sessie-only: niets wordt opgeslagen.
  Future<void> _maybeShowRehearsalSummary() async {
    // Tijd wordt altijd gemeten; deze schakelaar bepaalt enkel of het
    // eindscherm verschijnt (uit = stille modus, bv. bij een echte presentatie).
    // Staat de schakelaar aan, dan verschijnt het altijd — ook een korte run
    // toont dan het overzicht (leeg = "Geen slides gemeten.").
    if (!widget.showRehearsalSummary || !mounted) return;
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
      style: TextStyle(
        color: AppTheme.gray500,
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
      color: enabled ? PresenterPalette.surface : PresenterPalette.bg,
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
