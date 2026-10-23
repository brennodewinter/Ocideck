// Waar de audio voor een servertaak vandaan komt (§4.3, #2524). Eén
// functie, drie helften: `_io` leest een staging- of bestandspad (en
// `mem:`-sleutels via de gedeelde WebAssetStore), `_web` kent alleen
// `mem:`, `_stub` weigert. De engine roept dit aan via injectie, zodat de
// toestemming- en foutlogica op de VM testbaar blijft.
import 'dart:typed_data';

import 'asr_audio_source_stub.dart'
    if (dart.library.io) 'asr_audio_source_io.dart'
    if (dart.library.js_interop) 'asr_audio_source_web.dart'
    as impl;

/// Leest de bytes achter [path]: een `mem:`-sleutel of een bestandspad.
/// Gooit [SourceUnavailable] als de bron er niet is en [IoFailed] bij een
/// leesfout — nooit een leeg stuk dat als succes telt.
Future<Uint8List> readAsrAudio(String path) => impl.readAsrAudio(path);
