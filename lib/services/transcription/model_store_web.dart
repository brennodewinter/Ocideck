// De modelopslag op web (docs/design/TRANSCRIPTION.md §4.4, #2513).
//
// Er is geen schijf; gedownloade modellen wonen in IndexedDB als Blob —
// de enige browseropslag die honderden megabytes aankan. De regels uit het
// contract blijven gelden:
//  * het "pad" is een logische sleutel die nooit de modelmap ontsnapt —
//    bestandsnamen komen uit de catalogus en worden hier op patroon getoetst;
//  * een halfbestand telt nooit als "aanwezig": downloads schrijven naar
//    `<sleutel>.part` en pas na de SHA-256-toets naar de echte sleutel;
//  * `verify()` hasht met WebCrypto (native, snel op grote blobs) en
//    weigert dat hard bij een mismatch;
//  * de browser mag de opslag onder druk wissen — dat verschijnt dan als
//    `absent`, niet als corruptie: de gebruiker haalt het model opnieuw.
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../utils/log.dart';
import 'model_store.dart';
import 'transcription_errors.dart';
import 'whisper_model.dart';

/// Naam en store van de IndexedDB die de modelblobs draagt.
const modelDbName = 'ocideck-transcription';
const modelDbStore = 'models';

/// Voorvoegsel dat een deels gedownload record markeert — dezelfde rol als
/// `.part` op schijf: bewijs van "niet af", nooit van "geïnstalleerd".
const partialSuffix = '.part';

bool _looksLikeModelKey(String key) =>
    key.startsWith('models/') && !key.contains('..') && !key.endsWith('/');

/// Opent (of maakt) de modeldatabase. Faalt getypt als de browser IndexedDB
/// niet geeft — private windows en sommige kioskmodi weigeren hem, en een
/// afwezige of kapotte factory komt hier als werpfout binnen.
Future<web.IDBDatabase> openModelDb() {
  final completer = Completer<web.IDBDatabase>();
  final web.IDBOpenDBRequest request;
  try {
    request = web.window.indexedDB.open(modelDbName, 1);
  } catch (e) {
    return Future.error(UnsupportedSource('IndexedDB is niet beschikbaar: $e'));
  }
  request.onupgradeneeded = ((web.Event _) {
    final db = request.result as web.IDBDatabase;
    if (!db.objectStoreNames.contains(modelDbStore)) {
      db.createObjectStore(modelDbStore);
    }
  }).toJS;
  request.onsuccess = ((web.Event _) {
    completer.complete(request.result as web.IDBDatabase);
  }).toJS;
  request.onerror = ((web.Event _) {
    completer.completeError(
      IoFailed('IndexedDB openen mislukt: ${request.error?.message}'),
    );
  }).toJS;
  request.onblocked = ((web.Event _) {
    completer.completeError(
      const IoFailed('IndexedDB openen geblokkeerd door een andere tab'),
    );
  }).toJS;
  return completer.future;
}

/// Eén IDB-transactie van begin tot einde als Future. [work] krijgt de
/// objectstore en mag request-hangers zetten; de future voltooit wanneer de
/// transactie zelf voltooit (completeness, niet per-request succes).
Future<void> _runStoreTransaction(
  web.IDBDatabase db,
  String mode,
  void Function(web.IDBObjectStore store) work,
) {
  final completer = Completer<void>();
  final tx = db.transaction(modelDbStore.toJS, mode);
  work(tx.objectStore(modelDbStore));
  tx.oncomplete = ((web.Event _) => completer.complete()).toJS;
  final onFail = ((web.Event _) => completer.completeError(
    IoFailed('IndexedDB-transactie mislukt: ${tx.error?.message}'),
  )).toJS;
  tx.onerror = onFail;
  tx.onabort = onFail;
  return completer.future;
}

/// Eén `get` als Future — null bij afwezigheid.
Future<JSAny?> _get(web.IDBObjectStore store, String key) {
  final completer = Completer<JSAny?>();
  final request = store.get(key.toJS);
  request.onsuccess = ((web.Event _) {
    completer.complete(request.result);
  }).toJS;
  request.onerror = ((web.Event _) {
    completer.completeError(
      IoFailed('IndexedDB-leesfout: ${request.error?.message}'),
    );
  }).toJS;
  return completer.future;
}

/// Leest een recordsleutel als bytes — null als hij afwezig is of geen Blob
/// bevat (een vervormd record telt als afwezig, nooit als inhoud).
Future<Uint8List?> readModelRecord(String key) async {
  final db = await openModelDb();
  try {
    final tx = db.transaction(modelDbStore.toJS, 'readonly');
    final raw = await _get(tx.objectStore(modelDbStore), key);
    if (raw == null || !raw.isA<web.Blob>()) return null;
    return (await (raw as web.Blob).arrayBuffer().toDart).toDart.asUint8List();
  } finally {
    db.close();
  }
}

