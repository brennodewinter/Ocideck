@Tags(['golden'])
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/page_size.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/reader/paged_document_view.dart';

/// Een voetnoot die langer is dan het tekstvlak van een blad (#2469): het
/// nootvlak mag haar niet stil afknippen — de golden legt het scrollbare vlak
/// mét doorgang-regel vast.
void main() {
  testWidgets('overloopnoot in de paginaweergave', (tester) async {
    const size = Size(620, 760);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final note = List.generate(
      300,
      (i) => 'Nootregel $i van een voetnoot die veel te lang is voor één blad.',
    ).join(' ');

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
            markdown: 'Tekst met een noot [^1] erin.\n\n[^1]: $note',
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

    // Het vel met de noot: de doorgang-regel en de scrollbalk horen op het
    // beeld te staan.
    await expectLater(
      find.byKey(const Key('document-sheet')).first,
      matchesGoldenFile('goldens/document_footnote_overflow.png'),
    );
  });
}
