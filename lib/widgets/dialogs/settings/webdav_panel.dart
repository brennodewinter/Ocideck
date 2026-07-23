// Het WebDAV-paneel van het instellingenvenster.
//
// Stond tot #631 als `extension _SettingsWebdav on _SettingsDialogState` in de
// gedeelde `part`-scope, waar het bij élk veld van de andere parts kon —
// inclusief de inloggegevens van de andere bronnen. Nu een gewone widget met
// dezelfde expliciete API als [S3Panel].
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/webdav_settings.dart';
import '../../../services/webdav_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/log.dart';
import 'confirm_certificate.dart';
import 'settings_section_title.dart';
import 'settings_text_field.dart';
import 'webdav_form.dart';

class WebdavPanel extends StatefulWidget {
  /// Wat het paneel bewerkt. Eigendom van het venster, zodat een half ingetypte
  /// server het dichtklappen van dit paneel overleeft.
  final WebdavForm form;

  final ConfirmCertificate confirmCertificate;

  /// Meldt dat er aan [form] iets veranderde: de regel achter de
  /// verbindingsnaam toont de uitslag van de verbindingstest en staat buiten
  /// dit paneel.
  final VoidCallback onChanged;

  const WebdavPanel({
    super.key,
    required this.form,
    required this.confirmCertificate,
    required this.onChanged,
  });

  @override
  State<WebdavPanel> createState() => _WebdavPanelState();
}

class _WebdavPanelState extends State<WebdavPanel> {
  WebdavForm get _form => widget.form;

  void _update(VoidCallback fn) {
    setState(fn);
    widget.onChanged();
  }

