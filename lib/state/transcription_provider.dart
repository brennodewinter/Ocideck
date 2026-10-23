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

import 'dart:convert';

import '../models/asr_server_profile.dart';
import '../services/transcription/asr_engine_factory.dart';
import '../services/transcription/capture_source.dart';
import '../services/transcription/combination_source.dart';
import '../services/transcription/desktop_mic_source.dart';
import '../services/transcription/file_capture_source.dart';
import '../services/transcription/live_pass.dart';
import '../services/transcription/mic_capture_port.dart';
import '../services/transcription/mic_capture_registry.dart';
import '../services/transcription/mic_session_gate.dart';
import '../services/transcription/local_whisper_engine.dart';
import '../services/transcription/recording_session.dart';
import '../services/transcription/recording_staging.dart';
import '../services/transcription/transcription_engine.dart';
import '../services/transcription/whisper_model.dart';
import '../utils/log.dart';
import 'transcription_model_provider.dart';

const transcriptionModuleEnabledKey = 'transcriptionModuleEnabled';

/// Prefs-sleutel voor het ASR-serverprofiel (#2524) — één JSON-blob, de
/// sleutel zelf staat in de sleutelbos (`SecretStore.asrApiKeyKey`).
const asrServerProfileKey = 'asrServerProfile';

/// Prefs-sleutel voor de gekozen transcriptieroute: `local` (standaard)
/// of `server` (#2524). De instellingskaart van #2514 stelt hem.
const transcriptionRouteKey = 'transcriptionRoute';

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

/// Het niveau van de lopende microfoonopname, 0..1. De indicator leest
/// het; de bron schrijft het. Buiten een opname staat het op 0.
final micLevelProvider = NotifierProvider<MicLevelNotifier, double>(
  MicLevelNotifier.new,
);

class MicLevelNotifier extends Notifier<double> {
  @override
  double build() => 0;

  void set(double value) => state = value;
}

/// De poort die doorvoer en opname delen. Eén houder tegelijk.
final micSessionGateProvider = Provider<MicSessionGate>(
  (ref) => MicSessionGate.instance,
);

/// De platformbinding. Op web beschrijft de poort de browser zonder hem
/// te openen; de bron zelf neemt op.
final micCapturePortProvider = Provider<MicCapturePort>(
  (ref) => createMicCapturePort(),
);

/// De capture-bronnen die dit platform klaar heeft staan, op soort.
///
/// De kaart is bewust een `Provider` en geen dienst met eigen logica:
/// een platformhelft registreert zijn bron hier door de provider te
/// overschrijven; zonder registratie is de soort eerlijk "nog niet
/// beschikbaar" in plaats van stil weggelaten. De instellingskaart
/// (#2514) toont dit register.
///
/// #2515 registreerde de bestandsbron — die bestaat op elk platform dat
/// deze provider bouwt (zijn stub meldt eerlijk `unavailable`). Desktop
/// vult microfoon, systeemgeluid en de combinatie; web vult microfoon
/// en tabgeluid.
final captureSourcesProvider = Provider<Map<CaptureSourceKind, CaptureSource>>((
  ref,
) {
  final sources = <CaptureSourceKind, CaptureSource>{
    CaptureSourceKind.file: createFileCaptureSource(),
  };
  final mic = createDesktopMicrophoneSource(
    port: ref.watch(micCapturePortProvider),
    gate: ref.watch(micSessionGateProvider),
    onLevel: (level) => ref.read(micLevelProvider.notifier).set(level),
  );
  if (mic != null) sources[CaptureSourceKind.microphone] = mic;
  final webMic = createWebMicrophoneSource(
    gate: ref.watch(micSessionGateProvider),
  );
  if (webMic != null) sources[CaptureSourceKind.microphone] = webMic;
  final system = createSystemAudioSource();
  if (system != null) sources[CaptureSourceKind.systemAudio] = system;
  final display = createWebDisplaySource();
  if (display != null) sources[CaptureSourceKind.systemAudio] = display;
  final micSource = sources[CaptureSourceKind.microphone];
  final systemSource = sources[CaptureSourceKind.systemAudio];
  if (micSource is DesktopMicrophoneSource &&
      systemSource is DesktopMicrophoneSource) {
    sources[CaptureSourceKind.combination] = CombinationSource(
      microphone: micSource,
      systemAudio: systemSource,
    );
  }
  return sources;
});

/// De transcriptie-engine die op dit platform klaarstaat: de lokale
/// whisper-engine met het gekozen model — op desktop als helperproces
/// (#2512), op web als wasm in de tab (#2513). Of die werkelijk kan,
/// bepaalt zijn `status()`/`capabilities()`; op web hangt dat af van
/// cross-origin isolatie (§5.3).
///
/// Het ASR-serverprofiel (#2524): standaard uit en zonder endpoint. De
/// instellingskaart van #2514 is zijn schrijver.
final asrServerProfileProvider =
    NotifierProvider<AsrServerProfileNotifier, AsrServerProfile>(
      AsrServerProfileNotifier.new,
    );

class AsrServerProfileNotifier extends Notifier<AsrServerProfile> {
  @override
  AsrServerProfile build() {
    _load();
    return const AsrServerProfile();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(asrServerProfileKey);
      if (raw == null) return;
      state = AsrServerProfile.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
    } catch (e, s) {
      // Kapotte opgeslagen JSON = geen profiel — fail-closed, nooit raden.
      logError('AsrServerProfileNotifier: profiel lezen', e, s);
    }
  }

  Future<void> set(AsrServerProfile profile) async {
    state = profile;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(asrServerProfileKey, jsonEncode(profile.toJson()));
    } catch (e, s) {
      logError('AsrServerProfileNotifier: profiel schrijven', e, s);
    }
  }
}

