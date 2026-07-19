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

  /// De servertype-keuze. Alleen het padschema hangt eraan — het protocol
  /// eronder is in beide gevallen gewone WebDAV.
  Widget _webdavKindField(WebdavForm form) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<WebdavServerKind>(
        initialValue: form.kind,
        isDense: true,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          labelText: l10n.d('Servertype'),
          prefixIcon: const Icon(Icons.dns_outlined, size: 18),
        ),
        items: [
          DropdownMenuItem(
            value: WebdavServerKind.nextcloud,
            child: Text(l10n.d('Nextcloud of ownCloud')),
          ),
          DropdownMenuItem(
            value: WebdavServerKind.generic,
            child: Text(l10n.d('Andere WebDAV-server')),
          ),
        ],
        onChanged: (value) {
          if (value == null) return;
          _rebuild(() {
            form.kind = value;
            // De URL betekent per type iets anders (origin versus DAV-wortel),
            // dus een eerdere uitslag zegt niets meer over deze instelling.
            form.testOk = null;
            form.testMessage = null;
          });
        },
      ),
    );
  }

  Widget _webdavPanel(WebdavForm form) {
    final l10n = context.l10n;
    final testMsg = form.testMessage;
    final isNextcloud = form.kind == WebdavServerKind.nextcloud;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l10n.d('WebDAV-bron')),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            l10n.d(
              'Open en bewaar presentaties in een map op een WebDAV-server. Het wachtwoord wordt versleuteld in de sleutelhanger bewaard, niet bij de overige instellingen.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ),
        _webdavKindField(form),
        _webdavField(
          form.url,
          l10n.d('Server-URL'),
          // Bij Nextcloud is het pad afgeleid en telt alleen de host; bij een
          // andere server valt er niets te raden en ís het pad de DAV-wortel.
          hint: isNextcloud
              ? 'https://cloud.voorbeeld.nl'
              : 'https://dav.voorbeeld.nl/dav/bestanden',
          icon: Icons.link,
        ),
        if (!isNextcloud)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              l10n.d('Het pad in de server-URL is de WebDAV-wortel.'),
              style: TextStyle(fontSize: 11, color: AppTheme.slate400),
            ),
          ),
        _webdavField(
          form.user,
          l10n.d('Gebruikersnaam'),
          icon: Icons.person_outline,
        ),
        _webdavField(
          form.password.field,
          // Het app-wachtwoord is een Nextcloud-voorziening; bij een andere
          // server zou die tip de gebruiker naar een niet-bestaand scherm sturen.
          isNextcloud ? l10n.d('App-wachtwoord') : l10n.d('Wachtwoord'),
          hint: isNextcloud
              ? l10n.d('Maak hiervoor een app-wachtwoord aan in Nextcloud')
              : null,
          obscure: true,
          icon: Icons.key_outlined,
        ),
        _webdavField(
          form.root,
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
          value: form.trusted,
          onChanged: (value) => _rebuild(() {
            form.trusted = value;
            form.testOk = null;
            form.testMessage = null;
          }),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: form.testing
                  ? null
                  : () => _testWebdavConnection(form),
              icon: form.testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering, size: 16),
              label: Text(l10n.d('Verbinding testen')),
            ),
            const SizedBox(width: 12),
            if (form.testOk == true)
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
        if (form.testOk == false && testMsg != null)
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

  Future<void> _testWebdavConnection(WebdavForm form) async {
    final l10n = context.l10n;
    final server = form.server;
    if (!server.isConfigured) {
      _rebuild(() {
        form.testOk = false;
        form.testMessage = l10n.d('Vul server-URL en gebruikersnaam in');
      });
      return;
    }
    _rebuild(() {
      form.testing = true;
      form.testOk = null;
      form.testMessage = null;
    });
    final service = WebdavService(
      server: server,
      password: form.password.field.text,
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
      form.testing = false;
      form.testOk = error == null;
      form.testMessage = error;
    });
  }

  String _webdavErrorText(AppLocalizations l10n, WebdavError kind) {
    switch (kind) {
      case WebdavError.auth:
        return l10n.d(
          'Aanmelden mislukt — controleer gebruikersnaam en wachtwoord. Tip: gebruik bij Nextcloud een app-wachtwoord (Instellingen → Beveiliging), niet je accountwachtwoord.',
        );
      case WebdavError.unknownHost:
        return l10n.d(
          'De servernaam bestaat niet. Controleer de server-URL op een typefout.',
        );
      case WebdavError.blockedHost:
        return l10n.d(
          'De server staat op een privé-adres. Vink "Vertrouwde interne server" aan om verbinding toe te staan.',
        );
      case WebdavError.tls:
        return l10n.d(
          'Het certificaat van de server wordt niet vertrouwd — zelfondertekend, verlopen, of op een andere naam gesteld.',
        );
      case WebdavError.redirect:
        return l10n.d(
          'De server stuurt door naar een ander adres. Vul dat adres hier in.',
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
