import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/document_dossier.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/widgets/dossier/dossier_overview.dart';

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  final now = DateTime.utc(2026, 1, 1);
  final dossier = DocumentDossier(
    title: 'Onderzoeksdossier',
    createdAt: now,
    updatedAt: now,
    entries: [
      for (var i = 0; i < 20; i++)
        DossierEntry(
          id: '$i',
          title: 'Document ${i + 1}',
          relativePath: 'attachments/$i.md',
          sha256: 'a' * 64,
        ),
    ],
  );

  Widget overview({void Function(int, int)? onReorder}) => MaterialApp(
    theme: AppTheme.light,
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
      final error = tester.takeException();
      expect(
        error,
        isNull,
        reason: error is FlutterError ? error.toStringDeep() : null,
      );
    });
  }
}
