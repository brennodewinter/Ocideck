import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/deck.dart';
import '../../models/slide.dart';
import '../../state/deck_provider.dart';
import '../../state/document_provider.dart';
import '../../utils/document_front_matter.dart';
import '../../utils/tlp_explanation.dart';
import 'tlp_audience_dialog.dart';

/// Zet het documentniveau. AMBER+STRICT en RED vragen eerst voor wie;
/// de toelichting wordt een gewone alinea onder de titel (#2396).
Future<void> applyDocumentTlp(
  BuildContext context,
  WidgetRef ref,
  TlpLevel level,
) async {
  final doc = ref.read(documentProvider).document;
  if (doc == null || doc.tlp == level) return;
  final choice = level == TlpLevel.none
      ? null
      : await showTlpAudienceDialog(context, level: level);
  if (level != TlpLevel.none && choice == null) return;
  if (!context.mounted) return;
  final marked = doc.withTlp(level);
  if (choice == null || !choice.insertExplanation) {
    ref.read(documentProvider.notifier).edit(marked.source, coalesceKey: null);
    return;
  }
  final l10n = context.l10n;
  final sentence = tlpStandardSentence(l10n, level);
  final paragraph = tlpExplanationParagraph(
    sentence: sentence,
    audienceLine: _audienceLine(l10n, choice.recipients),
    note: choice.note,
  );
  final split = splitDocumentFrontMatter(marked.source);
  final body = insertTlpExplanation(split.body, paragraph, sentence);
  ref
      .read(documentProvider.notifier)
      .edit(split.block + body, coalesceKey: null);
}

/// Zet het presentatieniveau. De toelichting is een gewone opsommingsdia,
/// niet een nieuw slidetype, en komt niet in een verzegeld deck (#2396).
Future<void> applyPresentationTlp(
  BuildContext context,
  WidgetRef ref,
  TlpLevel level,
) async {
  final deck = ref.read(deckProvider).deck;
  if (deck == null || deck.tlp == level) return;
  final choice = level == TlpLevel.none
      ? null
      : await showTlpAudienceDialog(
          context,
          level: level,
          offerParagraph: false,
          offerSlide: !deck.finalized,
        );
  if (level != TlpLevel.none && choice == null) return;
  if (!context.mounted) return;
  Slide? slide;
  if (choice != null && choice.insertSlide && !deck.finalized) {
    final l10n = context.l10n;
    final sentence = tlpStandardSentence(l10n, level);
    final audience = _audienceLine(l10n, choice.recipients);
    slide = Slide.create(SlideType.bullets).copyWith(
      title: level.label,
      bullets: [
        sentence,
        if (audience.isNotEmpty) audience,
        if (choice.note.isNotEmpty) choice.note,
      ],
    );
  }
  applyPresentationTlpLevel(
    ref.read(deckProvider.notifier),
    level,
    explanation: slide,
  );
}

String _audienceLine(AppLocalizations l10n, String recipients) {
  final names = recipients.trim();
  if (names.isEmpty) return '';
  return '${l10n.d('Bestemd voor:')} $names';
}
