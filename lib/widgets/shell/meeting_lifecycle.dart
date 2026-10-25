// De call-levenscyclus zoals de shell hem bewaakt (#2536, NATIVE_CALLS.md §9):
// een actieve vergadering netjes beëindigen vóór het venster weg is. Los van
// app_shell, dat op zijn regelplafond zit; de aanroep staat in `_destroy()`.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/meeting_session_provider.dart';
import '../../utils/log.dart';

/// Verlaat een lopende call vóór het venster weg is. Wordt pas aangeroepen ná
/// de keuze voor sluiten — bij "annuleren" komt deze code niet aan de beurt en
/// loopt de call gewoon door. Begrensd: een leave hangt aan MUC-leave en
/// socket-close, en een dood netwerk mag het afsluiten niet vasthouden —
/// daarna ruimt de server de zombie-occupant zelf op via zijn eigen timeout.
Future<void> leaveMeetingBeforeQuit(WidgetRef ref) async {
  try {
    await ref
        .read(meetingSessionProvider.notifier)
        .leave()
        .timeout(const Duration(seconds: 5));
  } on TimeoutException {
    logWarning('call verlaten vóór afsluiten', 'leave duurde langer dan 5s');
  } on Object catch (e, s) {
    logError('call verlaten vóór afsluiten', e, s);
  }
}
