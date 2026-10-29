// De afsluit-levenscyclus zoals de shell hem bewaakt (#2631): elke
// best-effort-stap is begrensd en foutdovend, zodat [quitApp] altijd bereikt
// wordt — ook met een dood netwerk of een stap die gooit. Los van app_shell,
// dat op zijn regelplafond zit; de aanroepen staan in `_destroy()`.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/learning_session.dart';
import '../../services/single_instance.dart';
import '../../state/ociserve_provider.dart';
import '../../utils/log.dart';
import 'meeting_lifecycle.dart';
import 'recording_lifecycle.dart';

/// De opruimstappen die vóór [quitApp] nog mogen lopen. Elke stap is op
/// zichzelf al begrensd (netwerk via [boundedQuitStep], opname en call via
/// hun eigen lifecycle-helpers), dus de som is voorspelbaar kort — en toch
/// kan een trage stap de hele keten vasthouden. Daarvoor bestaat de
/// trage-sluiting-dialoog in de shell.
Future<void> runBestEffortQuitSteps(
  WidgetRef ref, {
  required List<LearningSessionRef> sessions,
}) async {
  for (final session in sessions) {
    await boundedQuitStep(
      () => ref.read(ociServeProvider.notifier).closeLessonSession(session),
      label: 'lessessie sluiten',
      budget: const Duration(seconds: 3),
    );
  }
  await stopRecordingBeforeQuit(ref);
  await leaveMeetingBeforeQuit(ref);
  // De enkel-exemplaar-socket op Linux (#2656): luisteraar dicht en het
  // bestand weg, zodat de volgende start niet eerst het lijk hoeft te ruimen.
  await boundedQuitStep(
    () => activeSingleInstance?.dispose() ?? Future.value(),
    label: 'enkel-exemplaar-socket',
    budget: const Duration(seconds: 1),
  );
}

/// Voer [step] uit als best-effort-afsluitstap: hooguit [budget] lang, en
/// elke fout of timeout gelogd maar nooit doorgegeven — de aanroeper mag er
/// op rekenen dat [quitApp] altijd bereikt wordt.
Future<void> boundedQuitStep(
  Future<void> Function() step, {
  required String label,
  required Duration budget,
}) async {
  try {
    await step().timeout(budget);
  } on TimeoutException {
    logWarning(
      'afsluiten: $label',
      'duurde langer dan ${budget.inSeconds} s — verder zonder wachten',
    );
  } on Object catch (error, stack) {
    logError('afsluiten: $label', error, stack);
  }
}
