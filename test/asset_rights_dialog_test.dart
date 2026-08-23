import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/asset_rights.dart';
import 'package:ocideck/services/git/asset_rights_index.dart';
import 'package:ocideck/services/git/git_forge.dart';
import 'package:ocideck/widgets/dialogs/asset_rights_dialog.dart';

class _UnusedForge implements GitForge {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Forge-aanroep niet verwacht');
}

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Widget host(RepoAssetRightsSnapshot snapshot) => MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('nl'),
    home: AssetRightsDialog(
      index: RepoAssetRightsIndex(forge: _UnusedForge(), branch: 'main'),
      initial: snapshot,
    ),
  );

  testWidgets('toont open signalen en hun mogelijke afdoeningen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final assessment = AssetRightsAssessment(
      sha256: List.filled(64, 'a').join(),
      mimeType: 'image/png',
      byteLength: 42,
      scannerVersion: 'test',
      scannedAt: DateTime.utc(2026),
      signals: const [
        AssetRightsSignal(
          ruleId: 'metadata-source-missing',
          risk: AssetRightsRisk.review,
          message: 'Herkomst ontbreekt',
          fingerprint: 'bron',
        ),
      ],
    );

    await tester.pumpWidget(
      host(
        RepoAssetRightsSnapshot(
          assessments: [assessment],
          unreadable: const ['assets/onleesbaar.png'],
          newlyScanned: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Herkomst ontbreekt'), findsOneWidget);
    expect(find.textContaining('1 afbeeldingen vragen'), findsOneWidget);
    expect(find.textContaining('1 bestanden konden niet'), findsOneWidget);

    await tester.tap(find.byTooltip('Afdoening'));
    await tester.pumpAndSettle();
    expect(find.text('Geldige rechten aangetoond'), findsOneWidget);
    expect(find.text('Onterechte signalering'), findsOneWidget);
    expect(find.text('Niet gebruiken'), findsOneWidget);
  });

  testWidgets('meldt het wanneer er geen openstaande signalen zijn', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const RepoAssetRightsSnapshot(
          assessments: [],
          unreadable: [],
          newlyScanned: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Geen openstaande aanwijzingen.'), findsOneWidget);
    expect(find.text('Sluiten'), findsOneWidget);
  });
}
