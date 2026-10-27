// Het beheer van transcriptiemodellen (docs/design/TRANSCRIPTION.md §4.4,
// #2512): welke staan er, welke is gekozen, en de lopende download.
//
// Bewuste vorm: de store en de downloader zijn services; deze provider is
// de enige plek die hun toestand aan de UI toont. Zo blijft "wat ligt er
// op schijf" herleidbaar en blijft de UI een spiegel — nooit de bron.
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/transcription/model_download.dart';
import '../services/transcription/model_store.dart';
import '../services/transcription/whisper_model.dart';
import '../utils/log.dart';

const transcriptionModelIdKey = 'transcriptionModelId';

final transcriptionModelStoreProvider = Provider<TranscriptionModelStore>(
  (ref) => createModelStore(),
);

final transcriptionModelDownloaderProvider = Provider<ModelDownloader>(
  (ref) => createModelDownloader(),
);

/// De aanbieding zoals de manager hem afloopt — een provider (net als de
/// store en downloader) zodat tests de catalogus kunnen vervangen zonder
/// aan de const-lijst te morrelen. Op web bevat hij alleen modellen die de
/// wasm-engine echt kan laden (§4.6: het 2 GB-plafond sluit `large-*` uit).
final whisperModelCatalogProvider = Provider<List<WhisperModel>>(
  (ref) => kIsWeb
      ? whisperModelCatalog.where((m) => m.webCapable).toList()
      : whisperModelCatalog,
);

/// De toestand van één catalogusitem zoals de UI hem tekent.
class TranscriptionModelStatus {
  const TranscriptionModelStatus({
    this.install = ModelInstallState.absent,
    this.downloading = false,
    this.installing = false,
    this.progress = 0.0,
    this.failure,
    this.externalCandidate,
  });

  final ModelInstallState install;

  /// Een transfer loopt — [progress] is dan 0..1.
  final bool downloading;

  /// Een adoptie van schijf loopt (hashen + kopiëren — #2601). Kan niet
  /// afgebroken worden; de overname is te kort om een eigen annuleerpad
  /// te rechtvaardigen.
  final bool installing;
  final double progress;

  /// De laatste download- of adoptiefout (voor de meldingsstrook), of null.
  final ModelDownloadFailure? failure;

  /// Een gelijkend bestand buiten de modelmap (#2601) — alleen gezet
  /// terwijl [install] `absent` is; de store toetst zijn echte identiteit
  /// pas bij adoptie.
  final ModelStorePath? externalCandidate;

  TranscriptionModelStatus copyWith({
    ModelInstallState? install,
    bool? downloading,
    bool? installing,
    double? progress,
    ModelDownloadFailure? failure,
    ModelStorePath? externalCandidate,
    bool clearFailure = false,
    bool clearCandidate = false,
  }) => TranscriptionModelStatus(
    install: install ?? this.install,
    downloading: downloading ?? this.downloading,
    installing: installing ?? this.installing,
    progress: progress ?? this.progress,
    failure: clearFailure ? null : (failure ?? this.failure),
    externalCandidate: clearCandidate
        ? null
        : (externalCandidate ?? this.externalCandidate),
  );
}

/// Per model-id zijn status; afwezig = "nog niet opgehaald" (toon als
/// [ModelInstallState.absent]).
final transcriptionModelManagerProvider =
    NotifierProvider<
      TranscriptionModelManager,
      Map<String, TranscriptionModelStatus>
    >(TranscriptionModelManager.new);

/// Het gekozen model — bewaard, en bewust in dezelfde provider-familie:
/// de engineprovider leest hem via [selectedTranscriptionModelProvider].
final selectedTranscriptionModelProvider =
    NotifierProvider<SelectedModelNotifier, String>(SelectedModelNotifier.new);

class SelectedModelNotifier extends Notifier<String> {
  @override
  String build() {
    _load();
    return ref.read(whisperModelCatalogProvider).first.id;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(transcriptionModelIdKey);
      if (stored != null && _byId(stored) != null) {
        state = stored;
      }
    } catch (e, s) {
      logError('SelectedModelNotifier: voorkeur lezen', e, s);
    }
  }

  WhisperModel? _byId(String id) {
    for (final m in ref.read(whisperModelCatalogProvider)) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<void> select(String id) async {
    if (_byId(id) == null) return;
    state = id;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(transcriptionModelIdKey, id);
    } catch (e, s) {
      logError('SelectedModelNotifier: voorkeur schrijven', e, s);
    }
  }
}

