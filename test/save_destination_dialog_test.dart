import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/widgets/dialogs/save_destination_dialog.dart';

Widget _host(void Function(BuildContext context) onPressed) {
  AppLocalizations.setActiveLanguageCode('nl');
  return MaterialApp(
    localizationsDelegates: const <LocalizationsDelegate<Object?>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
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
  testWidgets(
    'SaveDestinationDialog previews the target and returns the chosen library',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      SaveDestinationChoice? result;
      var popped = false;
      await tester.pumpWidget(
        _host((BuildContext context) async {
          result = await SaveDestinationDialog.show(
            context,
            libraries: const [
              LibraryFolder(name: 'Privé', path: '/home/prive'),
              LibraryFolder(name: 'Werk', path: '/home/werk'),
            ],
            deckTitle: 'Kwartaal Update',
          );
          popped = true;
        }),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(SaveDestinationDialog), findsOneWidget);
      // Beide bibliotheken zijn te kiezen.
      expect(find.text('Privé'), findsOneWidget);
      expect(find.text('Werk'), findsOneWidget);
      // De samenvatting toont het pad van de eerste bibliotheek met de
      // veilige bestandsnaam plus de images/-submap.
      expect(
        // Zoals de dialoog het toont: p.join(map, bestandsnaam), dus op Windows
        // met de OS-scheiding tussen map en bestand.
        find.textContaining(p.join('/home/prive', 'Kwartaal_Update.md')),
        findsOneWidget,
      );
      expect(find.textContaining('/home/prive/images'), findsOneWidget);

      // Kies de tweede bibliotheek; de samenvatting verspringt mee.
      await tester.tap(find.text('Werk'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('/home/werk/Kwartaal_Update.md'),
        findsOneWidget,
      );

      // Bevestigen geeft de gekozen map terug als startmap.
      await tester.tap(find.text('Kies bestandsnaam…'));
      await tester.pumpAndSettle();
      expect(popped, isTrue);
      expect(result?.directory, '/home/werk');
    },
  );

  testWidgets('SaveDestinationDialog cancel returns null', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    SaveDestinationChoice? result;
    var popped = false;
    await tester.pumpWidget(
      _host((BuildContext context) async {
        result = await SaveDestinationDialog.show(
          context,
          libraries: const [LibraryFolder(name: 'Werk', path: '/home/werk')],
          deckTitle: 'Demo',
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
}
