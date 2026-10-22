// De transcript-naad van de documenteditor (#2511).
//
// Twee dingen horen bij de editor zelf en niet bij het documentmodel:
//  * de [TranscriptNotice]-strook — beschadigde marker of ontbrekende
//    audio, boven het schrijfoppervlak;
//  * de toepassingsweg van [transcriptApplyRequestProvider]: een
//    transcriptie-flow levert een definitieve of nieuwe tekst aan, en alleen
//    hier kan die met de actuele documenttekst worden vergeleken. De
//    beslisregels staan in `planTranscriptUpdate` (§3.1): ongemoeide tekst
//    mag stil vervangen worden, aangeraakte tekst alleen via de zichtbare
//    vergelijking.
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../services/transcription/transcript_document.dart';
import '../state/document_provider.dart';
import '../state/transcription_provider.dart';
import 'dialogs/transcript_apply_dialog.dart';
import 'panels/transcript_notice.dart';

/// Strook + toepassingsverzoeken voor een transcriptdocument. Zonder
/// transcript is dit één `SizedBox.shrink()` — een gewoon document merkt
/// er niets van.
class TranscriptDocumentExtras extends ConsumerStatefulWidget {
  const TranscriptDocumentExtras({super.key});

  @override
  ConsumerState<TranscriptDocumentExtras> createState() =>
      _TranscriptDocumentExtrasState();
}

class _TranscriptDocumentExtrasState
    extends ConsumerState<TranscriptDocumentExtras> {
  @override
  Widget build(BuildContext context) {
    ref.listen(transcriptApplyRequestProvider, (previous, next) {
      if (next != null) unawaited(_answer(next));
    });
    final source = ref.watch(
      documentProvider.select((s) => s.document?.source ?? ''),
    );
    final filePath = ref.watch(documentProvider.select((s) => s.filePath));
    return TranscriptNotice(
      source: source,
      projectPath: filePath == null ? null : p.dirname(filePath),
    );
  }

  /// Beantwoordt één verzoek. Pas na de gebruikerskeuze — die even kan
  /// duren — wordt nog eens gekeken of dit verzoek nog het verzoek is:
  /// een nieuwer verzoek heeft het zijne dan al als vervallen beantwoord,
  /// en nog toepassen zou stil de nieuwere uitslag overschrijven.
  Future<void> _answer(TranscriptApplyRequest request) async {
    final source = ref.read(documentProvider).document?.source;
    var outcome = false;
    if (source != null) {
      outcome = switch (planTranscriptUpdate(
        source,
        request.incoming,
        baseline: request.baseline,
      )) {
        TranscriptUnchanged() => true,
        TranscriptApply(:final markdown) => _commit(markdown),
        TranscriptConflict(:final incoming) => await _compare(source, incoming),
        TranscriptTooLarge() => _tooLarge(),
      };
    }
    if (ref.read(transcriptApplyRequestProvider) == request) {
      ref.read(transcriptApplyRequestProvider.notifier).resolve(outcome);
    }
  }

  bool _commit(String markdown) {
    ref.read(documentProvider.notifier).edit(markdown, coalesceKey: null);
    return true;
  }

  Future<bool> _compare(String source, String incoming) async {
    final current = transcriptBodyText(source) ?? '';
    final choice = await showTranscriptApplyDialog(
      context,
      current: current,
      incoming: incoming,
    );
    if (choice != true) return false;
    return _commit(applyTranscriptBody(source, incoming));
  }

  bool _tooLarge() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.d('De transcripttekst is te groot om toe te passen.'),
        ),
      ),
    );
    return false;
  }
}