/// Serialiseert downloads (één tegelijk — twee transfers om dezelfde
/// `.part` laten vechten heeft geen zinnig antwoord) en houdt de UI-spiegel.
class TranscriptionModelManager
    extends Notifier<Map<String, TranscriptionModelStatus>> {
  /// De lopende download per model-id (hooguit één totaal, maar een map
  /// houdt de vorm eerlijk).
  final _active = <String, ModelDownload>{};

  @override
  Map<String, TranscriptionModelStatus> build() {
    // `Future(...)` plant op de event loop: `state` bestaat pas ná deze
    // return, dus de eerste refresh mag niet synchron uit build vertrekken.
    unawaited(Future(_refreshAll));
    return const {};
  }

  TranscriptionModelStatus _statusOf(String id) =>
      state[id] ?? const TranscriptionModelStatus();

  void _set(String id, TranscriptionModelStatus status) {
    state = {...state, id: status};
  }

  Future<void> _refreshAll() async {
    if (!ref.mounted) return;
    // Afgebroken downloads mogen geen `.part`-rest achterlaten dat eeuwig
    // opslag vreet — op web is dat een heel model in IndexedDB.
    try {
      await ref.read(transcriptionModelStoreProvider).sweepPartials();
    } catch (e, s) {
      logError('ModelManager: .part-resten vegen', e, s);
    }
    for (final model in ref.read(whisperModelCatalogProvider)) {
      final status = _statusOf(model.id);
      if (status.downloading || status.installing) continue;
      final install = await _stateOf(model);
      // Alleen bij `absent` is een kandidaat ergens anders op schijf nog
      // nieuws; bij present/verified is hij ingeruild en moet hij weg uit
      // de spiegel.
      final candidate = install == ModelInstallState.absent
          ? await _externalCandidate(model)
          : null;
      if (!ref.mounted) return;
      _set(
        model.id,
        _statusOf(model.id).copyWith(
          install: install,
          externalCandidate: candidate,
          clearCandidate: candidate == null,
        ),
      );
    }
  }

  Future<ModelInstallState> _stateOf(WhisperModel model) async {
    try {
      return await ref.read(transcriptionModelStoreProvider).stateOf(model);
    } catch (e, s) {
      logError('ModelManager: toestand van ${model.id} lezen', e, s);
      return ModelInstallState.absent;
    }
  }

  /// De eerste schijfkandidaat van [model] — meerdere hits zijn zeldzaam
  /// en de eerste volstaat: de hash bij `adopt` maakt de echte toets, de
  /// volgorde van de kandidaatlijst (Downloads vóór caches) is al de
  /// meest waarschijnlijke.
  Future<ModelStorePath?> _externalCandidate(WhisperModel model) async {
    try {
      final found = await ref
          .read(transcriptionModelStoreProvider)
          .externalCandidates(model);
      return found.firstOrNull;
    } catch (e, s) {
      logError('ModelManager: schijfkandidaten van ${model.id}', e, s);
      return null;
    }
  }

  /// Start de download die de gebruiker koos. Serialiseert: een tweede
  /// `download` terwijl er één loopt is een no-op — de UI biedt die knop
  /// dan ook niet aan.
  Future<void> download(WhisperModel model) async {
    // De poort kijkt naar de `downloading`-/`installing`-vlaggen, niet
    // alleen naar _active: die map vult pas na de eerste awaits, dus wie
    // hem alleen bewaakt laat een tweede schrijver op `.part` in het
    // opstartvenster toch door.
    if (_active.isNotEmpty ||
        state.values.any((s) => s.downloading || s.installing)) {
      return;
    }
    final store = ref.read(transcriptionModelStoreProvider);
    final downloader = ref.read(transcriptionModelDownloaderProvider);
    _set(
      model.id,
      _statusOf(
        model.id,
      ).copyWith(downloading: true, progress: 0, clearFailure: true),
    );
    try {
      final destination = await store.modelPath(model);
      final handle = downloader.start(model, destination);
      _active[model.id] = handle;
      unawaited(
        handle.progress.forEach((p) {
          if (!ref.mounted) return;
          final total = p.total > 0 ? p.total : model.downloadBytes;
          _set(
            model.id,
            _statusOf(model.id).copyWith(
              downloading: true,
              progress: total > 0 ? p.received / total : 0,
            ),
          );
        }),
      );
      await handle.done;
      if (!ref.mounted) return;
      _set(
        model.id,
        const TranscriptionModelStatus(install: ModelInstallState.present),
      );
    } on ModelDownloadException catch (e) {
      if (!ref.mounted) return;
      _set(
        model.id,
        _statusOf(model.id).copyWith(
          downloading: false,
          progress: 0,
          install: await _stateOf(model),
          failure: e.failure,
        ),
      );
    } on Object catch (e, s) {
      // Geen ModelDownloadException (bijv. de containment-worp uit
      // modelPath): de vlag moet alsnog terug, anders is de manager
      // voorgoed bezet. De fout zelf propageren we eerlijk verder.
      logError('ModelManager: download van ${model.id}', e, s);
      if (ref.mounted) {
        _set(
          model.id,
          _statusOf(model.id).copyWith(downloading: false, progress: 0),
        );
      }
      rethrow;
    } finally {
      _active.remove(model.id);
    }
  }

  /// Breekt de lopende download van [model] af. Het `.part`-bestand ruimt
  /// de downloader zelf op; hier verandert alleen de spiegel.
  void cancel(WhisperModel model) => _active[model.id]?.cancel();

  /// Neemt het op schijf gevonden [source] over als [model] — de actie
  /// die de sectie bij een `externalCandidate` biedt (#2601). Zelfde
  /// serialisatie als `download`: hooguit één schrijver op `.part`
  /// tegelijk. Een geslaagde overname eindigt `verified` — zijn hash is
  /// net getoetst, er valt niets meer te raden.
  Future<void> adopt(WhisperModel model, ModelStorePath source) async {
    if (_active.isNotEmpty ||
        state.values.any((s) => s.downloading || s.installing)) {
      return;
    }
    _set(
      model.id,
      _statusOf(
        model.id,
      ).copyWith(installing: true, clearFailure: true, clearCandidate: true),
    );
    try {
      final store = ref.read(transcriptionModelStoreProvider);
      await store.adopt(model, source);
      if (!ref.mounted) return;
      _set(
        model.id,
        const TranscriptionModelStatus(install: ModelInstallState.verified),
      );
    } on ModelDownloadException catch (e) {
      if (!ref.mounted) return;
      // De kandidaat blijft uit de spiegel: een hash-afwijzing bewees
      // net dat hij níét het model is, en opnieuw aanbieden zou alleen
      // dezelfde weigering opleveren. De volgende refresh scant hem
      // eventueel weer — dan is de knop de keuze van de gebruiker zelf.
      _set(
        model.id,
        _statusOf(model.id).copyWith(
          installing: false,
          install: await _stateOf(model),
          failure: e.failure,
        ),
      );
    } on Object catch (e, s) {
      logError('ModelManager: adopt van ${model.id}', e, s);
      if (ref.mounted) {
        _set(model.id, _statusOf(model.id).copyWith(installing: false));
      }
      rethrow;
    }
  }

  /// Verwijdert een geïnstalleerd model — expliciet, nooit als bijvangst
  /// van een mislukte download of een enginefout.
  Future<void> delete(WhisperModel model) async {
    try {
      await ref.read(transcriptionModelStoreProvider).delete(model);
    } catch (e, s) {
      logError('ModelManager: ${model.id} verwijderen', e, s);
    }
    if (!ref.mounted) return;
    _set(
      model.id,
      _statusOf(model.id).copyWith(install: await _stateOf(model)),
    );
  }

  /// Verse toestand vanuit schijf — bijvoorbeeld na externe wijziging.
  Future<void> refresh() => _refreshAll();
}
