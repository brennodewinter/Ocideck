import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/transcription/capture_source.dart';
import '../../state/transcription_provider.dart';
import '../dialogs/record_system_dialog.dart';

bool systemRecordingOffered(WidgetRef ref) =>
    ref.read(captureSourcesProvider).containsKey(CaptureSourceKind.systemAudio);

bool combinationRecordingOffered(WidgetRef ref) =>
    ref.read(captureSourcesProvider).containsKey(CaptureSourceKind.combination);

String recordSystemLabel(AppLocalizations l10n) =>
    kIsWeb ? l10n.d('Tabgeluid opnemen…') : l10n.d('Systeemgeluid opnemen…');

String recordCombinationLabel(AppLocalizations l10n) =>
    l10n.d('Microfoon en systeemgeluid opnemen…');

Future<void> recordSystem(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const RecordSystemDialog(target: RecordTarget.system),
  );
}

Future<void> recordCombination(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const RecordSystemDialog(target: RecordTarget.combination),
  );
}
