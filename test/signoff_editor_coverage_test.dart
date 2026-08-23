import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/info_safety_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/editors/_editor_field.dart';
import 'package:ocideck/widgets/editors/markdown_editor_field.dart';
import 'package:ocideck/widgets/editors/signoff_editor.dart';

/// Coverage for the [SignOffEditor]: the attestation fields author the
/// deck-level [DocumentSignature] via [DeckNotifier.setSignature], the slide
/// title flows through `onUpdate`, the freehand-signature control is offered,
/// and a finalised deck shows the read-only sealed notice.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));
  tearDown(() => AppLocalizations.setActiveLanguageCode('nl'));

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    void Function(Slide)? onUpdate,
    bool sealed = false,
  }) async {
    // De ondertekeningsdia hoort bij de informatieveiligheidsmodule, en de
    // verzegelknop erop zit achter dezelfde schakelaar. Deze harnas doet alsof
    // de module aan staat — de staat waarin je een rapport ondertekent.
    final container = ProviderContainer(
      overrides: [infoSafetyRevealProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);
    final notifier = container.read(deckProvider.notifier);
    notifier.newDeck('Rapport');
    notifier.updateSlide(0, Slide.create(SlideType.signOff));
    if (sealed) notifier.finalizeAndSeal();

    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SignOffEditor(
              slide: container.read(deckProvider).deck!.slides.single,
              onUpdate: onUpdate ?? (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Finder fieldByLabel(String label) => find.descendant(
    of: find.byWidgetPredicate(
      (w) =>
          (w is EditorField && w.label == label) ||
          (w is MarkdownEditorField && w.label == label),
    ),
    matching: find.byType(TextField),
  );

  testWidgets('filling the attestation authors the deck signature', (
    tester,
  ) async {
    final container = await pump(tester);

    await tester.enterText(
      fieldByLabel('Verklaring'),
      'Deze rapportage is naar waarheid opgesteld.',
    );
    await tester.enterText(fieldByLabel('Naam'), 'Jan Jansen');
    await tester.enterText(fieldByLabel('Rol of functie'), 'Onderzoeker');
    await tester.enterText(fieldByLabel('Certificering'), 'OSCP');
    await tester.enterText(fieldByLabel('Getypte handtekening'), 'J. Jansen');
    await tester.pump();

    final sig = container.read(deckProvider).deck!.signature;
    expect(sig, isNotNull);
    expect(sig!.statement, 'Deze rapportage is naar waarheid opgesteld.');
    expect(sig.name, 'Jan Jansen');
    expect(sig.role, 'Onderzoeker');
    expect(sig.certification, 'OSCP');
    expect(sig.typedSignature, 'J. Jansen');
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing the title flows through onUpdate', (tester) async {
    Slide? updated;
    await pump(tester, onUpdate: (s) => updated = s);

    await tester.enterText(fieldByLabel('Titel'), 'Ondertekening');
    await tester.pump();

    expect(updated, isNotNull);
    expect(updated!.title, 'Ondertekening');
  });

  testWidgets('the draw-signature and seal actions are offered', (
    tester,
  ) async {
    await pump(tester);

    // The freehand-signature "draw" control (gesture icon) is present.
    expect(
      find.widgetWithText(OutlinedButton, 'Handtekening tekenen'),
      findsOneWidget,
    );
    // The seal action is offered on an unsealed deck.
    expect(
      find.widgetWithText(FilledButton, 'Afronden & verzegelen'),
      findsOneWidget,
    );
  });

  testWidgets('a finalised deck shows the read-only sealed notice', (
    tester,
  ) async {
    await pump(tester, sealed: true);

    // The editable fields are gone; only the sealed notice remains.
    expect(find.byType(EditorField), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Afronden & verzegelen'),
      findsNothing,
    );
    expect(find.textContaining('Verzegeld op'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
