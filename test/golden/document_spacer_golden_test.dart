@Tags(['golden'])
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/page_size.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/reader/paged_document_view.dart';

/// Een `<!-- spacer -->`-marker in de paginaweergave (#2464): de golden legt
/// vast dat de ruimte zichtbaar is — één marker één tekstregel, twee markers
/// twee — en niet verdwijnt tussen de alinea's.
void main() {
  testWidgets('spacers in de paginaweergave', (tester) async {
    const size = Size(620, 760);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final baseTheme = AppTheme.fromProfile(AppAppearanceProfile.basic);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: baseTheme.copyWith(
          textTheme: baseTheme.textTheme.apply(fontFamily: 'Ahem'),
        ),
        locale: const Locale('nl'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          backgroundColor: AppTheme.slate100,
          body: PagedDocumentView(
            markdown:
                'Eerste alinea met wat tekst.\n\n<!-- spacer -->\n\n'
                'Tweede alinea na één regel extra ruimte.\n\n'
                '<!-- spacer -->\n\n<!-- spacer -->\n\n'
                'Derde alinea na twee regels extra ruimte.\n',
            pageSize: const PageSizeSpec(series: PaperSeries.a, number: 6),
            margins: const PageMargins(
              topMm: 10,
              rightMm: 10,
              bottomMm: 10,
              leftMm: 10,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const Key('document-sheet')).first,
      matchesGoldenFile('goldens/document_spacer.png'),
    );
  });
}
