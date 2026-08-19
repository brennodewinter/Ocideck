@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/page_size.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';
import 'package:ocideck/widgets/reader/paged_document_view.dart';

const _surfaceKey = ValueKey('document-timeline-golden-surface');

void main() {
  testWidgets('verticale documenttijdlijn', (tester) async {
    const size = Size(760, 720);
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
        home: Scaffold(
          backgroundColor: AppTheme.slate100,
          body: RepaintBoundary(
            key: _surfaceKey,
            child: ColoredBox(
              color: AppTheme.slate100,
              child: const Padding(
                padding: EdgeInsets.all(28),
                child: DocumentMarkdownView(
                  '''<!-- timeline -->
| Tijd | Gebeurtenis | Status |
| --- | --- | --- |
| 12:02 | Eerste melding via de servicedesk | Gemeld |
| 13:30 | Beheer meldt dat de rechten zijn hersteld | Verklaring EQUA |
| 13:41 | Herstelclaim **weerlegd** in een onafhankelijke controle | Vastgesteld |''',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    await expectLater(
      find.byKey(_surfaceKey),
      matchesGoldenFile('goldens/document_timeline.png'),
    );
  });

  testWidgets('rail op een tijdlijnvervolgpagina', (tester) async {
    const size = Size(620, 760);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final events = List.generate(
      19,
      (i) =>
          '| ${i.toString().padLeft(2, '0')}:00 | Gebeurtenis $i met voldoende toelichting voor meerdere pagina’s |',
    ).join('\n');

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
                '<!-- timeline -->\n'
                '| Tijd | Gebeurtenis |\n'
                '| --- | --- |\n'
                '$events',
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

    final continuation = find
        .byKey(const Key('document-timeline-continuation'))
        .first;
    final continuationSheet = find
        .ancestor(
          of: continuation,
          matching: find.byKey(const Key('document-sheet')),
        )
        .first;
    await expectLater(
      continuationSheet,
      matchesGoldenFile('goldens/document_timeline_continuation.png'),
    );
  });
}
