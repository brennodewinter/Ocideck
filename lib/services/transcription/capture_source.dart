// De providerneutrale brongrens (docs/design/TRANSCRIPTION.md §4.1).
//
// Hier komt audio vandaan; hoe het werkt weet alleen de bron zelf. Elke
// platformroute uit #2516–#2521 bouwt achter dit contract in plaats van
// eromheen: microfoon op macOS, WASAPI-loopback op Windows, PipeWire op
// Linux en MediaRecorder/getDisplayMedia op web zijn vier verschillende
// machines met één gezicht.
//
// Twee regels die het contract afdwingt in plaats van opschrijft:
//  * `probe()` mag nooit een toestemmingsprompt triggeren, een apparaat
//    openen of het netwerk aanraken — detectie is goedkoop en stil.
//  * `start()` is de enige call die om toestemming mág vragen, omdat de
//    gebruiker op de knop drukte die hem nodig heeft.
import 'dart:async';
import 'dart:typed_data';

/// Welke bronsoort een opname voedt. De namen volgen het contract; de
/// matrix in §5.1 zet ze per platform op beschikbaar, na toestemming,
/// niet beschikbaar of niet getest.
enum CaptureSourceKind {
  /// Een bestaand audio- of videobestand dat de gebruiker koos.
  file,

  /// De microfoon — eigen stem, en bij een vergadering in de kamer óók de
  /// luidspreker van die kamer.
  microphone,

  /// App- of systeemgeluid: wat het apparaat zelf afspeelt.
  systemAudio,

  /// Microfoon én systeemgeluid samen, waar het platform de kanalen
  /// gescheiden levert (§2.2).
  combination,
}

/// Hoe eerlijk een bron op dit apparaat, op dit moment, aangeboden kan
/// worden (§2.1: drie echte niveaus, niet het spec-ideale apparaat).
enum CaptureAvailability {
  /// Nu detecteerbaar, zonder prompt of handeling van de gebruiker.
  available,

  /// Het echte antwoord volgt pas ná de gebruikershandeling die om
  /// toestemming vraagt — proberen is de enige manier om het te weten.
  tryAfterPermission,

  /// Dit platform of deze opstelling kan het niet, met een benoemde reden.
  unavailable,

  /// Op papier aannemelijk, op díze machine nog niet bewezen.
  untested,
}

/// Waarom een capture-sessie van zichzelf eindigde — gemeld door de bron,
/// vertaald door de sessiegrens naar een [RecordingEndReason].
enum CaptureEndCause {
  /// De bron verdween of stopte van buitenaf: apparaat weg, gedeelde tab
  /// gesloten, schermdeling beëindigd door de OS.
  sourceLost,

  /// Het platform trok de toestemming in terwijl de opname liep
  /// (microfoonvoorkeur omgezet, schermtoestemming herroepen).
  permissionRevoked,
}

/// Een deelstukje live-audio voor de provisionele route (§4.2,
/// one-recording-two-outputs). Dezelfde bytes die in het duurzame bestand
/// landen — nooit een tweede greep op de microfoon.
class AudioChunk {
  const AudioChunk({required this.bytes, required this.offset});

  final Uint8List bytes;

  /// Positie in de opname waar dit blok begint.
  final Duration offset;
}

/// Wat er over is als een opname stopt: het duurzame bestand in staging
/// (dat bij bewaren naar `media/` verhuist) plus de feiten die de
/// proveniencetekst schrijft (§3.1).
class RecordedAudio {
  const RecordedAudio({
    required this.durablePath,
    required this.duration,
    required this.kinds,
  });

  /// Pad of `mem:`-sleutel van de voltooide opname. Leeg betekent: er is
  /// niets bewaard gebleven — bijvoorbeeld omdat de bron zelf al faalde
  /// voordat er bytes waren.
  final String durablePath;

  final Duration duration;

  /// De bronnen die deze opname voedden — één, of twee bij `combination`.
  final Set<CaptureSourceKind> kinds;
}

