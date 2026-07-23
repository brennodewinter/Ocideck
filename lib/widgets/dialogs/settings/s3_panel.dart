// Het S3-paneel van het instellingenvenster.
//
// Stond tot #631 als `extension _SettingsS3 on _SettingsDialogState` in de
// gedeelde `part`-scope, waar het bij élk veld van de zesentwintig andere parts
// kon — inclusief de inloggegevens van de andere bronnen. Het is nu een gewone
// widget met een expliciete API: het formulier dat het bewerkt, de weg naar de
// certificaatbevestiging, en een melding terug wanneer er iets veranderde.
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/s3_settings.dart';
import '../../../services/s3/s3_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/log.dart';
import 's3_form.dart';
import 'settings_section_title.dart';
import 'settings_text_field.dart';

/// Vraagt de gebruiker het certificaat van [origin] te bekijken en geeft de
/// vingerafdruk terug als hij het vertrouwt, of `null`.
typedef ConfirmCertificate =
    Future<String?> Function({
      required Uri origin,
      required String host,
      required bool allowPrivate,
    });

class S3Panel extends StatefulWidget {
  /// Wat het paneel bewerkt. Eigendom van het venster: het overleeft het
  /// dichtklappen van dit paneel, zodat een half ingetypt endpoint niet
  /// verdwijnt.
  final S3Form form;

  final ConfirmCertificate confirmCertificate;

  /// Meldt dat er aan [form] iets veranderde. Nodig omdat het venster erbuiten
  /// meekijkt: de regel achter de verbindingsnaam toont de uitslag van de
  /// verbindingstest.
  final VoidCallback onChanged;

  const S3Panel({
    super.key,
    required this.form,
    required this.confirmCertificate,
    required this.onChanged,
  });

  @override
  State<S3Panel> createState() => _S3PanelState();
}

class _S3PanelState extends State<S3Panel> {
  S3Form get _form => widget.form;

  /// Wijzig het formulier en laat zowel dit paneel als het venster erbuiten
  /// bijtekenen.
  void _update(VoidCallback fn) {
    setState(fn);
    widget.onChanged();
  }

