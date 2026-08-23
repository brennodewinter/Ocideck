import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/matrix_settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/models/settings.dart' show ThemeProfile;
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/matrix_client_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  const account = MatrixServer(
    homeserverUrl: 'https://hs.example',
    userId: '@u:hs.example',
    deviceId: 'DEV1',
  );

  Deck finalizedDeck() => Deck(
    title: 'd',
    slides: [Slide.create(SlideType.bullets)],
    finalized: true,
  );

  Future<WidgetRef> refWith(WidgetTester tester, MatrixServer? acc) async {
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [matrixAccountProvider.overrideWithValue(acc)],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return captured;
  }

  testWidgets('no sign command for an unfinalised deck', (tester) async {
    final ref = await refWith(tester, account);
    final cmds = provenanceSignCommands(
      ref,
      const AppLocalizations(Locale('nl')),
      Deck(title: 'd', slides: [Slide.create(SlideType.bullets)]),
      () {},
    );
    expect(cmds, isEmpty);
  });

  testWidgets('no sign command without a Matrix account', (tester) async {
    final ref = await refWith(tester, null);
    final cmds = provenanceSignCommands(
      ref,
      const AppLocalizations(Locale('nl')),
      finalizedDeck(),
      () {},
    );
    expect(cmds, isEmpty);
  });

  testWidgets('a finalised deck with an account offers the sign command', (
    tester,
  ) async {
    final ref = await refWith(tester, account);
    var invoked = 0;
    final cmds = provenanceSignCommands(
      ref,
      const AppLocalizations(Locale('nl')),
      finalizedDeck(),
      () => invoked++,
    );
    expect(cmds, hasLength(1));
    expect(cmds.single.label, 'Herkomst ondertekenen');
    cmds.single.onInvoke();
    expect(invoked, 1);
  });

  testWidgets('signing an unsaved deck asks to save first (guard)', (
    tester,
  ) async {
    final md = MarkdownService();
    final deckN =
        DeckNotifier(
            md,
            FileService(md, ImageService(), () => const ThemeProfile()),
          )
          // Finalised but dirty and without a seal hash → the guard fires.
          ..loadDeck(finalizedDeck());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matrixAccountProvider.overrideWithValue(account),
          deckProvider.overrideWith((ref) => deckN),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () =>
                    runProvenanceSigning(context, ref, save: () async {}),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Rond de presentatie eerst af'), findsOneWidget);
  });
}
