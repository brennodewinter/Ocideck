// De ingang van de bestandstranscriptie (#2515): kies een audio- of
// videobestand en open de transcriptie-dialoog.
//
// Twee bronvormen, één contractpad:
//  * desktop draagt het bestandspad — de bestandsbron leest en decodeert
//    rechtstreeks, het origineel wordt nooit gekopieerd of aangeraakt;
//  * web heeft geen pad: de bytes van de kiezer gaan in de `mem:`-
//    assetstore en de sleutel is de `sourcePath` — dezelfde grens als
//    waar de web-engine zijn audio leest.
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../services/transcription/media_sniff.dart';
import '../../services/web_asset_store.dart';
import '../../utils/error_snackbar.dart';
import '../../utils/log.dart';
import '../dialogs/transcribe_file_dialog.dart';

/// Welke containers de kiezer mag aanbieden. De lijst is ruim op
/// voorspraak van de decoder — de sniffer en de decode zijn de eigenlijke
/// uitspraak ("video zonder audiotrack" is een antwoord, geen afwijzing
/// vooraf).
final transcribableExtensions = mediaFileExtensions.toList()..sort();

/// De gedeelde media-openroute (#2932): de transcriptievoorbeschouwing
/// voor een al gekozen bron — vanuit de losse actie, de gewone
/// openwegen, drag-drop en de URL-router. [sourcePath] is het pad
/// (desktop) of de `mem:`-sleutel (web); herkennen start nog geen
/// decode — die begint pas na de Start-keuze in de dialoog.
///
/// Een geannuleerde dialoog is afgehandeld, géén fout: er valt niets te
/// melden en de aanroeper gaat gewoon door met het volgende bestand.
Future<void> openMediaForTranscription(
  BuildContext context, {
  required String sourcePath,
  required String displayName,
}) async {
  await showDialog<void>(
    context: context,
    builder: (_) =>
        TranscribeFileDialog(sourcePath: sourcePath, displayName: displayName),
  );
}

/// De bytesvariant van [openMediaForTranscription] voor de routes die
/// bytes hebben in plaats van een pad (web-picker, web-drop, URL-fetch).
/// De bytes gaan de `mem:`-assetstore in — zelfde grens als waar de
/// web-engine zijn audio leest — en de sleutel is de `sourcePath`.
Future<void> openMediaBytesForTranscription(
  BuildContext context,
  Uint8List bytes,
  String name,
) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  if (bytes.isEmpty) {
    showErrorSnackBar(
      messenger,
      l10n,
      l10n.d('Het bestand kon niet worden gelezen.'),
    );
    return;
  }
  final String sourcePath;
  try {
    sourcePath = WebAssetStore.put(bytes, name: name);
  } on WebAssetBudgetExceeded {
    showErrorSnackBar(
      messenger,
      l10n,
      l10n.d('Het bestand is te groot of er is te weinig geheugen vrij.'),
    );
    return;
  } on Object catch (e) {
    logWarning('openMediaBytesForTranscription: webopslag weigerde de bron', e);
    showErrorSnackBar(
      messenger,
      l10n,
      l10n.d('Het bestand kon niet worden gelezen.'),
    );
    return;
  }
  if (!context.mounted) return;
  await openMediaForTranscription(
    context,
    sourcePath: sourcePath,
    displayName: name,
  );
}

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

  if (kIsWeb) {
    final bytes = await file.readAsBytes();
    if (!context.mounted) return;
    await openMediaBytesForTranscription(context, bytes, file.name);
    return;
  }
  final path = file.path;
  if (path == null || path.isEmpty) {
    showErrorSnackBar(
      messenger,
      l10n,
      l10n.d('Het bestand kon niet worden gelezen.'),
    );
    return;
  }
  if (!context.mounted) return;
  await openMediaForTranscription(
    context,
    sourcePath: path,
    displayName: file.name,
  );
}

/// Het menulabel voor de transcriptie-ingang.
String transcribeFileLabel(AppLocalizations l10n) =>
    l10n.d('Audio/video transcriberen…');
