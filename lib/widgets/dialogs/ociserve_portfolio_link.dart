import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ociserve_portfolio.dart';
import '../../theme/app_theme.dart';

/// De portefeuille-koppeling — stap 1: verbinden, stap 2: kiezen wat je deelt.
///
/// OciServe#524 definieert het server-protocol. Tot die tijd toont dit
/// widget een "nog niet beschikbaar" status, zodat de cursist weet dat
/// de functie bestaat maar nog niet actief is.
///
/// Ontwerpregels:
/// - Niet zoeken op e-mailadres — dat lekt persoonsgegevens naar de provider.
/// - Tweestaps: eerst verbinden, dan pas kiezen wat je deelt.
/// - De cursist ziet altijd wat hij al deelt en kan het intrekken.
class OciServePortfolioLink extends StatefulWidget {
  const OciServePortfolioLink({super.key, required this.connection});

  final PortfolioConnection connection;

  @override
  State<OciServePortfolioLink> createState() => _OciServePortfolioLinkState();
}

class _OciServePortfolioLinkState extends State<OciServePortfolioLink> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return switch (widget.connection.state) {
      PortfolioConnectionState.unavailable => _unavailable(l10n, theme),
      PortfolioConnectionState.disconnected => _disconnected(l10n, theme),
      PortfolioConnectionState.connecting => _connecting(l10n, theme),
      PortfolioConnectionState.connected => _connected(l10n, theme),
      PortfolioConnectionState.revoked => _revoked(l10n, theme),
    };
  }

  Widget _unavailable(AppLocalizations l10n, ThemeData theme) {
    final palette = AppPalette.of(theme);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        children: [
          Icon(
            Icons.link_off_outlined,
            size: 48,
            color: palette.accentInk.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.d('Portefeuille koppelen'),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.d(
              'U kunt bewijs uit een externe portefeuille (zoals EduBadges) '
              'koppelen aan uw account. Deze functie is nog niet beschikbaar '
              'voor uw organisatie.',
            ),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.accentInk.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _disconnected(AppLocalizations l10n, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Portefeuille koppelen'),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.d(
            'Koppel een externe portefeuille om uw bestaande badges en '
            'certificaten te gebruiken als bewijs. U kiest zelf wat u deelt.',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => _showConnectStep(l10n, theme),
          icon: const Icon(Icons.link_outlined),
          label: Text(l10n.d('Portefeuille verbinden')),
        ),
      ],
    );
  }

  Widget _connecting(AppLocalizations l10n, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Portefeuille koppelen'),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(l10n.d('Verbinding maken…')),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l10n.d(
            'Sluit het venster van de portefeuilleprovider af om verder te gaan.',
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _connected(AppLocalizations l10n, ThemeData theme) {
    final palette = AppPalette.of(theme);
    final selected = widget.connection.selectedCredentials;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.link_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              l10n.d('Verbonden met {provider}').replaceAll(
                '{provider}',
                widget.connection.providerName.isEmpty
                    ? l10n.d('portefeuille')
                    : widget.connection.providerName,
              ),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _showRevokeConfirm(l10n, theme),
              icon: const Icon(Icons.link_off_outlined, size: 18),
              label: Text(l10n.d('Verbinding verbreken')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (widget.connection.credentials.isEmpty)
          Text(
            l10n.d('Geen credentials gevonden in deze portefeuille.'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: palette.accentInk.withValues(alpha: 0.6),
            ),
          )
        else ...[
          Text(
            l10n.d('Kies welke credentials u deelt als bewijs:'),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          for (final cred in widget.connection.credentials) ...[
            _credentialCard(l10n, theme, cred),
            const SizedBox(height: 8),
          ],
          if (selected.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n.d('{aantal} credential(s) geselecteerd om te delen').replaceAll(
                '{aantal}',
                selected.length.toString(),
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _credentialCard(
    AppLocalizations l10n,
    ThemeData theme,
    PortfolioCredential cred,
  ) {
    final palette = AppPalette.of(theme);
    final locale = MaterialLocalizations.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: CheckboxListTile(
        value: cred.selected,
        onChanged: (value) => setState(() {}),
        title: Text(cred.title, style: theme.textTheme.bodyMedium),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cred.issuer,
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.accentInk.withValues(alpha: 0.6),
              ),
            ),
            if (cred.expiresAt != null)
              Text(
                l10n
                    .d('Geldig tot {datum}')
                    .replaceAll('{datum}', locale.formatFullDate(cred.expiresAt!)),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cred.isActive
                      ? palette.accentInk.withValues(alpha: 0.6)
                      : theme.colorScheme.error,
                ),
              ),
          ],
        ),
        secondary: Icon(
          cred.isActive ? Icons.verified_outlined : Icons.warning_amber_outlined,
          color: cred.isActive
              ? theme.colorScheme.primary
              : theme.colorScheme.error,
        ),
      ),
    );
  }

  Widget _revoked(AppLocalizations l10n, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d('Portefeuille koppelen'),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.d('De verbinding is verbroken. U kunt opnieuw verbinden.'),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => _showConnectStep(l10n, theme),
          icon: const Icon(Icons.link_outlined),
          label: Text(l10n.d('Opnieuw verbinden')),
        ),
      ],
    );
  }

  // — Two-step consent flow —

  void _showConnectStep(AppLocalizations l10n, ThemeData theme) {
    // Step 1: explain what connecting means, then proceed to step 2.
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.d('Portefeuille verbinden')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.d(
                'U wordt doorgestuurd naar de portefeuilleprovider om in te loggen. '
                'OciDeck ontvangt geen wachtwoord en zoekt niet op e-mailadres.',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.d(
                'Na het inloggen kiest u in de volgende stap welke credentials u deelt. '
                'U kunt de verbinding altijd weer verbreken.',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _showChooseStep(l10n, theme);
            },
            child: Text(l10n.d('Doorgaan')),
          ),
        ],
      ),
    );
  }

  void _showChooseStep(AppLocalizations l10n, ThemeData theme) {
    // Step 2: choose what to share. This is the actual consent.
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.d('Kies wat u deelt')),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.d(
                  'Selecteer de credentials die u als bewijs wilt delen. '
                  'Niet-geselecteerde credentials blijven in uw portefeuille '
                  'maar worden niet gedeeld met deze organisatie.',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.d(
                  'Deze functie is nog niet beschikbaar. '
                  'U kunt dit venster sluiten.',
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.t('close')),
          ),
        ],
      ),
    );
  }

  void _showRevokeConfirm(AppLocalizations l10n, ThemeData theme) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.d('Verbinding verbreken?')),
        content: Text(
          l10n.d(
            'U deelt dan geen credentials meer vanuit deze portefeuille. '
            'Eerder aangeleverd bewijs blijft staan.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
            ),
            child: Text(l10n.d('Verbreken')),
          ),
        ],
      ),
    );
  }
}
