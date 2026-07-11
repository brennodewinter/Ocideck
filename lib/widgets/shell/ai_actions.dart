part of '../app_shell.dart';

/// AI-related shell actions, split into a `part of` extension to keep
/// `app_shell_main_layout.dart` under the line limit. Same library, so it keeps
/// access to `_MainLayoutState`'s `context`/`ref`/`mounted`.
extension _MainLayoutAiActions on _MainLayoutState {
  /// Safety net (AI_ASSIST §6.4): wipe every still-unreviewed AI-generated image
  /// alt-text, keeping human-written and reviewed ones. Confirmed and undoable.
  Future<void> clearAiAltTexts() async {
    final l10n = context.l10n;
    final notifier = ref.read(deckProvider.notifier);
    final count = notifier.aiGeneratedAltTextCount;
    if (count == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.d('AI-alt-teksten wissen')),
        content: Text(
          '${l10n.d('Verwijder alle nog niet-nagekeken AI-alt-teksten? Handmatige en nagekeken alt-teksten blijven staan.')} '
          '(${l10n.d('aantal')}: $count)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.d('Wissen')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final cleared = notifier.clearAiGeneratedAltTexts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$cleared ${l10n.d('AI-alt-teksten gewist.')}')),
    );
  }
}
