@Tags(['golden'])
library;

import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/editors/markdown_find_bar.dart';

const _surfaceKey = ValueKey('search-bar-golden-surface');
const _context =
    'Een lange zoekpassage met belangrijke context '
    'zodat de lezer begrijpt welke passage wordt geopend.';

Future<void> _pumpBar(
  WidgetTester tester, {
  required bool dark,
  required bool narrow,
  required bool empty,
  required VoidCallback onNext,
  required VoidCallback onPrevious,
  required VoidCallback onClose,
  required ValueChanged<int> onSelect,
}) async {
  final size = narrow ? const Size(320, 640) : const Size(760, 420);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  AppTheme.isDark = dark;
  AppLocalizations.setActiveLanguageCode('nl');
  final theme = AppTheme.fromProfile(
    dark ? AppAppearanceProfile.dark : AppAppearanceProfile.basic,
  );
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'Ahem'),
      ),
      locale: const Locale('nl'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          disableAnimations: true,
          textScaler: TextScaler.linear(narrow ? 2 : 1),
        ),
        child: Scaffold(
          body: RepaintBoundary(
            key: _surfaceKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MarkdownFindBar(
                  query: 'passage',
                  replace: '',
                  caseSensitive: false,
                  showReplace: false,
                  matchCount: empty ? 0 : 2,
                  matchIndex: empty ? -1 : 1,
                  resultContexts: empty ? const [] : const [_context, _context],
                  resultLocations: empty
                      ? const []
                      : const [
                          'Hoofdstuk 8 · Rij 3 · Kolom 2',
                          'Hoofdstuk 8 · Rij 14 · Kolom 2',
                        ],
                  wrapDirection: empty ? 0 : 1,
                  onQueryChanged: (_) {},
                  onReplaceChanged: (_) {},
                  onCaseSensitiveChanged: (_) {},
                  onNext: onNext,
                  onPrevious: onPrevious,
                  onReplaceCurrent: () {},
                  onReplaceAll: () {},
                  onClose: onClose,
                  onSelectMatch: onSelect,
                ),
                Expanded(child: ColoredBox(color: theme.colorScheme.surface)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => AppTheme.isDark = false);

  for (final dark in [false, true]) {
    for (final narrow in [false, true]) {
      for (final empty in [false, true]) {
        final name =
            'search_bar_${dark ? 'dark' : 'light'}_'
            '${narrow ? 'narrow_200' : 'wide'}_${empty ? 'empty' : 'results'}';
        testWidgets(name, (tester) async {
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var next = 0;
          var previous = 0;
          var close = 0;
          int? selected;
          await _pumpBar(
            tester,
            dark: dark,
            narrow: narrow,
            empty: empty,
            onNext: () => next++,
            onPrevious: () => previous++,
            onClose: () => close++,
            onSelect: (index) => selected = index,
          );
          expect(tester.takeException(), isNull);
          final query = find.byType(TextField);
          if (narrow) {
            expect(
              tester.getSize(query).width,
              greaterThanOrEqualTo(180),
              reason: 'Grote tekst moet als zoekvraag leesbaar blijven.',
            );
          }
          expect(tester.widget<TextField>(query).focusNode!.hasFocus, isTrue);
          for (final tooltip in ['Vorige', 'Volgende', 'Sluiten']) {
            expect(find.byTooltip(tooltip).hitTestable(), findsOneWidget);
          }
          if (!empty) {
            expect(find.text('Verder vanaf het begin'), findsOneWidget);
            final contextParagraph = tester.renderObject<RenderParagraph>(
              find
                  .byWidgetPredicate(
                    (widget) =>
                        widget is RichText &&
                        widget.text.toPlainText().contains('passage'),
                  )
                  .first,
            );
            final term = contextParagraph.text.toPlainText().indexOf('passage');
            expect(
              contextParagraph.getBoxesForSelection(
                TextSelection(baseOffset: term, extentOffset: term + 7),
              ),
              isNotEmpty,
              reason:
                  'De gezochte passage moet binnen de zichtbare resultaatcontext staan.',
            );
            await tester.tap(find.byTooltip('Volgende'));
            await tester.pump();
            expect(next, 1);
            await tester.tap(find.byTooltip('Vorige'));
            await tester.pump();
            expect(previous, 1);
            await tester.tap(find.byType(ListTile).first);
            await tester.pump();
            expect(selected, 0);
            expect(tester.widget<TextField>(query).focusNode!.hasFocus, isTrue);
          } else {
            expect(
              find.text('Geen resultaten. Probeer een kortere zoektekst.'),
              findsOneWidget,
            );
          }
          await expectLater(
            find.byKey(_surfaceKey),
            matchesGoldenFile('goldens/$name.png'),
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          expect(close, 1);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
