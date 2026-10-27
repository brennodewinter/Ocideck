// Waar gedownloade modellen wonen (docs/design/TRANSCRIPTION.md §4.4,
// #2512): een map onder de app-support-directory, nooit in de deck of op
// een door de gebruiker aanwijsbare plek. Drie uitvoerders:
//
//  * `_io`    — desktop: `getApplicationSupportDirectory()/transcription/
//               models`, met pad-containment en symlink-weigering;
//  * `_web`   — web: IndexedDB met `.part`-sleutels en WebCrypto-hashes;
//  * `_stub`  — platforms die geen van beide hebben.
//
// De store kent de catalogus, controleert grootte en SHA-256 en ruimt
// `.part`-resten van afgebroken downloads op. Hij downloadt zelf niets —
// dat is de downloader, die hier alleen zijn eindbestand parkeert. Wel
// wijst hij kandidaten buiten de map aan (§4.4, #2601): een gelijkend
// `ggml*.bin` op een gangbare plek mag de gebruiker adopteren in plaats
// van opnieuw te downloaden.
import 'model_store_stub.dart'
    if (dart.library.io) 'model_store_io.dart'
    if (dart.library.js_interop) 'model_store_web.dart'
    as impl;

import 'whisper_model.dart';

/// De toestand van één catalogusitem op dit apparaat.
enum ModelInstallState {
  /// Niet aanwezig (of alleen een `.part`-rest — dat telt niet).
  absent,

  /// Bestand aanwezig met de juiste omvang; de hash is alleen getoetst als
  /// [verified] waar is.
  present,

  /// Aanwezig én getoetst op SHA-256 — pas dit mag de engine laden.
  verified,
}

/// De modelopslag. Synchrone padvragen zijn puur; de rest is async omdat
/// hash-verificatie over honderden megabytes loopt.
abstract class TranscriptionModelStore {
  /// De modelmap zelf (wordt aangemaakt als hij ontbreekt).
  Future<ModelStorePath> directory();

  /// Waar [model] zou moeten liggen — ook als het er (nog) niet staat.
  /// Faalt hard op een catalogusitem dat buiten de map zou uitkomen:
  /// pad-containment wordt hier afgedwongen, niet in elke aanroeper.
  Future<ModelStorePath> modelPath(WhisperModel model);

  /// De snelle toestand: bestaat het bestand en klopt zijn omvang.
  /// Een symbolische koppeling telt als [ModelInstallState.absent] én wordt
  /// gerapporteerd — een link in de modelmap is nooit van ons.
  Future<ModelInstallState> stateOf(WhisperModel model);

  /// De volledige toets: leest het bestand en vergelijkt de SHA-256 met de
  /// catalogus. Traag op grote modellen; de engine gebruikt dit vóór hij een
  /// model aan het native proces voedt.
  Future<bool> verify(WhisperModel model);

  /// Verwijdert het model — en, als het een vreemde koppeling is, alleen de
  /// koppeling (nooit het doel). Antwoordt rustig als er niets staat.
  Future<void> delete(WhisperModel model);

  /// Verwijdert `.part`-resten van afgebroken downloads. Een deels bestand
  /// mag nooit als "aanwezig" meetellen, en evenmin eeuwig blijven liggen.
  Future<void> sweepPartials();

  /// Kandidaten buiten de modelmap die op [model] lijken — een
  /// `ggml*.bin`-bestand met precies de catalogusomvang (#2601). Desktop
  /// scant een vaste lijst gangbare plekken (Downloads, de huggingface-
  /// hubcache van de modelrepository, een whisper.cpp-checkout,
  /// pywhispercpp); web en stub leveren `[]` — een browser kan de schijf
  /// niet doorzoeken. De modelmap zelf doet niet mee; `stateOf` dekt hem.
  ///
  /// Het resultaat is een vermoeden, geen bewijs: omvang zegt "lijkend",
  /// pas de SHA-256 in [adopt] zegt "hetzelfde".
  Future<List<ModelStorePath>> externalCandidates(WhisperModel model);

  /// Neemt [source] over in de modelmap als [model]. De SHA-256-toets
  /// loopt vóór het kopiëren — een bestand dat niet is wat de catalogus
  /// belooft, wordt geweigerd (`ModelDownloadException`, `invalidHash`)
  /// en landt nooit in de map. Het origineel blijft waar het ligt:
  /// weggooien van iemands eigen bestand is niet aan ons.
  Future<ModelStorePath> adopt(WhisperModel model, ModelStorePath source);
}

/// Een pad dat de store heeft afgegeven. Het type bestaat om in UI en tests
/// expliciet te maken dat de string hier al door de containment-poort is.
class ModelStorePath {
  const ModelStorePath(this.path, this.isAbsolute);

  final String path;
  final bool isAbsolute;
}

TranscriptionModelStore createModelStore() => impl.createModelStore();
