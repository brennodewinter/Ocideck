import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/transcription/local_whisper_engine.dart';
import '../../../services/transcription/model_download.dart';
import '../../../services/transcription/model_store.dart';
import '../../../services/transcription/transcription_engine.dart';
import '../../../services/transcription/whisper_model.dart';
import '../../../state/transcription_model_provider.dart';
import '../../../state/transcription_provider.dart';
import '../../../theme/app_theme.dart';

/// Het modelbeheer onder de Transcriptie-modulekaart (§4.4, #2512).
///
/// Elke rij toont wat de gebruiker wil weten vóór hij honderden megabytes
/// binnenhaalt: naam, omvang, licentie en bron — plus de toestand en de
/// knop die erbij hoort. Niets hier start een download vanzelf.
class TranscriptionModelsSection extends ConsumerWidget {
  const TranscriptionModelsSection({super.key, required this.moduleEnabled});

  /// Binnenhalen van een model mag pas als de module aan staat — de sectie
  /// blijft wél zichtbaar als hij uit staat, zodat de gebruiker kan zien
  /// wat er al op schijf ligt en dat kan opruimen.
  final bool moduleEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final states = ref.watch(transcriptionModelManagerProvider);
    final selected = ref.watch(selectedTranscriptionModelProvider);
    final engine = ref.watch(transcriptionEngineProvider);
    final catalog = ref.watch(whisperModelCatalogProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(
            l10n.d(
              'Lokaal spraakmodel — blijft op dit apparaat; er gaat niets naar een server',
            ),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        _EngineStatusLine(engine: engine, l10n: l10n),
        RadioGroup<String>(
          groupValue: selected,
          onChanged: (id) {
            if (id != null) {
              ref.read(selectedTranscriptionModelProvider.notifier).select(id);
            }
          },
          child: Column(
            children: [
              for (final model in catalog)
                _ModelRow(
                  model: model,
                  status: states[model.id] ?? const TranscriptionModelStatus(),
                  moduleEnabled: moduleEnabled,
                  l10n: l10n,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EngineStatusLine extends ConsumerWidget {
  const _EngineStatusLine({required this.engine, required this.l10n});

  final TranscriptionEngine? engine;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = engine;
    if (local is! LocalWhisperEngine) return const SizedBox.shrink();
    return FutureBuilder<LocalEngineStatus>(
      future: local.status(),
      builder: (context, snap) {
        final (icon, text) = switch (snap.data?.support) {
          LocalEngineSupport.ready => (
            Icons.check_circle_outline,
            l10n.d('Engine: gereed — de lokale helper is aanwezig'),
          ),
          LocalEngineSupport.missingHelper => (
            Icons.error_outline,
            l10n.d('Engine ontbreekt in deze installatie'),
          ),
          LocalEngineSupport.unsupportedArchitecture => (
            Icons.error_outline,
            l10n.d('Deze processorarchitectuur heeft geen lokale engine'),
          ),
          LocalEngineSupport.noIsolation => (
            Icons.error_outline,
            l10n.d(
              'Deze browser of hosting kan geen lokale spraakengine draaien (cross-origin isolatie ontbreekt)',
            ),
          ),
          null => (Icons.hourglass_empty, l10n.d('Engine: controleren…')),
        };
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              Icon(icon, size: 15, color: AppTheme.slate600),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(fontSize: 12, color: AppTheme.slate600),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ModelRow extends ConsumerWidget {
  const _ModelRow({
    required this.model,
    required this.status,
    required this.moduleEnabled,
    required this.l10n,
  });

  final WhisperModel model;
  final TranscriptionModelStatus status;
  final bool moduleEnabled;
  final AppLocalizations l10n;

  String _tierLabel() => switch (model.tier) {
    'light' => l10n.d('Licht — snel, minder nauwkeurig'),
    'accurate' => l10n.d('Nauwkeurig — beste kwaliteit, groot'),
    _ => l10n.d('Gebalanceerd — aanbevolen'),
  };

  String _stateLabel() {
    if (status.downloading) {
      return l10n.d('Bezig met binnenhalen');
    }
    return switch (status.install) {
      ModelInstallState.verified => l10n.d('Geïnstalleerd en getoetst'),
      ModelInstallState.present => l10n.d('Geïnstalleerd'),
      ModelInstallState.absent => l10n.d('Niet geïnstalleerd'),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.read(transcriptionModelManagerProvider.notifier);
    final installed = status.install != ModelInstallState.absent;

    return RadioListTile<String>(
      value: model.id,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Text(
        '${l10n.d('Whisper')} ${model.id}',
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_tierLabel()} · ${_formatBytes(model.downloadBytes)} · '
            '${l10n.d('MIT · whisper.cpp')}',
            style: TextStyle(fontSize: 11, color: AppTheme.slate600),
          ),
          Text(
            _stateLabel() +
                (status.failure != null
                    ? ' — ${_failureLabel(status.failure!)}'
                    : ''),
            style: TextStyle(fontSize: 11, color: AppTheme.slate600),
          ),
          if (status.downloading)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(value: status.progress),
            ),
          // De actie staat ónder de tekst, niet als trailing-kolom: bij
          // tekstschaal 200% heeft een knop in de trailing-positie geen
          // ruimte naast een drieregelige titel en faalt de tile-layout.
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: _action(manager, installed),
          ),
        ],
      ),
    );
  }

  Widget _action(TranscriptionModelManager manager, bool installed) {
    if (status.downloading) {
      return IconButton(
        tooltip: l10n.d('Afbreken'),
        icon: const Icon(Icons.close, size: 18),
        onPressed: () => manager.cancel(model),
      );
    }
    if (installed) {
      return IconButton(
        tooltip: l10n.d('Verwijderen'),
        icon: const Icon(Icons.delete_outline, size: 18),
        onPressed: () => manager.delete(model),
      );
    }
    return TextButton.icon(
      icon: const Icon(Icons.download_outlined, size: 16),
      label: Text(l10n.d('Binnenhalen'), style: const TextStyle(fontSize: 12)),
      onPressed: moduleEnabled ? () => manager.download(model) : null,
    );
  }

  String _failureLabel(ModelDownloadFailure failure) => switch (failure) {
    ModelDownloadFailure.cancelled => l10n.d('afgebroken'),
    ModelDownloadFailure.networkFailed => l10n.d('netwerkfout'),
    ModelDownloadFailure.refused => l10n.d('door de beveiliging geweigerd'),
    ModelDownloadFailure.invalidHash => l10n.d(
      'controlesom klopt niet — probeer opnieuw',
    ),
    ModelDownloadFailure.ioFailed => l10n.d('schrijffout op schijf'),
  };

  static String _formatBytes(int bytes) {
    if (bytes >= 1 << 30) {
      return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
    }
    return '${(bytes / (1 << 20)).toStringAsFixed(0)} MB';
  }
}
