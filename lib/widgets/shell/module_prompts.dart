part of '../app_shell.dart';

extension _ModulePrompts on _AppShellState {
  void _listenImprovementModulePrompt(BuildContext context) {
    ref.listen<ImprovementModulePrompt?>(improvementModulePromptProvider, (
      _,
      prompt,
    ) {
      if (prompt == null) return;
      ref.read(improvementModulePromptProvider.notifier).state = null;
      final mod = ref.read(procesverbeteringProvider);
      if (mod.loading || mod.enabled) return;
      final l10n = context.l10n;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentMaterialBanner();
      _improvementPromptTabId = prompt.tabId;
      messenger.showMaterialBanner(
        MaterialBanner(
          content: Text(
            l10n.d(
              'Deze presentatie bevat onderdelen van de Procesverbetering-module. Zet de module aan om ze te bewerken.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: _showImprovementSlide,
              child: Text(l10n.d('Naar de slide')),
            ),
            TextButton(
              onPressed: () {
                _hideImprovementBanner();
                ref.read(procesverbeteringProvider.notifier).enable();
              },
              child: Text(l10n.d('Inschakelen')),
            ),
            IconButton(
              tooltip: l10n.d('Sluiten'),
              icon: const Icon(Icons.close),
              onPressed: _hideImprovementBanner,
            ),
          ],
        ),
      );
    });
  }

  void _showImprovementSlide() {
    final tab = ref.read(tabsProvider).current;
    if (tab == null || tab.id != _improvementPromptTabId) return;
    if (!tab.deckNotifier.mounted) return;
    final index =
        tab.deckNotifier.currentState.deck?.firstImprovementSlideIndex ?? -1;
    if (index < 0) return;
    tab.editorNotifier.select(index);
  }

  void _hideImprovementBanner() {
    if (_improvementPromptTabId == null) return;
    _improvementPromptTabId = null;
    ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
  }

  void _syncImprovementBannerWithTabs(TabsState tabs) {
    if (_improvementPromptTabId == null) return;
    final current = tabs.current;
    if (current == null ||
        current.id != _improvementPromptTabId ||
        !current.isOpen ||
        !current.deckNotifier.mounted) {
      _hideImprovementBanner();
      return;
    }
    final deck = current.deckNotifier.currentState.deck;
    if (deck == null || !deck.hasImprovementSlides) _hideImprovementBanner();
  }
}
