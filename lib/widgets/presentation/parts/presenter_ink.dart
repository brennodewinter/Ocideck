// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Split out for navigability; all imports live in the main library file.
part of '../fullscreen_presenter.dart';

extension _PresenterInk on _FullscreenPresenterState {
  /// Send the current slide's strokes to the beamer (keyed by index there).
  void _pushInk() {
    if (widget.audience == null) return;
    audienceChannel
        .invokeMethod('ink', {
          'index': _index,
          'strokes': encodeStrokes(_currentStrokes),
        })
        .catchError((Object e) {
          // Audience-window sync is best-effort, but a fully silent failure
          // left the beamer out of sync with no trace; make it observable.
          logWarning('FullscreenPresenter: audience window sync failed', e);
          return null;
        });
  }

  void _onStrokesChanged(List<InkStroke> strokes) {
    final key = _currentInkKey();
    _rebuild(() {
      if (strokes.isEmpty) {
        _ink.remove(key);
      } else {
        _ink[key] = strokes;
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
        .catchError((Object e) {
          // Audience-window sync is best-effort, but a fully silent failure
          // left the beamer out of sync with no trace; make it observable.
          logWarning('FullscreenPresenter: audience window sync failed', e);
          return null;
        });
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
        .catchError((Object e) {
          // Audience-window sync is best-effort, but a fully silent failure
          // left the beamer out of sync with no trace; make it observable.
          logWarning('FullscreenPresenter: audience window sync failed', e);
          return null;
        });
  }

  /// Select a tool, or toggle it off when it is already active.
  void _setTool(InkTool tool) {
    _rebuild(() => _tool = _tool == tool ? null : tool);
    if (_tool != InkTool.laser) _onLaserMove(null); // hide laser on tool switch
  }

  void _clearCurrentInk() {
    final key = _currentInkKey();
    if (!_ink.containsKey(key)) return;
    _rebuild(() => _ink.remove(key));
    widget.onAnnotationsChanged?.call(_ink);
    _pushInk();
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
          toolBtn(
            InkTool.eraser,
            Icons.cleaning_services_outlined,
            'Gum (E / ⇧E)',
          ),
          toolBtn(InkTool.laser, Icons.my_location, 'Laser (X)'),
          const SizedBox(width: 8),
          Container(width: 1, height: 22, color: Colors.white24),
          const SizedBox(width: 8),
          for (final c in palette)
            GestureDetector(
              onTap: () => _rebuild(() => _inkColor = c),
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
                _rebuild(() => _tool = null);
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

  Color _hexColor(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    final value = int.tryParse(
      cleaned.length == 6 ? 'FF$cleaned' : cleaned,
      radix: 16,
    );
    return Color(value ?? 0xFFFFFFFF);
  }
}
