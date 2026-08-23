import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/duplicate_badges.dart';

/// De twee markeringen in de presentatielijst die zeggen "let op, hier staat
/// hetzelfde nog een keer". Ze doen tegengestelde beweringen en dat verschil is
/// het hele punt: een `+N`-chip zegt dat de kopieën byte-identiek zijn (kies
/// gerust), de conflictmarkering zegt dat de inhoud juist verschilt (kies met
/// zorg). Wisselen ze om, dan opent iemand rustig de verkeerde versie.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  group('formatModifiedDate', () {
    test('een datum, geen tijdstip', () {
      // In een lijstregel voegt het tijdstip niets toe aan "welke kopie is de
      // recentste?" en kost het wel breedte.
      expect(formatModifiedDate(DateTime(2026, 7, 21, 13, 45)), '2026-07-21');
    });

    test('maand en dag houden hun voorloopnul', () {
      // Zonder padding sorteert een lijst van datums als tekst verkeerd.
      expect(formatModifiedDate(DateTime(2026, 1, 2)), '2026-01-02');
    });

    test('zonder datum blijft het leeg, geen "null"', () {
      expect(formatModifiedDate(null), '');
    });
  });

  group('IdenticalCopiesChip', () {
    Future<void> pumpChip(
      WidgetTester tester,
      List<String> others,
      void Function(String) onOpen,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: IdenticalCopiesChip(
                otherPaths: others,
                homeDir: '/Users/aisha',
                onOpen: onOpen,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('telt de ándere vindplaatsen, niet zichzelf', (tester) async {
      await pumpChip(tester, const [
        '/Users/aisha/Documenten/rapport.md',
        '/Users/aisha/Bureaublad/rapport.md',
      ], (_) {});

      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('het menu noemt elke kopie en opent de gekozene', (
      tester,
    ) async {
      final opened = <String>[];
      await pumpChip(tester, const [
        '/Users/aisha/Documenten/rapport.md',
        '/Volumes/archief/2026/rapport.md',
      ], opened.add);

      await tester.tap(find.byType(IdenticalCopiesChip));
      await tester.pumpAndSettle();

      // Het volledige pad staat in de tooltip; in beeld staat de leesbare map.
      expect(find.byType(PopupMenuItem<String>), findsNWidgets(2));
      expect(
        find.byTooltip('/Volumes/archief/2026/rapport.md'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('/Volumes/archief/2026/rapport.md'));
      await tester.pumpAndSettle();

      expect(opened, ['/Volumes/archief/2026/rapport.md']);
    });

    testWidgets('een pad in de eigen thuismap wordt ingekort', (tester) async {
      await pumpChip(tester, const [
        '/Users/aisha/Documenten/rapport.md',
      ], (_) {});

      await tester.tap(find.byType(IdenticalCopiesChip));
      await tester.pumpAndSettle();

      // Het volle pad blijft in de tooltip staan; de regel zelf toont het
      // ingekorte pad, anders past er niets meer naast.
      expect(find.text('/Users/aisha/Documenten'), findsNothing);
      expect(
        find.byTooltip('/Users/aisha/Documenten/rapport.md'),
        findsOneWidget,
      );
    });
  });

  group('TitleConflictMarker', () {
    testWidgets('zegt dat de inhoud afwijkt, met de datum erbij', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TitleConflictMarker(modified: DateTime(2026, 7, 21)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Zelfde titel, andere inhoud  ·  2026-07-21'),
        findsOneWidget,
      );
    });

    testWidgets('zonder datum blijft de melding zelf staan', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TitleConflictMarker(modified: null)),
        ),
      );
      await tester.pumpAndSettle();

      // Geen losse punt-scheiding zonder iets erachter.
      expect(find.text('Zelfde titel, andere inhoud'), findsOneWidget);
      expect(find.textContaining('·'), findsNothing);
    });
  });
}
