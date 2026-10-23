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
/// aan de const-lijst te morrelen.
final whisperModelCatalogProvider = Provider<List<WhisperModel>>(
  (ref) => whisperModelCatalog,
);

/// De toestand van één catalogusitem zoals de UI hem tekent.
class TranscriptionModelStatus {
  const TranscriptionModelStatus({
    this.install = ModelInstallState.absent,
    this.downloading = false,
    this.progress = 0.0,
    this.failure,
  });

  final ModelInstallState install;

  /// Een transfer loopt — [progress] is dan 0..1.
  final bool downloading;
  final double progress;

  /// De laatste downloadfout (voor de meldingsstrook), of null.
  final ModelDownloadFailure? failure;

  TranscriptionModelStatus copyWith({
    ModelInstallState? install,
    bool? downloading,
    double? progress,
    ModelDownloadFailure? failure,
    bool clearFailure = false,
  }) => TranscriptionModelStatus(
    install: install ?? this.install,
    downloading: downloading ?? this.downloading,
    progress: progress ?? this.progress,
    failure: clearFailure ? null : (failure ?? this.failure),
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
    if (kIsWeb || !ref.mounted) return;
    for (final model in ref.read(whisperModelCatalogProvider)) {
      if (_statusOf(model.id).downloading) continue;
      final install = await _stateOf(model);
      if (!ref.mounted) return;
      _set(model.id, _statusOf(model.id).copyWith(install: install));
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

  /// Start de download die de gebruiker koos. Serialiseert: een tweede
  /// `download` terwijl er één loopt is een no-op — de UI biedt die knop
  /// dan ook niet aan.
  Future<void> download(WhisperModel model) async {
    // De poort kijkt naar de `downloading`-vlag, niet alleen naar _active:
    // die map vult pas na de eerste awaits, dus wie hem alleen bewaakt laat
    // een tweede download in het opstartvenster toch door.
    if (kIsWeb ||
        _active.isNotEmpty ||
        state.values.any((s) => s.downloading)) {
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

  /// Verwijdert een geïnstalleerd model — expliciet, nooit als bijvangst
  /// van een mislukte download of een enginefout.
  Future<void> delete(WhisperModel model) async {
    if (kIsWeb) return;
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
