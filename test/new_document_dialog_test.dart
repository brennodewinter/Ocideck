import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/library_folder.dart';
import 'package:ocideck/widgets/dialogs/new_document_dialog.dart';

/// De aanmaakdialoog voor een nieuw document (#2177): naam + mapkeuze, het
/// volledige doelpad als live preview, "Nog niet opslaan" als klad-optie, en
/// de naamconflict-waarschuwing.
Widget _host(void Function(BuildContext context) onPressed) {
  AppLocalizations.setActiveLanguageCode('nl');
  return MaterialApp(
    localizationsDelegates: const <LocalizationsDelegate<Object?>>[
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    home: Scaffold(
      body: Builder(
        builder: (BuildContext context) => ElevatedButton(
          onPressed: () => onPressed(context),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('naam en gekozen bibliotheek leveren het volledige pad', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    NewDocumentChoice? result;
    var popped = false;
    await tester.pumpWidget(
      _host((BuildContext context) async {
        result = await NewDocumentDialog.show(
          context,
          libraries: const [
            LibraryFolder(name: 'Privé', path: '/home/prive'),
            LibraryFolder(name: 'Werk', path: '/home/werk'),
          ],
        );
        popped = true;
      }),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(NewDocumentDialog), findsOneWidget);
    expect(find.text('Privé'), findsOneWidget);
    expect(find.text('Werk'), findsOneWidget);

    // De preview volgt de getypte naam: spaties worden underscores, net als
    // de voorgestelde bestandsnaam van een presentatie.
    await tester.enterText(find.byType(TextFormField), 'mijn notities');
    await tester.pump();
    expect(
      find.textContaining(p.join('/home/prive', 'mijn_notities.md')),
      findsOneWidget,
    );

    // De tweede bibliotheek wint; de preview verspringt mee.
    await tester.tap(find.text('Werk'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(p.join('/home/werk', 'mijn_notities.md')),
      findsOneWidget,
    );

    await tester.tap(find.text('Aanmaken'));
    await tester.pumpAndSettle();
    expect(popped, isTrue);
    expect(result?.path, p.join('/home/werk', 'mijn_notities.md'));
  });

  testWidgets('een meegetypte .md wordt niet verdubbeld', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    NewDocumentChoice? result;
    await tester.pumpWidget(
      _host((BuildContext context) async {
        result = await NewDocumentDialog.show(
          context,
          libraries: const [LibraryFolder(name: 'Werk', path: '/home/werk')],
        );
      }),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'rapport.md');
    await tester.tap(find.text('Aanmaken'));
    await tester.pumpAndSettle();
    expect(result?.path, p.join('/home/werk', 'rapport.md'));
  });

  testWidgets("'Nog niet opslaan' geeft een klad zonder pad", (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    NewDocumentChoice? result;
    var popped = false;
    await tester.pumpWidget(
      _host((BuildContext context) async {
        result = await NewDocumentDialog.show(
          context,
          libraries: const [LibraryFolder(name: 'Werk', path: '/home/werk')],
        );
        popped = true;
      }),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nog niet opslaan'));
    await tester.pumpAndSettle();

    // Geen naam nodig voor een klad — Aanmaken zonder naam werkt gewoon.
    await tester.tap(find.text('Aanmaken'));
    await tester.pumpAndSettle();
    expect(popped, isTrue);
    expect(result, isNotNull);
    expect(result!.path, isNull);
  });

  testWidgets('zonder bibliotheek staat "Nog niet opslaan" voorgekozen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    NewDocumentChoice? result;
    await tester.pumpWidget(
      _host((BuildContext context) async {
        result = await NewDocumentDialog.show(context, libraries: const []);
      }),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // Geen map beschikbaar: de preview zegt wat er gebeurt.
    expect(find.textContaining('blijft een klad'), findsOneWidget);
    await tester.tap(find.text('Aanmaken'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.path, isNull);
  });

  testWidgets('annuleren geeft null terug', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    NewDocumentChoice? result;
    var popped = false;
    await tester.pumpWidget(
      _host((BuildContext context) async {
        result = await NewDocumentDialog.show(
          context,
          libraries: const [LibraryFolder(name: 'Werk', path: '/home/werk')],
        );
        popped = true;
      }),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();
    expect(popped, isTrue);
    expect(result, isNull);
  });

  testWidgets('lege naam valideert en sluit de dialoog niet', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var popped = false;
    await tester.pumpWidget(
      _host((BuildContext context) async {
        await NewDocumentDialog.show(
          context,
          libraries: const [LibraryFolder(name: 'Werk', path: '/home/werk')],
        );
        popped = true;
      }),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aanmaken'));
    await tester.pumpAndSettle();
    expect(find.text('Vul een naam in'), findsOneWidget);
    expect(find.byType(NewDocumentDialog), findsOneWidget);
    expect(popped, isFalse);
  });

  testWidgets('naamconflict blokkeert en verdwijnt bij een vrije naam', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dir = Directory.systemTemp.createTempSync('newdoc_dialog');
    addTearDown(() => dir.deleteSync(recursive: true));
    File(p.join(dir.path, 'bestaand.md')).writeAsStringSync('houd mij');

    NewDocumentChoice? result;
    var popped = false;
    await tester.pumpWidget(
      _host((BuildContext context) async {
        result = await NewDocumentDialog.show(
          context,
          libraries: [LibraryFolder(name: 'Map', path: dir.path)],
        );
        popped = true;
      }),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'bestaand');
    await tester.tap(find.text('Aanmaken'));
    await tester.pumpAndSettle();
    expect(
      find.text('Er bestaat al een bestand met deze naam in deze map.'),
      findsOneWidget,
    );
    expect(popped, isFalse);
    // En het bestaande bestand is ongemoeid.
    expect(
      File(p.join(dir.path, 'bestaand.md')).readAsStringSync(),
      'houd mij',
    );

    // Een vrije naam gaat wél door.
    await tester.enterText(find.byType(TextFormField), 'nieuw');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aanmaken'));
    await tester.pumpAndSettle();
    expect(popped, isTrue);
    expect(result?.path, p.join(dir.path, 'nieuw.md'));
  });
}
