// Het ASR-serverprofiel onder de Transcriptie-modulekaart
// (docs/design/TRANSCRIPTION.md §4.3; #2524 bouwde de route, #2514 maakt
// hem bedienbaar).
//
// Dit is de enige plek waar audio het apparaat kan verlaten — daarom
// gelden hier drie vormregels:
//  * het profiel is bewust handmatig: niets vertrekt tot Opslaan, en de
//    poortregels (loopback / vertrouwd intern / bevestigde cloud) staan
//    waar de velden zijn, niet verstopt in een algemene melding;
//  * "Verbinding testen" stuurt alleen een GET — geen audio; de echte
//    audiotest hangt achter zijn eigen bevestigingsdialoog die host én
//    inhoud benoemt (de per-taak [ServerConsent] uit §4.3);
//  * de API-sleutel is alleen een invoerveld — hij gaat naar de
//    sleutelbos of nergens heen, nooit naar het profiel, de URL of een
//    logregel.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/asr_server_profile.dart';
import '../../../services/secret_store.dart';
import '../../../services/transcription/asr_engine_factory.dart';
import '../../../services/transcription/asr_server_engine.dart';
import '../../../services/transcription/asr_server_gate.dart';
import '../../../services/transcription/transcription_engine.dart';
import '../../../services/transcription/transcription_errors.dart';
import '../../../services/web_asset_store.dart';
import '../../../state/transcription_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/log.dart';
import 'settings_section_title.dart';
import 'settings_text_field.dart';

/// Bouwt de engine voor een proef — testhaak: widgettests leveren een
/// engine met fake-transport. [keyReader] leest het ingetypte sleutelveld
/// eerst en de sleutelbos daarna.
typedef AsrEngineBuilder =
    AsrServerEngine Function(
      AsrServerProfile profile,
      Future<String?> Function() keyReader,
    );

class TranscriptionServerSection extends ConsumerStatefulWidget {
  const TranscriptionServerSection({super.key, this.engineBuilder});

  final AsrEngineBuilder? engineBuilder;

  @override
  ConsumerState<TranscriptionServerSection> createState() =>
      _TranscriptionServerSectionState();
}

