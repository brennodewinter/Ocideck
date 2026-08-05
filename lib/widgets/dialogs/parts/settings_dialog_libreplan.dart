// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (the LibrePlan-connector tab). Instance
// methods live in an extension on _SettingsDialogState — same library, same
// members.
part of '../settings_dialog.dart';

extension _SettingsLibreplan on _SettingsDialogState {
  /// Initialiseer de LibrePlan-velden vanuit de opgeslagen instellingen.
  /// Laadt het wachtwoord asynchroon uit de keychain (zelfde patroon als AI).
  void _initLibreplanFields(LibreplanSettings lp) {
    _libreplanEnabled = lp.enabled;
    _libreplanBaseUrl = TextEditingController(text: lp.baseUrl);
    _libreplanUsername = TextEditingController(text: lp.username);
    _libreplanTrustedInternal = lp.trustedInternal;
    if (!lp.hasBackend) return;
    final key = SecretStore.libreplanKey(lp.baseUrl, lp.username);
    ref.read(settingsProvider.notifier).readLibreplanPassword(key).then((pass) {
      if (mounted && pass != null) {
        _rebuild(() => _libreplanPassword.text = pass);
      }
    });
  }

  Widget _libreplanTab() {
    final l10n = context.l10n;
    if (isWebPlatform) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(l10n.d('LibrePlan-connector')),
          Text(
            l10n.d(
              'De LibrePlan-connector is alleen beschikbaar in de desktopversie.',
            ),
            style: const TextStyle(fontSize: 12, height: 1.4),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d(
            'LibrePlan-connector is optioneel en staat standaard uit. Er wordt niets opgehaald totdat u dit inschakelt en zelf een server configureert. Alleen-lezen: de connector schrijft niets terug naar LibrePlan. Het wachtwoord wordt in de sleutelhanger van uw besturingssysteem opgeslagen, niet in het deck.',
          ),
          style: const TextStyle(fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 16),
        _libreplanForm(l10n),
      ],
    );
  }

  Widget _libreplanForm(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsTextField(
          _libreplanBaseUrl,
          l10n.d('Server-URL'),
          hint: l10n.d('https://libreplan.example.org/libreplan/'),
        ),
        const SizedBox(height: 12),
        SettingsTextField(
          _libreplanUsername,
          l10n.d('Gebruikersnaam'),
          hint: l10n.d('wsreader'),
        ),
        const SizedBox(height: 12),
        SettingsTextField(
          _libreplanPassword,
          l10n.d('Wachtwoord'),
          hint: l10n.d('Opgeslagen in de sleutelhanger'),
          obscure: true,
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          value: _libreplanTrustedInternal,
          onChanged: (v) => _rebuild(() => _libreplanTrustedInternal = v),
          title: Text(
            l10n.d('Vertrouwde interne server'),
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: Text(
            l10n.d(
              'Alleen voor servers op het eigen netwerk (LAN). Staat plain-HTTP toe en staat privé-adressen door de NetGuard. Uitgeschakeld: HTTPS verplicht.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate600),
          ),
        ),
        const SizedBox(height: 12),
        _libreplanTestRow(l10n),
        const SizedBox(height: 20),
        _libreplanImportButton(l10n),
      ],
    );
  }

  Widget _libreplanImportButton(AppLocalizations l10n) {
    return ElevatedButton.icon(
      onPressed: () => LibreplanImportDialog.show(context),
      icon: const Icon(Icons.download, size: 18),
      label: Text(l10n.d('Importeren uit LibrePlan')),
    );
  }

  Widget _libreplanTestRow(AppLocalizations l10n) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 6,
      children: [
        ElevatedButton(
          onPressed: _libreplanTesting ? null : () => _libreplanTest(),
          child: Text(l10n.d('Verbinding testen')),
        ),
        if (_libreplanTesting)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (_libreplanTestOk != null) ...[
          Icon(
            _libreplanTestOk! ? Icons.check_circle : Icons.error_outline,
            size: 16,
            color: _libreplanTestOk! ? AppTheme.accentFg : AppTheme.dangerFg,
          ),
          Text(
            _libreplanTestMessage ?? '',
            style: TextStyle(
              fontSize: 11,
              color: _libreplanTestOk! ? AppTheme.accentFg : AppTheme.dangerFg,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _libreplanTest() async {
    final baseUrl = _libreplanBaseUrl.text.trim();
    final username = _libreplanUsername.text.trim();
    if (baseUrl.isEmpty || username.isEmpty) {
      _rebuild(() {
        _libreplanTestOk = false;
        _libreplanTestMessage = context.l10n.d(
          'Vul server-URL en gebruikersnaam in.',
        );
      });
      return;
    }

    _rebuild(() {
      _libreplanTesting = true;
      _libreplanTestOk = null;
      _libreplanTestMessage = null;
    });

    try {
      final client = LibreplanClient(
        settings: LibreplanSettings(
          enabled: true,
          baseUrl: baseUrl,
          username: username,
          trustedInternal: _libreplanTrustedInternal,
        ),
        password: _libreplanPassword.text,
        isWeb: false,
      );
      await client.testConnection();
      _rebuild(() {
        _libreplanTesting = false;
        _libreplanTestOk = true;
        _libreplanTestMessage = context.l10n.d('Verbinding succesvol.');
      });
    } on LibreplanRequestException catch (e) {
      _rebuild(() {
        _libreplanTesting = false;
        _libreplanTestOk = false;
        _libreplanTestMessage = e.message;
      });
    } catch (e) {
      _rebuild(() {
        _libreplanTesting = false;
        _libreplanTestOk = false;
        _libreplanTestMessage = context.l10n.d('Onverwachte fout.');
      });
    }
  }
}
