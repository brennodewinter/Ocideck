// De bestandsbron van de capturegrens (docs/design/TRANSCRIPTION.md
// §3.2, §4.1; #2515). Een bestaand audio- of videobestand is óók een
// bron: geen microfoon, geen permissie, wel dezelfde duurzame grens.
//
// Twee werkvormen achter één gezicht:
//  * PCM-WAV gaat direct door — de engine leest hem, het origineel blijft
//    waar de gebruiker het neerzette (gerefereerd, nooit gekopieerd);
//  * elke andere container wordt gedecodeerd naar een 16 kHz mono-WAV in
//    de sessie-staging: desktop via een gepinde platformdecoder
//    (`afconvert` op macOS, `ffmpeg` waar die staat), web via het eigen
//    `decodeAudioData` van de browser. De decoderuitslag is de waarheid
//    over "is er audio" — een video zonder audiotrack eindigt in een
//    benoemde [DecodeFailed], niet in stilte.
//
// De sessie is bewust geen "opname": er loopt geen indicator en er komt
// geen live-route — `ended` en `liveChunks` zijn null. `stop()` levert de
// decode; `cancel()` breekt hem af. De flow die de sessie drijft
// (transcribe_file_dialog) bezit de stagingmap en ruimt hem weer op.
import 'dart:async';

import 'capture_source.dart';
import 'file_capture_source_stub.dart'
    if (dart.library.io) 'file_capture_source_io.dart'
    if (dart.library.js_interop) 'file_capture_source_web.dart'
    as impl;
import 'media_sniff.dart';
import 'transcription_errors.dart';

/// Wat een [FileCaptureSource.describe] over één bestand weet — de
/// voorbeschouwing die de dialoog toont vóór er iets start. Alles hier is
/// passief verkregen: bestaat, grootte, container, duur waar die zonder
/// decoder te zien is.
class FileSourceInfo {
  const FileSourceInfo({
    required this.path,
    required this.sizeBytes,
    required this.container,
    this.duration,
    required this.engineReadsDirectly,
    required this.decodable,
    this.decodeNote,
  });

  /// Pad of `mem:`-sleutel zoals hij aan [CaptureRequest.sourcePath]
  /// wordt meegegeven.
  final String path;
  final int sizeBytes;
  final MediaContainer container;

  /// Duur als die zonder decode te zien is (WAV-header); anders null en
  /// vertelt de uitkomst van `stop()` hem wel.
  final Duration? duration;

  /// PCM-WAV: de engine leest het bestand zelf — geen decode-stap.
  final bool engineReadsDirectly;

  /// Kan deze opstelling deze container decoderen? `false` alleen met
  /// een benoemde reden in [decodeNote].
  final bool decodable;

  /// Waarom niet decodeerbaar (bijv. "ffmpeg ontbreekt op dit systeem"),
  /// of welke onzekerheid rest (bijv. browsedekking). Diagnose voor de
  /// UI, geen vertaalde zin.
  final String? decodeNote;
}

/// De `file`-variant van [CaptureSource]. Dezelfde grens als elke andere
/// bron — [probe] is passief, [start] is de enige call die iets mag doen —
/// plus [describe] voor de voorbeschouwing die de dialoog toont.
abstract class FileCaptureSource extends CaptureSource {
  const FileCaptureSource();

  /// Kijkt naar één bestand zonder er iets aan te doen: stat, magische
  /// bytes, WAV-header. Gooit [IoFailed] bij een onleesbaar pad en
  /// [CapacityExceeded] boven de invoergrens — de getypte fouten zijn
  /// bewust alvast dezelfde als waar `stop()` mee zou eindigen.
  Future<FileSourceInfo> describe(String sourcePath);

  /// Verscherpt het grensreturntype: de bestandssessie kent [cancel] —
  /// nodig voor de Stop-knop van de flow.
  @override
  Future<FileCaptureSession> start(CaptureRequest request);
}

/// De sessie van de bestandsbron: naast de capturegrens-methoden kent hij
/// [cancel] — de Stop-knop van de flow verbreekt een lopende decode.
abstract class FileCaptureSession extends CaptureSession {
  /// Breekt de voorbereiding af; [stop] voltooit dan met [Cancelled].
  /// Niets aan de hand als er niets liep.
  void cancel();
}

FileCaptureSource createFileCaptureSource() => impl.createFileCaptureSource();

/// De invoergrens: grotere bronnen gaan niet de decoder of de engine in —
/// op web past dit binnen het `mem:`-budget met ruimte voor het WAV-
/// resultaat, op desktop is het gewoon een eerlijke bovengrens.
const maxFileSourceBytes = 2 * 1024 * 1024 * 1024; // 2 GiB

/// De decodegrens in uitvoer: 16 kHz mono-WAV ≈ 32 kB/s, dus 1 GiB is
/// ruim acht uur. Dezelfde begrenzing als de mediacap waar `media/` onder
/// valt (§3.2) — een dagopname past, een oneindige bron niet.
const maxDecodedWavBytes = 1024 * 1024 * 1024; // 1 GiB
