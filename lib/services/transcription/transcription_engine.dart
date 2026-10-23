// De providerneutrale enginegrens (docs/design/TRANSCRIPTION.md §4.2–4.3).
//
// Hier komt tekst vandaan. Drie engine-soorten achter één interface: een
// lokale engine op het apparaat, een door de gebruiker gekozen batchserver,
// en een door de gebruiker gekozen live-server. De tabel in §4.3 legt per
// soort vast welke toestemming geldt — per taak, per sessie, of helemaal
// geen.
//
// Twee harde regels uit het contract:
//  * de serverroute is een eigen profiel, nooit een modus van
//    `AiClientService` — de AI-backend spreekt chat/completions-tekst, een
//    ASR-route spreekt audio-in/tekst-uit, en wie ze samenvoegt geeft elke
//    geconfigureerde chat-endpoint stil een audiofeed mee;
//  * een lokale route valt nooit stil terug op upload: faalt de lokale
//    engine, dan hoort de gebruiker dat en kiest hij zelf de volgende stap.
import 'dart:async';

import 'capture_source.dart' show AudioChunk;
import 'transcription_errors.dart';

/// Welke machine de tekst maakt — bepaalt welke toestemming geldt (§4.3).
enum EngineKind {
  /// Op het apparaat zelf; niets verlaat het toestel.
  local,

  /// Een door de gebruiker geconfigureerd ASR-endpoint: een voltooide
  /// opname uploaden, een transcript terugkrijgen. Toestemming per taak.
  batchServer,

  /// Een geconfigureerd endpoint met een bewezen streaming-protocol voor
  /// provisionele tekst. Toestemming per sessie.
  liveServer,
}

/// Wat deze engine op dit apparaat waarachtig kan leveren. De UI bouwt zijn
/// aanbod hieruit en uit niets anders (§4.2) — tijdstempels en
/// sprekerlabels bestaan alleen waar de engine ze levert (§2.4).
class EngineCapabilities {
  const EngineCapabilities({
    this.languages = const {},
    this.timestamps = false,
    this.diarization = false,
    this.streaming = false,
    this.requiresModel,
  });

  /// Taalcodes die de engine aankan; leeg = nog niet bekend/geen keuze.
  final Set<String> languages;
  final bool timestamps;
  final bool diarization;

  /// Kan [TranscriptionEngine.transcribeLive] leveren.
  final bool streaming;

  /// Welk model deze engine nodig heeft als dat er is, of null.
  /// Aanwezig is geen belofte dat het er staat — modellen beheert de
  /// gebruiker (#2512/#2513), [EngineUnavailable] is het eerlijke antwoord
  /// als het ontbreekt.
  final String? requiresModel;
}

/// Eén stuk transcript zoals de engine het leverde: tekst, met alleen de
/// details die echt bestaan. Een segment zonder `start` kreeg geen
/// tijdstempel; zonder `speaker` kreeg het geen spreker. Afwezig is een
/// feit, geen weggelaten verplichting (§2.4).
class TranscriptSegment {
  const TranscriptSegment({required this.text, this.start, this.speaker});

  final String text;
  final Duration? start;
  final String? speaker;
}

/// De uitslag van de definitieve pass: platte tekst plus — waar de engine
/// het leverde — de segmenten waaruit tijdstempels en sprekers komen.
class TranscriptResult {
  const TranscriptResult({this.segments = const []});

  final List<TranscriptSegment> segments;

  /// De doorlopende tekst: de segmenten aan elkaar, of de enige vorm die
  /// de engine gaf.
  String get text => segments.map((s) => s.text).join();
}

/// Eén regel provisionele tekst uit de live-route. Mag overal gemarkeerd
/// zijn als voorlopig tot de definitieve pass hem vervangt
/// (§4.2 one-recording-two-outputs).
class PartialTranscript {
  const PartialTranscript({required this.text, required this.offset});

  final String text;
  final Duration offset;
}

/// De bewuste toestemming voor één servertaak (§4.3: per taak, met host én
/// bestand benoemd). De consentdialoog is de enige eerlijke maker; de
/// engine toetst of de bevestigde waarden exact overeenkomen met wat hij
/// gaat versturen — alles anders is [ConsentRequired].
class ServerConsent {
  const ServerConsent({required this.host, required this.audioPath});

  /// De host die in de bevestiging stond — moet gelijk zijn aan de host
  /// van het serverprofiel.
  final String host;

  /// De audioverwijzing die in de bevestiging stond — moet gelijk zijn aan
  /// de `AudioRef.path` van deze taak.
  final String audioPath;
}

/// Keuzes voor één transcriptietaak. Klein gehouden: wat elke engine
/// eerlijk kan aannemen, niet wat één leverancier toevallig kent.
class TranscriptionOptions {
  const TranscriptionOptions({
    this.language,
    this.serverConsent,
    this.onProgress,
  });

  /// Gewenste taal (bijv. `nl`), of null voor "laat de engine detecteren".
  final String? language;

  /// Verplicht voor een `batchServer`/`liveServer`-engine; een lokale
  /// engine negeert dit veld.
  final ServerConsent? serverConsent;

  /// Voortgang per verwerkt audiosegment: een fractie 0..1 van de duur
  /// als die bekend is (#2515). Engines die niets zinnigs kunnen zeggen
  /// (een server met één bulkantwoord) roepen hem simpelweg niet — de
  /// UI toont dan een onbepaalde voortgang, geen verzonnen percentage.
  final void Function(double fraction)? onProgress;
}

/// Verwijzing naar duurzame audio voor [TranscriptionEngine.transcribe] —
/// een stagingpad op desktop of een `mem:`-sleutel op web. Het is aan de
/// engine-implementatie om hem te lezen; de grens draagt hem alleen.
class AudioRef {
  const AudioRef(this.path);

  final String path;
}

/// Waar tekst vandaan komt. Implementaties: de lokale engines uit
/// #2512/#2513 en de serverprofielen uit #2524/#2525.
abstract class TranscriptionEngine {
  EngineKind get kind;

  /// Wat deze engine waarachtig kan op dit apparaat (§4.2). Detectie
  /// alleen — opent geen model, raakt geen netwerk bij `local`.
  Future<EngineCapabilities> capabilities();

  /// De definitieve pass over een voltooide opname. Staat op élke
  /// engine-soort — provisionele tekst is nooit een vervanging.
  Future<TranscriptResult> transcribe(
    AudioRef audio,
    TranscriptionOptions options,
  );

  /// Provisionele tekst over live blokken — alleen `liveServer` en lokale
  /// engines met `streaming`. Null betekent "geen live route".
  Stream<PartialTranscript>? transcribeLive(Stream<AudioChunk> chunks);

  /// Breekt een lopende [transcribe] af; de toekomst voltooit met
  /// [Cancelled]. Niets aan de hand als er niets liep.
  void cancel();
}
