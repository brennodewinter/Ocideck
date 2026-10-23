// De statusmatrix onder de Transcriptie-modulekaart (§2.1, §5.1; #2514):
// wat dit apparaat, deze build en deze configuratie op díít moment
// aankunnen — als feiten, met de herstelstap in dezelfde adem.
//
// Twee regels die hier gelden:
//  * alles op deze kaart is passief — geen permissieprompt, geen apparaat
//    openen, geen netwerk; wat een echte test vraagt (ping, audio) zit bij
//    de knop die daar expliciet om vraagt;
//  * "nog niet" is een antwoord. Een bronsoort zonder geregistreerde
//    platformroute wordt benoemd als niet beschikbaar, niet weggelaten.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/transcription/asr_server_engine.dart';
import '../../../services/transcription/capture_source.dart';
import '../../../services/transcription/environment_probe.dart';
import '../../../services/transcription/local_whisper_engine.dart';
import '../../../services/transcription/model_store.dart';
import '../../../services/transcription/transcription_engine.dart';
import '../../../state/transcription_model_provider.dart';
import '../../../state/transcription_provider.dart';
import '../../../theme/app_theme.dart';
import 'settings_section_title.dart';

/// Eén feitenregel: icoon, benoeming, en de gevonden waarde.
class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value, this.icon});

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? Icons.info_outline, size: 14, color: AppTheme.slate600),
          const SizedBox(width: 6),
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12, color: AppTheme.slate600),
            ),
          ),
        ],
      ),
    );
  }
}

/// De passieve capability- en randvoorwaardenmatrix.
class TranscriptionStatusSection extends ConsumerWidget {
  const TranscriptionStatusSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final route = ref.watch(transcriptionRouteProvider);
    final engine = ref.watch(transcriptionEngineProvider);
    final profile = ref.watch(asrServerProfileProvider);
    final catalog = ref.watch(whisperModelCatalogProvider);
    final selectedId = ref.watch(selectedTranscriptionModelProvider);
    final states = ref.watch(transcriptionModelManagerProvider);
    final sources = ref.watch(captureSourcesProvider);

