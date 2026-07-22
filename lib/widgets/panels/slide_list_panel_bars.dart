// Part of the slide_list_panel library — see slide_list_panel.dart.
// Split out for navigability (skip banner & bulk-action bar); all imports
// live in the main library file. Top-level widgets relocate verbatim.
part of 'slide_list_panel.dart';

/// Smalle balk bovenin de slidelijst die toont hoeveel slides overgeslagen
/// worden, met één knop om alle markeringen ineens te wissen.
class _SkipBanner extends StatelessWidget {
  final int count;
  final VoidCallback onClearAll;

  const _SkipBanner({required this.count, required this.onClearAll});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 4, 5),
      decoration: BoxDecoration(
        color: AppTheme.goldOverlay,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.goldDark),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.visibility_off_outlined,
            size: 13,
            color: AppTheme.gold,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              count == 1
                  ? l10n.d('1 slide overgeslagen')
                  : '$count ${l10n.d('slides overgeslagen')}',
              style: const TextStyle(
                color: AppTheme.goldSoft,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: onClearAll,
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.gold,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              minimumSize: const Size(0, 26),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(l10n.d('Alles tonen')),
          ),
        ],
      ),
    );
  }
}

/// Balk voor dia's die worden achtergehouden omdat hun TLP-classificatie
/// strenger is dan die van de presentatie.
///
/// Bewust een eigen balk naast [_SkipBanner] en niet dezelfde teller: dit is
/// geen keuze die de auteur per dia maakte, maar een gevolg van het
/// classificatiebeleid — beide standaardwaarden zijn `TlpLevel.none`, dus één
/// dia op AMBER verdwijnt uit een deck waarvan het deckniveau nooit is gezet.
/// Er zit geen knop op: het deckniveau verhogen is een classificatiebeslissing
/// die in Presentatie-info hoort, niet een opruimhandeling in een zijbalk.
class _WithheldBanner extends StatelessWidget {
  final int count;

  const _WithheldBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Tooltip(
      message: l10n.d(
        'Deze slides gaan niet mee bij presenteren, exporteren of in het pakket. Verhoog het TLP-niveau van de presentatie bij Presentatie-info om ze mee te nemen.',
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
        decoration: BoxDecoration(
          color: AppTheme.badgeErrorOverlay.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.badgeErrorOverlay),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_outline, size: 13, color: Colors.white),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                count == 1
                    ? l10n.d('1 slide achtergehouden door haar TLP')
                    : '$count ${l10n.d('slides achtergehouden door hun TLP')}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Bulk-actiebalk (meervoudige selectie) ─────────────────────────────────────

class _BulkActionBar extends StatelessWidget {
  final int count;
  final VoidCallback onCopyToDeck;
  final VoidCallback onDelete;
  final VoidCallback onSkip;
  final VoidCallback onShow;
  final VoidCallback onDeselect;

  const _BulkActionBar({
    required this.count,
    required this.onCopyToDeck,
    required this.onDelete,
    required this.onSkip,
    required this.onShow,
    required this.onDeselect,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppTheme.tealOverlay,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$count ${l10n.d('geselecteerd')}',
              style: TextStyle(
                color: AppTheme.slate200,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _BulkIcon(
            icon: Icons.drive_file_move_outline,
            tooltip: l10n.d('Kopiëren naar ander deck'),
            onTap: onCopyToDeck,
          ),
          _BulkIcon(
            icon: Icons.visibility_off_outlined,
            tooltip: l10n.d('Overslaan bij presenteren/exporteren'),
            onTap: onSkip,
          ),
          _BulkIcon(
            icon: Icons.visibility_outlined,
            tooltip: l10n.d('Weer tonen'),
            onTap: onShow,
          ),
          _BulkIcon(
            icon: Icons.delete_outline,
            tooltip: l10n.d('Verwijderen'),
            color: AppTheme.coral,
            onTap: onDelete,
          ),
          _BulkIcon(
            icon: Icons.close,
            tooltip: l10n.d('Selectie opheffen'),
            onTap: onDeselect,
          ),
        ],
      ),
    );
  }
}

class _BulkIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  const _BulkIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 16),
        onPressed: onTap,
        color: color ?? AppTheme.slate300,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
