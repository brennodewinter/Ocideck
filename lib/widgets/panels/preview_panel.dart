import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../models/deck.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../state/deck_provider.dart';
import '../../state/editor_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/url_launcher_util.dart';
import '../../l10n/app_localizations.dart';
import '../slides/slide_preview.dart';

/// Of het preview-paneel ingeklapt is (UI-voorkeur, app-breed).
final previewCollapsedProvider = StateProvider<bool>((_) => false);

class PreviewPanel extends ConsumerStatefulWidget {
  const PreviewPanel({super.key});

  @override
  ConsumerState<PreviewPanel> createState() => _PreviewPanelState();
}

class _PreviewPanelState extends ConsumerState<PreviewPanel> {
  final TransformationController _transform = TransformationController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'PreviewPanel');
  double _zoom = 1.0;

  static const double _minZoom = 1.0;
  static const double _maxZoom = 4.0;
  static const double _zoomStep = 0.5;

  @override
  void dispose() {
    _transform.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Verplaats de slideselectie met de pijltjestoetsen (toegankelijkheid).
  void _move(int delta) {
    final deck = ref.read(deckProvider).deck;
    if (deck == null) return;
    final current = ref.read(editorProvider).selectedIndex;
    final next = (current + delta).clamp(0, deck.slides.length - 1);
    if (next != current) ref.read(editorProvider.notifier).select(next);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.pageUp:
        _move(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.pageDown:
        _move(1);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  void _zoomIn() {
    final next = (_zoom + _zoomStep).clamp(_minZoom, _maxZoom);
    _applyZoom(next);
  }

  void _zoomOut() {
    final next = (_zoom - _zoomStep).clamp(_minZoom, _maxZoom);
    _applyZoom(next);
  }

  void _resetZoom() {
    _applyZoom(_minZoom);
  }

  void _applyZoom(double zoom) {
    setState(() => _zoom = zoom);
    _transform.value = Matrix4.identity()..scaleByDouble(zoom, zoom, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final deckState = ref.watch(deckProvider);
    final deck = deckState.deck!;
    final editor = ref.watch(editorProvider);

    final idx = editor.selectedIndex.clamp(0, deck.slides.length - 1);
    final slide = deck.slides[idx];

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: _focusNode.requestFocus,
        child: Container(
          color: const Color(0xFFF1F5F9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──────────────────────────────────────────────────────
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.preview_outlined,
                      size: 16,
                      color: Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.d('Preview'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const Spacer(),
                    // ── Zoom controls ──────────────────────────────────────
                    Tooltip(
                      message: l10n.d('Uitzoomen'),
                      child: IconButton(
                        icon: const Icon(Icons.remove, size: 16),
                        onPressed: _zoom > _minZoom ? _zoomOut : null,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    GestureDetector(
                      onTap: _zoom != _minZoom ? _resetZoom : null,
                      child: Tooltip(
                        message: l10n.d('Zoom resetten'),
                        child: Text(
                          '${(_zoom * 100).round()}%',
                          style: TextStyle(
                            fontSize: 11,
                            color: _zoom != _minZoom
                                ? AppTheme.accent
                                : const Color(0xFF94A3B8),
                            fontWeight: _zoom != _minZoom
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                    Tooltip(
                      message: l10n.d('Inzoomen'),
                      child: IconButton(
                        icon: const Icon(Icons.add, size: 16),
                        onPressed: _zoom < _maxZoom ? _zoomIn : null,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${idx + 1} / ${deck.slides.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: l10n.d('Preview inklappen'),
                      child: IconButton(
                        icon: const Icon(Icons.chevron_right, size: 18),
                        onPressed: () =>
                            ref.read(previewCollapsedProvider.notifier).state =
                                true,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // ── Slide canvas ─────────────────────────────────────────────────
              Expanded(
                child: ClipRect(
                  child: InteractiveViewer(
                    transformationController: _transform,
                    minScale: _minZoom,
                    maxScale: _maxZoom,
                    constrained: true,
                    onInteractionUpdate: (details) {
                      final scale = _transform.value.getMaxScaleOnAxis();
                      if ((scale - _zoom).abs() > 0.01) {
                        setState(() => _zoom = scale.clamp(_minZoom, _maxZoom));
                      }
                    },
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Container(
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: SlidePreviewWidget(
                            slide: slide,
                            projectPath: deck.projectPath,
                            themeProfile: deck.themeProfile,
                            onLinkTap: openExternalUrl,
                            slideNumber: idx + 1,
                            slideCount: deck.slides.length,
                            tlp: deck.tlp,
                            // In de editor mag audio/video bediend worden, maar
                            // niet vanzelf starten (anders dreunt het door op
                            // elke slide-wissel).
                            enableMedia: true,
                            autoplayMedia: false,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Navigation footer ────────────────────────────────────────────
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: idx > 0
                          ? () => ref
                                .read(editorProvider.notifier)
                                .select(idx - 1)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                      iconSize: 20,
                      tooltip: l10n.d('Vorige slide'),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        l10n.d(slide.type.label),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: idx < deck.slides.length - 1
                          ? () => ref
                                .read(editorProvider.notifier)
                                .select(idx + 1)
                          : null,
                      icon: const Icon(Icons.chevron_right),
                      iconSize: 20,
                      tooltip: l10n.d('Volgende slide'),
                    ),
                  ],
                ),
              ),

              // ── Theme chip ───────────────────────────────────────────────────
              Container(
                color: const Color(0xFFF8FAFC),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.palette_outlined,
                      size: 12,
                      color: Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${l10n.d('Thema')}: ${deck.theme}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    if (deck.paginate) ...[
                      const SizedBox(width: 10),
                      const Icon(Icons.tag, size: 12, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 2),
                      Text(
                        l10n.d('paginering aan'),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Full-deck preview overlay ─────────────────────────────────────────────────

class FullDeckPreview extends StatelessWidget {
  final Deck deck;
  final ThemeProfile themeProfile;

  const FullDeckPreview({
    super.key,
    required this.deck,
    required this.themeProfile,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: const Color(0xFF1E2028),
      appBar: AppBar(
        title: Text('${deck.title} — ${l10n.d('volledig deck')}'),
        backgroundColor: AppTheme.navy,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 40),
        itemCount: deck.slides.length,
        itemBuilder: (_, i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${l10n.d('Slide')} ${i + 1}',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  decoration: const BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 12,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: SlidePreviewWidget(
                    slide: deck.slides[i],
                    projectPath: deck.projectPath,
                    themeProfile: themeProfile,
                    onLinkTap: openExternalUrl,
                    slideNumber: i + 1,
                    slideCount: deck.slides.length,
                    tlp: deck.tlp,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Ingeklapt preview-paneel ──────────────────────────────────────────────────

/// Smal verticaal balkje dat het ingeklapte preview-paneel vervangt; klikken
/// klapt het weer uit.
class CollapsedPreviewBar extends ConsumerWidget {
  const CollapsedPreviewBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Container(
      width: 34,
      color: Colors.white,
      child: Column(
        children: [
          const SizedBox(height: 6),
          Tooltip(
            message: l10n.d('Preview uitklappen'),
            child: IconButton(
              icon: const Icon(Icons.chevron_left, size: 18),
              onPressed: () =>
                  ref.read(previewCollapsedProvider.notifier).state = false,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 8),
          // Verticaal label "PREVIEW".
          RotatedBox(
            quarterTurns: 1,
            child: Text(
              context.l10n.d('PREVIEW'),
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
