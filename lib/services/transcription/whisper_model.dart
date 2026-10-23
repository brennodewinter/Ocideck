// De modelcatalogus voor de lokale engine (docs/design/TRANSCRIPTION.md
// §4.4, #2512).
//
// Elke rij is een whisper.cpp-model (`ggml-*.bin`) dat de gebruiker zélf
// binnenhaalt — niets hiervan wordt meegeleverd of stil gedownload. De
// catalogus is bewust klein: modellen kosten honderden megabytes schijf en
// elke extra keuze is een extra keuze die de gebruiker moet begrijpen.
//
// Waarom deze drie:
//  * `base` en `tiny` produceerden in de proef op Nederlandse spraak te veel
//    verwisselde woorden om als standaard aan te bieden (zie §4.5) — `base`
//    staat er wél bij als lichtste optie voor zwakke hardware, eerlijk
//    gelabeld als "licht";
//  * `small` is de kleinste die op Nederlands bruikbaar scoort;
//  * `large-v3-turbo` levert de kwaliteit die het issue vraagt en draait op
//    hedendaagse desktophardware ruim sneller dan realtime.
//
// De URL's pinnen op de commit van de model-repository (niet op `main`),
// en elke rij draagt de SHA-256 van het `.bin`-bestand. Downloaden zonder
// die twee is als pinnen op "latest" — de hash hieronder ís de pin.
//
// Bron en licentie: de gewichten zijn OpenAI Whisper (MIT), gedistribueerd
// als ggml `.bin` door de whisper.cpp-modelrepository. De runtime is
// whisper.cpp v1.9.5 (MIT), zie native/whisper_cli/manifest.json.

/// Herkomst-revisie van `huggingface.co/ggerganov/whisper.cpp` waarop de
/// model-URL's pinnen — zo kan een herverpakte `main` nooit stil iets anders
/// opleveren dan wat hier getoetst is.
const whisperModelRepoRevision = '5359861c739e955e79d9a303bcbc70fb988958b1';

/// Eén aanbiedbaar model: wat er binnengehaald kan worden, hoe zwaar het is,
/// en hoe de gebruiker kan toetsen dat hij kreeg wat beloofd is.
class WhisperModel {
  const WhisperModel({
    required this.id,
    required this.fileName,
    required this.sha256,
    required this.downloadBytes,
    required this.diskBytes,
    required this.tier,
  });

  /// Stabiele sleutel voor instellingen en `EngineCapabilities.requiresModel`.
  final String id;

  /// Bestandsnaam zoals hij onder de modelmap op schijf komt — tevens de naam
  /// in de upstream-repository.
  final String fileName;

  /// Verwachte SHA-256 van het bestand. Een mismatch is een weigering, geen
  /// waarschuwing (#2512): een model dat niet is wat het catalogusitem zegt
  /// wordt nooit aan de engine aangeboden.
  final String sha256;

  /// Wat de gebruiker over de lijn haalt — staat in de UI vóórdat hij kiest.
  final int downloadBytes;

  /// Wat het bestand op schijf moet innemen; `isInstalled` toetst hierop
  /// als snelle pre-check vóór een eventuele hash-verificatie.
  final int diskBytes;

  /// Eerlijke kwaliteitsaanduiding voor in de UI: `light` (snel, zwakker),
  /// `balanced` (standaard), `accurate` (grootst, best).
  final String tier;

  /// De URL waar dit model vandaan komt — https, op de repository-revisie
  /// gepind. Het pad mag nooit uit dit patroon ontsnappen: de downloader
  /// behandelt elke redirect-hop als een nieuwe, onbetrouwbare bestemming.
  Uri get url => Uri.parse(
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/'
    '$whisperModelRepoRevision/$fileName',
  );
}

/// De catalogus. De eerste rij is de aanbevolen standaard (§7: beste
/// prijs/kwaliteit op Nederlands); `base` staat laatst als eerlijk
/// gelabelde lichtste optie.
const whisperModelCatalog = <WhisperModel>[
  WhisperModel(
    id: 'small',
    fileName: 'ggml-small.bin',
    sha256: '1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b',
    downloadBytes: 487601967,
    diskBytes: 487601967,
    tier: 'balanced',
  ),
  WhisperModel(
    id: 'large-v3-turbo',
    fileName: 'ggml-large-v3-turbo.bin',
    sha256: '1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69',
    downloadBytes: 1624555275,
    diskBytes: 1624555275,
    tier: 'accurate',
  ),
  WhisperModel(
    id: 'base',
    fileName: 'ggml-base.bin',
    sha256: '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe',
    downloadBytes: 147951465,
    diskBytes: 147951465,
    tier: 'light',
  ),
];

/// Het item bij [id], of null als de catalogus hem niet kent — afwezig is
/// een feit, geen gok (#2512: een onbekend model is `EngineUnavailable`,
/// nooit "haal maar iets").
WhisperModel? whisperModelById(String? id) {
  for (final model in whisperModelCatalog) {
    if (model.id == id) return model;
  }
  return null;
}
