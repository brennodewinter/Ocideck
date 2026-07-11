import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/editors/_editor_field.dart';
import 'package:ocideck/widgets/editors/signoff_editor.dart';

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Future<ProviderContainer> pump(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(deckProvider.notifier);
    notifier.newDeck('Rapport');
    notifier.updateSlide(0, Slide.create(SlideType.signOff));

    await tester.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SignOffEditor(
              slide: container.read(deckProvider).deck!.slides.single,
              onUpdate: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('editing the rapporteur updates the deck signature', (
    tester,
  ) async {
    final container = await pump(tester);

    final naam = find.descendant(
      of: find.byWidgetPredicate((w) => w is EditorField && w.label == 'Naam'),
      matching: find.byType(TextField),
    );
    await tester.enterText(naam, 'Jan Jansen');
    final cert = find.descendant(
      of: find.byWidgetPredicate(
        (w) => w is EditorField && w.label == 'Certificering',
      ),
      matching: find.byType(TextField),
    );
    await tester.enterText(cert, 'OSCP');
    await tester.pump();

    final sig = container.read(deckProvider).deck!.signature;
    expect(sig?.name, 'Jan Jansen');
    expect(sig?.certification, 'OSCP');
  });

  testWidgets('the seal action is offered on the sign-off slide', (
    tester,
  ) async {
    await pump(tester);
    // The "Afronden & verzegelen" button is present (nl active).
    expect(
      find.widgetWithText(FilledButton, 'Afronden & verzegelen'),
      findsOneWidget,
    );
  });
}
