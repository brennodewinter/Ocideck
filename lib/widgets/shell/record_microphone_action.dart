import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../dialogs/record_microphone_dialog.dart';

/// De microfoonroute bestaat op desktop en in de browser. De browser
/// vraagt pas toestemming als de opname start.
bool get microphoneRecordingOffered => true;

String recordMicrophoneLabel(AppLocalizations l10n) =>
    l10n.d('Microfoon opnemen…');

Future<void> recordMicrophone(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const RecordMicrophoneDialog(),
  );
}
