import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/state/collab_session_provider.dart';

void main() {
  group('collabSidecarOpsDir', () {
    test('puts the ops folder beside the deck, stripping .md', () {
      expect(
        collabSidecarOpsDir('decks/talk.md'),
        'decks/talk.ocideck-collab/ops',
      );
    });
    test('handles a path without a .md extension', () {
      expect(collabSidecarOpsDir('deck'), 'deck.ocideck-collab/ops');
    });
  });

  group('CollabSessionState', () {
    test('starts idle and reports its phase', () {
      const s = CollabSessionState();
      expect(s.phase, CollabPhase.idle);
      expect(s.isActive, isFalse);
      expect(s.isConnecting, isFalse);
    });
    test('copyWith clears the error unless given', () {
      const s = CollabSessionState(phase: CollabPhase.failed, error: 'x');
      expect(s.copyWith(phase: CollabPhase.idle).error, isNull);
    });
  });

  group('the unbound root notifier (no tab)', () {
    test('cannot collaborate', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(collabSessionProvider.notifier).canCollaborate,
        isFalse,
      );
    });

    test('host fails with not-webdav and leave returns to idle', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(collabSessionProvider.notifier);

      await notifier.host();
      expect(container.read(collabSessionProvider).phase, CollabPhase.failed);
      expect(container.read(collabSessionProvider).error, 'not-webdav');

      await notifier.leave();
      expect(container.read(collabSessionProvider).phase, CollabPhase.idle);
    });

    test('join also fails not-webdav without a tab', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(collabSessionProvider.notifier).join();
      expect(container.read(collabSessionProvider).error, 'not-webdav');
    });
  });
}
