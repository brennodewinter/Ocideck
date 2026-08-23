import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/editors/slide_type_help.dart';

void main() {
  test('every slide type has a non-empty help text', () {
    const l10n = AppLocalizations(Locale('nl'));
    for (final type in SlideType.values) {
      expect(
        slideTypeHelpText(l10n, type).trim(),
        isNotEmpty,
        reason: 'no help text for $type',
      );
    }
    expect(slideTlpHelpText(l10n).trim(), isNotEmpty);
  });

  testWidgets('the toggle shows its label and reports taps', (tester) async {
    var toggled = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SlideTypeHelpToggle(open: false, onToggle: () => toggled++),
        ),
      ),
    );
    expect(find.text('Wat kan ik hier?'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);

    await tester.tap(find.text('Wat kan ik hier?'));
    expect(toggled, 1);
  });

  testWidgets('the body renders the selected type hint', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SlideTypeHelpBody(type: SlideType.chart)),
      ),
    );
    const chartHint =
        'Importeer cijfers uit een CSV-bestand of typ ze in het rooster. '
        'Kies staaf, lijn, taart of radar.';
    expect(find.text(chartHint), findsOneWidget);
  });
}
