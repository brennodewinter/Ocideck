import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/classification_enforcement_policy.dart';
import 'package:ocideck/services/classification_policy.dart';

void main() {
  group('ClassificationEnforcementPolicy', () {
    test('without rules every level is allowed', () {
      const policy = ClassificationEnforcementPolicy();
      expect(policy.hasGate, isFalse);
      for (final level in TlpLevel.values) {
        expect(policy.evaluate(level).allowed, isTrue, reason: level.name);
      }
    });

    group('release ceiling (plafond)', () {
      test('allows levels at or below the ceiling', () {
        const policy = ClassificationEnforcementPolicy(
          maxReleaseLevel: TlpLevel.amber,
        );
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

      test('blocks levels above the ceiling', () {
        const policy = ClassificationEnforcementPolicy(
          maxReleaseLevel: TlpLevel.amber,
        );
        for (final level in [TlpLevel.amberStrict, TlpLevel.red]) {
          final decision = policy.evaluate(level);
          expect(decision.allowed, isFalse, reason: level.name);
          // Sinds #576 is de reden een enum plus de twee niveaus in plaats van
          // een zin — een weigering die het niveau interpoleert kan niet
          // vertaald worden. De zin zelf staat onder toets in
          // export_block_localization_test.dart.
          expect(decision.reason, ExportBlockReason.aboveCeiling);
          expect(decision.deckLevel, level);
          expect(decision.limit, TlpLevel.amber);
        }
      });

      test('a ceiling of none only allows unclassified decks', () {
        const policy = ClassificationEnforcementPolicy(
          maxReleaseLevel: TlpLevel.none,
        );
        expect(policy.evaluate(TlpLevel.none).allowed, isTrue);
        expect(policy.evaluate(TlpLevel.clear).allowed, isFalse);
      });
    });

    group('minimum level (vloer)', () {
      test('blocks decks below the required minimum', () {
        const policy = ClassificationEnforcementPolicy(
          minRequiredLevel: TlpLevel.green,
        );
        expect(policy.evaluate(TlpLevel.none).allowed, isFalse);
        expect(policy.evaluate(TlpLevel.clear).allowed, isFalse);
        expect(policy.evaluate(TlpLevel.green).allowed, isTrue);
        expect(policy.evaluate(TlpLevel.amber).allowed, isTrue);
      });

      test('explains when the deck is unclassified', () {
        const policy = ClassificationEnforcementPolicy(
          minRequiredLevel: TlpLevel.green,
        );
        final decision = policy.evaluate(TlpLevel.none);
        expect(decision.reason, ExportBlockReason.belowMinimum);
        expect(decision.deckLevel, TlpLevel.none);
        expect(decision.limit, TlpLevel.green);
      });
    });

    group('requireClassification', () {
      test('blocks unclassified decks when enabled', () {
        const policy = ClassificationEnforcementPolicy(
          requireClassification: true,
        );
        expect(policy.hasGate, isTrue);
        expect(policy.evaluate(TlpLevel.none).allowed, isFalse);
        expect(policy.evaluate(TlpLevel.clear).allowed, isTrue);
      });

      test('does not block classified decks on its own', () {
        const policy = ClassificationEnforcementPolicy(
          requireClassification: true,
        );
        for (final level in TlpLevel.values.where((l) => l != TlpLevel.none)) {
          expect(policy.evaluate(level).allowed, isTrue, reason: level.name);
        }
      });
    });

    test('floor is checked before ceiling', () {
      const policy = ClassificationEnforcementPolicy(
        minRequiredLevel: TlpLevel.green,
        maxReleaseLevel: TlpLevel.amber,
      );
      final low = policy.evaluate(TlpLevel.clear);
      expect(low.allowed, isFalse);
      expect(low.reason, ExportBlockReason.belowMinimum);

      final high = policy.evaluate(TlpLevel.red);
      expect(high.allowed, isFalse);
      expect(high.reason, ExportBlockReason.aboveCeiling);
    });

    group('fromAppSettings', () {
      test('maps stored keys and flags', () {
        const settings = AppSettings(
          maxReleaseExportTlpKey: 'amber',
          minRequiredExportTlpKey: 'green',
          requireClassificationOnExport: true,
          classificationWatermarkEnabled: true,
        );
        final policy = ClassificationEnforcementPolicy.fromAppSettings(
          settings,
        );
        expect(policy.maxReleaseLevel, TlpLevel.amber);
        expect(policy.minRequiredLevel, TlpLevel.green);
        expect(policy.requireClassification, isTrue);
        expect(policy.hasGate, isTrue);
      });

      test('defaults leave enforcement off', () {
        final policy = ClassificationEnforcementPolicy.fromAppSettings(
          const AppSettings(),
        );
        expect(policy.hasGate, isFalse);
        expect(policy.evaluate(TlpLevel.red).allowed, isTrue);
      });
    });

    test('releasePolicy matches the legacy ClassificationPolicy', () {
      const enforcement = ClassificationEnforcementPolicy(
        maxReleaseLevel: TlpLevel.green,
        minRequiredLevel: TlpLevel.clear,
        requireClassification: true,
      );
      const legacy = ClassificationPolicy(maxReleaseLevel: TlpLevel.green);
      for (final level in TlpLevel.values) {
        expect(
          enforcement.releasePolicy.evaluate(level).allowed,
          legacy.evaluate(level).allowed,
          reason: level.name,
        );
      }
    });

    test('fromMaxReleaseKey is backward compatible with fromKey', () {
      final enforcement = ClassificationEnforcementPolicy.fromMaxReleaseKey(
        TlpLevel.amber.key,
      );
      final legacy = ClassificationPolicy.fromKey(TlpLevel.amber.key);
      for (final level in TlpLevel.values) {
        expect(
          enforcement.evaluate(level).allowed,
          legacy.evaluate(level).allowed,
          reason: level.name,
        );
      }
    });
  });
}
