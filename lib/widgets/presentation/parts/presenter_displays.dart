// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Split out for navigability; all imports live in the main library file.
part of '../fullscreen_presenter.dart';

extension _PresenterDisplays on _FullscreenPresenterState {
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
      _rebuild(() {
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
      if (mounted) _rebuild(() => _displayIndex = index);
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
    // Doof de laser op de beamer: het venster verhuist en zou anders een
    // achtergebleven stip laten staan tot de muis weer beweegt.
    _onLaserMove(null);
    await _moveToDisplay((_displayIndex + 1) % _displays.length);
  }
}
