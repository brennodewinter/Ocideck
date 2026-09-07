import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/ociserve_settings.dart';
import '../../../services/secret_store.dart';
import '../../../state/ociserve_provider.dart';
import '../../../theme/app_theme.dart';

/// Configuration and sign-in surface for the optional OciServe connector.
class OciServeModuleCard extends ConsumerStatefulWidget {
  const OciServeModuleCard({super.key});

  @override
  ConsumerState<OciServeModuleCard> createState() => _OciServeModuleCardState();
}

class _OciServeModuleCardState extends ConsumerState<OciServeModuleCard> {
  late final TextEditingController _server;
  late final FocusNode _serverFocus;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _server = TextEditingController(
      text: ref.read(ociServeProvider).settings.baseUrl,
    );
    _serverFocus = FocusNode();
  }

  @override
  void dispose() {
    _server.dispose();
    _serverFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final state = ref.watch(ociServeProvider);
    final settings = state.settings;
    if (!_serverFocus.hasFocus && _server.text != settings.baseUrl) {
      _server.value = TextEditingValue(
        text: settings.baseUrl,
        selection: TextSelection.collapsed(offset: settings.baseUrl.length),
      );
    }
    return Material(
      color: colors.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            value: settings.enabled,
            onChanged: state.status == OciServeStatus.loading
                ? null
                : (value) =>
                      ref.read(ociServeProvider.notifier).setEnabled(value),
            title: Text(
              l10n.d('OciServe'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              l10n.d(
                'Volg opleidingen uit uw OciServe-omgeving. Cursusbestanden openen alleen in afspeelmodus; voortgang wordt alleen na aanmelden gesynchroniseerd.',
              ),
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
            secondary: const Icon(Icons.school_outlined),
          ),
          if (settings.enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _details(context, l10n, state),
            ),
        ],
      ),
    );
  }

  Widget _details(
    BuildContext context,
    AppLocalizations l10n,
    OciServeState state,
  ) {
    final colors = Theme.of(context).colorScheme;
    final settings = state.settings;
    if (!platformCanStoreSecrets) {
      return Text(
        l10n.d(
          'OciServe-aanmelding is alleen beschikbaar in de desktop-app, omdat de webversie geen veilige sleutelbos heeft.',
        ),
        style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
      );
    }
    final busy = _saving || state.status == OciServeStatus.authenticating;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _server,
          focusNode: _serverFocus,
          enabled: !busy && !state.authenticated,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: l10n.d('OciServe-server'),
            hintText: l10n.d('https://leren.example.org'),
          ),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: settings.rememberLogin,
          onChanged: busy
              ? null
              : (value) =>
                    _save(settings.copyWith(rememberLogin: value ?? false)),
          title: Text(l10n.d('Ingelogd blijven op dit apparaat')),
          subtitle: Text(
            l10n.d(
              'Met deze keuze wordt het vernieuwtoken in de sleutelbos bewaard. Een versleutelde wachtrij voor nog niet verstuurde voortgang wordt daar los van bewaard.',
            ),
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: settings.trustedInternal,
          onChanged: busy || state.authenticated
              ? null
              : (value) =>
                    _save(settings.copyWith(trustedInternal: value ?? false)),
          title: Text(l10n.d('Vertrouwde interne server')),
          subtitle: Text(
            l10n.d(
              'Sta een HTTPS-server op een intern netwerk toe. Tokens worden nooit via gewone HTTP verzonden.',
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            l10n.d(
              'Bij het volgen van een cursus stuurt OciDeck uw laatste dia, voltooiing en getoonde tijd per dia naar de gekozen OciServe-organisatie. Antwoorden, notities en cursusinhoud worden niet als voortgang verstuurd.',
            ),
            style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant),
          ),
        ),
        if (state.errorCode != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorText(l10n, state.errorCode!),
            style: TextStyle(fontSize: 12, color: AppTheme.dangerFg),
          ),
        ],
        if (state.identityProviderHost case final host?)
          _identityProviderNotice(l10n, colors, host, busy),
        if (state.warningCode case final warning?) ...[
          const SizedBox(height: 8),
          Text(
            _warningText(l10n, warning),
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 12),
        if (state.authenticated) ...[
          Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 18,
                color: AppTheme.accentFg,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.account!.displayName.isEmpty
                      ? l10n.d('Ingelogd bij OciServe')
                      : l10n
                            .d('Ingelogd als {naam}')
                            .replaceAll('{naam}', state.account!.displayName),
                ),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => ref.read(ociServeProvider.notifier).logout(),
                child: Text(l10n.d('Uitloggen')),
              ),
            ],
          ),
          if (state.pendingReports > 0)
            Text(
              l10n
                  .d(
                    '{aantal} voortgangsrapport(en) wacht(en) op synchronisatie.',
                  )
                  .replaceAll('{aantal}', '${state.pendingReports}'),
              style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant),
            ),
        ] else
          Row(
            children: [
              FilledButton.icon(
                onPressed: busy ? null : () => _login(settings),
                icon: busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login, size: 18),
                label: Text(l10n.d('Inloggen')),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _save(OciServeSettings current) async {
    setState(() => _saving = true);
    try {
      await ref
          .read(ociServeProvider.notifier)
          .saveSettings(current.copyWith(baseUrl: _server.text));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _identityProviderNotice(
    AppLocalizations l10n,
    ColorScheme colors,
    String host,
    bool busy,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 8),
      Text(
        l10n
            .d(
              'Deze OciServe-server gebruikt {host} voor het aanmelden. Er worden pas gegevens met die identiteitsprovider uitgewisseld nadat u dit toestaat.',
            )
            .replaceAll('{host}', host),
        style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
      ),
      TextButton(
        onPressed: busy
            ? null
            : () => ref
                  .read(ociServeProvider.notifier)
                  .acceptIdentityProvider(host),
        child: Text(l10n.d('Deze identiteitsprovider toestaan')),
      ),
    ],
  );

  Future<void> _login(OciServeSettings current) async {
    await _save(current);
    if (!mounted) return;
    await ref.read(ociServeProvider.notifier).login();
  }

  String _errorText(AppLocalizations l10n, String code) => switch (code) {
    'https_required' => l10n.d('Gebruik een HTTPS-adres voor OciServe.'),
    'invalid_url' => l10n.d('Vul een geldig OciServe-adres in.'),
    'no_active_membership' => l10n.d(
      'Uw account hoort niet bij een actieve organisatie.',
    ),
    'logout_cleanup_failed' => l10n.d(
      'De lokale aanmelding kon niet volledig worden gewist. Probeer opnieuw.',
    ),
    _ => l10n.d(
      'Aanmelden bij OciServe is niet gelukt. Controleer de server en probeer opnieuw.',
    ),
  };

  String _warningText(AppLocalizations l10n, String code) => switch (code) {
    'pending_reports_not_discarded' => l10n.d(
      'De server is niet gewijzigd, omdat nog voortgang op verzending wacht.',
    ),
    'pending_reports_preserved' => l10n.d(
      'Nog niet verstuurde voortgang is op dit apparaat bewaard.',
    ),
    _ => l10n.d('Er wacht nog voortgang op synchronisatie.'),
  };
}
