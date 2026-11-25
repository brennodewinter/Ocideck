// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Split out for navigability; all imports live in the main library file.
part of '../fullscreen_presenter.dart';

/// A native fullscreen move may report true, then false, then true. Escape
/// still exits normally outside that bounded transition.
class _DisplayTransitionGuard {
  DateTime? _until;
  bool _sawExit = false;
  bool switching = false;

  void arm() {
    _sawExit = false;
    _until = DateTime.now().add(const Duration(seconds: 15));
  }

  bool ignoresFullscreenLoss(bool fullscreen) {
    final until = _until;
    if (until == null || !DateTime.now().isBefore(until)) return false;
    if (!fullscreen) {
      _sawExit = true;
      return true;
    }
    if (_sawExit) _until = null;
    return false;
  }
}

Future<void> _movePresenterToDisplay(
  _FullscreenPresenterState state,
  int index,
  List<DisplayInfo> displays,
) async {
  if (displays.length < 2 || state._displayGuard.switching) return;
  state._displayGuard.switching = true;
  final previous = state._displayIndex;
  try {
    // Leave the main fullscreen Space untouched if the audience cannot move.
    await state.widget.audience?.controller.coverScreen(presenterScreen: index);
    state._displayGuard.arm();
    moveToDisplay(index, displays);
    if (state.mounted) {
      state._rebuild(() {
        state._displays = displays;
        state._displayIndex = index;
      });
    }
  } catch (e) {
    try {
      await state.widget.audience?.controller.coverScreen(
        presenterScreen: previous,
      );
    } catch (restoreError) {
      logWarning(
        '_FullscreenPresenterState: audience restore failed',
        restoreError,
      );
    }
    logError('_FullscreenPresenterState._moveToDisplay: failed', e);
    if (state.mounted) {
      ScaffoldMessenger.of(state.context).showSnackBar(
        SnackBar(
          content: Text(
            state.context.l10n.d(
              'De schermen zijn niet gewisseld. De notities staan nog hier.',
            ),
          ),
        ),
      );
    }
  } finally {
    state._displayGuard.switching = false;
  }
}

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

  Future<void> _cycleDisplay() async {
    if (_displays.isEmpty) await _loadDisplays();
    // Enumerate again right before use: _displays was captured earlier and a
    // screen can have vanished since (dock/cable). A stale list would move the
    // window onto the geometry of a dead display (#3162).
    final displays = getAllDisplays();
    if (displays.length < 2) {
      if (displays.length != _displays.length && mounted) {
        _rebuild(() => _displays = displays);
      }
      return;
    }
    _onLaserMove(null);
    await _movePresenterToDisplay(
      this,
      (_displayIndex + 1) % displays.length,
      displays,
    );
  }
}
