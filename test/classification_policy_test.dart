import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/services/classification_policy.dart';

void main() {
  group('ClassificationPolicy', () {
    test(
      'without a ceiling every level is allowed (classificeren optioneel)',
      () {
        const policy = ClassificationPolicy();
        expect(policy.hasGate, isFalse);
        for (final level in TlpLevel.values) {
          expect(policy.evaluate(level).allowed, isTrue);
        }
      },
    );

    test('a ceiling allows levels at or below it', () {
      const policy = ClassificationPolicy(maxReleaseLevel: TlpLevel.amber);
      expect(policy.hasGate, isTrue);
      for (final level in [
        TlpLevel.none,
        TlpLevel.clear,
        TlpLevel.green,
        TlpLevel.amber,
      ]) {
        expect(policy.evaluate(level).allowed, isTrue, reason: level.name);
      }
    });

    test('a ceiling blocks levels above it, with a clear reason', () {
      const policy = ClassificationPolicy(maxReleaseLevel: TlpLevel.amber);
      for (final level in [TlpLevel.amberStrict, TlpLevel.red]) {
        final decision = policy.evaluate(level);
        expect(decision.allowed, isFalse, reason: level.name);
        // De reden is sinds #576 een enum plus de twee niveaus, geen zin: een
        // weigering die het niveau interpoleert kan niet vertaald worden. De
        // zin zelf wordt in de schil gemaakt; hier toetsen we dat de gegevens
        // om hem te máken kloppen.
        expect(decision.reason, ExportBlockReason.aboveCeiling);
        expect(decision.deckLevel, level);
        expect(decision.limit, TlpLevel.amber);
      }
    });

    test('a ceiling of none only allows unclassified decks', () {
      const policy = ClassificationPolicy(maxReleaseLevel: TlpLevel.none);
      expect(policy.evaluate(TlpLevel.none).allowed, isTrue);
      expect(policy.evaluate(TlpLevel.clear).allowed, isFalse);
    });

    group('fromKey', () {
      test('null key means no gate', () {
        final policy = ClassificationPolicy.fromKey(null);
        expect(policy.hasGate, isFalse);
        expect(policy.evaluate(TlpLevel.red).allowed, isTrue);
      });

      test('a TLP key sets the ceiling', () {
        final policy = ClassificationPolicy.fromKey(TlpLevel.green.key);
        expect(policy.maxReleaseLevel, TlpLevel.green);
        expect(policy.evaluate(TlpLevel.green).allowed, isTrue);
        expect(policy.evaluate(TlpLevel.amber).allowed, isFalse);
      });
    });
  });
}
