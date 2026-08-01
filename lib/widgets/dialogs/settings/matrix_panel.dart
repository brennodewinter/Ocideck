// Het Matrix-paneel van het instellingenvenster: het app-globale account voor
// realtime samenwerken (SELF_ENCRYPTED_RELAY.md §6, §8). Spiegelt [GitPanel] in
// vorm, maar de invulstroom is bewust anders (besluit 2026-08-01): de app raakt
// nooit een wachtwoord aan. De gebruiker plakt de homeserver en een elders
// aangemaakt access-token; "Verbinding testen" bevestigt het token via `whoami`
// en vult daarmee de user-id én — belangrijk — de device-id in. Die laatste is
// niet vrij te kiezen: de sleutel-uitwisseling adresseert een to-device-bericht
// op `user-id:device-id`, dus een verkeerd device-id laat een mede-auteur stil
// buiten de sessie vallen (§4.3).
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../collab/collab_device_store.dart';
import '../../../collab/collab_recovery_key.dart';
import '../../../collab/matrix_client.dart';
import '../../../models/matrix_settings.dart';
import '../../../services/secret_store.dart';
import '../../../state/matrix_client_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/log.dart';
import '../recovery_key_dialogs.dart';
import 'matrix_form.dart';
import 'settings_section_title.dart';
import 'settings_text_field.dart';

/// Bouwt een client voor de verbindingstest. Injecteerbaar zodat een widgettest
/// de test-knop kan uitoefenen zonder socket; standaard de echte transport.
typedef MatrixTestClientBuilder =
    MatrixClient Function(MatrixServer account, String? token);

class MatrixPanel extends StatefulWidget {
  /// Wat het paneel bewerkt. Eigendom van het venster, zodat een half ingevuld
  /// account het dichtklappen van dit paneel overleeft.
  final MatrixForm form;

  /// Overschrijft de clientbouwer voor de verbindingstest. Alleen voor tests.
  final MatrixTestClientBuilder? buildTestClient;

  /// Overschrijft [platformCanStoreSecrets] voor het tokenveld. Alleen voor tests.
  final bool? canStore;

  /// De sleutelhanger voor de herstelsleutel-stroom. Injecteerbaar voor tests;
  /// standaard de echte [SecretStore].
  final SecretStore? secretStore;

  const MatrixPanel({
    super.key,
    required this.form,
    this.buildTestClient,
    this.canStore,
    this.secretStore,
  });

  @override
  State<MatrixPanel> createState() => _MatrixPanelState();
}

class _MatrixPanelState extends State<MatrixPanel> {
  MatrixForm get _form => widget.form;

  @override
  void initState() {
    super.initState();
    // The recovery section appears once homeserver/user/device are filled, so
    // the panel must rebuild as those fields change (whether typed or filled by
    // the connection test). The form owns the controllers; we only listen.
    for (final c in [_form.homeserver, _form.userId, _form.deviceId]) {
      c.addListener(_onAccountFieldChanged);
    }
  }

  @override
  void dispose() {
    for (final c in [_form.homeserver, _form.userId, _form.deviceId]) {
      c.removeListener(_onAccountFieldChanged);
    }
    super.dispose();
  }

  void _onAccountFieldChanged() {
    if (mounted) setState(() {});
  }

