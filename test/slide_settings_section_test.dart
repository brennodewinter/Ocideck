import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/panels/editor_panel.dart';

const _l10n = AppLocalizations(Locale('nl'));

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required TlpLevel tlp,
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(deckProvider.notifier);
    notifier.newDeck('Test');
    final slide = container
        .read(deckProvider)
        .deck!
        .slides
        .single
        .copyWith(tlp: tlp);
    notifier.updateSlide(0, slide);

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
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: EditorPanel()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('slide settings start collapsed and expand on tap', (
    tester,
  ) async {
    await pump(tester, tlp: TlpLevel.none);

    final settingsToggle = find.byTooltip(_l10n.d('Slide-instellingen'));
    expect(settingsToggle, findsOneWidget);
    // Collapsed: the individual controls are not built yet.
    expect(find.text(_l10n.d('Automatisch doorgaan na')), findsNothing);
    expect(find.text(_l10n.d('TLP van deze slide')), findsNothing);

    await tester.tap(settingsToggle);
    await tester.pumpAndSettle();

    expect(find.text(_l10n.d('Automatisch doorgaan na')), findsOneWidget);
    expect(find.text(_l10n.d('TLP van deze slide')), findsOneWidget);
  });

  testWidgets('the collapsed header summarizes an active TLP level', (
    tester,
  ) async {
    await pump(tester, tlp: TlpLevel.amber);
    // The classification stays visible at a glance without expanding.
    expect(find.text('TLP:AMBER'), findsOneWidget);
  });
}
