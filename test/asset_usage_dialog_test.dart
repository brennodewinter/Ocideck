import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/git/asset_index.dart';
import 'package:ocideck/widgets/dialogs/asset_usage_dialog.dart';

/// Het overzicht van de gedeelde afbeeldingenpool (§9.3).
///
/// De regel die hier telt is een veiligheidsregel: dit scherm mag alleen
/// opruimkandidaten noemen als de ronde compleet wás. Kon één deck of één
/// uitgebrachte versie niet gelezen worden, dan is "niemand gebruikt dit" een
/// onbewezen bewering — en weggooien is onomkeerbaar (P2). Een lijst tonen die
/// je niet kunt hardmaken is hier het ergste wat het scherm kan doen.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  AssetUsage asset(
    String ref, {
    List<String> decks = const [],
    List<String> releases = const [],
    int? size,
  }) =>
      AssetUsage(reference: ref, decks: decks, releases: releases, size: size);

  Future<void> pump(WidgetTester tester, AssetIndexSnapshot snapshot) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AssetUsageDialog(snapshot: snapshot)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('de opruimsectie', () {
    testWidgets('een onleesbaar deck blokkeert elk opruimvoorstel', (
      tester,
    ) async {
      await pump(
        tester,
        AssetIndexSnapshot(
          assets: [asset('repo:sha256:aaaa', decks: const [])],
          unreadableDecks: const ['decks/kwartaal'],
          scannedReleases: true,
        ),
      );

      expect(
        find.textContaining('Niet te zeggen wat ongebruikt is'),
        findsOneWidget,
      );
      expect(
        find.textContaining('decks/kwartaal'),
        findsOneWidget,
        reason: 'zeg erbij wát er niet gelezen kon worden',
      );
      // En vooral: géén kandidatenlijst, ook al lijkt de asset ongebruikt.
      expect(
        find.textContaining('worden nergens meer aangehaald'),
        findsNothing,
        reason: 'een onbewezen kandidaat mag hier niet staan',
      );
    });

    testWidgets('een onleesbare uitgebrachte versie telt even zwaar', (
      tester,
    ) async {
      await pump(
        tester,
        AssetIndexSnapshot(
          assets: [asset('repo:sha256:aaaa')],
          unreadableDecks: const [],
          unreadableReleases: const ['v1.2.0'],
          scannedReleases: true,
        ),
      );

      expect(
        find.textContaining('Niet te zeggen wat ongebruikt is'),
        findsOneWidget,
      );
      expect(find.textContaining('v1.2.0'), findsOneWidget);
      expect(
        find.textContaining('worden nergens meer aangehaald'),
        findsNothing,
      );
    });

    testWidgets('een complete ronde noemt de kandidaten mét voorbehoud', (
      tester,
    ) async {
      await pump(
        tester,
        AssetIndexSnapshot(
          assets: [
            asset('repo:sha256:aaaa', decks: const ['kwartaal']),
            asset('repo:sha256:bbbb'),
            asset('repo:sha256:cccc'),
          ],
          unreadableDecks: const [],
          scannedReleases: true,
        ),
      );

      expect(
        find.textContaining('2 afbeeldingen worden nergens meer'),
        findsOneWidget,
      );
      expect(
        find.textContaining('een voorstel, geen oordeel'),
        findsOneWidget,
        reason: 'op een andere branch kan hij nog in gebruik zijn',
      );
    });

    testWidgets('is alles in gebruik, dan staat dát er', (tester) async {
      await pump(
        tester,
        AssetIndexSnapshot(
          assets: [
            asset('repo:sha256:aaaa', decks: const ['kwartaal']),
          ],
          unreadableDecks: const [],
          scannedReleases: true,
        ),
      );

      expect(
        find.text('Elke afbeelding wordt ergens gebruikt.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('worden nergens meer aangehaald'),
        findsNothing,
      );
    });
  });

  group('de regel per afbeelding', () {
    testWidgets('drie toestanden zijn uit elkaar te houden', (tester) async {
      await pump(
        tester,
        AssetIndexSnapshot(
          assets: [
            asset('repo:sha256:aaaa', decks: const ['kwartaal', 'jaarplan']),
            asset('repo:sha256:bbbb', releases: const ['v1.0.0']),
            asset('repo:sha256:cccc'),
          ],
          unreadableDecks: const [],
          scannedReleases: true,
        ),
      );

      expect(find.text('kwartaal, jaarplan'), findsOneWidget);
      // Alleen nog in een release: dat is niet hetzelfde als ongebruikt, en de
      // regel hoort dat verschil te zeggen.
      expect(
        find.textContaining('alleen nog in een uitgebrachte versie: v1.0.0'),
        findsOneWidget,
      );
      expect(find.text('nergens meer gevonden'), findsOneWidget);
    });

    testWidgets('een lege pool zegt dat, in plaats van een lege lijst', (
      tester,
    ) async {
      await pump(
        tester,
        const AssetIndexSnapshot(
          assets: [],
          unreadableDecks: [],
          scannedReleases: true,
        ),
      );

      expect(find.text('De pool is nog leeg.'), findsOneWidget);
      expect(
        find.textContaining('0 afbeeldingen in de gedeelde pool'),
        findsOneWidget,
      );
    });
  });

  group('shortRef', () {
    test('een korte naam blijft heel', () {
      expect(AssetUsageDialog.shortRef('repo:assets/logo.png'), 'logo.png');
    });

    test('een lange naam wordt gekort maar houdt zijn extensie', () {
      // Zonder de extensie is een pool van hashes niet uit elkaar te houden:
      // je ziet dan niet meer of het een png of een pdf is.
      final kort = AssetUsageDialog.shortRef(
        'repo:assets/3f9a1c8e2b4d5a6f7c8e9d0a.png',
      );
      expect(kort, '3f9a1c8e2b….png');
      expect(kort.length, lessThan(20));
    });

    test('iets dat geen poolverwijzing is valt terug op zichzelf', () {
      expect(AssetUsageDialog.shortRef('images/foto.jpg'), 'foto.jpg');
    });
  });

  group('formatSize', () {
    test('geen of nul bytes levert geen tekst op', () {
      expect(AssetUsageDialog.formatSize(null), '');
      expect(AssetUsageDialog.formatSize(0), '');
      expect(AssetUsageDialog.formatSize(-1), '');
    });

    test('bytes, kilobytes en megabytes elk in hun eigen eenheid', () {
      expect(AssetUsageDialog.formatSize(512), '512 B');
      expect(AssetUsageDialog.formatSize(1024), '1 kB');
      expect(AssetUsageDialog.formatSize(1536), '2 kB');
      expect(AssetUsageDialog.formatSize(1024 * 1024), '1.0 MB');
      expect(
        AssetUsageDialog.formatSize(3 * 1024 * 1024 + 512 * 1024),
        '3.5 MB',
      );
    });
  });
}
