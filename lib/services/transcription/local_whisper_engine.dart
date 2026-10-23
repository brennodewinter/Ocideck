// De lokale engine: whisper.cpp als geïsoleerd hulpproces
// (docs/design/TRANSCRIPTION.md §4.2, §4.4, §7; #2512).
//
// Waarom een subproces en geen ffi-bibliotheek: het model is honderden
// megabytes native code waar een crash of OOM in kan ontstaan. In een
// eigen proces is die grens gratis — het OS ruimt een gesneuvelde helper
// op en OciDeck blijft staan, opgenomen audio inbegrepen. De keerzijde
// (servertijd? nee: het is lokaal) is alleen de startkost, en die meet de
// benchmark in §7 op ~135 ms.
//
// Twee uitvoerders:
//  * `_io`   — macOS/Windows/Linux: bundel-binary zoeken, model hashen,
//              `whisper-cli` starten met argv-array, tijdslimiet, kill;
//  * `_stub` — web: de route bestaat niet; `capabilities()` geeft dat
//              eerlijk terug in plaats van een engine voor te wenden.
//
// Drie harde regels uit het contract, hier afgedwongen:
//  * het modelpad komt alleen uit `TranscriptionModelStore.modelPath` —
//    containment is dus al afgedwongen vóór argv bestaat;
//  * de hash is getoetst vóór het model aan het proces wordt gevoed
//    (`ModelInstallState.verified` of een verse `verify()`);
//  * falen is zichtbaar: een kapotte run eindigt in een getypeerde
//    [TranscriptionError], nooit in een upload of een stille fallback.
import 'dart:async';

import 'local_whisper_engine_stub.dart'
    if (dart.library.io) 'local_whisper_engine_io.dart'
    as impl;

import 'transcription_engine.dart';
import 'transcription_errors.dart';
import 'whisper_model.dart';

/// Wat de capability-melding van het lokale spoor betekent — de UI
/// vertaalt dit; de kern rapporteert feiten, geen advies.
enum LocalEngineSupport {
  /// Helper-binary én architectuur zijn in orde voor deze build.
  ready,

  /// De architectuur is niet onder de drie die de buildketen levert
  /// (macOS arm64/x86_64, Windows x64, Linux x64) — §5.3.
  unsupportedArchitecture,

  /// De helper ontbreekt in het artefact (bijv. een dev-run zonder
  /// `OCIDECK_WHISPER_CLI`) — een eerlijke "kan niet", geen crash.
  missingHelper,
}

/// De status zoals `capabilities()` hem nodig heeft: een enkelvoudige
/// toestand plus — voor [LocalEngineSupport.missingHelper] en
/// [LocalEngineSupport.unsupportedArchitecture] — de reden als tekst
/// voor diagnose (geen gebruikerszin; die leeft in de l10n-laag).
class LocalEngineStatus {
  const LocalEngineStatus(this.support, this.detail);

  final LocalEngineSupport support;
  final String detail;
}

/// De lokale engine. Naast de contractmethoden heeft hij [status] (waarom
/// is hij wel/niet klaar) en [cancel] — de interface kent geen
/// annuleringstoken, dus hangt de Stop-knop aan de concrete klasse.
abstract class LocalWhisperEngine implements TranscriptionEngine {
  /// Toetst architectuur en helper-aanwezigheid. Goedkoop en zuiver:
  /// raakt geen model en start niets.
  Future<LocalEngineStatus> status();

  /// Welk catalogusmodel deze engine zou laden.
  WhisperModel? get model;

  /// Breekt een lopende [transcribe] af — het proces wordt met `SIGKILL`
  /// beëindigd en de toekomst voltooit met [Cancelled]. Niets aan de hand
  /// als er niets liep.
  void cancel();
}

LocalWhisperEngine createLocalWhisperEngine({WhisperModel? model}) =>
    impl.createLocalWhisperEngine(model: model);