/// De gekozen transcriptieroute (`local`/`server`). Standaard lokaal —
/// de serverroute bestaat pas als de gebruiker hem aanzet (#2524), en
/// valt nooit stil de andere kant op.
final transcriptionRouteProvider =
    NotifierProvider<TranscriptionRouteNotifier, String>(
      TranscriptionRouteNotifier.new,
    );

class TranscriptionRouteNotifier extends Notifier<String> {
  @override
  String build() {
    _load();
    return 'local';
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getString(transcriptionRouteKey) ?? 'local';
    } catch (e, s) {
      logError('TranscriptionRouteNotifier: route lezen', e, s);
    }
  }

  Future<void> set(String route) async {
    state = route;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(transcriptionRouteKey, route);
    } catch (e, s) {
      logError('TranscriptionRouteNotifier: route schrijven', e, s);
    }
  }
}

/// De provider bouwt opnieuw zodra de gekozen model-id wijzigt; een lopende
/// `transcribe` is daar immuun voor omdat hij zijn eigen instantie vasthoudt.
final transcriptionEngineProvider = Provider<TranscriptionEngine?>((ref) {
  final route = ref.watch(transcriptionRouteProvider);
  if (route == 'server') {
    final profile = ref.watch(asrServerProfileProvider);
    if (profile.isConfigured) {
      return createAsrServerEngine(profile);
    }
    // Server gekozen maar niet bruikbaar geconfigureerd: terug naar lokaal
    // is de veilige richting (er verlaat dan niets het apparaat); de
    // instellingskaart toont waarom de keuze niet draagt.
  }
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

/// Voorlopige tekst van een live-engine, plus of die tekst achterloopt.
/// Leeg zolang geen engine `transcribeLive` levert — de batchroute liegt
/// hier niet.
class ProvisionalCaption {
  const ProvisionalCaption({this.text = '', this.lagging = false});

  final String text;
  final bool lagging;
}

class ProvisionalCaptionNotifier extends Notifier<ProvisionalCaption> {
  @override
  ProvisionalCaption build() => const ProvisionalCaption();

  void show(String text, {required bool lagging}) {
    state = ProvisionalCaption(text: text, lagging: lagging);
  }

  void clear() => state = const ProvisionalCaption();
}

final provisionalCaptionProvider =
    NotifierProvider<ProvisionalCaptionNotifier, ProvisionalCaption>(
      ProvisionalCaptionNotifier.new,
    );

/// Houdt de lopende [RecordingHandle]. `start()` is de enige weg naar een
/// sessie — met de bron en het toestemmingsbewijs die de manager eist.
/// `stopAll` is de enige weg eraf, voor elke eindreden.
class RecordingSessionNotifier extends Notifier<RecordingHandle?> {
  @override
  RecordingHandle? build() => null;

  LivePass? _live;
  StreamSubscription<PartialTranscript>? _partials;

  /// Start een opname via de sessiegrens. Gooit de getypte fouten van
  /// [RecordingManager.start] door naar de aanroepende flow.
  Future<RecordingHandle> start(
    CaptureSource source, {
    required Set<CaptureSourceKind> kinds,
    required RecordingConsent consent,
    String? sourcePath,
    String? inputDeviceId,
  }) async {
    final handle = await ref
        .read(recordingManagerProvider)
        .start(
          source,
          kinds: kinds,
          consent: consent,
          sourcePath: sourcePath,
          inputDeviceId: inputDeviceId,
        );
    state = handle;
    _attachLive(handle);
    handle.events.listen((event) {
      // De manager ruimt `_active` zelf op; de provider spiegelt hem zodat
      // watchers (indicator) de laatste fase nog zien. `ended`/`failed` is
      // de enige emissie die ertoe doet — daarna is de stream dicht.
      // `mounted`: de app kan de provider al weggooien terwijl de stop
      // nog een gebeurtenis aflevert.
      if (!ref.mounted) return;
      if (state == handle && event.phase != RecordingPhase.recording) {
        unawaited(_dropLive());
        state = null;
      }
    });
    return handle;
  }

  void _attachLive(RecordingHandle handle) {
    final engine = ref.read(transcriptionEngineProvider);
    if (engine == null || handle.liveChunks == null) return;
    final pass = LivePass();
    _live = pass;
    try {
      final partials = pass.attach(
        engine: engine,
        chunks: handle.liveChunks,
        onLag: (lagging) {
          if (!ref.mounted) return;
          final current = ref.read(provisionalCaptionProvider);
          ref
              .read(provisionalCaptionProvider.notifier)
              .show(current.text, lagging: lagging);
        },
      );
      if (partials == null) return;
      _partials = partials.listen((part) {
        if (!ref.mounted) return;
        ref
            .read(provisionalCaptionProvider.notifier)
            .show(part.text, lagging: pass.lagging);
      });
    } on Object {
      unawaited(pass.close());
      _live = null;
    }
  }

  Future<void> _dropLive() async {
    await _partials?.cancel();
    _partials = null;
    await _live?.close();
    _live = null;
    if (ref.mounted) ref.read(provisionalCaptionProvider.notifier).clear();
  }

  /// Stop de lopende opname om [reason] — elke eindweg uit #2510 loopt
  /// hier doorheen.
  Future<void> stopAll(RecordingEndReason reason) async {
    await ref.read(recordingManagerProvider).stop(reason);
    await _dropLive();
    state = null;
  }
}
