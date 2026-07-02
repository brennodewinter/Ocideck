// Part of the app_shell library — see ../app_shell.dart.
// Split out for navigability; all imports live in the main library file.
part of '../app_shell.dart';

class _DeckStatusBar extends StatelessWidget {
  final Deck deck;
  final DeckState deckState;
  final String? exportDirectory;
  final Future<void> Function() onSave;
  final VoidCallback? onExport;
  final String exportTooltip;

  const _DeckStatusBar({
    required this.deck,
    required this.deckState,
    required this.exportDirectory,
    required this.onSave,
    required this.onExport,
    required this.exportTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final skipped = deck.slides.where((s) => s.skipped).length;
    final fileLabel = deckState.filePath == null
        ? l10n.t('notSavedYet')
        : p.basename(deckState.filePath!);
    final saveLabel = deckState.isDirty ? l10n.t('unsaved') : l10n.t('saved');
    final exportLabel = exportDirectory == null
        ? l10n.t('exportNextToDeck')
        : '${l10n.t('exportFolder')}: ${p.basename(exportDirectory!)}';

    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            _StatusAction(
              icon: deckState.isDirty
                  ? Icons.radio_button_checked
                  : Icons.check_circle_outline,
              label: saveLabel,
              tooltip: deckState.isDirty
                  ? l10n.t('unsavedChanges')
                  : l10n.t('noUnsavedChanges'),
              color: deckState.isDirty
                  ? const Color(0xFFD97706)
                  : const Color(0xFF15803D),
              onTap: () => onSave(),
            ),
            const _StatusDivider(),
            _StatusItem(
              icon: Icons.description_outlined,
              label: fileLabel,
              tooltip: deckState.filePath ?? l10n.t('noFileYet'),
            ),
            const _StatusDivider(),
            _StatusItem(
              icon: Icons.slideshow_outlined,
              label: skipped == 0
                  ? '${deck.slides.length} ${l10n.t('slides')}'
                  : '${deck.slides.length} ${l10n.t('slides')} · $skipped ${l10n.t('skipped')}',
              tooltip: skipped == 0
                  ? l10n.t('allSlidesIncluded')
                  : '$skipped ${l10n.t('skippedSlidesExcluded')}',
              color: skipped == 0 ? null : const Color(0xFF8A6D3B),
            ),
            const _StatusDivider(),
            _StatusItem(
              icon: Icons.palette_outlined,
              label: deck.themeProfile.name,
              tooltip: '${l10n.t('styleProfile')}: ${deck.themeProfile.name}',
            ),
            if (deck.tlp != TlpLevel.none) ...[
              const _StatusDivider(),
              _StatusItem(
                icon: Icons.shield_outlined,
                label: deck.tlp.label,
                tooltip: '${l10n.t('classification')}: ${deck.tlp.label}',
                color: Color(deck.tlp.foreground),
              ),
            ],
            const Spacer(),
            _StatusItem(
              icon: Icons.folder_outlined,
              label: exportLabel,
              tooltip: exportDirectory ?? l10n.t('exportsNextToDeck'),
            ),
            const SizedBox(width: 6),
            _StatusAction(
              icon: Icons.upload_file_outlined,
              label: l10n.t('export'),
              tooltip: exportTooltip,
              onTap: onExport,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final Color? color;

  const _StatusItem({
    required this.icon,
    required this.label,
    required this.tooltip,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fg = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 210),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: fg,
                fontWeight: color == null ? FontWeight.normal : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final Color? color;
  final VoidCallback? onTap;

  const _StatusAction({
    required this.icon,
    required this.label,
    required this.tooltip,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = enabled
        ? (color ?? Theme.of(context).colorScheme.secondary)
        : Theme.of(context).disabledColor;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: fg),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: fg,
                  fontWeight: enabled ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusDivider extends StatelessWidget {
  const _StatusDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 14,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

/// Dunne verticale scheiding tussen groepen AppBar-knoppen.
class _ActionsDivider extends StatelessWidget {
  const _ActionsDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Colors.white24,
    );
  }
}

/// TLP-classificatie als altijd zichtbare, direct instelbare chip in de
/// AppBar-titel. Toont de huidige status in de officiële TLP-kleur en opent
/// bij klikken een keuzelijst met alle niveaus (incl. "Geen").
class _TlpChip extends StatelessWidget {
  final TlpLevel tlp;
  final bool warnUnset;
  final ValueChanged<TlpLevel> onSelected;

  const _TlpChip({
    required this.tlp,
    this.warnUnset = false,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isSet = tlp != TlpLevel.none;
    final fg = Color(tlp.foreground);
    final borderColor = warnUnset
        ? const Color(0xFFF59E0B)
        : (isSet ? fg.withValues(alpha: 0.7) : Colors.white24);

    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: isSet
            ? Colors.black
            : (warnUnset ? Colors.black45 : Colors.transparent),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: warnUnset ? 1.5 : 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isSet)
            const Icon(Icons.shield_outlined, size: 14, color: Colors.white70),
          if (!isSet) const SizedBox(width: 5),
          Text(
            isSet ? tlp.label : 'TLP',
            style: TextStyle(
              color: isSet ? fg : Colors.white70,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
              letterSpacing: 0.3,
            ),
          ),
          Icon(
            Icons.arrow_drop_down,
            size: 16,
            color: isSet ? fg : Colors.white54,
          ),
        ],
      ),
    );

    return PopupMenuButton<TlpLevel>(
      tooltip: warnUnset
          ? l10n.d(
              'Stel een TLP-niveau in — export is geblokkeerd door het classificatiebeleid.',
            )
          : l10n.d('TLP-classificatie (Traffic Light Protocol)'),
      position: PopupMenuPosition.under,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final level in TlpLevel.values)
          PopupMenuItem<TlpLevel>(
            value: level,
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: level == TlpLevel.none
                        ? Colors.transparent
                        : Color(level.foreground),
                    border: Border.all(color: AppTheme.slate400),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Text(level == TlpLevel.none ? l10n.d('Geen') : level.label),
                if (level == tlp) ...[
                  const SizedBox(width: 12),
                  const Spacer(),
                  const Icon(Icons.check, size: 16, color: AppTheme.slate600),
                ],
              ],
            ),
          ),
      ],
      child: child,
    );
  }
}