  /// De servertype-keuze. Alleen het padschema hangt eraan — het protocol
  /// eronder is in beide gevallen gewone WebDAV.
  Widget _kindField(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<WebdavServerKind>(
        initialValue: _form.kind,
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
          _update(() {
            _form.kind = value;
            // De URL betekent per type iets anders (origin versus DAV-wortel),
            // dus een eerdere uitslag zegt niets meer over deze instelling.
            _form.testOk = null;
            _form.testMessage = null;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isNextcloud = _form.kind == WebdavServerKind.nextcloud;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionTitle(l10n.d('WebDAV-bron')),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            l10n.d(
              'Open en bewaar presentaties in een map op een WebDAV-server. Het wachtwoord wordt versleuteld in de sleutelhanger bewaard, niet bij de overige instellingen.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ),
        _kindField(l10n),
        SettingsTextField(
          _form.url,
          l10n.d('Server-URL'),
          // Bij Nextcloud is het pad afgeleid en telt alleen de host; bij een
          // andere server valt er niets te raden en ís het pad de DAV-wortel.
          hint: isNextcloud
              ? l10n.d('https://cloud.librekat.nl')
              : l10n.d('https://dav.librekat.nl/dav/files'),
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
        if (isNextcloud) _pastedDavUrlHint(l10n),
        SettingsTextField(
          _form.user,
          l10n.d('Gebruikersnaam'),
          icon: Icons.person_outline,
        ),
        SettingsSecretField(
          _form.password.field,
          // Het app-wachtwoord is een Nextcloud-voorziening; bij een andere
          // server zou die tip de gebruiker naar een niet-bestaand scherm sturen.
          isNextcloud ? l10n.d('App-wachtwoord') : l10n.d('Wachtwoord'),
          hint: isNextcloud
              ? l10n.d('Maak hiervoor een app-wachtwoord aan in Nextcloud')
              : null,
        ),
        SettingsTextField(
          _form.root,
          l10n.d('Submap (optioneel)'),
          hint: l10n.d('/Presentaties'),
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
          value: _form.trusted,
          onChanged: (value) => _update(() {
            _form.trusted = value;
            _form.testOk = null;
            _form.testMessage = null;
          }),
        ),
        _testSection(l10n),
        const SizedBox(height: 8),
        Text(
          l10n.d('Wijzigingen worden bewaard wanneer je op Opslaan klikt.'),
          style: TextStyle(fontSize: 11, color: AppTheme.slate400),
        ),
      ],
    );
  }

  /// Merkt op wanneer er een volledige Nextcloud-DAV-URL in het serverveld
  /// staat, en biedt aan hem uit elkaar te halen.
  ///
  /// Nextcloud toont die URL in zijn eigen instellingenscherm, dus mensen
  /// plakken hem hier. Dat wérkte meestal — [WebdavServer.origin] gooit het pad
  /// weg en het pad wordt tóch afgeleid — maar een submap die erin stond ging
  /// stil verloren, en het veld bleef iets tonen dat niet is wat de app
  /// gebruikt. Liever opmerken dan stilzwijgend negeren.
  ///
  /// Bewust met een knop en niet automatisch: dit herschrijft wat de gebruiker
  /// zojuist plakte, en dat hoort zijn keuze te blijven.
  Widget _pastedDavUrlHint(AppLocalizations l10n) {
    return ListenableBuilder(
      listenable: _form.url,
      builder: (context, _) {
        final parsed = WebdavServer.readPastedDavUrl(_form.url.text);
        // Niets te melden zodra het veld alleen nog de origin bevat — zo
        // verdwijnt de hint vanzelf nadat je hem hebt gevolgd.
        if (parsed == null || _form.url.text.trim() == parsed.baseUrl) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lightbulb_outline, size: 16, color: AppTheme.amber700),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.d(
                    'Dit lijkt een volledige DAV-URL. Bij Nextcloud leidt OciDeck dat pad zelf af — hier hoort alleen de server te staan.',
                  ),
                  style: TextStyle(fontSize: 11, color: AppTheme.amber700),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _applyPastedDavUrl(parsed),
                child: Text(l10n.d('Overnemen')),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Zet de onderdelen uit de geplakte URL in de juiste velden.
  ///
  /// Vult alleen wat leeg is: had de gebruiker de gebruikersnaam of submap al
  /// ingetypt, dan wint wat hij zelf koos. De server-URL wordt wél altijd
  /// opgeschoond — dat is de hele reden dat deze knop er staat.
  void _applyPastedDavUrl(PastedDavUrl parsed) {
    _update(() {
      _form.url.text = parsed.baseUrl;
      if (parsed.username.isNotEmpty && _form.user.text.trim().isEmpty) {
        _form.user.text = parsed.username;
      }
      if (parsed.rootPath.isNotEmpty && _form.root.text.trim().isEmpty) {
        _form.root.text = parsed.rootPath;
      }
      // De server verandert hiermee, dus een eerdere uitslag zegt niets meer.
      _form.testOk = null;
      _form.testMessage = null;
    });
  }

  /// De verbindingstest: de knop, de uitslag, en — als het op het certificaat
  /// strandde — de weg om dat te bekijken.
  Widget _testSection(AppLocalizations l10n) {
    final testMsg = _form.testMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _form.testing ? null : _testConnection,
              icon: _form.testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering, size: 16),
              label: Text(l10n.d('Verbinding testen')),
            ),
            const SizedBox(width: 12),
            if (_form.testOk == true)
              Row(
                children: [
                  Icon(Icons.check_circle, color: AppTheme.tealFg, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    l10n.d('Verbinding gelukt'),
                    style: TextStyle(fontSize: 12, color: AppTheme.tealFg),
                  ),
                ],
              ),
          ],
        ),
        if (_form.testCertRejected)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _trustCertificate,
                icon: const Icon(Icons.verified_user_outlined, size: 16),
                label: Text(l10n.d('Certificaat bekijken')),
              ),
            ),
          ),
        if (_form.testOk == false && testMsg != null)
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
      ],
    );
  }

  Future<void> _testConnection() async {
    final l10n = context.l10n;
    final server = _form.server;
    if (!server.isConfigured) {
      _update(() {
        _form.testOk = false;
        _form.testMessage = l10n.d('Vul server-URL en gebruikersnaam in');
      });
      return;
    }
    _update(() {
      _form.testing = true;
      _form.testOk = null;
      _form.testMessage = null;
    });
    final service = WebdavService(
      server: server,
      password: _form.password.field.text,
    );
    String? error;
    var certRejected = false;
    try {
      await service.probe();
    } on WebdavException catch (e) {
      error = _errorText(l10n, e.kind);
      certRejected = e.kind == WebdavError.tls;
    } catch (e, st) {
      logError('SettingsDialog: WebDAV-verbindingstest', e, st);
      error = l10n.d('Verbinding mislukt');
    }
    if (!mounted) return;
    _update(() {
      _form.testing = false;
      _form.testOk = error == null;
      _form.testMessage = error;
      _form.testCertRejected = certRejected;
    });
  }

  /// Haal het certificaat op, laat het zien en pin het als de gebruiker het
  /// vertrouwt.
  ///
  /// Bewust een aparte handeling na een mislukte test, en geen automatische
  /// vraag: vertrouwen is een besluit, en een dialoog die ongevraagd opduikt
  /// midden in het invullen wordt weggeklikt in plaats van gelezen.
  Future<void> _trustCertificate() async {
    final server = _form.server;
    final origin = server.origin;
    if (origin == null) return;
    final fingerprint = await widget.confirmCertificate(
      origin: origin,
      host: server.host,
      allowPrivate: server.trustedInternal,
    );
    if (fingerprint == null || !mounted) return;
    _update(() {
      _form.pinnedCertSha256 = fingerprint;
      _form.testCertRejected = false;
      _form.testOk = null;
      _form.testMessage = null;
    });
    // Meteen opnieuw proberen: de gebruiker wil weten of het hiermee lukt,
    // niet nóg een knop indrukken.
    await _testConnection();
  }

  String _errorText(AppLocalizations l10n, WebdavError kind) {
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
      case WebdavError.forbidden:
        return l10n.d(
          'Aangemeld, maar geen toegang — je wachtwoord is niet het probleem. Vraag rechten op deze map.',
        );
      case WebdavError.notFound:
        return l10n.d('Map niet gevonden op de server');
      case WebdavError.config:
        return l10n.d('Ongeldige server-URL');
      case WebdavError.tooLarge:
        return l10n.d('Het antwoord van de server was te groot');
      case WebdavError.server:
        // Bereikbaar, maar de server zelf gaf een fout — iets anders dan
        // "verbinding mislukt", en het vraagt om iets anders van de gebruiker.
        return l10n.d('De server gaf een fout. Probeer het later opnieuw.');
      case WebdavError.network:
        return l10n.d('Verbinding mislukt');
    }
  }
}
