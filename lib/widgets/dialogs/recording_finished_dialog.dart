// De keuze ná Stop (#2516): nu transcriberen, bewaren voor later, of
// weggooien. De file staat al in de staging; "later" laat hem daar de
// herstelperiode van zeven dagen liggen.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/transcription/capture_source.dart';
import '../../services/transcription/recording_session.dart';
import '../../state/transcription_provider.dart';
import 'transcribe_file_dialog.dart';

Future<void> showRecordingFinishedDialog(
  BuildContext context,
  WidgetRef ref, {
  required RecordedAudio audio,
  required String? sessionDir,
  required RecordingEndReason reason,
}) {
  final l10n = context.l10n;
  final body = switch (reason) {
    RecordingEndReason.storageFailed => l10n.d(
      'De schijf raakte vol. Deze opname stopt; eerder afgeronde opnames blijven staan.',
    ),
    RecordingEndReason.sourceLost => l10n.d(
      'De microfoon viel weg. Wat er al stond is bewaard.',
    ),
    _ => l10n.d(
      'De opname staat op dit apparaat. Transcribeer hem nu, of bewaar hem zeven dagen om dat later te doen.',
    ),
  };
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.d('Opname bewaard')),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () async {
            Navigator.of(ctx).pop();
            await ref.read(recordingStagingProvider).discardDir(sessionDir);
          },
          child: Text(l10n.d('Opname weggooien')),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l10n.d('Bewaar voor later')),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            showDialog<void>(
              context: context,
              builder: (_) => TranscribeFileDialog(
                sourcePath: audio.durablePath,
                displayName: l10n.d('Microfoonopname'),
              ),
            );
          },
          child: Text(l10n.d('Nu transcriberen')),
        ),
      ],
    ),
  );
}