  MatrixClient _client(MatrixServer account, String? token) =>
      (widget.buildTestClient ??
      (a, t) => buildMatrixClient(account: a, token: t))(account, token);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionTitle(l10n.d('Realtime samenwerken (Matrix)')),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            l10n.d(
              'Werk live samen aan een presentatie via een Matrix-homeserver als versleutelde doorgeefluik. De inhoud wordt end-to-end versleuteld met OciDecks eigen sleutels; de server ziet alleen versleutelde gegevens. Vul een homeserver en een elders aangemaakt access-token in — OciDeck vraagt nooit om je wachtwoord. Het token wordt versleuteld in de sleutelhanger bewaard, niet bij de overige instellingen.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ),
        SettingsTextField(
          _form.homeserver,
          l10n.d('Homeserver'),
          hint: l10n.d('https://matrix.example.org'),
          icon: Icons.dns_outlined,
        ),
        SettingsSecretField(
          _form.token.field,
          l10n.d('Access-token'),
          canStore: widget.canStore,
        ),
        _tokenHelp(l10n),
        const SizedBox(height: 8),
        _testRow(l10n),
        const SizedBox(height: 12),
        // Ingevuld door de verbindingstest, maar bewerkbaar voor wie zijn
        // homeserver anders adresseert dan whoami teruggeeft.
        SettingsTextField(
          _form.userId,
          l10n.d('Gebruikers-id'),
          hint: l10n.d('@jij:matrix.example.org'),
          icon: Icons.person_outline,
        ),
        SettingsTextField(
          _form.deviceId,
          l10n.d('Apparaat-id'),
          hint: l10n.d('wordt door de test ingevuld'),
          icon: Icons.devices_outlined,
        ),
        CheckboxListTile(
          value: _form.trusted,
          onChanged: (v) => setState(() {
            _form.trusted = v ?? false;
            _form.clearTestResult();
          }),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: Text(
            l10n.d('Vertrouwde interne server'),
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: Text(
            l10n.d(
              'Nodig wanneer de homeserver op een privé- of thuisnetwerk draait. Zonder deze vlag weigert de beveiliging een privé-adres.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ),
        _recoverySection(l10n),
      ],
    );
  }

  SecretStore get _secrets => widget.secretStore ?? SecretStore();

  /// The identity recovery-key controls (Blok B). Shown once the account is
  /// filled in — a device id is needed to mint or restore an identity, and it is
  /// the connection test that fills it. Before that there is nothing to back up.
  Widget _recoverySection(AppLocalizations l10n) {
    final ready =
        _form.homeserver.text.trim().isNotEmpty &&
        _form.userId.text.trim().isNotEmpty &&
        _form.deviceId.text.trim().isNotEmpty;
    if (!ready) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSectionTitle(l10n.d('Identiteit & herstelsleutel')),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              l10n.d(
                'Je apparaat heeft een eigen samenwerkingsidentiteit — dat is wat mede-auteurs verifiëren. Bewaar de herstelsleutel om diezelfde identiteit later op een ander apparaat terug te zetten; zonder die sleutel begin je daar opnieuw.',
              ),
              style: TextStyle(fontSize: 11, color: AppTheme.slate400),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.vpn_key_outlined, size: 16),
                onPressed: _showRecoveryKey,
                label: Text(l10n.d('Herstelsleutel tonen')),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.settings_backup_restore, size: 16),
                onPressed: _restoreIdentity,
                label: Text(l10n.d('Identiteit herstellen')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Ensure this account has an identity (mint one if absent), then show its
  /// recovery key to save.
  Future<void> _showRecoveryKey() async {
    final l10n = context.l10n;
    final homeserver = _form.homeserver.text.trim();
    final userId = _form.userId.text.trim();
    final deviceId = _form.deviceId.text.trim();
    try {
      // Minting if absent is what makes "show me my recovery key" work before the
      // first session; a later session reuses the very same seeds (same device id).
      await loadOrCreateDeviceKeys(
        secretStore: _secrets,
        homeserver: homeserver,
        userId: userId,
        deviceId: deviceId,
      );
      final seeds = await readDeviceSeeds(
        secretStore: _secrets,
        homeserver: homeserver,
        userId: userId,
      );
      if (!mounted || seeds == null) return;
      await showRecoveryKeyDialog(context, l10n, seeds.recoveryKey());
    } catch (e) {
      logError('MatrixPanel._showRecoveryKey failed', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.d('De herstelsleutel kon niet worden gelezen.')),
          ),
        );
      }
    }
  }

  /// Prompt for a recovery key and restore the identity from it, mapping a
  /// malformed key to a plain message rather than a stack trace.
  Future<void> _restoreIdentity() async {
    final l10n = context.l10n;
    final key = await promptRecoveryKey(context, l10n);
    if (key == null || !mounted) return;
    try {
      await importRecoveryKey(
        secretStore: _secrets,
        homeserver: _form.homeserver.text.trim(),
        userId: _form.userId.text.trim(),
        deviceId: _form.deviceId.text.trim(),
        recoveryKey: key,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.d('Identiteit hersteld.'))));
      }
    } on RecoveryKeyException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_recoveryError(l10n, e.reason))));
      }
    }
  }

  String _recoveryError(
    AppLocalizations l10n,
    RecoveryKeyError reason,
  ) => switch (reason) {
    RecoveryKeyError.checksum => l10n.d(
      'Deze herstelsleutel klopt niet — controleer of je hem volledig en foutloos hebt overgenomen.',
    ),
    RecoveryKeyError.format => l10n.d('Dit lijkt geen geldige herstelsleutel.'),
    RecoveryKeyError.version => l10n.d(
      'Deze herstelsleutel komt uit een nieuwere versie van OciDeck.',
    ),
  };

  Widget _tokenHelp(AppLocalizations l10n) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 14, color: AppTheme.slate400),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            l10n.d(
              'Maak een access-token aan in je Matrix-client (bijvoorbeeld in Element onder Alle instellingen → Hulp & info), of op je homeserver. "Verbinding testen" bevestigt het token en vult je gebruikers-id en apparaat-id in.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ),
      ],
    ),
  );

  Widget _testRow(AppLocalizations l10n) {
    final message = _form.testMessage;
    final (Color color, IconData icon) = _form.testOk == true
        ? (AppTheme.tealFg, Icons.check_circle)
        : (AppTheme.danger600, Icons.error_outline);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ElevatedButton.icon(
          onPressed: _form.testing ? null : _test,
          icon: _form.testing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.wifi_tethering, size: 16),
          label: Text(l10n.d('Verbinding testen')),
        ),
        if (_form.testOk != null && message != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(fontSize: 12, color: color),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Bevestig het token via `whoami` en vul user-id + device-id in.
  Future<void> _test() async {
    final l10n = context.l10n;
    final account = _form.config;
    if (account.origin == null) {
      setState(() {
        _form.testOk = false;
        _form.testMessage = l10n.d('Vul een geldige homeserver-URL in');
      });
      return;
    }
    if (_form.token.field.text.trim().isEmpty) {
      setState(() {
        _form.testOk = false;
        _form.testMessage = l10n.d('Vul een access-token in');
      });
      return;
    }
    setState(() {
      _form.testing = true;
      _form.clearTestResult();
    });
    String? error;
    MatrixWhoami? who;
    try {
      who = await _client(account, _form.token.field.text.trim()).whoami();
    } on MatrixException catch (e) {
      error = _errorText(l10n, e);
    } catch (e, st) {
      logError('SettingsDialog: matrix-verbindingstest', e, st);
      error = l10n.d('Verbinding mislukt');
    }
    if (!mounted) return;
    setState(() {
      _form.testing = false;
      _form.testOk = error == null;
      if (who != null) {
        _form.userId.text = who.userId;
        final device = who.deviceId;
        if (device != null) _form.deviceId.text = device;
        _form.testMessage = device == null
            ? l10n.d(
                'Verbinding gelukt, maar de homeserver gaf geen apparaat-id terug — vul die zelf in, anders komen sleutels van mede-auteurs niet aan.',
              )
            : l10n.d(
                'Verbinding gelukt — gebruikers-id en apparaat-id ingevuld',
              );
      } else {
        _form.testMessage = error;
      }
    });
  }

  String _errorText(AppLocalizations l10n, MatrixException e) {
    return switch (e.kind) {
      MatrixErrorKind.auth => l10n.d(
        'Het access-token wordt geweigerd — controleer of je het goed hebt overgenomen en of het niet is ingetrokken.',
      ),
      MatrixErrorKind.forbidden => l10n.d('De homeserver weigert dit token.'),
      MatrixErrorKind.notFound => l10n.d(
        'Dit adres antwoordt niet als een Matrix-homeserver. Klopt de URL?',
      ),
      MatrixErrorKind.rateLimited => l10n.d(
        'De homeserver vraagt om even te wachten. Probeer het zo opnieuw.',
      ),
      MatrixErrorKind.redirect => l10n.d(
        'De homeserver stuurt door naar een ander adres — dat wordt om veiligheidsredenen niet gevolgd. Vul het uiteindelijke adres rechtstreeks in.',
      ),
      MatrixErrorKind.config => l10n.d(
        'Een homeserver moet https zijn: het access-token reist bij elk verzoek mee.',
      ),
      MatrixErrorKind.network => l10n.d(
        'De homeserver is niet bereikbaar, of het certificaat wordt niet vertrouwd.',
      ),
      MatrixErrorKind.server => l10n.d(
        'De homeserver gaf een fout. Probeer het later opnieuw.',
      ),
    };
  }
}
