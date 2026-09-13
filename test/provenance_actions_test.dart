import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/app_shell.dart';

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Deck finalizedDeck() => Deck(
    title: 'd',
    slides: [Slide.create(SlideType.bullets)],
    finalized: true,
  );

  Future<WidgetRef> refWith(WidgetTester tester) async {
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
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
    final ref = await refWith(tester);
    final cmds = provenanceSignCommands(
      ref,
      const AppLocalizations(Locale('nl')),
      Deck(title: 'd', slides: [Slide.create(SlideType.bullets)]),
      () {},
    );
    expect(cmds, isEmpty);
  });

  testWidgets('no sign command for a finalised deck', (tester) async {
    final ref = await refWith(tester);
    final cmds = provenanceSignCommands(
      ref,
      const AppLocalizations(Locale('nl')),
      finalizedDeck(),
      () {},
    );
    expect(cmds, isEmpty);
  });
}
