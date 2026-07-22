// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (S3-paneel); all imports live in the main library
// file. Instance methods live in an extension on _SettingsDialogState — same
// library, same members.
part of '../settings_dialog.dart';

extension _SettingsS3 on _SettingsDialogState {
  /// De adresseringskeuze. Alleen waar de bucketnaam in de URL landt hangt
  /// hieraan; het protocol eronder is in beide gevallen hetzelfde.
  Widget _s3AddressingField(S3Form form) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<S3AddressingStyle>(
        initialValue: form.addressingStyle,
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
          _rebuild(() {
            form.addressingStyle = value;
            // De vorige uitslag ging over een andere URL-vorm en zegt nu niets
            // meer.
            form.testOk = null;
            form.testMessage = null;
          });
        },
      ),
    );
  }

  Widget _s3Panel(S3Form form) {
    final l10n = context.l10n;
    final testMsg = form.testMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Kop plus toelichting, net als bij de andere netwerkbronnen. De kop is
        // ook het anker waar een zoektreffer naartoe springt — zie
        // [StorageConnectionKindUi.sectionSource].
        _sectionTitle(l10n.d('S3-bucket')),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            l10n.d(
              'Open en bewaar presentaties in een S3-bucket: AWS S3, of een S3-compatible dienst zoals een eigen MinIO. De secret access key wordt versleuteld in de sleutelhanger bewaard, niet bij de overige instellingen.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
          ),
        ),
        _webdavField(
          form.endpoint,
          l10n.d('Endpoint'),
          hint: 'https://s3.eu-central-1.amazonaws.com',
          icon: Icons.link,
        ),
        _webdavField(
          form.bucket,
          l10n.d('Bucket'),
          icon: Icons.inventory_2_outlined,
        ),
        _s3AddressingField(form),
        _webdavField(
          form.region,
          l10n.d('Regio'),
          hint: 'eu-central-1',
          icon: Icons.public,
        ),
        _webdavField(
          form.accessKeyId,
          l10n.d('Access key ID'),
          icon: Icons.badge_outlined,
        ),
        _secretField(form.secret.field, l10n.d('Secret access key')),
        _webdavField(
          form.root,
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
              onPressed: form.testing ? null : () => _testS3Connection(form),
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
        if (form.testCertRejected)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _trustS3Certificate(form),
                icon: const Icon(Icons.verified_user_outlined, size: 16),
                label: Text(l10n.d('Certificaat bekijken')),
              ),
            ),
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

  Future<void> _testS3Connection(S3Form form) async {
    final l10n = context.l10n;
    final config = form.config;
    if (!config.isConfigured) {
      _rebuild(() {
        form.testOk = false;
        form.testMessage = l10n.d('Vul endpoint, bucket en access key ID in');
      });
      return;
    }
    _rebuild(() {
      form.testing = true;
      form.testOk = null;
      form.testMessage = null;
    });
    final service = S3Service(
      bucket: config,
      secretAccessKey: form.secret.field.text,
    );
    String? error;
    var certRejected = false;
    try {
      await service.probe();
    } on S3Exception catch (e) {
      error = _s3ErrorText(l10n, e.kind);
      certRejected = e.kind == S3Error.tls;
    } catch (e, st) {
      logError('SettingsDialog: S3-verbindingstest', e, st);
      error = l10n.d('Verbinding mislukt');
    }
    if (!mounted) return;
    _rebuild(() {
      form.testing = false;
      form.testOk = error == null;
      form.testMessage = error;
      form.testCertRejected = certRejected;
    });
  }

  /// Laat het certificaat zien en pin het als de gebruiker het vertrouwt.
  Future<void> _trustS3Certificate(S3Form form) async {
    final config = form.config;
    final origin = config.origin;
    if (origin == null) return;
    final fingerprint = await _confirmCertificate(
      origin: origin,
      host: config.endpointHost,
      allowPrivate: config.trustedInternal,
    );
    if (fingerprint == null || !mounted) return;
    _rebuild(() {
      form.pinnedCertSha256 = fingerprint;
      form.testCertRejected = false;
      form.testOk = null;
      form.testMessage = null;
    });
    await _testS3Connection(form);
  }

  String _s3ErrorText(AppLocalizations l10n, S3Error kind) {
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
