// Part of the app_shell library — see ../app_shell.dart.
// De opname-levenscyclus zoals de shell hem bewaakt (#2510, TRANSCRIPTION.md
// §2.3/§3.2): verlopen staging vegen bij opstarten, en een lopende opname
// netjes laten eindigen vóór het venster weg is. Als losse top-level-functies
// omdat _AppShellState op zijn plafond zit; de calls zelf blijven zichtbaar
// op de plek waar ze horen (initState, _destroy).
part of '../app_shell.dart';

/// Veeg verlopen opname-staging: mappen jonger dan de herstelperiode (7
/// dagen, §3.2) blijven liggen, oudere gaan weg. Best effort — een veegfout
/// mag de start van de app niet blokkeren.
void _sweepStaleRecordings(WidgetRef ref) {
  unawaited(
    ref
        .read(recordingStagingProvider)
        .sweep(maxAge: const Duration(days: 7))
        .catchError((Object e) => logWarning('opname-staging vegen', e)),
  );
}

/// Stop een lopende opname vóór het venster weg is. Wordt pas aangeroepen
/// ná de keuze voor sluiten — bij "annuleren" komt deze code niet aan de
/// beurt en loopt de opname gewoon door. De duurzame file wordt nog netjes
/// afgerond en blijft in staging voor de herstelperiode (§3.2).
Future<void> _stopRecordingBeforeQuit(WidgetRef ref) {
  return ref
      .read(recordingSessionProvider.notifier)
      .stopAll(RecordingEndReason.appQuit);
}
