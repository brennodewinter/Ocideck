import '../models/slide.dart';

/// Deterministische quick-fix voor de kwaliteitsmelding "bullet met meerdere
/// zinnen": knip elke meerzinnige bullet op zinsgrenzen in losse bullets op
/// hetzelfde inspring-niveau. Checklist-items behouden hun aangevinkt-status.
///
/// De zinsgrens-definitie spiegelt de detectie in de kwaliteitsanalyse
/// (interpunctie gevolgd door witruimte of einde), zodat de fix precies
/// oplost wat de melding signaleert.
final _sentenceEnd = RegExp(r'[.!?](?:\s+|$)');
final _checklistPrefix = RegExp(r'^\[[ xX]\]\s*');

/// Of [slide] bullets heeft die [splitSentencesInBullets] daadwerkelijk zou
/// opknippen — zodat de UI de actie alleen aanbiedt als die iets doet.
bool canSplitSentenceBullets(Slide slide) =>
    slide.bullets.any(_isMultiSentence) || slide.bullets2.any(_isMultiSentence);

bool _isMultiSentence(String bullet) =>
    _splitSentences(_plainText(bullet)).length > 1;

String _plainText(String bullet) =>
    bulletText(bullet).replaceFirst(_checklistPrefix, '');

/// Nieuwe slide waarin elke meerzinnige bullet is opgeknipt in één bullet per
/// zin. Bullets met hooguit één zin blijven ongemoeid.
Slide splitSentenceBullets(Slide slide) {
  return slide.copyWith(
    bullets: splitSentencesInBullets(slide.bullets),
    bullets2: splitSentencesInBullets(slide.bullets2),
  );
}

/// Knip elke meerzinnige bullet in [bullets] op in losse bullets; volgorde en
/// inspring-niveau blijven behouden.
List<String> splitSentencesInBullets(List<String> bullets) {
  final result = <String>[];
  for (final bullet in bullets) {
    if (!_isMultiSentence(bullet)) {
      result.add(bullet);
      continue;
    }
    final level = bulletLevel(bullet);
    final isChecklist = _checklistPrefix.hasMatch(bulletText(bullet));
    final checked = isChecklist && checklistItemChecked(bullet);
    for (final sentence in _splitSentences(_plainText(bullet))) {
      result.add(
        isChecklist
            ? checklistBullet(level: level, text: sentence, checked: checked)
            : '${'\t' * level}$sentence',
      );
    }
  }
  return result;
}

List<String> _splitSentences(String text) {
  final parts = <String>[];
  var start = 0;
  for (final match in _sentenceEnd.allMatches(text)) {
    // Inclusief het leesteken zelf, exclusief de witruimte erna.
    parts.add(text.substring(start, match.start + 1).trim());
    start = match.end;
  }
  if (start < text.length) {
    final rest = text.substring(start).trim();
    if (rest.isNotEmpty) parts.add(rest);
  }
  return [
    for (final part in parts)
      if (part.isNotEmpty) part,
  ];
}
