import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../services/media/youtube_reference.dart';
import '../../services/media/media_transcript.dart';
import '../../state/deck_provider.dart';
import 'youtube_source_dialog.dart';

/// Only an explicit action scans locally. Opening or playing the deck never
/// starts a source request or ASR job and never changes its Markdown.
Future<void> transcribeDeckYoutube(BuildContext context, WidgetRef ref) async {
  final deck = ref.read(deckProvider).deck;
  if (deck == null) return;
  final sources = findDeckYoutubeReferences(deck.slides);
  final l10n = context.l10n;
  if (sources.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.d('Geen YouTube-video’s gevonden in deze presentatie.'),
        ),
      ),
    );
    return;
  }
  final selected = await showDialog<DeckYoutubeReference>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(l10n.d('YouTube-video transcriberen…')),
      children: [
        for (final entry in sources)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(entry),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(deck.slides[entry.slideNumbers.first - 1].title),
                Text(
                  '${l10n.d('Dia')} ${entry.slideNumbers.join(', ')} · ${entry.reference.videoId}',
                ),
                Text(
                  '${sourceTimeLabel(Duration(milliseconds: entry.reference.proposedStartMs))} – '
                  '${entry.reference.proposedEndMs == 0 ? '∞' : sourceTimeLabel(Duration(milliseconds: entry.reference.proposedEndMs))}',
                ),
              ],
            ),
          ),
      ],
    ),
  );
  if (selected == null || !context.mounted) return;
  await showYoutubeSourceDialog(
    context,
    selected.reference,
    title: deck.slides[selected.slideNumbers.first - 1].title,
  );
}
