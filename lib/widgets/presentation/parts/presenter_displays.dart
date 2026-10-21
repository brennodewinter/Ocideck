// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Split out for navigability; all imports live in the main library file.
part of '../fullscreen_presenter.dart';

extension _PresenterDisplays on _FullscreenPresenterState {
  Future<void> _loadDisplays() async {
    try {
      final displays = getAllDisplays();
      if (!mounted || displays.isEmpty) return;
      final center = getCurrentWindowCenter();
      final current = screenIndexContaining(displays, center) ?? 0;
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
    if (_displays.length < 2 || _displaySwitchInProgress) return;
    _displaySwitchInProgress = true;
    final previous = _displayIndex;
    try {
      // Keep the audience opposite the presenter and avoid moving the main
      // fullscreen Space if the secondary window cannot move.
      await widget.audience?.controller?.coverScreen(presenterScreen: index);
      _displayTransitionSawExit = false;
      _displayTransitionUntil = DateTime.now().add(const Duration(seconds: 15));
      moveToDisplay(index, _displays);
      if (mounted) _rebuild(() => _displayIndex = index);
    } catch (e) {
      try {
        await widget.audience?.controller?.coverScreen(
          presenterScreen: previous,
        );
      } catch (restoreError) {
        logWarning(
          '_FullscreenPresenterState: audience restore failed',
          restoreError,
        );
      }
      logError('_FullscreenPresenterState._moveToDisplay: failed', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.d('Kon niet van scherm wisselen.')),
          ),
        );
      }
    } finally {
      _displaySwitchInProgress = false;
    }
  }

  Future<void> _cycleDisplay() async {
    if (_displays.isEmpty) await _loadDisplays();
    if (_displays.length < 2) return;
    _onLaserMove(null);
    await _moveToDisplay((_displayIndex + 1) % _displays.length);
  }
}
