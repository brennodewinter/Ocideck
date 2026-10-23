// De passieve platformfeiten voor de statusmatrix in Instellingen
// (docs/design/TRANSCRIPTION.md §2.1, §5.1; #2514).
//
// Dezelfde regel als bij `CaptureSource.probe()`: detectie is goedkoop en
// stil — deze probe triggert nooit een toestemmingsprompt, opent geen
// apparaat en raakt geen netwerk. Alles hier is een getter of een
// systeemeigenschap die de platformlaag al weet:
//
//  * `_io`   — desktop: OS-naam en processorarchitectuur;
//  * `_web`  — browser: secure context, cross-origin isolatie,
//              MediaRecorder en zijn MIME-steun, opslagquota-schatting;
//  * `_stub` — geen van beide: alleen "dit platform".
//
// Wat de UI ermee doet (welke rijen, welke bewoording) hoort bij de
// instellingskaart; hier komen alleen de feiten binnen.
import 'environment_probe_stub.dart'
    if (dart.library.io) 'environment_probe_io.dart'
    if (dart.library.js_interop) 'environment_probe_web.dart'
    as impl;

/// Waar een capability-rij feitelijk van uitgaat. Elke `null` betekent
/// "op dit platform niet passief te bepalen" — de rij toont dan eerlijk
/// dat in plaats van een geraden vinkje.
class TranscriptionEnvironment {
  const TranscriptionEnvironment({
    required this.platformLabel,
    this.architecture,
    this.secureContext,
    this.crossOriginIsolated,
    this.mediaRecorderAvailable,
    this.supportedAudioMimes = const {},
    this.freeStorageBytes,
  });

  /// Mensleesbare platformnaam: `macOS`, `Windows`, `Linux`, `web`, …
  final String platformLabel;

  /// Processorarchitectuur (`arm64`, `x64`) — alleen desktop.
  final String? architecture;

  /// Alleen web: draait de pagina in een secure context (https/localhost).
  /// Zonder dit bestaat `crypto.subtle` niet en is hashverificatie
  /// onmogelijk (§4.4).
  final bool? secureContext;

  /// Alleen web: COOP/COEP-headers leveren cross-origin isolatie —
  /// de harde voorwaarde voor de wasm-engine met pthreads (§4.6).
  final bool? crossOriginIsolated;

  /// Alleen web: bestaat `MediaRecorder` in deze browser — voorwaarde voor
  /// microfoon- en tabopname (#2517/#2520).
  final bool? mediaRecorderAvailable;

  /// Alleen web: welke audiocontainers `MediaRecorder.isTypeSupported`
  /// bevestigt. Leeg op desktop, waar de bron zijn eigen decoder kent.
  final Set<String> supportedAudioMimes;

  /// Vrije opslagruimte in bytes waar die passief bekend is (web:
  /// `navigator.storage.estimate()`). Null op desktop — een betrouwbare
  /// vrije-ruimte-vraag bestaat daar niet in de standaardbibliotheek; de
  /// download faalt daar zichtbaar met `ioFailed` als de schijf vol is.
  final int? freeStorageBytes;
}

Future<TranscriptionEnvironment> probeTranscriptionEnvironment() =>
    impl.probeTranscriptionEnvironment();
