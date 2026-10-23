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
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/transcription/capture_source.dart';
import '../services/transcription/local_whisper_engine.dart';
import '../services/transcription/recording_session.dart';
import '../services/transcription/recording_staging.dart';
import '../services/transcription/transcription_engine.dart';
import '../services/transcription/whisper_model.dart';
import '../utils/log.dart';
import 'transcription_model_provider.dart';

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

/// De transcriptie-engine die op dit platform klaarstaat: de lokale
/// whisper-engine met het gekozen model — op desktop als helperproces
/// (#2512), op web als wasm in de tab (#2513). Of die werkelijk kan,
/// bepaalt zijn `status()`/`capabilities()`; op web hangt dat af van
/// cross-origin isolatie (§5.3).
///
/// De provider bouwt opnieuw zodra de gekozen model-id wijzigt; een lopende
/// `transcribe` is daar immuun voor omdat hij zijn eigen instantie vasthoudt.
final transcriptionEngineProvider = Provider<TranscriptionEngine?>((ref) {
  // Zoek in de platformcatalogus — niet de hele lijst: een op desktop
  // opgeslagen keuze voor een model dat web niet kan dragen (bv.
  // `large-v3-turbo`) mag hier nooit de web-engine voeden.
  final catalog = ref.watch(whisperModelCatalogProvider);
  final selectedId = ref.watch(selectedTranscriptionModelProvider);
  WhisperModel? model;
  for (final m in catalog) {
    if (m.id == selectedId) model = m;
  }
  return createLocalWhisperEngine(model: model ?? catalog.first);
});

/// Een verzoek aan het open transcriptdocument: pas deze binnenkomende tekst
/// toe — een definitieve pass na opname, of een nieuwe modelrun. De sessie
/// die hem schreef weet welke tekst er al stond en geeft die mee als
/// [baseline]; wijkt de huidige body daarvan af, dan heeft iemand hem
/// aangeraakt en mag alleen de gebruiker besluiten (§3.1: provenance en
/// tekst die iemand bewerkte zijn geen klad).
class TranscriptApplyRequest {
  TranscriptApplyRequest({required this.incoming, this.baseline});

  /// De binnenkomende transcripttekst voor onder de `---`-scheiding.
  final String incoming;

  /// De tekst die de sessie er eerder zelf neerzette, als die er is.
  final String? baseline;

  /// `true` = de tekst is overgenomen; `false` = de gebruiker koos zijn
  /// eigen tekst, of de weg ernaartoe was versperd.
  final completer = Completer<bool>();
}

/// Hooguit één openstaand toepassingsverzoek. De producers (#2515 bestand,
/// #2522 live+definitief) zetten hem; de documenteditor beantwoordt hem.
final transcriptApplyRequestProvider =
    NotifierProvider<TranscriptApplyNotifier, TranscriptApplyRequest?>(
      TranscriptApplyNotifier.new,
    );

class TranscriptApplyNotifier extends Notifier<TranscriptApplyRequest?> {
  @override
  TranscriptApplyRequest? build() => null;

  /// Dient een verzoek in en wacht op de afloop. Een nieuw verzoek lost een
  /// hangend verzoek op met `false` — de tekst waarop hij draaide is inmiddels
  /// vervangen, dus doorgaan had stil de nieuwe staat overschreven.
  Future<bool> request({required String incoming, String? baseline}) {
    state?.completer.complete(false);
    final next = TranscriptApplyRequest(incoming: incoming, baseline: baseline);
    state = next;
    return next.completer.future;
  }

  /// De antwoordkant — de editor meldt of de tekst overgenomen is.
  void resolve(bool applied) {
    final pending = state;
    state = null;
    pending?.completer.complete(applied);
  }
}

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
