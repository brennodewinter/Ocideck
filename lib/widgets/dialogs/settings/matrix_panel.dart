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
import '../../../collab/matrix_client.dart';
import '../../../models/matrix_settings.dart';
import '../../../state/matrix_client_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/log.dart';
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

  const MatrixPanel({
    super.key,
    required this.form,
    this.buildTestClient,
    this.canStore,
  });

  @override
  State<MatrixPanel> createState() => _MatrixPanelState();
}

class _MatrixPanelState extends State<MatrixPanel> {
  MatrixForm get _form => widget.form;

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
      ],
    );
  }

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
