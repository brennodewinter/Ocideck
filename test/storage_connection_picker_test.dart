import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/models/s3_settings.dart';
import 'package:ocideck/models/storage_connection.dart';
import 'package:ocideck/models/webdav_settings.dart';
import 'package:ocideck/widgets/dialogs/storage_connection_picker.dart';

/// De vraag "welke verbinding?" vóór een actie die naar buiten schrijft.
///
/// De regel die dit scherm bruikbaar houdt, is dat het er meestal niet is: bij
/// één verbinding wordt die zonder omhaal gekozen. Zou de dialoog daar tóch
/// verschijnen, dan zou iedereen met één Nextcloud voortaan een extra klik
/// maken voor een keuze die er niet is. En andersom: verschijnt hij níét bij
/// twee, dan schrijft iemand naar de verkeerde klant — en dáár komt geen
/// foutmelding van.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  const webdav = WebdavConnection(
    id: 'w1',
    name: 'Klant A',
    server: WebdavServer(baseUrl: 'https://a.example', username: 'aisha'),
  );
  const s3 = S3Connection(
    id: 's1',
    name: 'Klant B',
    bucket: S3Bucket(
      endpoint: 'https://s3.example',
      region: 'eu-central-1',
      bucket: 'klant-b',
      accessKeyId: 'AKIA-wegwerp',
    ),
  );
  const git = GitConnection(
    id: 'g1',
    name: '',
    repo: GitRepoConfig(
      baseUrl: 'https://git.example',
      owner: 'ocideck',
      repo: 'decks',
    ),
  );
  const local = LocalConnection(id: 'l1', name: 'Schijf', path: '/decks');

  /// Opent de kiezer en geeft terug wat hij oplevert, plus of er een dialoog
  /// in beeld is gekomen.
  Future<({StorageConnection? picked, bool shown})> pick(
    WidgetTester tester,
    List<StorageConnection> connections, {
    Future<void> Function(WidgetTester)? interact,
  }) async {
    StorageConnection? picked;
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                picked = await StorageConnectionPicker.show(
                  context,
                  connections,
                );
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final shown = find.byType(StorageConnectionPicker).evaluate().isNotEmpty;
    if (interact != null) {
      await interact(tester);
      await tester.pumpAndSettle();
    }
    expect(done, isTrue, reason: 'de keuze hoorde afgerond te zijn');
    return (picked: picked, shown: shown);
  }

  testWidgets('geen verbindingen: geen dialoog, geen keuze', (tester) async {
    final result = await pick(tester, const []);

    expect(result.shown, isFalse);
    expect(result.picked, isNull);
  });

  testWidgets('één verbinding wordt zonder vraag gekozen', (tester) async {
    final result = await pick(tester, const [webdav]);

    expect(result.shown, isFalse, reason: 'een keuze uit één is geen keuze');
    expect(result.picked, webdav);
  });

  testWidgets('twee verbindingen leveren wél de vraag op', (tester) async {
    final result = await pick(tester, const [
      webdav,
      s3,
    ], interact: (tester) async => tester.tap(find.text('Klant B')));

    expect(result.shown, isTrue);
    expect(result.picked, s3);
  });

  testWidgets('annuleren kiest niets', (tester) async {
    final result = await pick(
      tester,
      const [webdav, s3],
      interact: (tester) async =>
          tester.tap(find.widgetWithText(TextButton, 'Annuleren')),
    );

    expect(result.picked, isNull);
  });

  testWidgets('elke soort krijgt zijn eigen pictogram', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StorageConnectionPicker(connections: [local, webdav, s3, git]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Vier soorten, vier verschillende iconen: hetzelfde icoon voor twee
    // soorten maakt de lijst juist onleesbaar waar hij nodig is.
    for (final icon in const [
      Icons.folder_outlined,
      Icons.cloud_outlined,
      Icons.inventory_2_outlined,
      Icons.account_tree_outlined,
    ]) {
      expect(find.byIcon(icon), findsOneWidget, reason: '$icon');
    }
  });

  testWidgets('een naamloze verbinding toont waar hij heen wijst', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StorageConnectionPicker(connections: [git, s3])),
      ),
    );
    await tester.pumpAndSettle();

    // Zonder naam is de slug het enige waaraan je hem herkent; een lege regel
    // zou de keuze onmogelijk maken.
    expect(find.text(git.repo.slug), findsWidgets);
    // Met naam staat het adres eronder, zodat twee gelijknamige verbindingen
    // nog te onderscheiden zijn.
    expect(find.text('Klant B'), findsOneWidget);
    expect(find.text(s3.fallbackLabel), findsOneWidget);
  });
}
