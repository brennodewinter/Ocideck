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
  DisplaySnapshot snapshot,
  DisplayInfo target,
) async {
  if (!snapshot.canPresentAudience || state._displayGuard.switching) return;
  state._displayGuard.switching = true;
  final previous = snapshot.presenter!;
  final audience = state.widget.audience;
  final originalAudienceId = audience?.displayId;
  try {
    // Leave the main fullscreen Space untouched if the audience cannot move.
    if (audience != null) {
      await audience.cover(snapshot, presenter: target);
    }
    if (!state.mounted) {
      throw StateError('Presenter closed during display move');
    }
    state._displayGuard.arm();
    await moveToDisplay(target, previous: previous);
    if (state.mounted) {
      state._rebuild(() {
        state._displays = snapshot.displays;
      });
    }
  } catch (e) {
    try {
      if (audience != null) {
        final live = captureDisplaySnapshot();
        final original = live.find(previous.nativeId);
        final originalAudience = live.find(originalAudienceId);
        if (original == null || originalAudience == null) {
          throw StateError('Original display disappeared');
        }
        await audience.cover(
          live,
          presenter: original,
          target: originalAudience,
        );
      }
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
    final snapshot = captureDisplaySnapshot();
    if (!mounted) return;
    _rebuild(
      () => _displays = snapshot.canPresentAudience
          ? snapshot.displays
          : const [],
    );
  }

  Future<void> _cycleDisplay() async {
    if (_displayGuard.switching) return;
    final snapshot = captureDisplaySnapshot();
    if (!mounted) return;
    _rebuild(
      () => _displays = snapshot.canPresentAudience
          ? snapshot.displays
          : const [],
    );
    final target = snapshot.next();
    if (target == null) return;
    _onLaserMove(null);
    await _movePresenterToDisplay(this, snapshot, target);
  }
}
