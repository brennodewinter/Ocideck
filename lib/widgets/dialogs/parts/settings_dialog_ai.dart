// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (AI-assistentie tab); all imports live in the main
// library file. Instance methods relocate into an extension on
// _SettingsDialogState — same library, same members.
part of '../settings_dialog.dart';

extension _SettingsAi on _SettingsDialogState {
  /// Initialiseer de AI-velden vanuit de opgeslagen [ai]-instellingen. Laadt de
  /// API-sleutel asynchroon uit de keychain (zelfde patroon als WebDAV).
  void _initAiFields(AiSettings ai) {
    _aiEnabled = ai.enabled;
    _aiMode = ai.mode;
    _aiTrusted = ai.trustedInternal;
    _aiCloudConfirmed = ai.cloudConfirmed;
    _aiBaseUrl = TextEditingController(text: ai.baseUrl);
    _aiModel = TextEditingController(text: ai.model);
    _aiApiKey = TextEditingController();
    _initialAiBaseUrl = ai.baseUrl;
    if (ai.baseUrl.trim().isEmpty) return;
    ref.read(settingsProvider.notifier).readAiApiKey(ai.baseUrl).then((key) {
      if (mounted && key != null) {
        _rebuild(() {
          _aiApiKey.text = key;
          _loadedAiApiKey = key;
        });
      }
    });
  }

  /// Bouw de [AiSettings] uit de huidige veldwaarden (zonder API-sleutel).
  AiSettings _aiSettingsFromFields() {
    var url = _aiBaseUrl.text.trim();
    // Zonder schema is loopback de meest waarschijnlijke bedoeling; vul http://
    // aan. De veiligheidsgate valideert daarna alsnog scheme én host.
    if (url.isNotEmpty && !url.contains('://')) url = 'http://$url';
    return AiSettings(
      enabled: _aiEnabled,
      mode: _aiMode,
      baseUrl: url,
      model: _aiModel.text.trim(),
      trustedInternal: _aiTrusted,
      cloudConfirmed: _aiCloudConfirmed,
    );
  }

  void _saveAiSettings(SettingsNotifier notifier) {
    final settings = _aiSettingsFromFields();
    notifier.setAiSettings(settings);
    // Schrijf de API-sleutel als hij is gewijzigd, of wanneer de basis-URL (en
    // dus de keychain-sleutel) wijzigde. Zo leegt Opslaan vóór de asynchrone
    // keychain-load de sleutel niet, maar verhuist hij wél mee.
    final baseUrlChanged = settings.baseUrl != _initialAiBaseUrl;
    if ((_aiApiKey.text != _loadedAiApiKey || baseUrlChanged) &&
        settings.baseUrl.trim().isNotEmpty) {
      notifier.setAiApiKey(settings.baseUrl, _aiApiKey.text);
    }
  }

