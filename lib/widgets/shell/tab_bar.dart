// Part of the app_shell library — see ../app_shell.dart.
// Split out for navigability; all imports live in the main library file.
part of '../app_shell.dart';

class _AppTabBar extends StatelessWidget {
  final TabsState tabsState;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;
  final VoidCallback onAdd;

  const _AppTabBar({
    required this.tabsState,
    required this.onSelect,
    required this.onClose,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = Theme.of(context).extension<AppPalette>()!;
    return Container(
      height: 36,
      color: palette.panel,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < tabsState.tabs.length; i++)
                    _TabChip(
                      tab: tabsState.tabs[i],
                      isActive: i == tabsState.clampedIndex,
                      showClose:
                          tabsState.tabs.length > 1 || tabsState.tabs[i].isOpen,
                      panelText: palette.panelText,
                      accent: Theme.of(context).colorScheme.secondary,
                      onTap: () => onSelect(i),
                      onClose: () => onClose(i),
                    ),
                ],
              ),
            ),
          ),
          Tooltip(
            message: l10n.t('newTab'),
            child: InkWell(
              onTap: onAdd,
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(
                  Icons.add,
                  size: 16,
                  color: palette.panelText.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final TabInfo tab;
  final bool isActive;
  final bool showClose;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final Color panelText;
  final Color accent;

  const _TabChip({
    required this.tab,
    required this.isActive,
    required this.showClose,
    required this.onTap,
    required this.onClose,
    required this.panelText,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 80, maxWidth: 200),
        height: 36,
        decoration: BoxDecoration(
          color: isActive
              ? panelText.withValues(alpha: 0.12)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isActive ? accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tab.isDirty)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 5),
                decoration: const BoxDecoration(
                  color: Colors.orangeAccent,
                  shape: BoxShape.circle,
                ),
              ),
            Flexible(
              child: Text(
                tab.label,
                style: TextStyle(
                  fontSize: 12,
                  color: isActive
                      ? panelText
                      : panelText.withValues(alpha: 0.72),
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (showClose) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: onClose,
                borderRadius: BorderRadius.circular(3),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.close,
                    size: 12,
                    color: panelText.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Per-tab content ───────────────────────────────────────────────────────────

class _TabContent extends ConsumerWidget {
  const _TabContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOpen = ref.watch(deckProvider.select((s) => s.isOpen));
    if (!isOpen) return const _WelcomeScreen();
    return _MainLayout(exportService: ExportService());
  }
}

// ── Welcome screen ────────────────────────────────────────────────────────────