    final selected =
        catalog.where((m) => m.id == selectedId).firstOrNull ?? catalog.first;
    final selectedState = states[selected.id];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: SettingsSectionTitle(l10n.d('Status op dit apparaat')),
        ),
        _platformRows(l10n),
        _FactRow(
          icon: Icons.route_outlined,
          label: l10n.d('Route'),
          value: route == 'server' && profile.isConfigured
              ? '${l10n.d('Eigen ASR-server')} (${profile.provenanceName})'
              : l10n.d('Lokaal — er vertrekt geen audio van dit apparaat'),
        ),
        _engineRow(l10n, engine),
        _FactRow(
          icon: Icons.model_training_outlined,
          label: l10n.d('Model'),
          value:
              '${l10n.d('Whisper')} ${selected.id} · '
              '${selected.sha256.substring(0, 12)}… · '
              '${_installLabel(l10n, selectedState)}',
        ),
        for (final kind in CaptureSourceKind.values)
          _sourceRow(l10n, kind, sources[kind]),
        _FactRow(
          icon: Icons.mic_none_outlined,
          label: l10n.d('Microfoonpermissie'),
          value: l10n.d(
            'Onbekend — pas bij de eerste opname vraagt het systeem toestemming; instellingen openen triggert geen prompt',
          ),
        ),
        _storageRow(l10n),
        _capabilityRow(l10n, engine),
        _FactRow(
          icon: Icons.call_outlined,
          label: l10n.d('OciDeck-gesprek'),
          value: l10n.d(
            'Alleen mogelijk tijdens een actieve vergadering met een bewezen systeemaudiobron — die bron is hier nog niet beschikbaar',
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// Platform, architectuur en — op web — de browsergrenzen die bepalen of
  /// lokale inferentie en opname überhaupt kunnen.
  Widget _platformRows(AppLocalizations l10n) {
    return FutureBuilder<TranscriptionEnvironment>(
      future: probeTranscriptionEnvironment(),
      builder: (context, snap) {
        final env = snap.data;
        if (env == null) {
          return _FactRow(
            label: l10n.d('Platform'),
            value: l10n.d('detecteren…'),
          );
        }
        return Column(
          children: [
            _FactRow(
              icon: Icons.computer_outlined,
              label: l10n.d('Platform'),
              value: env.architecture == null
                  ? l10n.d(env.platformLabel)
                  : '${l10n.d(env.platformLabel)} · ${env.architecture}',
            ),
            if (env.secureContext != null)
              _FactRow(
                icon: env.secureContext! ? Icons.lock_outline : Icons.lock_open,
                label: l10n.d('Beveiligde context'),
                value: env.secureContext!
                    ? l10n.d('ja — https')
                    : l10n.d(
                        'nee — zonder https geen sleutelbos en geen modelverificatie',
                      ),
              ),
            if (env.crossOriginIsolated != null)
              _FactRow(
                icon: env.crossOriginIsolated!
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                label: l10n.d('Cross-origin isolatie'),
                value: env.crossOriginIsolated!
                    ? l10n.d('ja — de lokale wasm-engine kan draaien')
                    : l10n.d(
                        'nee — hosting mist COOP/COEP; lokale inferentie kan niet (zie HOSTING.md)',
                      ),
              ),
            if (env.mediaRecorderAvailable != null)
              _FactRow(
                icon: env.mediaRecorderAvailable!
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                label: l10n.d('MediaRecorder'),
                value: env.mediaRecorderAvailable!
                    ? (env.supportedAudioMimes.isEmpty
                          ? l10n.d(
                              'aanwezig, maar geen bruikbare audiocontainer',
                            )
                          : '${l10n.d('aanwezig')} — ${env.supportedAudioMimes.join(', ')}')
                    : l10n.d('ontbreekt — opname in de browser kan niet'),
              ),
            if (env.freeStorageBytes != null)
              _FactRow(
                icon: Icons.storage_outlined,
                label: l10n.d('Vrije opslag'),
                value: '± ${_formatBytes(env.freeStorageBytes!)}',
              ),
          ],
        );
      },
    );
  }

  Widget _engineRow(AppLocalizations l10n, TranscriptionEngine? engine) {
    final e = engine;
    if (e is AsrServerEngine) {
      return _FactRow(
        icon: Icons.dns_outlined,
        label: l10n.d('Engine'),
        value: '${l10n.d('server')} — ${e.profile.provenanceName}',
      );
    }
    if (e is LocalWhisperEngine) {
      return FutureBuilder<LocalEngineStatus>(
        future: e.status(),
        builder: (context, snap) {
          final text = switch (snap.data?.support) {
            LocalEngineSupport.ready => l10n.d('lokaal — gereed'),
            LocalEngineSupport.missingHelper => l10n.d(
              'lokaal — helper ontbreekt in deze installatie',
            ),
            LocalEngineSupport.unsupportedArchitecture => l10n.d(
              'lokaal — deze processorarchitectuur heeft geen engine',
            ),
            LocalEngineSupport.noIsolation => l10n.d(
              'lokaal — geen cross-origin isolatie',
            ),
            null => l10n.d('controleren…'),
          };
          return _FactRow(
            icon: Icons.memory_outlined,
            label: l10n.d('Engine'),
            value: text,
          );
        },
      );
    }
    return _FactRow(
      icon: Icons.memory_outlined,
      label: l10n.d('Engine'),
      value: l10n.d('geen engine beschikbaar'),
    );
  }

  /// Eén bronrij uit het platformregister. Geen geregistreerde bron is een
  /// eerlijk "nog niet", geen lege plek (§5.1).
  Widget _sourceRow(
    AppLocalizations l10n,
    CaptureSourceKind kind,
    CaptureSource? source,
  ) {
    final label = switch (kind) {
      CaptureSourceKind.file => l10n.d('Bestaand audio/videobestand'),
      CaptureSourceKind.microphone => l10n.d('Microfoon'),
      CaptureSourceKind.systemAudio => l10n.d('Systeem-/appgeluid'),
      CaptureSourceKind.combination => l10n.d('Microfoon + systeemgeluid'),
    };
    if (source == null) {
      return _FactRow(
        icon: Icons.not_interested_outlined,
        label: label,
        value: l10n.d('nog niet beschikbaar op dit platform'),
      );
    }
    return FutureBuilder<CaptureAvailability>(
      future: source.probe(),
      builder: (context, snap) {
        final (icon, value) = switch (snap.data) {
          CaptureAvailability.available => (
            Icons.check_circle_outline,
            l10n.d('beschikbaar'),
          ),
          CaptureAvailability.tryAfterPermission => (
            Icons.lock_clock_outlined,
            l10n.d('waarschijnlijk — toestemming volgt bij eerste gebruik'),
          ),
          CaptureAvailability.unavailable => (
            Icons.error_outline,
            l10n.d('niet beschikbaar op deze opstelling'),
          ),
          CaptureAvailability.untested => (
            Icons.help_outline,
            l10n.d('nog niet bewezen op dit apparaat'),
          ),
          null => (Icons.hourglass_empty, l10n.d('detecteren…')),
        };
        return _FactRow(icon: icon, label: label, value: value);
      },
    );
  }

  /// Waar transcript en modellen landen, en wie over het audio-origineel
  /// beslist — de retentievraag die §3.2 bij de gebruiker legt.
  Widget _storageRow(AppLocalizations l10n) {
    return FutureBuilder<String?>(
      future: _modelsDir(),
      builder: (context, snap) => _FactRow(
        icon: Icons.folder_outlined,
        label: l10n.d('Opslag en retentie'),
        value:
            l10n.d(
              'Transcript komt in het deck; of het audio-origineel mee bewaard blijft kiest u bij Opslaan',
            ) +
            (snap.data == null ? '' : '\n${l10n.d('Modellen')}: ${snap.data}'),
      ),
    );
  }

  /// Batch/live — wat de gekozen route waarachtig kan, niet wat de
  /// brochure belooft (§4.2).
  Widget _capabilityRow(AppLocalizations l10n, TranscriptionEngine? engine) {
    final e = engine;
    if (e == null) return const SizedBox.shrink();
    return FutureBuilder<EngineCapabilities>(
      future: e.capabilities(),
      builder: (context, snap) {
        final streaming = snap.data?.streaming ?? false;
        return _FactRow(
          icon: Icons.speed_outlined,
          label: l10n.d('Batch / live'),
          value: streaming
              ? l10n.d('batch én provisionele live-tekst')
              : l10n.d('batchtranscriptie; live-tekst kan deze route niet'),
        );
      },
    );
  }

  Future<String?> _modelsDir() async {
    try {
      return (await createModelStore().directory()).path;
    } on Object {
      // Geen plugin-context (tests, vroege opstart) — dan zwijgt de rij
      // over het pad liever dan te gokken.
      return null;
    }
  }

  String _installLabel(AppLocalizations l10n, TranscriptionModelStatus? s) {
    if (s == null) return l10n.d('detecteren…');
    if (s.downloading) return l10n.d('wordt binnengehaald');
    return switch (s.install) {
      ModelInstallState.verified => l10n.d('geïnstalleerd en getoetst'),
      ModelInstallState.present => l10n.d('geïnstalleerd'),
      ModelInstallState.absent => l10n.d('niet geïnstalleerd'),
    };
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1 << 30) {
      return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
    }
    return '${(bytes / (1 << 20)).toStringAsFixed(0)} MB';
  }
}
