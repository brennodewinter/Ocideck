// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Split out for navigability; all imports live in the main library file.
part of '../fullscreen_presenter.dart';

extension _PresenterDisplays on _FullscreenPresenterState {
  Future<void> _loadDisplays() async {
    try {
      final displays = DisplayManager.instance.getAll();
      if (!mounted || displays.isEmpty) return;
      final window = WindowManager.instance.getCurrent();
      if (window == null) return;
      final current = displays.indexWhere(
        (d) => Rect.fromLTWH(
          d.position.dx,
          d.position.dy,
          d.size.width,
          d.size.height,
        ).contains(window.bounds.center),
      );
      _rebuild(() {
        _displays = displays;
        _displayIndex = current < 0 ? 0 : current;
      });
    } catch (e) {
      logWarning(
        '_FullscreenPresenterState._loadDisplays: screen detection failed',
        e,
      );
    }
  }

  Future<void> _moveToDisplay(int index) async {
    if (_displays.length < 2) return;
    final d = _displays[index.clamp(0, _displays.length - 1)];
    try {
      final window = WindowManager.instance.getCurrent();
      if (window == null) return;
      window.isFullScreen = false;
      window.bounds = Rect.fromLTWH(
        d.position.dx,
        d.position.dy,
        d.size.width,
        d.size.height,
      );
      window.isFullScreen = true;
      if (mounted) _rebuild(() => _displayIndex = index);
    } catch (e) {
      logError('_FullscreenPresenterState._moveToDisplay: failed', e);
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
    _onLaserMove(null);
    await _moveToDisplay((_displayIndex + 1) % _displays.length);
  }
}
