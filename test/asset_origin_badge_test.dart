import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/asset_origin.dart';
import 'package:ocideck/widgets/asset_origin_badge.dart';

/// Gedragsdekking voor [AssetOriginBadge]: de badge zwijgt over media die
/// gewoon meeverhuist, en noemt bij de rest zowel de toestand als het gevolg.
Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('zwijgt over media die bij het deck hoort', (tester) async {
    await tester.pumpWidget(
      _host(const AssetOriginBadge(origin: AssetOrigin.inDeck)),
    );

    expect(find.byType(Tooltip), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('zwijgt als er geen afbeelding is', (tester) async {
    await tester.pumpWidget(
      _host(const AssetOriginBadge(origin: AssetOrigin.none)),
    );

    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('meldt een extern bestand met gevolg én uitweg', (tester) async {
    await tester.pumpWidget(
      _host(const AssetOriginBadge(origin: AssetOrigin.external)),
    );

    expect(find.text('Buiten de presentatie'), findsOneWidget);
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, contains('gaat niet mee'));
    expect(tooltip.message, contains('Sla op'));
  });

  testWidgets('meldt de wachtkamer als tussenstand, niet als fout', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const AssetOriginBadge(origin: AssetOrigin.staged)),
    );

    expect(find.text('Nog niet opgeslagen'), findsOneWidget);
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, contains('staat veilig'));
  });

  testWidgets('meldt materiaal van internet', (tester) async {
    await tester.pumpWidget(
      _host(const AssetOriginBadge(origin: AssetOrigin.remote)),
    );

    expect(find.text('Van internet'), findsOneWidget);
  });

  testWidgets('meldt een afbeelding die alleen in het geheugen staat', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const AssetOriginBadge(origin: AssetOrigin.memory)),
    );

    expect(find.text('Alleen in deze sessie'), findsOneWidget);
  });

  test('elke te melden herkomst heeft tekst én uitleg', () {
    final l10n = AppLocalizations(const Locale('nl'));
    for (final origin in AssetOrigin.values) {
      if (!assetOriginNeedsAttention(origin)) continue;
      expect(
        assetOriginLabel(l10n, origin),
        isNotEmpty,
        reason: 'ontbrekend label voor $origin',
      );
      expect(
        assetOriginExplanation(l10n, origin),
        isNotEmpty,
        reason: 'ontbrekende uitleg voor $origin',
      );
    }
  });
}
