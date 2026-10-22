// De getypte fouttaxonomie van transcriptie en opname
// (docs/design/TRANSCRIPTION.md §4.4). Vastgelegd vóór de platformcode, zodat
// elke bron en engine dezelfde uitsplitsing produceert: een geweigerde
// toestemming is geen ontbrekende bron, en allebei zijn het iets anders dan
// een ontbrekende engine. De UI koppelt elk type aan zijn eigen benoemde
// vervolgstap in plaats van aan één generieke "het lukte niet".

/// Basistype voor elke fout die een opname- of transcriptieroute kan geven.
///
/// `sealed`, zodat een `switch` op de fout de hele ruimte dekt en de compiler
/// roept wanneer er een variant bijkomt.
sealed class TranscriptionError implements Exception {
  const TranscriptionError(this.message);

  /// Vaste, diagnoseerbare omschrijving — nooit ruwe audio- of
  /// transcriptie-inhoud (§1: niets persoonlijks in logs).
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// De gebruiker (of het OS namens hem) weigerde de toestemming die deze bron
/// vraagt — pas nadat een bewuste actie om toestemming mocht vragen. Dit is
/// een normale uitkomst met een vervolgstap, geen crash.
class PermissionDenied extends TranscriptionError {
  const PermissionDenied(super.message);
}

/// De bron is weg of was er nooit: microfoon ontkoppeld, PipeWire niet
/// beschikbaar, de browsertab met audio is weggevallen.
class SourceUnavailable extends TranscriptionError {
  const SourceUnavailable(super.message);
}

/// De bron bestaat maar kan niet mee: DRM-beveiligde audio, een
/// Remote Desktop-sessie, een browsercap op dit platform.
class UnsupportedSource extends TranscriptionError {
  const UnsupportedSource(super.message);
}

/// Een bestaand mediabestand dat niet te decoderen is voor de
/// gekozen route (§3.2: `decodeAudioData`-dekkingsgaten op web).
class DecodeFailed extends TranscriptionError {
  const DecodeFailed(super.message);
}

/// De gevraagde engine is niet geïnstalleerd of mist zijn model — de
/// gebruiker kiest en installeert modellen zelf (§1: niets gebundeld,
/// niets stil gedownload).
class EngineUnavailable extends TranscriptionError {
  const EngineUnavailable(super.message);
}

/// De invoer is te lang of te groot voor deze route — bijvoorbeeld een
/// opname die het `mem:`-budget op web niet haalt (§3.2) of een bestand
/// dat de batchgrens van een serverprofiel overschrijdt.
class CapacityExceeded extends TranscriptionError {
  const CapacityExceeded(super.message);
}

/// De server weigerde of was onbereikbaar: netwerk, TLS of CORS. Alleen voor
/// de expliciet gekozen serverroutes (§4.3) — nooit een stille fallback van
/// een lokale route.
class ServerRefused extends TranscriptionError {
  const ServerRefused(super.message);
}

/// De route vraagt een toestemming die nog niet is verleend — een
/// serveregress-taak zonder aangekruiste bestemming (§4.3), of een bron die
/// andermans stemmen vastlegt terwijl de melding daarover niet is bevestigd
/// (§2.3).
class ConsentRequired extends TranscriptionError {
  const ConsentRequired(super.message);
}

/// De gebruiker stopte de opname of taak bewust — geen fout om te melden,
/// maar wel een uitkomst om van `failed` te onderscheiden.
class Cancelled extends TranscriptionError {
  const Cancelled(super.message);
}

/// Schijf- of budgetfout: staging kon niet worden aangemaakt, de duurzame
/// opname kon niet worden weggeschreven, het `mem:`-budget raakte vol.
class IoFailed extends TranscriptionError {
  const IoFailed(super.message);
}
