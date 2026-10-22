import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/transcript_embed_syntax.dart';

/// Tekent een `x-embed-transcript`-blok — de `<!-- transcript … -->`-marker
/// bovenaan een transcriptdocument — als één subtiele aanduidingsregel:
/// "Transcript", plus de bestandsnaam uit `audio="…"` als die er staat.
///
/// De embed is één documentteken: selecteren en Backspace/Delete haalt de
/// marker weg (het document wordt dan een gewoon document), en Undo zet hem
/// terug. Bewerken van de attributen doe je in de bron — bewust, want het
/// `audio`-pad is geen proza om per ongeluk in te typen.
class TranscriptEmbedBuilder extends EmbedBuilder {
  const TranscriptEmbedBuilder();

  @override
  String get key => EmbeddableTranscript.transcriptType;

  /// De marker is een blok, geen inline-teken: hij vult de breedte.
  @override
  bool get expanded => true;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final theme = Theme.of(context);
    final marker = embedContext.node.value.data as String? ?? '';
    final audio = RegExp('audio="([^"]+)"').firstMatch(marker)?.group(1);
    final audioName = audio?.split('/').last;
    final color = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55);
    return Semantics(
      label: context.l10n.d('Transcript'),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mic_none, size: 13, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              audioName == null
                  ? context.l10n.d('Transcript')
                  : '${context.l10n.d('Transcript')} · $audioName',
              style: TextStyle(fontSize: 11, color: color, letterSpacing: 0.5),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
