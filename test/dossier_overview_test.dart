import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/document_dossier.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/dossier/dossier_overview.dart';
import 'package:ocideck/widgets/dossier/dossier_dialogs.dart';

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  final now = DateTime.utc(2026, 1, 1);
  final dossier = DocumentDossier(
    title: 'Onderzoeksdossier',
    description: 'Onderzoek naar de bronstukken',
    startNumber: 10,
    createdAt: now,
    updatedAt: now,
    entries: [
      for (var i = 0; i < 20; i++)
        DossierEntry(
          id: '$i',
          title: 'Document ${i + 1}',
          relativePath: 'attachments/$i.md',
          sha256: 'a' * 64,
          originalName: 'bronstuk-$i.md',
          sourceRelativePath: 'bronnen/bronstuk-$i.md',
          sizeBytes: 1536,
          checkedAt: now,
        ),
    ],
  );

  Widget overview({
    void Function(int, int)? onReorder,
    ThemeData? theme,
    int? openingProgress,
    int? openingTotal,
    VoidCallback? onCancelOpening,
    int? verificationProgress,
    int? verificationTotal,
    Set<String> unsavedEntryIds = const {},
  }) => MaterialApp(
    theme: theme ?? AppTheme.light,
    localizationsDelegates: const [AppLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: DossierOverview(
        dossier: dossier,
        onOpenEntry: (_) {},
        onOpenAll: () {},
        onOpenAsDocument: () {},
        onAdd: () {},
        onVerifyEntry: (_) {},
        onVerifyAll: () {},
        onRefreshReference: (_) {},
        onRenameEntry: (_, _) {},
        onRemoveEntry: (_) {},
        onReorder: onReorder ?? (_, _) {},
        onRenameDossier: (_) {},
        onChangeDescription: (_) {},
        onChangeStartNumber: (_) {},
        onChangeEntryNumber: (_, _) {},
        openingProgress: openingProgress,
        openingTotal: openingTotal,
        onCancelOpening: onCancelOpening,
        verificationProgress: verificationProgress,
        verificationTotal: verificationTotal,
        unsavedEntryIds: unsavedEntryIds,
      ),
    ),
  );

  for (final width in [360.0, 480.0, 1024.0]) {
    testWidgets('dossier with 20 entries fits ${width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(overview());
      await tester.pumpAndSettle();
      expect(find.text('Onderzoeksdossier'), findsOneWidget);
      expect(find.text('Inhoudsopgave'), findsOneWidget);
      expect(find.text('Onderzoek naar de bronstukken'), findsOneWidget);
      final error = tester.takeException();
      expect(
        error,
        isNull,
        reason: error is FlutterError ? error.toStringDeep() : null,
      );
    });
  }

  testWidgets('dark theme keeps source details and status readable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      overview(theme: AppTheme.fromProfile(AppAppearanceProfile.dark)),
    );
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('bronstuk-0.md'),
      find.byType(Scrollable).first,
      const Offset(0, -120),
    );
    expect(find.text('bronstuk-0.md'), findsWidgets);
    expect(find.textContaining('bronnen/bronstuk-0.md'), findsWidgets);
    expect(find.text('1.5 KB'), findsWidgets);
    expect(find.text('Nog niet gecontroleerd'), findsWidgets);
    expect(find.text('10'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.fromProfile(AppAppearanceProfile.dark)),
  ]) {
    testWidgets('$name theme text contrasts with its actual background', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1024, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(overview(theme: theme));
      await tester.pumpAndSettle();

      void expectContrast(Finder finder, Color background) {
        final widget = tester.widget<Text>(finder.first);
        final foreground = Color.alphaBlend(widget.style!.color!, background);
        final light = foreground.computeLuminance();
        final dark = background.computeLuminance();
        final ratio =
            (light > dark ? light + 0.05 : dark + 0.05) /
            (light > dark ? dark + 0.05 : light + 0.05);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '${widget.data}: $ratio',
        );
      }

      final palette = AppPalette.of(theme);
      expectContrast(find.text('Inhoudsopgave'), theme.scaffoldBackgroundColor);
      expectContrast(find.text('Document 1'), palette.panel);
      expectContrast(find.text('bronstuk-0.md'), palette.panel);
      expectContrast(find.text('Nog niet gecontroleerd'), palette.panel);
      expectContrast(find.text('10'), AppTheme.amberVivid);
    });
  }

  testWidgets('opening progress announces count and offers cancellation', (
    tester,
  ) async {
    var cancelled = false;
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      overview(
        openingProgress: 2,
        openingTotal: 20,
        onCancelOpening: () => cancelled = true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Documenten openen: 2 / 20'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Annuleren'));
    expect(cancelled, isTrue);
  });

  testWidgets('verification and unsaved disk warning remain distinct', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      overview(
        verificationProgress: 2,
        verificationTotal: 20,
        unsavedEntryIds: const {'0'},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Documenten controleren: 2 / 20'), findsOneWidget);
    expect(
      find.text(
        'Onopgeslagen wijzigingen in tabblad; SHA-256 controleert de schijfversie.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('duplicate manual number is rejected with an explanation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => DossierDialogs.editNumber(
                context,
                initialNumber: 1,
                title: 'Nummer wijzigen',
                usedNumbers: const {2},
              ),
              child: const Text('Wijzig'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Wijzig'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '2');
    await tester.tap(find.text('Opslaan'));
    await tester.pumpAndSettle();
    expect(find.text('Dit nummer is al in gebruik.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('create dossier keeps fields alive through closing animation', (
    tester,
  ) async {
    (String, String)? created;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  created = await DossierDialogs.createDossier(context),
              child: const Text('Maak dossier'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Maak dossier'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'De map');
    await tester.enterText(find.byType(TextField).at(1), 'Beschrijving');
    await tester.tap(find.text('Dossier maken'));
    await tester.pumpAndSettle();
    expect(created, ('De map', 'Beschrijving'));
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
