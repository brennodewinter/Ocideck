import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards against a subtle, silent bug class: a derived provider (one that
/// reads the per-tab-scoped [deckProvider]/[editorProvider]) that is NOT also
/// overridden in the per-tab `ProviderScope` in `AppShell`. Such a provider
/// resolves its dependency in the ROOT container instead of the active tab, so
/// it silently sees an empty deck (`deck == null`) and quietly does nothing —
/// exactly how `imageContrastIssuesProvider` first failed.
///
/// This is a source-scan in the same spirit as `app_localizations_test.dart`,
/// so it catches the next occurrence at test time rather than at runtime.
///
/// Detection is file-level: if a `lib/state` file reads the scoped deck
/// anywhere (including from a top-level function that backs a provider, like
/// `computeImageContrastIssues`), every provider defined in that file must be
/// overridden per tab or explicitly allowlisted. File-level keeps it robust
/// against function-backed providers at the cost of allowlisting pure
/// siblings.
void main() {
  test(
    'providers that read the scoped deck are overridden per tab in AppShell',
    () {
      // The base providers the tab scope overrides; they define the scoped
      // state itself rather than deriving from it.
      const baseProviders = {'deckProvider', 'editorProvider'};

      // Providers that share a file with a deck reader but do not themselves
      // depend on the deck. Keep each entry justified.
      const allowlist = <String>{
        // Stateless analyzer service; the deck is passed in at call sites.
        'slideQualityAnalyzerProvider',
        // Idem: a stateless scanner; the deck is passed in at call sites.
        'privacyScannerProvider',
        // Het gezichtsmodel: leest het deck niet, en het laden ervan kost meer
        // dan de detectie zelf. Per tab overriden zou het model per tab opnieuw
        // inlezen zonder dat er iets tab-specifieks aan is.
        'imageFaceScannerProvider',
        // De chat-open-vlag is bewust app-globaal (er is één actief tabblad in
        // beeld); hij leest het deck niet. Woont in dezelfde file als
        // collabSessionProvider, dat het deck wél leest en per tab wordt
        // overriden.
        'collabChatOpenProvider',
      };

      // `_tabScope` (met de per-tab overrides) woont in de tab_bar-part van de
      // app_shell-library; lees beide, zodat de scan hem vindt waar hij ook staat.
      final appShell =
          File('lib/widgets/app_shell.dart').readAsStringSync() +
          File('lib/widgets/shell/tab_bar.dart').readAsStringSync();
      final readPattern = RegExp(
        r'ref\.(?:watch|read|listen)\(\s*(?:deckProvider|editorProvider)',
      );
      final defPattern = RegExp(r'final (\w+Provider)\s*=');

      final offenders = <String>[];
      for (final file
          in Directory('lib/state')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final content = file.readAsStringSync();
        if (!readPattern.hasMatch(content)) continue;

        for (final match in defPattern.allMatches(content)) {
          final name = match.group(1)!;
          if (baseProviders.contains(name) || allowlist.contains(name)) {
            continue;
          }
          if (!appShell.contains('$name.overrideWith')) {
            offenders.add('$name (${file.path})');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'These providers live in a file that reads the per-tab '
            'deck/editor but are not overridden in the AppShell tab '
            'ProviderScope, so they would read the empty root deck: '
            '$offenders. Add `<name>.overrideWith(...)` next to '
            'deckQualityProvider, or allowlist a genuine non-deck sibling '
            'with a reason.',
      );
    },
  );
}