/// De bevestiging dat de gebruiker de opname bewust startte, mét de melding
/// die daarbij hoorde (§2.3). Geen juridische poort: een registratie dat de
/// toestemmingsdialoog zijn tekst heeft getoond. De dialoog is de enige
/// afnemer die dit object eerlijk kan maken; test-fakes mogen dat niet.
class RecordingConsent {
  const RecordingConsent({required this.participantNoticeAcknowledged});

  /// De melding "opnemen van anderen kan hun toestemming vragen" is getoond
  /// en bevestigd. Verplicht `true` voor bronnen die per constructie meer
  /// dan de eigen stem vastleggen (`systemAudio`, `combination`); de
  /// sessiegrens weigert zo'n start anders met [ConsentRequired].
  final bool participantNoticeAcknowledged;
}

/// Wat [CaptureSource.start] meekrijgt. Het `consent`-veld is niet
/// optioneel: een opname zonder getoonde melding kan niet bestaan zodra
/// de types kloppen.
class CaptureRequest {
  const CaptureRequest({
    required this.kinds,
    required this.consent,
    this.stagingDir,
    this.sourcePath,
  });

  /// Gevraagde bronnen — één voor de enkelvoudige routes, `microfoon` +
  /// `systemAudio` voor `combination`.
  final Set<CaptureSourceKind> kinds;

  final RecordingConsent consent;

  /// De sessie-stagingmap die [RecordingStaging] aanmaakte (desktop). Null
  /// op web, waar de bron zijn duurzame bytes in de `mem:`-assetstore legt.
  final String? stagingDir;

  /// Alleen voor `kinds == {file}`: het bestand dat getranscribeerd wordt.
  /// Wordt gerefereerd, niet gekopieerd — de bewaarkeuze bij Opslaan
  /// beslist of er een kopie in `media/` komt (§3.2).
  final String? sourcePath;
}

/// Waar bytes vandaan komen. Platformroutes implementeren dit; de rest van
/// de app kent alleen dit gezicht.
abstract class CaptureSource {
  const CaptureSource();
  CaptureSourceKind get kind;

  /// Alleen detectie. Triggert nooit een toestemmingsprompt, opent nooit
  /// een apparaat, raakt nooit het netwerk. Goedkoop genoeg om in
  /// Instellingen te draaien (§2.1).
  Future<CaptureAvailability> probe();

  /// De enige call die om toestemming mag vragen — omdat de gebruiker op
  /// een knop drukte die hem nodig heeft. Faalt gesloten met een getypte
  /// [TranscriptionError]-variant.
  Future<CaptureSession> start(CaptureRequest request);
}

/// Een lopende capture. Schrijft vanaf `start` al naar de duurzame
/// staginglocatie — een crash verliest nooit meer dan de staart.
abstract class CaptureSession {
  /// Het duurzame bestand dat wordt weggeschreven (stagingpad of
  /// `mem:`-sleutel; verhuist naar `media/` bij Opslaan). Altijd aanwezig —
  /// een sessie die niet kan bewaren is geen sessie.
  String get durablePath;

  /// Live blokken voor provisionele transcriptie, als de combinatie
  /// bron+engine dat kan. Null betekent "geen live route", niet
  /// "live is stuk" (§4.2).
  Stream<AudioChunk>? get liveChunks;

  /// Eén gebeurtenis als de bron van zichzelf eindigt — bronverlies of
  /// ingetrokken toestemming. Null als de bron geen spontaan einde kent
  /// (een bestand "loopt" niet). De sessiegrens abonneert zich hierop en
  /// stopt de opname netjes: een opname die doorgaat nadat zijn bron weg
  /// is, zou onzichtbaar doorlopen — precies wat §2.3 verbiedt.
  Stream<CaptureEndCause>? get ended;

  /// Stopt de capture; resolveert zodra het duurzame bestand compleet en
  /// geflusht is. Idempotent: een tweede `stop()` geeft hetzelfde resultaat
  /// en mag nooit twee keer dezelfde track afbreken.
  Future<RecordedAudio> stop();
}
