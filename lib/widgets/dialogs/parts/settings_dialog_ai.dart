// Part of the settings_dialog library — see ../settings_dialog.dart.
// Split out for navigability (AI-assistentie tab); all imports live in the main
// library file. Instance methods relocate into an extension on
// _SettingsDialogState — same library, same members.
part of '../settings_dialog.dart';

extension _SettingsAi on _SettingsDialogState {
  /// Initialiseer de AI-velden vanuit de opgeslagen [ai]-instellingen. Laadt de
  /// API-sleutel asynchroon uit de keychain (zelfde patroon als WebDAV).
  void _initAiFields(AiSettings ai) {
    _ai.adoptFrom(ai);
    // Verandert de bestemming, dan vervalt de bevestiging én de sleutel.
    //
    // `cloudConfirmed` is een kale bool die aan niets vastzat, terwijl het
    // doc-commentaar spreekt van een bevestiging "die de bestemming benoemt".
    // Wie provider A bevestigde en later alleen de URL naar B wijzigde, stuurde
    // bij het eerstvolgende voorstel tekst naar een bestemming die hij nooit
    // heeft goedgekeurd. En het sleutelveld hield intussen de sleutel van A
    // vast, dus die ging als `Authorization` mee naar B — óók al bij een
    // verbindingstest, en bij opslaan werd hij in de keychain naar B gekopieerd.
    final confirmedFor = ai.baseUrl.trim();
    _ai.baseUrl.addListener(() {
      final changed = _ai.baseUrl.text.trim() != confirmedFor;
      if (!changed || (!_ai.cloudConfirmed && _ai.apiKey.field.text.isEmpty)) {
        return;
      }
      _rebuild(() {
        _ai.cloudConfirmed = false;
        _ai.apiKey.field.clear();
        _ai.testOk = null;
        _ai.testMessage = null;
      });
    });
    if (ai.baseUrl.trim().isEmpty) return;
    ref.read(settingsProvider.notifier).readAiApiKey(ai.baseUrl).then((key) {
      if (mounted && key != null) _rebuild(() => _ai.apiKey.adopt(key));
    });
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
        // De aan/uit-schakelaar staat op Uitbreidingen, bij de modulekaart
        // (#731). Twee knoppen die bijna hetzelfde zeggen is één te veel; wie
        // hier komt, komt om te configureren.
        //
        // De configuratie blijft ook zichtbaar met de module uit, zolang er een
        // backend staat: anders maakt de schakelaar bestaand werk onbereikbaar
        // (#648). Zie [_aiModuleOffNotice] voor wat er dan boven staat.
        if (!_ai.enabled) const AiModuleOffNotice(),
        if (_ai.revealsTab) ..._aiConfigSection(l10n),
      ],
    );
  }

  List<Widget> _aiConfigSection(AppLocalizations l10n) {
    return [
      const SizedBox(height: 12),
      _aiModeDropdown(l10n),
      const SizedBox(height: 12),
      if (_ai.mode != AiBackendMode.none) ..._aiBackendFields(l10n),
    ];
  }

  Widget _aiModeDropdown(AppLocalizations l10n) {
    return DropdownButtonFormField<AiBackendMode>(
      initialValue: _ai.mode,
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
        _ai.mode = value ?? AiBackendMode.none;
        if (_ai.mode == AiBackendMode.local &&
            _ai.baseUrl.text.trim().isEmpty) {
          _ai.baseUrl.text = AiSettings.defaultLocalBaseUrl;
        }
        _ai.testOk = null;
        _ai.testMessage = null;
      }),
    );
  }

  List<Widget> _aiBackendFields(AppLocalizations l10n) {
    final isSelfHosted = _ai.mode == AiBackendMode.selfHosted;
    final isCloud = _ai.mode == AiBackendMode.cloud;
    return [
      SettingsTextField(
        _ai.baseUrl,
        l10n.d('Server-URL'),
        hint: l10n.d('http://127.0.0.1:11434/v1'),
        icon: Icons.link,
      ),
      SettingsTextField(
        _ai.model,
        l10n.d('Modelnaam'),
        hint: l10n.d('gemma3:4b'),
        icon: Icons.memory_outlined,
      ),
      if (isSelfHosted || isCloud)
        SettingsSecretField(
          _ai.apiKey.field,
          l10n.d('API-sleutel (optioneel)'),
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
      value: _ai.trusted,
      onChanged: (value) => _rebuild(() {
        _ai.trusted = value;
        _ai.testOk = null;
        _ai.testMessage = null;
      }),
    );
  }

  List<Widget> _aiCloudConfirm(AppLocalizations l10n) {
    return [
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Text(
          l10n.d(
            'Een clouddienst vereist eerst je privacytoestemming bij "Privacy en classificatie" en werkt niet in de webversie.',
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
        value: _ai.cloudConfirmed,
        onChanged: (value) => _rebuild(() {
          _ai.cloudConfirmed = value;
          _ai.testOk = null;
          _ai.testMessage = null;
        }),
      ),
    ];
  }

  Widget _aiTestRow(AppLocalizations l10n) {
    final testMsg = _ai.testMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _ai.testing ? null : _testAiConnection,
              icon: _ai.testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering, size: 16),
              label: Text(l10n.d('Verbinding testen')),
            ),
            const SizedBox(width: 12),
            if (_ai.testOk == true)
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
        if (_ai.testOk == false && testMsg != null)
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
      _ai.testing = true;
      _ai.testOk = null;
      _ai.testMessage = null;
    });
    final client = AiClientService(
      settings: _ai.settings,
      hasOutboundConsent: ref.read(consentProvider).hasAccepted,
      apiKey: _ai.apiKey.field.text,
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
      _ai.testing = false;
      _ai.testOk = error == null;
      _ai.testMessage = error;
    });
  }
}
