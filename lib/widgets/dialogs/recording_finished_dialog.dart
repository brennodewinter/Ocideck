// De keuze ná Stop (#2516): nu transcriberen, bewaren voor later, of
// weggooien. De file staat al in de staging; "later" laat hem daar de
// herstelperiode van zeven dagen liggen. Voor een callopname (#2530) noemt
// de dialoog ook welke bronstukken ontbraken — `sources.json` in de
// sessiemap zegt welke bronnen stilte bijdroegen.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../meetings/call_audio_manifest.dart';
import '../../meetings/call_recording.dart';
import '../../services/transcription/capture_source.dart';
import '../../services/web_asset_store.dart';
import '../../services/download_delivery.dart';
import '../../services/transcription/recording_session.dart';
import '../../state/transcription_provider.dart';
import 'transcribe_file_dialog.dart';

Future<void> showRecordingFinishedDialog(
  BuildContext context,
  WidgetRef ref, {
  required RecordedAudio audio,
  required String? sessionDir,
  required RecordingEndReason reason,
}) async {
  final lease = WebAssetStore.lease([
    audio.durablePath,
    ?WebAssetStore.pathForName('${audio.durablePath}.sources.json'),
  ]);
  try {
    if (!context.mounted) return;
    final l10n = context.l10n;
    final web = deliversByDownload;
    final call = audio.kinds.contains(CaptureSourceKind.callAudio);
    final gaps = call
        ? missingCallAudio(readCallSources(audio.durablePath))
        : null;
    if (!context.mounted) return;
    var body = web
        ? l10n.d(
            'Download deze opname om hem te bewaren. Na het sluiten van dit venster of tabblad gaat de audio verloren.',
          )
        : switch (reason) {
            RecordingEndReason.storageFailed => l10n.d(
              'De schijf raakte vol. Deze opname stopt; eerder afgeronde opnames blijven staan.',
            ),
            RecordingEndReason.sourceLost =>
              call
                  ? l10n.d(
                      'De vergadering of de audiobron viel weg. Wat er al stond is bewaard.',
                    )
                  : l10n.d(
                      'De microfoon viel weg. Wat er al stond is bewaard.',
                    ),
            _ => l10n.d(
              'De opname staat op dit apparaat. Transcribeer hem nu, of bewaar hem zeven dagen om dat later te doen.',
            ),
          };
    if (gaps != null) {
      body +=
          '\n\n${l10n.d('Er ontbrak ~{s} s bronaudio verdeeld over {n} bron(nen) — track- of netwerkverlies tijdens de opname.').replaceAll('{s}', '${(gaps.$2.inMilliseconds / 1000).round()}').replaceAll('{n}', '${gaps.$1}')}';
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(web ? l10n.d('Audio') : l10n.d('Opname bewaard')),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              if (!web) {
                await ref.read(recordingStagingProvider).discardDir(sessionDir);
              }
            },
            child: Text(l10n.d('Opname weggooien')),
          ),
          if (web)
            TextButton(
              onPressed: () {
                final name = _offerAudioDownload(audio.durablePath);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      name == null
                          ? l10n.d('Het bestand kon niet worden opgeslagen.')
                          : '${l10n.d('Aangeboden als download:')} $name',
                    ),
                  ),
                );
              },
              child: Text(l10n.d('Download')),
            )
          else
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.d('Bewaar voor later')),
            ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await showTranscribeFileDialog(
                context,
                sourcePath: audio.durablePath,
                displayName: call
                    ? l10n.d('Vergaderingsopname')
                    : l10n.d('Microfoonopname'),
              );
            },
            child: Text(l10n.d('Nu transcriberen')),
          ),
        ],
      ),
    );
  } finally {
    audio.releaseAssets();
    lease.release();
    WebAssetStore.collectGarbage();
  }
}

String? _offerAudioDownload(String path) {
  final bytes = WebAssetStore.bytesFor(path);
  if (bytes == null) return null;
  final sidecar = WebAssetStore.pathForName('$path.sources.json');
  final metadata = sidecar == null ? null : WebAssetStore.bytesFor(sidecar);
  return deliverAsDownload([
    (name: WebAssetStore.nameFor(path) ?? 'recording.wav', bytes: bytes),
    if (metadata != null) (name: 'sources.json', bytes: metadata),
  ], bundleName: 'recording-audio.zip');
}
