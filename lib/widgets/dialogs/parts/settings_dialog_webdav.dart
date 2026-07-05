// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (WebDAV tab); all imports live in the main
// library file. Instance methods relocate verbatim into an extension on
// _SettingsDialogState — same library, same members, no behaviour change.
part of '../settings_dialog.dart';

extension _SettingsWebdav on _SettingsDialogState {
  Widget _webdavField(
    TextEditingController controller,
    String label, {
    String? hint,
    bool obscure = false,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          hintText: hint,
          prefixIcon: icon == null ? null : Icon(icon, size: 18),
        ),
      ),
    );
  }

  Widget _webdavTab() {
    final l10n = context.l10n;
    final testMsg = _webdavTestMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l10n.d('Nextcloud-bron (WebDAV)')),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            l10n.d(
              'Open en bewaar presentaties in een map op je Nextcloud. Het wachtwoord wordt versleuteld in de sleutelhanger bewaard, niet bij de overige instellingen.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ),
        _webdavField(
          _webdavUrl,
          l10n.d('Server-URL'),
          hint: 'https://cloud.voorbeeld.nl',
          icon: Icons.link,
        ),
        _webdavField(
          _webdavUser,
          l10n.d('Gebruikersnaam'),
          icon: Icons.person_outline,
        ),
        _webdavField(
          _webdavPassword,
          l10n.d('App-wachtwoord'),
          hint: l10n.d('Maak hiervoor een app-wachtwoord aan in Nextcloud'),
          obscure: true,
          icon: Icons.key_outlined,
        ),
        _webdavField(
          _webdavRoot,
          l10n.d('Submap (optioneel)'),
          hint: '/Presentaties',
          icon: Icons.folder_outlined,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            l10n.d('Vertrouwde interne server'),
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: Text(
            l10n.d(
              'Nodig wanneer de server op een privé- of thuisnetwerk (LAN) draait. Sta alleen verbindingen toe naar servers die je zelf vertrouwt.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
          value: _webdavTrusted,
          onChanged: (value) => _rebuild(() {
            _webdavTrusted = value;
            _webdavTestOk = null;
            _webdavTestMessage = null;
          }),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _webdavTesting ? null : _testWebdavConnection,
              icon: _webdavTesting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering, size: 16),
              label: Text(l10n.d('Verbinding testen')),
            ),
            const SizedBox(width: 12),
            if (_webdavTestOk == true)
              Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: AppTheme.teal,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l10n.d('Verbinding gelukt'),
                    style: const TextStyle(fontSize: 12, color: AppTheme.teal),
                  ),
                ],
              ),
          ],
        ),
        if (_webdavTestOk == false && testMsg != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppTheme.danger600,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    testMsg,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.danger600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Text(
          l10n.d('Wijzigingen worden bewaard wanneer je op Opslaan klikt.'),
          style: TextStyle(fontSize: 11, color: AppTheme.slate400),
        ),
      ],
    );
  }

  Future<void> _testWebdavConnection() async {
    final l10n = context.l10n;
    final server = _webdavServerFromFields();
    if (!server.isConfigured) {
      _rebuild(() {
        _webdavTestOk = false;
        _webdavTestMessage = l10n.d('Vul server-URL en gebruikersnaam in');
      });
      return;
    }
    _rebuild(() {
      _webdavTesting = true;
      _webdavTestOk = null;
      _webdavTestMessage = null;
    });
    final service = WebdavService(
      server: server,
      password: _webdavPassword.text,
    );
    String? error;
    try {
      await service.probe();
    } on WebdavException catch (e) {
      error = _webdavErrorText(l10n, e.kind);
    } catch (e, st) {
      logError('SettingsDialog: WebDAV-verbindingstest', e, st);
      error = l10n.d('Verbinding mislukt');
    }
    if (!mounted) return;
    _rebuild(() {
      _webdavTesting = false;
      _webdavTestOk = error == null;
      _webdavTestMessage = error;
    });
  }

  String _webdavErrorText(AppLocalizations l10n, WebdavError kind) {
    switch (kind) {
      case WebdavError.auth:
        return l10n.d(
          'Aanmelden mislukt — controleer gebruikersnaam en wachtwoord. Tip: gebruik bij Nextcloud een app-wachtwoord (Instellingen → Beveiliging), niet je accountwachtwoord.',
        );
      case WebdavError.blockedHost:
        return l10n.d(
          'De server staat op een privé-adres. Vink "Vertrouwde interne server" aan om verbinding toe te staan.',
        );
      case WebdavError.notFound:
        return l10n.d('Map niet gevonden op de server');
      case WebdavError.config:
        return l10n.d('Ongeldige server-URL');
      case WebdavError.tooLarge:
        return l10n.d('Het antwoord van de server was te groot');
      case WebdavError.network:
      case WebdavError.server:
        return l10n.d('Verbinding mislukt');
    }
  }
}
