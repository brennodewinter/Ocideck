import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/s3/s3_service.dart';
import 'package:ocideck/services/webdav_service.dart';
import 'package:ocideck/state/s3_provider.dart';
import 'package:ocideck/state/webdav_provider.dart';
import 'package:ocideck/widgets/dialogs/s3_browser_dialog.dart';
import 'package:ocideck/widgets/dialogs/webdav_browser_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De twee bladeraars over externe opslag (WebDAV/Nextcloud en S3) zijn
/// tweelingen: ze filteren, navigeren en falen op dezelfde manier. Ze staan
/// daarom in één bestand, met dezelfde reeks beweringen voor allebei — loopt er
/// één uit de pas, dan valt dat hier op.
///
/// Wat bewezen wordt is de keuze die de gebruiker maakt, niet dat het scherm
/// tekent: welke bestanden klikbaar zijn (en welke pertinent niet), waar het
/// pad heen gaat, wat er teruggegeven wordt, en dat een fout de échte reden
/// noemt in plaats van "er ging iets mis".
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  const connectionId = 'verbinding-1';

  // ── WebDAV ────────────────────────────────────────────────────────────────

  WebdavEntry dav(String name, {bool dir = false, String? path}) =>
      WebdavEntry(name: name, relativePath: path ?? name, isCollection: dir);

  final davTree = <String, List<WebdavEntry>>{
    '': [
      dav('Rapporten', dir: true),
      dav('rapport.ocideck'),
      dav('notities.md'),
      dav('logo.png'),
      dav('offerte.pdf'),
    ],
    'Rapporten': [
      dav('2026', dir: true, path: 'Rapporten/2026'),
      dav('intern.ocideck', path: 'Rapporten/intern.ocideck'),
    ],
    'Rapporten/2026': [dav('q1.ocideck', path: 'Rapporten/2026/q1.ocideck')],
  };

  Future<WebdavEntry?> openWebdav(
    WidgetTester tester, {
    WebdavBrowseMode mode = WebdavBrowseMode.deck,
    Map<String, List<WebdavEntry>>? tree,
    Object? error,
  }) async {
    WebdavEntry? picked;
    var done = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          webdavListingProvider.overrideWith((ref, key) async {
            if (error != null) throw error;
            return (tree ?? davTree)[key.remotePath] ?? const [];
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  picked = await WebdavBrowserDialog.show(
                    context,
                    connectionId: connectionId,
                    mode: mode,
                  );
                  done = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return done ? picked : null;
  }

  // ── S3 ────────────────────────────────────────────────────────────────────

  S3Entry obj(String name, {bool dir = false, String? path}) =>
      S3Entry(name: name, relativePath: path ?? name, isCollection: dir);

  final s3Tree = <String, List<S3Entry>>{
    '': [
      obj('Rapporten', dir: true),
      obj('rapport.ocideck'),
      obj('notities.md'),
      obj('logo.png'),
      obj('offerte.pdf'),
    ],
    'Rapporten': [obj('intern.ocideck', path: 'Rapporten/intern.ocideck')],
  };

  Future<S3Entry?> openS3(
    WidgetTester tester, {
    S3BrowseMode mode = S3BrowseMode.deck,
    Map<String, List<S3Entry>>? tree,
    Object? error,
  }) async {
    S3Entry? picked;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          s3ListingProvider.overrideWith((ref, key) async {
            if (error != null) throw error;
            return (tree ?? s3Tree)[key.remotePath] ?? const [];
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  picked = await S3BrowserDialog.show(
                    context,
                    connectionId: connectionId,
                    mode: mode,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return picked;
  }

  bool tileEnabled(WidgetTester tester, String label) =>
      tester.widget<ListTile>(find.widgetWithText(ListTile, label)).onTap !=
      null;

  group('WebDAV-bladeraar', () {
    testWidgets('toont decks en mappen, en verzwijgt de rest', (tester) async {
      await openWebdav(tester);

      expect(find.text('Rapporten'), findsOneWidget);
      expect(find.text('rapport.ocideck'), findsOneWidget);
      expect(find.text('notities.md'), findsOneWidget);
      // Een PDF of plaatje kun je niet als deck openen; die horen in de
      // deck-stand niet in de lijst te staan en niet klikbaar te zijn.
      expect(find.text('offerte.pdf'), findsNothing);
      expect(find.text('logo.png'), findsNothing);
    });

    testWidgets('in de afbeeldingsstand keert die keuze precies om', (
      tester,
    ) async {
      await openWebdav(tester, mode: WebdavBrowseMode.image);

      expect(find.text('logo.png'), findsOneWidget);
      expect(find.text('Rapporten'), findsOneWidget);
      expect(find.text('rapport.ocideck'), findsNothing);
      expect(find.text('notities.md'), findsNothing);
      expect(
        find.text('Afbeelding kiezen op WebDAV'),
        findsOneWidget,
        reason: 'de titel moet zeggen wat er gekozen wordt',
      );
    });

    testWidgets('een map openen verplaatst het pad en laadt de inhoud', (
      tester,
    ) async {
      await openWebdav(tester);
      expect(find.text('/'), findsOneWidget);

      await tester.tap(find.text('Rapporten'));
      await tester.pumpAndSettle();

      expect(find.text('/Rapporten'), findsOneWidget);
      expect(find.text('intern.ocideck'), findsOneWidget);
      expect(find.text('rapport.ocideck'), findsNothing);

      // Nog een niveau dieper, zodat "omhoog" iets te kiezen heeft.
      await tester.tap(find.text('2026'));
      await tester.pumpAndSettle();
      expect(find.text('/Rapporten/2026'), findsOneWidget);
      expect(find.text('q1.ocideck'), findsOneWidget);

      // Omhoog gaat één stap terug, niet meteen naar de wortel.
      await tester.tap(find.byTooltip('Omhoog'));
      await tester.pumpAndSettle();
      expect(find.text('/Rapporten'), findsOneWidget);
      expect(find.text('intern.ocideck'), findsOneWidget);

      await tester.tap(find.byTooltip('Omhoog'));
      await tester.pumpAndSettle();
      expect(find.text('/'), findsOneWidget);
      expect(find.text('rapport.ocideck'), findsOneWidget);
    });

    testWidgets('omhoog staat uit in de wortel', (tester) async {
      await openWebdav(tester);

      final up = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.arrow_upward),
          matching: find.byType(IconButton),
        ),
      );
      expect(up.onPressed, isNull);
    });

    testWidgets('een gekozen bestand komt bij de aanroeper terug', (
      tester,
    ) async {
      WebdavEntry? picked;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            webdavListingProvider.overrideWith(
              (ref, key) async => davTree[key.remotePath] ?? const [],
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async =>
                      picked = await WebdavBrowserDialog.show(
                        context,
                        connectionId: connectionId,
                      ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('rapport.ocideck'));
      await tester.pumpAndSettle();

      expect(picked, isNotNull);
      expect(picked!.name, 'rapport.ocideck');
      expect(picked!.relativePath, 'rapport.ocideck');
    });

    testWidgets('een lege map zegt dat, in plaats van niets te tonen', (
      tester,
    ) async {
      await openWebdav(tester, tree: {'': const []});

      expect(find.text('Deze map is leeg'), findsOneWidget);
    });

    testWidgets('een fout noemt de echte reden en biedt opnieuw proberen', (
      tester,
    ) async {
      await openWebdav(tester, error: WebdavException(WebdavError.auth, 'nee'));

      // Niet platgeslagen tot "controleer je verbinding": de gebruiker moet
      // weten dát het het wachtwoord is.
      expect(
        find.textContaining('Controleer gebruikersnaam en wachtwoord'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Opnieuw proberen'),
        findsOneWidget,
      );
    });

    testWidgets('annuleren geeft niets terug', (tester) async {
      final picked = await openWebdav(tester);
      expect(picked, isNull);

      await tester.tap(find.widgetWithText(TextButton, 'Annuleren'));
      await tester.pumpAndSettle();
      expect(find.byType(WebdavBrowserDialog), findsNothing);
    });
  });

  group('S3-bladeraar', () {
    testWidgets('toont decks en prefixen, en verzwijgt de rest', (
      tester,
    ) async {
      await openS3(tester);

      expect(find.text('Rapporten'), findsOneWidget);
      expect(find.text('rapport.ocideck'), findsOneWidget);
      expect(find.text('notities.md'), findsOneWidget);
      expect(find.text('offerte.pdf'), findsNothing);
      expect(find.text('logo.png'), findsNothing);
    });

    testWidgets('in de afbeeldingsstand keert die keuze precies om', (
      tester,
    ) async {
      await openS3(tester, mode: S3BrowseMode.image);

      expect(find.text('logo.png'), findsOneWidget);
      expect(find.text('rapport.ocideck'), findsNothing);
      expect(find.text('Afbeelding kiezen in S3'), findsOneWidget);
    });

    testWidgets('een prefix gedraagt zich als een map', (tester) async {
      await openS3(tester);
      await tester.tap(find.text('Rapporten'));
      await tester.pumpAndSettle();

      expect(find.text('/Rapporten'), findsOneWidget);
      expect(find.text('intern.ocideck'), findsOneWidget);

      await tester.tap(find.byTooltip('Omhoog'));
      await tester.pumpAndSettle();
      expect(find.text('/'), findsOneWidget);
    });

    testWidgets('een gekozen object komt bij de aanroeper terug', (
      tester,
    ) async {
      S3Entry? picked;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            s3ListingProvider.overrideWith(
              (ref, key) async => s3Tree[key.remotePath] ?? const [],
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async => picked = await S3BrowserDialog.show(
                    context,
                    connectionId: connectionId,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('rapport.ocideck'));
      await tester.pumpAndSettle();

      expect(picked!.relativePath, 'rapport.ocideck');
    });

    testWidgets('een lege bucket zegt dat', (tester) async {
      await openS3(tester, tree: {'': const []});

      expect(find.text('Hier staat niets'), findsOneWidget);
    });

    testWidgets('een fout noemt de echte reden', (tester) async {
      await openS3(tester, error: S3Exception(S3Error.config, 'niets'));

      expect(
        find.textContaining('endpoint, bucket en sleutels'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Opnieuw proberen'),
        findsOneWidget,
      );
    });
  });

  group('beide bladeraars', () {
    testWidgets('in de deck-stand is elke getoonde tegel ook bedraad', (
      tester,
    ) async {
      // Een map is altijd aan te klikken (erin duiken), een bestand alleen als
      // het bij de stand past. Een tegel die wél in beeld staat maar niets doet
      // is erger dan geen tegel.
      await openWebdav(tester);

      expect(tileEnabled(tester, 'Rapporten'), isTrue);
      expect(tileEnabled(tester, 'rapport.ocideck'), isTrue);
      expect(tileEnabled(tester, 'notities.md'), isTrue);
    });

    testWidgets('in de afbeeldingsstand idem, met de andere selectie', (
      tester,
    ) async {
      await openWebdav(tester, mode: WebdavBrowseMode.image);

      expect(tileEnabled(tester, 'logo.png'), isTrue);
      expect(tileEnabled(tester, 'Rapporten'), isTrue);
    });

    testWidgets('een bestand dat niet bij de stand past wordt niet aangeboden', (
      tester,
    ) async {
      // Een deck in de afbeeldingsstand: de server mag hem best meesturen, maar
      // hij hoort niet in de lijst. Aanbieden-en-dan-niets-doen is de variant
      // waar een gebruiker op klikt en denkt dat de app hangt.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            webdavListingProvider.overrideWith(
              (ref, key) async => [dav('rapport.ocideck')],
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: WebdavBrowserDialog(
                mode: WebdavBrowseMode.image,
                connectionId: connectionId,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'rapport.ocideck'), findsNothing);
      expect(find.text('Deze map is leeg'), findsOneWidget);
    });

    testWidgets('een niet-ingestelde verbinding meldt dat, en blijft niet '
        'eeuwig laden', (tester) async {
      // Bewust zónder override: de échte provider, die zelf een
      // WebdavException/S3Exception gooit als er geen client te bouwen is.
      //
      // Riverpod 3 herhaalt een gegooide Exception uit zichzelf, en een
      // herhalende provider staat in AsyncLoading — dus dit scherm bleef op de
      // laadindicator hangen en de uitgeschreven foutmeldingen kwamen nooit in
      // beeld. Zie noAutoRetry in lib/state/provider_retry.dart.
      for (final body in const [
        WebdavBrowserDialog(
          mode: WebdavBrowseMode.deck,
          connectionId: 'onbekend',
        ),
        S3BrowserDialog(mode: S3BrowseMode.deck, connectionId: 'onbekend'),
      ]) {
        SharedPreferences.setMockInitialValues({});
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(home: Scaffold(body: body)),
          ),
        );
        // Begrensd doorpompen: de provider is asynchroon, maar mag niet
        // eindeloos laden.
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
        }

        expect(
          find.byType(CircularProgressIndicator),
          findsNothing,
          reason: '$body bleef laden',
        );
        expect(
          find.widgetWithText(OutlinedButton, 'Opnieuw proberen'),
          findsOneWidget,
          reason: '$body bood geen zichtbare herkansing',
        );
      }
    });

    testWidgets('vernieuwen laadt de lijst opnieuw op', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            webdavListingProvider.overrideWith((ref, key) async {
              calls++;
              return [dav('rapport.ocideck')];
            }),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: WebdavBrowserDialog(
                mode: WebdavBrowseMode.deck,
                connectionId: connectionId,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);

      await tester.tap(find.byTooltip('Vernieuwen'));
      await tester.pumpAndSettle();
      expect(calls, 2, reason: 'de knop moet de cache echt ongeldig maken');
    });
  });
}