  /// De adresseringskeuze. Alleen waar de bucketnaam in de URL landt hangt
  /// hieraan; het protocol eronder is in beide gevallen hetzelfde.
  Widget _addressingField(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<S3AddressingStyle>(
        initialValue: _form.addressingStyle,
        isDense: true,
        // De twee keuzes dragen allebei hun dienstnaam mee ("(AWS S3)",
        // "(MinIO en andere)") en zijn daarmee breder dan het paneel. Zonder
        // dit loopt de rij eruit; hiermee krimpt het veld mee en valt hooguit
        // de staart weg, terwijl de uitgeklapte lijst de volle tekst houdt.
        isExpanded: true,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          labelText: l10n.d('Adressering'),
          prefixIcon: const Icon(Icons.alt_route, size: 18),
        ),
        items: [
          DropdownMenuItem(
            value: S3AddressingStyle.virtualHosted,
            child: Text(l10n.d('Bucket in de hostnaam (AWS S3)')),
          ),
          DropdownMenuItem(
            value: S3AddressingStyle.path,
            child: Text(l10n.d('Bucket in het pad (MinIO en andere)')),
          ),
        ],
        onChanged: (value) {
          if (value == null) return;
          _update(() {
            _form.addressingStyle = value;
            // De vorige uitslag ging over een andere URL-vorm en zegt nu niets
            // meer.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Kop plus toelichting, net als bij de andere netwerkbronnen. De kop is
        // ook het anker waar een zoektreffer naartoe springt — zie
        // [StorageConnectionKindUi.sectionSource].
        SettingsSectionTitle(l10n.d('S3-bucket')),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            l10n.d(
              'Open en bewaar presentaties in een S3-bucket: AWS S3, of een S3-compatible dienst zoals een eigen MinIO. De secret access key wordt versleuteld in de sleutelhanger bewaard, niet bij de overige instellingen.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ),
        SettingsTextField(
          _form.endpoint,
          l10n.d('Endpoint'),
          hint: 'https://s3.eu-central-1.amazonaws.com',
          icon: Icons.link,
        ),
        SettingsTextField(
          _form.bucket,
          l10n.d('Bucket'),
          icon: Icons.inventory_2_outlined,
        ),
        _addressingField(l10n),
        SettingsTextField(
          _form.region,
          l10n.d('Regio'),
          hint: 'eu-central-1',
          icon: Icons.public,
        ),
        SettingsTextField(
          _form.accessKeyId,
          l10n.d('Access key ID'),
          icon: Icons.badge_outlined,
        ),
        SettingsSecretField(_form.secret.field, l10n.d('Secret access key')),
        SettingsTextField(
          _form.root,
          l10n.d('Prefix (optioneel)'),
          hint: 'presentaties',
          icon: Icons.folder_outlined,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            l10n.d('Vertrouwd intern endpoint'),
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: Text(
            l10n.d(
              'Nodig wanneer het endpoint op een privé- of thuisnetwerk (LAN) draait, zoals een eigen MinIO. Sta alleen verbindingen toe naar servers die je zelf vertrouwt.',
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
    final config = _form.config;
    if (!config.isConfigured) {
      _update(() {
        _form.testOk = false;
        _form.testMessage = l10n.d('Vul endpoint, bucket en access key ID in');
      });
      return;
    }
    _update(() {
      _form.testing = true;
      _form.testOk = null;
      _form.testMessage = null;
    });
    final service = S3Service(
      bucket: config,
      secretAccessKey: _form.secret.field.text,
    );
    String? error;
    var certRejected = false;
    try {
      await service.probe();
    } on S3Exception catch (e) {
      error = _errorText(l10n, e.kind);
      certRejected = e.kind == S3Error.tls;
    } catch (e, st) {
      logError('SettingsDialog: S3-verbindingstest', e, st);
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

  /// Laat het certificaat zien en pin het als de gebruiker het vertrouwt.
  Future<void> _trustCertificate() async {
    final config = _form.config;
    final origin = config.origin;
    if (origin == null) return;
    final fingerprint = await widget.confirmCertificate(
      origin: origin,
      host: config.endpointHost,
      allowPrivate: config.trustedInternal,
    );
    if (fingerprint == null || !mounted) return;
    _update(() {
      _form.pinnedCertSha256 = fingerprint;
      _form.testCertRejected = false;
      _form.testOk = null;
      _form.testMessage = null;
    });
    await _testConnection();
  }

  String _errorText(AppLocalizations l10n, S3Error kind) {
    switch (kind) {
      case S3Error.auth:
        return l10n.d(
          'Aanmelden mislukt — controleer de access key, de secret key en de regio. Een verkeerde regio geeft dezelfde fout als een verkeerde sleutel.',
        );
      case S3Error.unknownHost:
        return l10n.d(
          'De endpoint-naam bestaat niet. Controleer het endpoint op een typefout.',
        );
      case S3Error.blockedHost:
        return l10n.d(
          'Het endpoint staat op een privé-adres. Vink "Vertrouwd intern endpoint" aan om verbinding toe te staan.',
        );
      case S3Error.notFound:
        return l10n.d(
          'Bucket niet gevonden. Bij een eigen MinIO helpt het vaak om "Bucket in het pad" te kiezen.',
        );
      case S3Error.config:
        return l10n.d('Ongeldig endpoint');
      case S3Error.tooLarge:
        return l10n.d('Het antwoord van de server was te groot');
      case S3Error.conditionalUnsupported:
        return l10n.d(
          'Dit endpoint ondersteunt geen voorwaardelijk schrijven; gelijktijdig bewerken is hier slechter beschermd.',
        );
      case S3Error.tls:
        return l10n.d(
          'Het certificaat van het endpoint wordt niet vertrouwd — zelfondertekend, verlopen, of op een andere naam gesteld.',
        );
      case S3Error.server:
        return l10n.d('Het endpoint gaf een fout. Probeer het later opnieuw.');
      case S3Error.network:
        return l10n.d('Verbinding mislukt');
    }
  }
}
