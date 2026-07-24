// Part of the fullscreen_presenter library — see ../fullscreen_presenter.dart.
// Split out for navigability (toetstabel, wakelock-hulpjes en de twee kleine
// knop-/labelwidgets); all imports live in the main library file.
part of '../fullscreen_presenter.dart';

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
            color: enabled ? PresenterPalette.text : PresenterPalette.surface4,
            size: 24,
          ),
        ),
      ),
    );
  }
}