  Widget _aiTab() {
    final l10n = context.l10n;
    if (isWebPlatform) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(l10n.d('AI-assistentie')),
          Text(
            l10n.d('AI-assistentie is alleen beschikbaar in de desktopversie.'),
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
            'AI-assistentie is optioneel en staat standaard uit. Er wordt niets verstuurd totdat je dit inschakelt en zelf een backend kiest. Deze functie werkt alleen op de desktopversie.',
          ),
          style: const TextStyle(fontSize: 12, height: 1.4),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            l10n.d('AI-assistentie inschakelen'),
            style: const TextStyle(fontSize: 13),
          ),
          value: _aiEnabled,
          onChanged: (value) => _rebuild(() {
            _aiEnabled = value;
            _aiTestOk = null;
            _aiTestMessage = null;
          }),
        ),
        if (_aiEnabled) ..._aiConfigSection(l10n),
      ],
    );
  }

  List<Widget> _aiConfigSection(AppLocalizations l10n) {
    return [
      const SizedBox(height: 12),
      _aiModeDropdown(l10n),
      const SizedBox(height: 12),
      if (_aiMode != AiBackendMode.none) ..._aiBackendFields(l10n),
    ];
  }

  Widget _aiModeDropdown(AppLocalizations l10n) {
    return DropdownButtonFormField<AiBackendMode>(
      initialValue: _aiMode,
      isDense: true,
      decoration: InputDecoration(
        isDense: true,
        labelText: l10n.d('AI-backend'),
        prefixIcon: const Icon(Icons.hub_outlined, size: 18),
      ),
      items: [
        DropdownMenuItem(
          value: AiBackendMode.none,
          child: Text(l10n.d('Geen'), style: const TextStyle(fontSize: 13)),
        ),
        DropdownMenuItem(
          value: AiBackendMode.local,
          child: Text(
            l10n.d('Lokaal (op dit apparaat)'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        DropdownMenuItem(
          value: AiBackendMode.selfHosted,
          child: Text(
            l10n.d('Zelf gehost (eigen server)'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        DropdownMenuItem(
          value: AiBackendMode.cloud,
          child: Text(
            l10n.d('Cloud (externe dienst)'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
      onChanged: (value) => _rebuild(() {
        _aiMode = value ?? AiBackendMode.none;
        if (_aiMode == AiBackendMode.local && _aiBaseUrl.text.trim().isEmpty) {
          _aiBaseUrl.text = AiSettings.defaultLocalBaseUrl;
        }
        _aiTestOk = null;
        _aiTestMessage = null;
      }),
    );
  }

  List<Widget> _aiBackendFields(AppLocalizations l10n) {
    final isSelfHosted = _aiMode == AiBackendMode.selfHosted;
    final isCloud = _aiMode == AiBackendMode.cloud;
    return [
      _webdavField(
        _aiBaseUrl,
        l10n.d('Server-URL'),
        hint: 'http://127.0.0.1:11434/v1',
        icon: Icons.link,
      ),
      _webdavField(
        _aiModel,
        l10n.d('Modelnaam'),
        hint: 'gemma3:4b',
        icon: Icons.memory_outlined,
      ),
      if (isSelfHosted || isCloud)
        _webdavField(
          _aiApiKey,
          l10n.d('API-sleutel (optioneel)'),
          obscure: true,
          icon: Icons.key_outlined,
        ),
      if (isSelfHosted) _aiTrustedSwitch(l10n),
      if (isCloud) ..._aiCloudConfirm(l10n),
      const SizedBox(height: 12),
      _aiTestRow(l10n),
    ];
  }

  Widget _aiTrustedSwitch(AppLocalizations l10n) {
    return SwitchListTile(
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
      value: _aiTrusted,
      onChanged: (value) => _rebuild(() {
        _aiTrusted = value;
        _aiTestOk = null;
        _aiTestMessage = null;
      }),
    );
  }

  List<Widget> _aiCloudConfirm(AppLocalizations l10n) {
    return [
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Text(
          l10n.d(
            'Een clouddienst vereist eerst je privacytoestemming bij "Licentie en Privacy" en werkt niet in de webversie.',
          ),
          style: TextStyle(fontSize: 11, color: AppTheme.slate400),
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          l10n.d(
            'Ik begrijp dat gegevens naar deze externe dienst worden verstuurd',
          ),
          style: const TextStyle(fontSize: 13),
        ),
        value: _aiCloudConfirmed,
        onChanged: (value) => _rebuild(() {
          _aiCloudConfirmed = value;
          _aiTestOk = null;
          _aiTestMessage = null;
        }),
      ),
    ];
  }

  Widget _aiTestRow(AppLocalizations l10n) {
    final testMsg = _aiTestMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _aiTesting ? null : _testAiConnection,
              icon: _aiTesting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering, size: 16),
              label: Text(l10n.d('Verbinding testen')),
            ),
            const SizedBox(width: 12),
            if (_aiTestOk == true)
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
        if (_aiTestOk == false && testMsg != null)
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

  Future<void> _testAiConnection() async {
    final l10n = context.l10n;
    _rebuild(() {
      _aiTesting = true;
      _aiTestOk = null;
      _aiTestMessage = null;
    });
    final client = AiClientService(
      settings: _aiSettingsFromFields(),
      hasOutboundConsent: ref.read(consentProvider).hasAccepted,
      apiKey: _aiApiKey.text,
    );
    String? error;
    try {
      await client.testConnection();
    } on AiGateException catch (e) {
      error = e.reason == AiGateDenial.notConfigured
          ? l10n.d('Ongeldige server-URL')
          : l10n.d('Verbinding mislukt');
    } catch (e, st) {
      logError('SettingsDialog: AI-verbindingstest', e, st);
      error = l10n.d('Verbinding mislukt');
    }
    if (!mounted) return;
    _rebuild(() {
      _aiTesting = false;
      _aiTestOk = error == null;
      _aiTestMessage = error;
    });
  }
}
