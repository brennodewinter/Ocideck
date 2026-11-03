import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_writing_suggestion.dart';
import 'package:ocideck/services/deck_source_checks.dart';

// Draait native én in de browser
// (`flutter test --platform chrome test/deck_source_checks_test.dart`), steeds
// met de standaardrunner: precies die faalde op web (#2764).

const DeckCheckArgs _args = (
  source: '---\nmarp: true\n# nooit gesloten\n\nDit dit is dubbel.\n',
  compatContext: null,
  deckScope: true,
);

List<String> _shape(DeckCheckResult r) => [
  for (final i in r.validation.issues) 'v ${i.line} ${i.severity} ${i.message}',
  for (final s in r.suggestions) 's ${s.line} ${s.kind} ${s.args}',
];

void main() {
  test(
    'de standaardrunner geeft hetzelfde oordeel als de directe controle',
    () async {
      final direct = deckSourceChecks(_args);
      expect(direct.validation.hasIssues, isTrue);

      final before = debugMarkdownWritingInspectionCount;
      final viaRunner = await deckChecksRunner(_args);

      expect(_shape(viaRunner), _shape(direct));
      // Native loopt de bundel op een eigen isolate en laat de teller van deze
      // isolate dus staan; in de browser bestaat die uitwijk niet en draait hij
      // hier — geen off-thread-belofte voor web.
      expect(debugMarkdownWritingInspectionCount, kIsWeb ? before + 1 : before);
    },
  );

  test('een verlopen ronde levert niets af', () async {
    final asked = Completer<void>();
    var delivered = false;
    scheduleDeckChecks(
      args: _args,
      current: () {
        asked.complete();
        return false;
      },
      onResult: (_) => delivered = true,
    );
    await asked.future;
    await Future<void>.value();
    expect(delivered, isFalse);
  });

  test('een geldige ronde levert precies één keer af', () async {
    final result = Completer<DeckCheckResult>();
    scheduleDeckChecks(
      args: _args,
      current: () => true,
      onResult: result.complete,
    );
    expect(_shape(await result.future), _shape(deckSourceChecks(_args)));
  });
}
