import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';

/// Regression tests for the status bar's filename slot. The bug: on web, saving
/// is a browser download that never yields a file path, so a saved deck kept
/// showing "not saved yet" next to the green "Saved" chip. The fix remembers
/// the downloaded name and prefers it. Uses Dutch (nl) so d()/t() return their
/// literal source strings, independent of translation content.
void main() {
  const l10n = AppLocalizations(Locale('nl'));
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  group('deckFileStatusLabel', () {
    test('desktop: shows the on-disk file basename and full path tooltip', () {
      final r = deckFileStatusLabel(
        const DeckState(filePath: '/home/u/decks/MTTR.md'),
        l10n,
      );
      expect(r.label, 'MTTR.md');
      expect(r.tooltip, '/home/u/decks/MTTR.md');
    });

    test(
      'web after download: shows the downloaded name, not the placeholder',
      () {
        final r = deckFileStatusLabel(
          const DeckState(downloadName: 'MTTR.md'),
          l10n,
        );
        expect(r.label, 'MTTR.md');
        expect(r.label, isNot(l10n.t('notSavedYet')));
        expect(
          r.tooltip,
          l10n.d('Opgeslagen als download in je map met downloads.'),
        );
      },
    );

    test('never saved: shows the "not saved yet" placeholder', () {
      final r = deckFileStatusLabel(const DeckState(), l10n);
      expect(r.label, l10n.t('notSavedYet'));
      expect(r.tooltip, l10n.t('noFileYet'));
    });

    test('a real file path wins over a remembered download name', () {
      final r = deckFileStatusLabel(
        const DeckState(filePath: '/x/Real.md', downloadName: 'Old.md'),
        l10n,
      );
      expect(r.label, 'Real.md');
    });
  });
}
