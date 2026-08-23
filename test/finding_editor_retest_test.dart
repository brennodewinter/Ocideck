import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/widgets/editors/finding_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The finding editor's Hertest (retest) dropdown writes the retest status into
/// the finding's Markdown, and a note field appears once an outcome is set.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLocalizations.setActiveLanguageCode('nl');
  });
  tearDown(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('choosing "Opgelost" writes a Resolved retest line', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(deckProvider.notifier);
    notifier.newDeck('Test');
    final finding = Slide.create(SlideType.finding).copyWith(
      findingId: 'F-1',
      customMarkdown: const FindingSpec(heading: 'F-1').toMarkdown(),
    );
    notifier.updateSlide(0, finding);

    Slide? updated;
    await tester.binding.setSurfaceSize(const Size(1000, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: FindingEditor(
              slide: finding,
              onUpdate: (s) => updated = s,
              imageService: ImageService(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No retest yet: no note field, no Retest line.
    expect(find.text('Hertest-notitie'), findsNothing);

    await tester.tap(find.byType(DropdownButtonFormField<RetestStatus>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Opgelost').last);
    await tester.pumpAndSettle();

    expect(updated, isNotNull);
    expect(updated!.customMarkdown, contains('**Retest:** Resolved'));
    // The note field now shows.
    expect(find.text('Hertest-notitie'), findsOneWidget);
  });
}
