// De module Transcriptie en opname en zijn root-scoped opnamesessie
// (docs/design/TRANSCRIPTION.md §1, §2.3). Zelfde vorm als de
// videovergaderingsmodule: een prefs-gestuurde schakelaar, standaard uit,
// plus één app-brede sessie die een tabwissel overleeft.
//
// Het verschil zit in het uitzetten. Een lopende vergadering mag je niet
// stranden door de schakelaar om te zetten; een lopende opname moet je
// juist wél stoppen — "de module uit" is één van de aantoonbare eindwegen
// uit #2510. De opname stopt netjes (de capture rondt zijn stagingbestand
// af), de herstelperiode bewaart wat er lag, en het transcript staat er
// niet zomaar een halfbestand bij.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/transcription/capture_source.dart';
import '../services/transcription/recording_session.dart';
import '../services/transcription/recording_staging.dart';
import '../services/transcription/transcription_engine.dart';
import '../utils/log.dart';

const transcriptionModuleEnabledKey = 'transcriptionModuleEnabled';

/// De staginggrens van de opnamemodule. Heeft een eigen provider omdat de
/// shell hem bij opstarten laat vegen én tests hem vervangen door een
/// instantie op een tijdelijke map.
final recordingStagingProvider = Provider<RecordingStaging>(
  (ref) => createRecordingStaging(),
);

/// De enige [RecordingManager] van de app — de grens die bezit wat
/// "een opname loopt" betekent.
final recordingManagerProvider = Provider<RecordingManager>((ref) {
  return RecordingManager(staging: ref.watch(recordingStagingProvider));
});

/// De transcriptie-engine die op dit platform klaarstaat — `null` tot een
/// latere route er een registreert (#2512 desktop, #2513 web, #2524/#2525
/// serverprofielen). `null` is geen afwezigheid maar een capaciteit: de
/// grens beantwoordt hem als `engineUnavailable` (§4.4). Opnemen mag dus
/// nog steeds — alleen van een vers opgenomen bestand komt nog geen
/// transcript.
final transcriptionEngineProvider = Provider<TranscriptionEngine?>(
  (ref) => null,
);

final transcriptionModuleProvider =
    NotifierProvider<TranscriptionModuleNotifier, TranscriptionModuleState>(
      TranscriptionModuleNotifier.new,
    );

/// Of de Transcriptie-schakelaar aan staat (de bewaarde voorkeur).
final transcriptionEnabledProvider = Provider<bool>((ref) {
  return ref.watch(
    transcriptionModuleProvider.select((state) => state.enabled),
  );
});

/// Zichtbaar zodra de module aan staat — en zolang een opname loopt, wat
/// de schakelaar ook zegt: een actieve sessie strandt zijn indicator niet.
final transcriptionRevealProvider = Provider<bool>((ref) {
  return ref.watch(transcriptionEnabledProvider) ||
      ref.watch(recordingSessionProvider) != null;
});

/// De lopende opname, root-scoped zodat hij een tab- of vensterwissel
/// overleeft (§2.3: de indicator mag nooit verdwijnen terwijl er wordt
/// opgenomen). Null als er niets loopt.
final recordingSessionProvider =
    NotifierProvider<RecordingSessionNotifier, RecordingHandle?>(
      RecordingSessionNotifier.new,
    );

class TranscriptionModuleState {
  final bool enabled;
  final bool loading;

  const TranscriptionModuleState({this.enabled = false, this.loading = true});
}

class TranscriptionModuleNotifier extends Notifier<TranscriptionModuleState> {
  @override
  TranscriptionModuleState build() {
    _initialize();
    return const TranscriptionModuleState();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = TranscriptionModuleState(
        enabled: prefs.getBool(transcriptionModuleEnabledKey) ?? false,
        loading: false,
      );
    } catch (e, s) {
      logError('TranscriptionModuleNotifier: voorkeur lezen', e, s);
      state = const TranscriptionModuleState(loading: false);
    }
  }

  Future<void> setEnabled(bool value) async {
    state = TranscriptionModuleState(enabled: value, loading: false);
    if (!value) {
      // Module uit = opname uit. De gebruiker koos de schakelaar bewust;
      // het duurzame stagingbestand blijft liggen voor de herstelperiode.
      await ref
          .read(recordingSessionProvider.notifier)
          .stopAll(RecordingEndReason.moduleDisabled);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(transcriptionModuleEnabledKey, value);
    } catch (e, s) {
      logError('TranscriptionModuleNotifier: voorkeur schrijven', e, s);
    }
  }
}

/// Houdt de lopende [RecordingHandle]. `start()` is de enige weg naar een
/// sessie — met de bron en het toestemmingsbewijs die de manager eist.
/// `stopAll` is de enige weg eraf, voor elke eindreden.
class RecordingSessionNotifier extends Notifier<RecordingHandle?> {
  @override
  RecordingHandle? build() => null;

  /// Start een opname via de sessiegrens. Gooit de getypte fouten van
  /// [RecordingManager.start] door naar de aanroepende flow.
  Future<RecordingHandle> start(
    CaptureSource source, {
    required Set<CaptureSourceKind> kinds,
    required RecordingConsent consent,
    String? sourcePath,
  }) async {
    final handle = await ref
        .read(recordingManagerProvider)
        .start(source, kinds: kinds, consent: consent, sourcePath: sourcePath);
    state = handle;
    handle.events.listen((event) {
      // De manager ruimt `_active` zelf op; de provider spiegelt hem zodat
      // watchers (indicator) de laatste fase nog zien. `ended`/`failed` is
      // de enige emissie die ertoe doet — daarna is de stream dicht.
      if (state == handle && event.phase != RecordingPhase.recording) {
        state = null;
      }
    });
    return handle;
  }

  /// Stop de lopende opname om [reason] — elke eindweg uit #2510 loopt
  /// hier doorheen.
  Future<void> stopAll(RecordingEndReason reason) async {
    await ref.read(recordingManagerProvider).stop(reason);
    state = null;
  }
}
