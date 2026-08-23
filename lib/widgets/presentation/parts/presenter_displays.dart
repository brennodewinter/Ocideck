// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Split out for navigability; all imports live in the main library file.
part of '../fullscreen_presenter.dart';

extension _PresenterDisplays on _FullscreenPresenterState {
  Future<void> _loadDisplays() async {
    try {
      final displays = getAllDisplays();
      if (!mounted || displays.isEmpty) return;
      final center = getCurrentWindowCenter();
      int current = 0;
      if (center != null) {
        current = displays.indexWhere(
          (d) => Rect.fromLTWH(d.x, d.y, d.width, d.height).contains(center),
        );
        if (current < 0) current = 0;
      }
      _rebuild(() {
        _displays = displays;
        _displayIndex = current;
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
    try {
      moveToDisplay(index, _displays);
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
