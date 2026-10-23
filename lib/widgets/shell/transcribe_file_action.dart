// De ingang van de bestandstranscriptie (#2515): kies een audio- of
// videobestand en open de transcriptie-dialoog.
//
// Twee bronvormen, één contractpad:
//  * desktop draagt het bestandspad — de bestandsbron leest en decodeert
//    rechtstreeks, het origineel wordt nooit gekopieerd of aangeraakt;
//  * web heeft geen pad: de bytes van de kiezer gaan in de `mem:`-
//    assetstore en de sleutel is de `sourcePath` — dezelfde grens als
//    waar de web-engine zijn audio leest.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../services/web_asset_store.dart';
import '../../utils/error_snackbar.dart';
import '../../utils/log.dart';
import '../dialogs/transcribe_file_dialog.dart';

/// Welke containers de kiezer mag aanbieden. De lijst is ruim op
/// voorspraak van de decoder — de sniffer en de decode zijn de eigenlijke
/// uitspraak ("video zonder audiotrack" is een antwoord, geen afwijzing
/// vooraf).
const transcribableExtensions = [
  'wav',
  'mp3',
  'm4a',
  'aac',
  'flac',
  'ogg',
  'opus',
  'mp4',
  'm4v',
  'mov',
  'webm',
  'mkv',
  'avi',
];

/// Kies een bestand en open de transcriptie-dialoog. `null`-keuze of een
/// mislukte lezing eindigen stil resp. in een fout-snackbar — net als de
/// andere kies-acties.
Future<void> transcribeFile(BuildContext context) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: transcribableExtensions,
    dialogTitle: l10n.d('Audio- of videobestand kiezen'),
  );
  if (picked.isEmpty || !context.mounted) return;
  final file = picked.first;

  String sourcePath;
  if (kIsWeb) {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      showErrorSnackBar(
        messenger,
        l10n,
        l10n.d('Het bestand kon niet worden gelezen.'),
      );
      return;
    }
    try {
      sourcePath = WebAssetStore.put(bytes, name: file.name);
    } on WebAssetBudgetExceeded {
      showErrorSnackBar(
        messenger,
        l10n,
        l10n.d('Het bestand is te groot of er is te weinig geheugen vrij.'),
      );
      return;
    } on Object catch (e) {
      logWarning('transcribeFile: webopslag weigerde de bron', e);
      showErrorSnackBar(
        messenger,
        l10n,
        l10n.d('Het bestand kon niet worden gelezen.'),
      );
      return;
    }
  } else {
    final path = file.path;
    if (path == null || path.isEmpty) {
      showErrorSnackBar(
        messenger,
        l10n,
        l10n.d('Het bestand kon niet worden gelezen.'),
      );
      return;
    }
    sourcePath = path;
  }
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (_) =>
        TranscribeFileDialog(sourcePath: sourcePath, displayName: file.name),
  );
}

/// Het menulabel voor de transcriptie-ingang.
String transcribeFileLabel(AppLocalizations l10n) =>
    l10n.d('Audio/video transcriberen…');
