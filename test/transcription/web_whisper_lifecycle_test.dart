@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ocideck/services/transcription/local_whisper_engine_web.dart';
import 'package:ocideck/services/transcription/model_store_web.dart';
import 'package:ocideck/services/transcription/transcription_engine.dart';
import 'package:ocideck/services/transcription/transcription_errors.dart';
import 'package:ocideck/services/transcription/whisper_model.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/state/transcription_model_provider.dart';
import 'package:ocideck/state/transcription_provider.dart';

@JS('eval')
external JSAny? evaluate(JSString code);

const _model = WhisperModel(
  id: 'test-lifecycle',
  fileName: 'ggml-test-lifecycle.bin',
  sha256: '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
  downloadBytes: 3,
  diskBytes: 3,
  tier: 'light',
);

void _js(String code) => evaluate(code.toJS);
int _count(String field) =>
    (evaluate('nativeState.$field'.toJS) as JSNumber).toDartInt;

Future<void> _until(String condition) async {
  for (var i = 0; i < 200; i++) {
    if ((evaluate(condition.toJS) as JSBoolean).toDart) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('niet bereikt: $condition');
}

void main() {
  late AudioRef audio;
  final engines = <WebWhisperEngine>[];
  WebWhisperEngine engine() {
    final e = WebWhisperEngine(model: _model);
    engines.add(e);
    return e;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    WebAssetStore.clear();
    audio = AudioRef(
      WebAssetStore.put(Uint8List.fromList([4, 5]), name: 'a.wav'),
    );
    await writeModelRecord(
      'models/${_model.fileName}',
      Uint8List.fromList([1, 2, 3]),
    );
    _js('''
      globalThis.savedLifecycleBridge = globalThis.ocideckWhisper;
      globalThis.nativeState = {loads:0, frees:0, runs:0, cancels:0,
        generation:1, contexts:new Map(), holdLoad:false, holdDecode:false, holdRun:false};
      globalThis.ocideckWhisper = {
        isSupported: () => true,
        get runtimeGeneration() { return nativeState.generation; },
        contextGeneration: i => nativeState.contexts.get(i) || 0,
        loadModel: async () => {
          const s = nativeState;
          s.loads++;
          if(s.holdLoad) await new Promise(r => s.finishLoad = r);
          if(s.contexts.size >= 4) throw new Error('contexttabel vol');
          const index = s.loads;
          s.contexts.set(index, s.generation);
          return index;
        },
        decodeAudio: async () => {
          if(nativeState.holdDecode) await new Promise(r => nativeState.finishDecode = r);
          return new Float32Array(1600);
        },
        transcribe: async i => {
          const s = nativeState;
          if(!s.contexts.has(i)) throw new Error('use after free');
          s.runs++;
          if(s.holdRun) await new Promise(r => s.finishRun = r);
          if(!s.contexts.has(i)) throw new Error('freed during run');
          return {segments:[{text:'tekst', t0:0, t1:1000}], cancelled:false};
        },
        requestCancel: () => { nativeState.cancels++; },
        free: i => {
          if(!nativeState.contexts.delete(i)) throw new Error('stale free');
          nativeState.frees++;
        }
      };
    ''');
  });
  tearDown(() async {
    for (final e in engines) {
      e.dispose();
    }
    engines.clear();
    // Laat alle geserialiseerde dispose-beurten aflopen vóór bridge-herstel.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    _js('globalThis.ocideckWhisper = savedLifecycleBridge');
    WebAssetStore.clear();
  });

  Future<TranscriptResult> run(WebWhisperEngine e) =>
      e.transcribe(audio, const TranscriptionOptions());

  test(
    'lokale WASM meldt geen taalwisselroute en start die niet stil',
    () async {
      final e = engine();
      expect((await e.capabilities()).languageSwitching, isFalse);
      await expectLater(
        e.transcribe(
          audio,
          const TranscriptionOptions(languageSwitching: true),
        ),
        throwsA(isA<EngineUnavailable>()),
      );
      expect(_count('loads'), 0);
      expect(_count('runs'), 0);
    },
  );

  test('WASM bewaart de geleverde eindtijd', () async {
    final result = await run(engine());
    expect(result.segments.single.end, const Duration(seconds: 1));
  });

  test(
    'provider invalidatie ruimt meer dan vier opeenvolgende modellen op',
    () async {
      final container = ProviderContainer(
        overrides: [
          whisperModelCatalogProvider.overrideWithValue([_model]),
        ],
      );
      try {
        for (var i = 0; i < 7; i++) {
          final e = container.read(transcriptionEngineProvider)!;
          expect(
            (await e.transcribe(audio, const TranscriptionOptions())).text,
            'tekst',
          );
          container.invalidate(transcriptionEngineProvider);
          await container.pump();
        }
      } finally {
        container.dispose();
      }
      await _until('nativeState.frees === 7');
      expect(_count('loads'), 7);
      expect(_count('contexts.size'), 0);
    },
  );

  test(
    'modelwissel tijdens run stelt free uit en serializeert de opvolger',
    () async {
      _js('nativeState.holdRun = true');
      final a = engine();
      final first = run(a);
      await _until('nativeState.runs === 1');
      a.dispose();
      final b = engine();
      final next = run(b);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(_count('frees'), 0);
      expect(_count('loads'), 1);
      _js('nativeState.holdRun = false; nativeState.finishRun()');
      expect((await first).text, 'tekst');
      expect((await next).text, 'tekst');
      expect(_count('frees'), 1);
      await expectLater(run(a), throwsA(isA<EngineUnavailable>()));
    },
  );

  test(
    'dispose tijdens modelladen houdt de late context tot taakafloop',
    () async {
      _js('nativeState.holdLoad = true');
      final e = engine();
      final task = run(e);
      await _until('typeof nativeState.finishLoad === "function"');
      e.dispose();
      _js('nativeState.finishLoad()');
      expect((await task).text, 'tekst');
      expect(_count('frees'), 1);
    },
  );

  test('cancel tijdens modelladen start geen decode of native run', () async {
    _js('nativeState.holdLoad = true');
    final e = engine();
    final task = run(e);
    final check = expectLater(task, throwsA(isA<Cancelled>()));
    await _until('typeof nativeState.finishLoad === "function"');
    e.cancel();
    e.dispose();
    _js('nativeState.finishLoad()');
    await check;
    expect(_count('runs'), 0);
    expect(_count('frees'), 1);
  });

  test('cancel tijdens decode start geen native run', () async {
    _js('nativeState.holdDecode = true');
    final e = engine();
    final task = run(e);
    final check = expectLater(task, throwsA(isA<Cancelled>()));
    await _until('typeof nativeState.finishDecode === "function"');
    e.cancel();
    _js('nativeState.finishDecode()');
    await check;
    expect(_count('runs'), 0);
    expect(_count('cancels'), 0);
  });

  test('annuleren van wachtrijtaak raakt actieve andere engine niet', () async {
    _js('nativeState.holdRun = true');
    final first = run(engine());
    await _until('nativeState.runs === 1');
    final waiting = engine();
    final next = run(waiting);
    final check = expectLater(next, throwsA(isA<Cancelled>()));
    waiting.cancel();
    expect(_count('cancels'), 0);
    _js('nativeState.finishRun()');
    await first;
    await check;
    expect(_count('runs'), 1);
  });

  test('cancel native run onderdrukt ook een late succesuitslag', () async {
    _js('nativeState.holdRun = true');
    final e = engine();
    final task = run(e);
    final check = expectLater(task, throwsA(isA<Cancelled>()));
    await _until('nativeState.runs === 1');
    e.cancel();
    _js('nativeState.finishRun()');
    await check;
    expect(_count('cancels'), 1);
  });

  test('runtime-abort herlaadt bij volgende expliciete run', () async {
    final e = engine();
    await run(e);
    _js('nativeState.generation++; nativeState.contexts.clear()');
    await run(e);
    expect(_count('loads'), 2);
    e.dispose();
    await _until('nativeState.frees === 1');
  });

  test(
    'oude context mag hergebruikte index in nieuwe runtime niet vrijgeven',
    () async {
      final old = engine();
      await run(old);
      _js(
        'nativeState.generation++; nativeState.contexts.clear(); nativeState.loads = 0',
      );
      final fresh = engine();
      await run(fresh);
      old.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(_count('frees'), 0);
      await run(fresh);
      expect(_count('loads'), 1);
    },
  );
}
