import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';

/// De melding na een git-opslag met waarschuwingen beloofde dat "video en
/// audio (nog) niet meegaan" — achterhaald sinds media gewoon gepoold en
/// gecommit wordt (deck_repo_serializer, poolAsset over videoPath/audioPath).
/// De warnings betekenen "verwijzing niet leesbaar of buiten het project",
/// en dat hoort de melding dan ook te zeggen.
///
/// De oude sleutel moet bovendien overal wég blijven: een merge=union-rebase
/// van twee l10n-takken kan een verwijderde sleutel stil laten herrijzen, en
/// dan liegt de melding opnieuw in 31 talen.
void main() {
  const nieuw =
      'niet elk gekoppeld bestand kon mee (onleesbaar of buiten het project)';
  const oud = 'video en audio gaan (nog) niet mee naar git';

  test('de nieuwe formulering bestaat in elke taal', () {
    for (final code in AppLocalizations.languageNames.keys) {
      if (code == 'nl') continue;
      expect(
        AppLocalizations.hasDirectDutchSourceTranslation(code, nieuw),
        isTrue,
        reason: '$code mist de vertaling van de nieuwe melding',
      );
    }
  });

  test('de oude media-belofte is uit alle vertaaltabellen verdwenen', () {
    for (final code in AppLocalizations.languageNames.keys) {
      if (code == 'nl') continue;
      expect(
        AppLocalizations.hasDirectDutchSourceTranslation(code, oud),
        isFalse,
        reason: '$code draagt de verwijderde sleutel nog (of weer)',
      );
    }
  });
}