class _TranscriptionServerSectionState
    extends ConsumerState<TranscriptionServerSection> {
  final _urlCtl = TextEditingController();
  final _nameCtl = TextEditingController();
  final _keyCtl = TextEditingController();

  AsrServerMode _mode = AsrServerMode.none;
  bool _enabled = false;
  bool _trustedInternal = false;
  bool _cloudConfirmed = false;

  bool _hasStoredKey = false;
  bool _probing = false;
  AsrServerProbe? _probe;
  bool _audioTesting = false;
  ({bool ok, String text})? _audioResult;

  @override
  void initState() {
    super.initState();
    _loadFromSaved(ref.read(asrServerProfileProvider));
    for (final ctl in [_urlCtl, _nameCtl, _keyCtl]) {
      ctl.addListener(_onField);
    }
  }

  @override
  void dispose() {
    for (final ctl in [_urlCtl, _nameCtl, _keyCtl]) {
      ctl.dispose();
    }
    super.dispose();
  }

  void _loadFromSaved(AsrServerProfile p) {
    _mode = p.mode;
    _enabled = p.enabled;
    _trustedInternal = p.trustedInternal;
    _cloudConfirmed = p.cloudConfirmed;
    _urlCtl.text = p.baseUrl;
    _nameCtl.text = p.name;
    _refreshStoredKey();
  }

  void _onField() {
    setState(() {
      // Een gewijzigd veld maakt eerdere uitslagen ongeldig.
      _probe = null;
      _audioResult = null;
    });
    unawaited(_refreshStoredKey());
  }

  Future<void> _refreshStoredKey() async {
    final url = _urlCtl.text.trim();
    final has =
        url.isNotEmpty &&
        (await SecretStore().readAsrApiKey(url))?.isNotEmpty == true;
    if (mounted && has != _hasStoredKey) {
      setState(() => _hasStoredKey = has);
    }
  }

  /// Het profiel zoals de velden het nu tonen — opslag- en testobject zijn
  /// hetzelfde ding, zodat "testen" altijd over díe server gaat.
  AsrServerProfile _draft() => AsrServerProfile(
    enabled: _enabled,
    mode: _mode,
    baseUrl: _urlCtl.text.trim(),
    name: _nameCtl.text.trim(),
    trustedInternal: _trustedInternal,
    cloudConfirmed: _cloudConfirmed,
  );

  AsrServerEngine _engine() {
    Future<String?> keyReader() async {
      final typed = _keyCtl.text.trim();
      if (typed.isNotEmpty) return typed;
      final secrets = SecretStore();
      if (!secrets.canStore) return null;
      return secrets.readAsrApiKey(_urlCtl.text.trim());
    }

    final builder = widget.engineBuilder;
    if (builder != null) return builder(_draft(), keyReader);
    return createAsrServerEngine(_draft(), apiKeyReader: keyReader);
  }

  bool _dirtyAgainst(AsrServerProfile saved) =>
      _draft() != saved || _keyCtl.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // De provider laadt zijn profiel uit prefs ná de eerste frame — zonder
    // dit luisteraar zou een bewaard profiel de velden nooit bereiken.
    // Alleen bijhouden als de velden nog het vorige profiel tonen, zodat
    // een reload nooit getypte concepttekst overschrijft.
    ref.listen<AsrServerProfile>(asrServerProfileProvider, (prev, next) {
      if (next == prev || (prev != null && _dirtyAgainst(prev))) return;
      setState(() => _loadFromSaved(next));
    });
    final saved = ref.watch(asrServerProfileProvider);
    final dirty = _dirtyAgainst(saved);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: SettingsSectionTitle(l10n.d('Eigen ASR-server')),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(
            l10n.d(
              'Optioneel en uit tenzij u het aanzet: audio gaat dan naar een transcriptieserver die u zelf kiest. Lokaal blijft de standaard; er is nooit een stille fallback tussen beide.',
            ),
            style: TextStyle(fontSize: 11, color: AppTheme.slate600),
          ),
        ),
        _modeField(l10n),
        if (_mode != AsrServerMode.none) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                SettingsTextField(
                  _urlCtl,
                  l10n.d('Serveradres (basis-URL)'),
                  hint: _mode == AsrServerMode.loopback
                      ? AsrServerProfile.defaultLoopbackBaseUrl
                      : l10n.d('https://asr.uwdomein.nl'),
                  icon: Icons.link,
                ),
                SettingsTextField(
                  _nameCtl,
                  l10n.d('Eigen naam (optioneel)'),
                  hint: l10n.d('verschijnt in de provenienceregel'),
                  icon: Icons.label_outline,
                ),
                SettingsSecretField(
                  _keyCtl,
                  l10n.d('API-sleutel'),
                  hint: _hasStoredKey
                      ? l10n.d('opgeslagen — leeg laten houdt hem')
                      : null,
                ),
              ],
            ),
          ),
          if (_mode == AsrServerMode.lan)
            _optIn(
              value: _trustedInternal,
              title: l10n.d('Vertrouwd intern adres'),
              subtitle: l10n.d(
                'Bevestig dat dit adres op uw eigen netwerk staat; pas dan mag een privé-adres de netwerkblokkade passeren.',
              ),
              onChanged: (v) => setState(() => _trustedInternal = v),
            ),
          if (_mode == AsrServerMode.cloud)
            _optIn(
              value: _cloudConfirmed,
              title: l10n.d('Externe dienst bevestigd'),
              subtitle: l10n.d(
                'Bevestig dat audio naar deze specifieke externe bestemming mag — dat is de enige toestemming die deze route vraagt.',
              ),
              onChanged: (v) => setState(() => _cloudConfirmed = v),
            ),
          _optIn(
            value: _enabled,
            title: l10n.d('Profiel actief'),
            subtitle: l10n.d(
              'Pas een actief profiel kan verzoeken versturen; uit betekent: niets vertrekt.',
            ),
            onChanged: (v) => setState(() => _enabled = v),
          ),
          _gateLine(l10n),
          _actions(l10n, dirty),
          _results(l10n),
        ] else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              saved.hasEndpoint
                  ? l10n.d(
                      'Er is een profiel bewaard maar uitgeschakeld — kies een serverklasse om het te bewerken of te gebruiken.',
                    )
                  : l10n.d('Geen server gekozen — transcriptie blijft lokaal.'),
              style: TextStyle(fontSize: 11, color: AppTheme.slate600),
            ),
          ),
        ],
      ],
    );
  }

  Widget _modeField(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: DropdownButtonFormField<AsrServerMode>(
        initialValue: _mode,
        isDense: true,
        isExpanded: true,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          labelText: l10n.d('Serverklasse'),
          prefixIcon: const Icon(Icons.dns_outlined, size: 18),
        ),
        items: [
          DropdownMenuItem(
            value: AsrServerMode.none,
            child: Text(l10n.d('Geen server (lokaal houden)')),
          ),
          DropdownMenuItem(
            value: AsrServerMode.loopback,
            child: Text(l10n.d('Op dit apparaat (loopback)')),
          ),
          DropdownMenuItem(
            value: AsrServerMode.lan,
            child: Text(l10n.d('Eigen server in vertrouwd netwerk (LAN)')),
          ),
          DropdownMenuItem(
            value: AsrServerMode.cloud,
            child: Text(l10n.d('Externe ASR-dienst (https)')),
          ),
        ],
        onChanged: (v) {
          if (v == null) return;
          setState(() {
            _mode = v;
            _probe = null;
            _audioResult = null;
          });
        },
      ),
    );
  }

  Widget _optIn({
    required bool value,
    required String title,
    required String subtitle,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(title, style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 11, color: AppTheme.slate600),
      ),
      value: value,
      onChanged: onChanged,
    );
  }

  /// De poortuitslag over het concept — live, zonder netwerk, zodat een
  /// ontbrekende opt-in meteen uitleg krijgt in plaats van een mislukte
  /// test later.
  Widget _gateLine(AppLocalizations l10n) {
    final decision = AsrServerGate.evaluate(_draft(), isWeb: kIsWeb);
    final (icon, color, text) = switch (decision) {
      AsrGateAllow() => (
        Icons.check_circle_outline,
        AppTheme.tealFg,
        l10n.d('Poort staat toe: verzoeken mogen vertrekken'),
      ),
      AsrGateDeny(:final reason) => (
        Icons.block_outlined,
        AppTheme.amber700,
        _denialText(l10n, reason),
      ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }

  String _denialText(AppLocalizations l10n, AsrGateDenial reason) {
    return switch (reason) {
      AsrGateDenial.disabled => l10n.d(
        'Profiel staat uit — zet "Profiel actief" aan om te versturen',
      ),
      AsrGateDenial.modeNone => l10n.d('Geen serverklasse gekozen'),
      AsrGateDenial.notConfigured => l10n.d(
        'Endpoint ontbreekt of is ongeldig — gebruik een kale http(s)-URL zonder gebruikersnaam of wachtwoord erin',
      ),
      AsrGateDenial.loopbackRequired => l10n.d(
        'Loopback mag alleen naar dit apparaat zelf — gebruik 127.0.0.1 of localhost',
      ),
      AsrGateDenial.lanNotTrusted => l10n.d(
        'LAN-route vraagt eerst "Vertrouwd intern adres"',
      ),
      AsrGateDenial.cloudNeedsTls => l10n.d(
        'Een externe dienst vereist https — http naar buiten is onacceptabel',
      ),
      AsrGateDenial.cloudNotConfirmed => l10n.d(
        'Bevestig eerst dat audio naar deze externe dienst mag',
      ),
      AsrGateDenial.insecureHttpOnWeb => l10n.d(
        'Vanaf deze webpagina kan alleen https (of loopback) — de browser blokkeert http naar dit adres',
      ),
    };
  }

  Widget _actions(AppLocalizations l10n, bool dirty) {
    final busy = _probing || _audioTesting;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ElevatedButton.icon(
            onPressed: dirty && !busy ? _save : null,
            icon: const Icon(Icons.save_outlined, size: 16),
            label: Text(l10n.d('Profiel opslaan')),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : _testConnection,
            icon: _probing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering, size: 16),
            label: Text(l10n.d('Verbinding testen (zonder audio)')),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : _testWithAudio,
            icon: _audioTesting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_outlined, size: 16),
            label: Text(l10n.d('Test met echte audio')),
          ),
          if (ref.read(asrServerProfileProvider).hasEndpoint)
            TextButton.icon(
              onPressed: busy ? null : _remove,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: Text(l10n.d('Profiel verwijderen')),
            ),
        ],
      ),
    );
  }

  Widget _results(AppLocalizations l10n) {
    final probe = _probe;
    final audio = _audioResult;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (probe != null)
          _resultLine(
            ok: probe.status == AsrProbeStatus.reachable,
            text: _probeText(l10n, probe),
          ),
        if (audio != null) _resultLine(ok: audio.ok, text: audio.text),
      ],
    );
  }

  Widget _resultLine({required bool ok, required String text}) {
    final color = ok ? AppTheme.tealFg : AppTheme.danger600;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.error_outline,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }

  String _probeText(AppLocalizations l10n, AsrServerProbe probe) {
    return switch (probe.status) {
      AsrProbeStatus.reachable => l10n.d(
        'Server bereikbaar en antwoordde als HTTP-server',
      ),
      AsrProbeStatus.authRequired => l10n.d(
        'Server bereikbaar maar eist authenticatie — controleer of vul de API-sleutel',
      ),
      AsrProbeStatus.unreachable =>
        '${l10n.d('Server onbereikbaar of geweigerd — controleer adres, TLS en of de server draait')} (${probe.detail})',
      AsrProbeStatus.refused => _denialText(
        l10n,
        AsrGateDenial.values.asNameMap()[probe.detail] ??
            AsrGateDenial.notConfigured,
      ),
    };
  }

  Future<void> _save() async {
    final draft = _draft();
    final old = ref.read(asrServerProfileProvider);
    await ref.read(asrServerProfileProvider.notifier).set(draft);
    final secrets = SecretStore();
    try {
      final key = _keyCtl.text.trim();
      if (secrets.canStore) {
        // Verhuist de sleutel mee bij een nieuw endpoint en laat een leeg
        // veld de bestaande sleutel ongemoeid.
        if (old.baseUrl != draft.baseUrl) {
          await secrets.deleteAsrApiKey(old.baseUrl);
        }
        if (key.isNotEmpty) {
          await secrets.writeAsrApiKey(draft.baseUrl, key);
          _keyCtl.clear();
        }
      }
    } catch (e, s) {
      logError('TranscriptionServerSection: sleutel bewaren', e, s);
    }
    if (mounted) {
      setState(() => _probe = null);
      unawaited(_refreshStoredKey());
    }
  }

  Future<void> _remove() async {
    final old = ref.read(asrServerProfileProvider);
    await ref
        .read(asrServerProfileProvider.notifier)
        .set(const AsrServerProfile());
    try {
      await SecretStore().deleteAsrApiKey(old.baseUrl);
    } catch (e, s) {
      logError('TranscriptionServerSection: sleutel verwijderen', e, s);
    }
    if (!mounted) return;
    setState(() {
      _loadFromSaved(const AsrServerProfile());
      _keyCtl.clear();
      _hasStoredKey = false;
      _probe = null;
      _audioResult = null;
    });
  }

  /// De verbindingstest: één GET, geen audio — `probe()` mag dus zonder
  /// aparte bevestiging; de knop ís de expliciete handeling.
  Future<void> _testConnection() async {
    setState(() {
      _probing = true;
      _probe = null;
    });
    try {
      final result = await _engine().probe();
      if (mounted) setState(() => _probe = result);
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  /// De audiotest: stuurt één seconde stille testaudio ná een
  /// bevestigingsdialoog die host en inhoud benoemt — dat is de
  /// per-taakconsent die de engine afdwingt (§4.3).
  Future<void> _testWithAudio() async {
    final l10n = context.l10n;
    final draft = _draft();
    final host = draft.host.isEmpty ? draft.baseUrl.trim() : draft.host;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.d('Test met echte audio')),
        content: Text(
          '${l10n.d('Er wordt één seconde stille testaudio (~32 kB) verstuurd naar')} $host.\n\n${l10n.d('De API-sleutel gaat mee als beveiligde header, niet in de URL. Dit is dezelfde bevestiging die elke transcriptietaak straks vraagt.')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.d('Annuleren')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.d('Versturen')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _audioTesting = true;
      _audioResult = null;
    });
    var text = '';
    var ok = false;
    try {
      final path = WebAssetStore.put(_silenceWav(), name: 'asr-test.wav');
      final result = await _engine().transcribe(
        AudioRef(path),
        TranscriptionOptions(
          serverConsent: ServerConsent(host: draft.host, audioPath: path),
        ),
      );
      ok = true;
      text = result.text.trim().isEmpty
          ? l10n.d(
              'Server antwoordde met een leeg transcript — verwacht voor stille testaudio',
            )
          : '${l10n.d('Server antwoordde')}: "${result.text.trim()}"';
    } on ConsentRequired catch (e) {
      text = '${l10n.d('Bevestiging vereist')}: ${e.message}';
    } on EngineUnavailable catch (e) {
      text = '${l10n.d('Serverprofiel niet bruikbaar')}: ${e.message}';
    } on ServerRefused catch (e) {
      text = '${l10n.d('Server weigerde of was onbereikbaar')}: ${e.message}';
    } on CapacityExceeded catch (e) {
      text = '${l10n.d('Upload te groot')}: ${e.message}';
    } on Cancelled catch (e) {
      text = '${l10n.d('Afgebroken')}: ${e.message}';
    } on TranscriptionError catch (e) {
      text = e.message;
    } catch (e, s) {
      logError('TranscriptionServerSection: audiotest', e, s);
      text = l10n.d('Test mislukt');
    } finally {
      if (mounted) {
        setState(() {
          _audioTesting = false;
          _audioResult = (ok: ok, text: text);
        });
      }
    }
  }
}

/// Eén seconde digitale stilte als mono-16kHz-WAV — het kleinste eerlijke
/// "echte audio"-bestand: volgt dezelfde upload-, consent- en parse-route
/// als een echte opname, maar bevat niemands stem.
Uint8List _silenceWav() {
  const sampleRate = 16000;
  const dataBytes = sampleRate * 2; // 1s × 16-bit mono
  final header = ByteData(44)
    ..setUint32(0, 0x46464952) // 'RIFF'
    ..setUint32(4, 36 + dataBytes, Endian.little)
    ..setUint32(8, 0x45564157) // 'WAVE'
    ..setUint32(12, 0x20746d66) // 'fmt '
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, 1, Endian.little) // mono
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 2, Endian.little) // byte/sec
    ..setUint16(32, 2, Endian.little) // block align
    ..setUint16(34, 16, Endian.little) // bits
    ..setUint32(36, 0x61746164) // 'data'
    ..setUint32(40, dataBytes, Endian.little);
  return Uint8List.fromList([
    ...header.buffer.asUint8List(),
    ...Uint8List(dataBytes),
  ]);
}
