import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/editor_provider.dart';

/// Hardening bovenop #1478: de per-tab notifiers hebben gedeelde eigendom
/// (aangemaakt/bewaard door TabsNotifier, gedisposed door hun ProviderScope).
/// Raakt een teardown-race twee scopes aan dezelfde instantie, dan gooit de
/// basis-`dispose` "Tried to use ... after `dispose`". De GlobalKey-fix haalde
/// de bekende trigger weg; deze idempotente `dispose` maakt élke resterende
/// dubbele dispose een no-op in plaats van een crash-vloed.
///
/// Zonder de guard is de tweede `dispose()` een StateError; met de guard een
/// no-op. Deze test faalt dus zonder de fix en slaagt ermee.
void main() {
  test('DeckNotifier.dispose is idempotent', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = DeckNotifier(
      container.read(markdownServiceProvider),
      container.read(fileServiceProvider),
    );
    n.dispose();
    expect(n.mounted, isFalse);
    expect(
      n.dispose,
      returnsNormally,
      reason: 'tweede dispose mag niet gooien',
    );
  });

  test('EditorNotifier.dispose is idempotent', () {
    final n = EditorNotifier();
    n.dispose();
    expect(n.mounted, isFalse);
    expect(
      n.dispose,
      returnsNormally,
      reason: 'tweede dispose mag niet gooien',
    );
  });
}
