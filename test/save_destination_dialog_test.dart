import 'package:material_ui/material_ui.dart';
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
      // Zelfde reden als hierboven: de dialoog toont `p.join(map, 'images')`,
      // dus op Windows met de OS-scheiding tussen map en submap.
      expect(
        find.textContaining(p.join('/home/prive', 'images')),
        findsOneWidget,
      );

      // Kies de tweede bibliotheek; de samenvatting verspringt mee.
      await tester.tap(find.text('Werk'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(p.join('/home/werk', 'Kwartaal_Update.md')),
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

  // #1211: lange bestandspaden waren afgekapt met "…". De dialoog is nu
  // breedte-aanpasbaar en paden breken af naar de volgende regel.
  testWidgets('resize handle widens the dialog on drag (#1211)', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _host((BuildContext context) async {
        await SaveDestinationDialog.show(
          context,
          libraries: const [LibraryFolder(name: 'Werk', path: '/home/werk')],
          deckTitle: 'Demo',
        );
      }),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // De handgreep is aanwezig en draagt een gelokaliseerd tooltip-label.
    expect(find.byTooltip('Breedte aanpassen'), findsOneWidget);

    // De content-SizedBox is degene met width >= 420 (de resize-gevoelige
    // breedte); de samenvatting staat erin als herkenningspunt.
    SizedBox contentBox() {
      final boxes = tester.widgetList<SizedBox>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(SizedBox),
        ),
      );
      return boxes.firstWhere((b) => (b.width ?? 0) >= 420);
    }

    expect(contentBox().width, 560);
    // Naar rechts slepen verbreedt (touch-slop slokt een paar px op, dus
    // relatief beweren, niet exact).
    await tester.drag(find.byIcon(Icons.drag_indicator), const Offset(80, 0));
    await tester.pump();
    final wider = contentBox().width ?? 560;
    expect(wider, greaterThan(560.0));

    // Naar links slepen vernauwt weer.
    await tester.drag(find.byIcon(Icons.drag_indicator), const Offset(-40, 0));
    await tester.pump();
    expect(contentBox().width ?? wider, lessThan(wider));
  });

  testWidgets('a long library path is shown in full, not truncated (#1211)', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final longPath = '/home/${'sub/' * 20}diep';
    await tester.pumpWidget(
      _host((BuildContext context) async {
        await SaveDestinationDialog.show(
          context,
          libraries: [LibraryFolder(name: 'Diep', path: longPath)],
          deckTitle: 'Demo',
        );
      }),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Het volledige pad staat als Text-data in de optie (softWrap i.p.v.
    // ellipsis), en de samenvatting toont het pad naar het presentatiebestand.
    expect(find.text(longPath), findsOneWidget);
    expect(find.textContaining(p.join(longPath, 'Demo.md')), findsOneWidget);
  });
}