/// Schrijft bytes onder een recordsleutel.
Future<void> writeModelRecord(String key, Uint8List bytes) async {
  final db = await openModelDb();
  try {
    await _runStoreTransaction(db, 'readwrite', (store) {
      store.put(web.Blob([bytes.toJS].toJS), key.toJS);
    });
  } finally {
    db.close();
  }
}

/// Verwijdert één recordsleutel; stil als hij niet bestond.
Future<void> deleteModelRecord(String key) async {
  final db = await openModelDb();
  try {
    await _runStoreTransaction(db, 'readwrite', (store) {
      store.delete(key.toJS);
    });
  } finally {
    db.close();
  }
}

/// Alle sleutels in de modelstore (voor `.part`-sweeps).
Future<List<String>> listModelKeys() async {
  final db = await openModelDb();
  try {
    final completer = Completer<List<String>>();
    final tx = db.transaction(modelDbStore.toJS, 'readonly');
    final request = tx.objectStore(modelDbStore).getAllKeys();
    request.onsuccess = ((web.Event _) {
      final result = request.result.dartify();
      completer.complete([
        for (final k in (result is List ? result : const <Object?>[]))
          if (k is String) k,
      ]);
    }).toJS;
    request.onerror = ((web.Event _) {
      completer.completeError(
        IoFailed('IndexedDB-sleutellijst mislukt: ${request.error?.message}'),
      );
    }).toJS;
    return await completer.future;
  } finally {
    db.close();
  }
}

/// SHA-256 over [bytes] via WebCrypto — native en snel, ook op ~500 MB.
/// Null wanneer er geen secure context is: zonder https biedt de browser
/// `crypto.subtle` niet, en dan is er geen betrouwbare toets om te doen.
Future<String?> sha256Web(Uint8List bytes) async {
  final subtle = web.window.crypto.subtle;
  try {
    final digest = await subtle.digest('SHA-256'.toJS, bytes.toJS).toDart;
    final view = (digest as JSArrayBuffer).toDart.asUint8List();
    return view.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  } on Object catch (e, s) {
    logError('modelStoreWeb: sha256', e, s);
    return null;
  }
}

/// Vrije opslagruimte volgens de browser — null waar de Storage API niet
/// antwoordt (oudere Safari). Alleen indicatief; de echte grens is de
/// mislukte `put`, die we apart afvangen.
Future<int?> storageFreeBytes() async {
  try {
    final estimate = await web.window.navigator.storage.estimate().toDart;
    return (estimate.quota - estimate.usage).toInt();
  } on Object catch (e, s) {
    logError('modelStoreWeb: storage-estimate', e, s);
    return null;
  }
}

class WebModelStore implements TranscriptionModelStore {
  const WebModelStore();

  String _keyOf(WhisperModel model) {
    final key = 'models/${model.fileName}';
    if (!_looksLikeModelKey(key)) {
      // Kan alleen bij een corrupte catalogusrij voorkomen; hard falen is
      // hier de containment-check zelf.
      throw UnsupportedSource('modelsleutel buiten bereik: ${model.fileName}');
    }
    return key;
  }

  @override
  Future<ModelStorePath> directory() async =>
      const ModelStorePath('indexeddb:$modelDbName/$modelDbStore', false);

  @override
  Future<ModelStorePath> modelPath(WhisperModel model) async =>
      ModelStorePath(_keyOf(model), false);

  @override
  Future<ModelInstallState> stateOf(WhisperModel model) async {
    final bytes = await readModelRecord(_keyOf(model));
    if (bytes == null) return ModelInstallState.absent;
    if (bytes.length != model.diskBytes) {
      // Een restje telt niet — beter: weg ermee, dan kan het nooit
      // per ongeluk als "aanwezig" meetellen.
      await deleteModelRecord(_keyOf(model));
      return ModelInstallState.absent;
    }
    return ModelInstallState.present;
  }

  @override
  Future<bool> verify(WhisperModel model) async {
    final bytes = await readModelRecord(_keyOf(model));
    if (bytes == null || bytes.length != model.diskBytes) return false;
    final hex = await sha256Web(bytes);
    return hex != null && hex == model.sha256;
  }

  @override
  Future<void> delete(WhisperModel model) async {
    await deleteModelRecord(_keyOf(model));
    await deleteModelRecord('${_keyOf(model)}$partialSuffix');
  }

  @override
  Future<void> sweepPartials() async {
    for (final key in await listModelKeys()) {
      if (key.endsWith(partialSuffix)) {
        await deleteModelRecord(key);
      }
    }
  }

  /// Een browser kan de schijf niet doorzoeken — er is nooit een externe
  /// kandidaat en dus ook geen adoptie om af te wijzen met een knop.
  @override
  Future<List<ModelStorePath>> externalCandidates(WhisperModel model) =>
      Future.value(const []);

  @override
  Future<ModelStorePath> adopt(WhisperModel model, ModelStorePath source) =>
      throw const UnsupportedSource(
        'modelbeheer op schijf vraagt een bestandssysteem',
      );
}

TranscriptionModelStore createModelStore() => const WebModelStore();
