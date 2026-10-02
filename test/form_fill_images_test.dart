// Foto's op de invulpagina: toevoegen (zuiveren en melden), de feiten die de
// validator nodig heeft, en wat er staat als er niets te kiezen valt.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/form/form_image_service.dart';
import 'package:ocideck/widgets/forms/form_fill_view.dart';
import 'package:ocideck/widgets/forms/form_image_support.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

const String formulier = '''<!-- form id=f version=1 -->
<!-- field id=foto type=image count=1..3 min-width=2000 alt credit -->
**Foto's**
<!-- answer -->
<!-- /field id=foto -->
''';

const String metFoto = '''<!-- form id=f version=1 -->
<!-- field id=foto type=image count=1..3 min-width=2000 alt credit -->
**Foto's**
<!-- answer -->
![](images/foto-1.jpg)
<!-- /field id=foto -->
''';

FormImageStored stored(String path, {bool gps = false, int width = 3000}) =>
    FormImageStored(
      path,
      FormImageIntake(
        FormImageReport(
          kind: FormImageKind.jpeg,
          bytes: Uint8List(0),
          width: width,
          height: 2000,
          removed: FormImageRemoved(gps: gps, exif: gps),
        ),
        FormImageFact(displayedWidth: width, bytes: 1000, format: 'jpg'),
      ),
    );

class _Host extends StatefulWidget {
  const _Host(this.initial, {super.key, this.images});

  final String initial;
  final FormImageSupport? images;

  @override
  State<_Host> createState() => HostState();
}

class HostState extends State<_Host> {
  late String body = widget.initial;

  void replace(String text) => setState(() => body = text);

  @override
  Widget build(BuildContext context) => FormFillView(
    body: body,
    onChanged: (text, _) => setState(() => body = text),
    images: widget.images,
  );
}

Future<GlobalKey<HostState>> pump(
  WidgetTester tester,
  String text, {
  FormImageSupport? images,
}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final key = GlobalKey<HostState>();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('nl'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: _Host(text, key: key, images: images),
      ),
    ),
  );
  await tester.pump();
  return key;
}

void main() {
  testWidgets('zonder ondersteuning staat er waarom foto\'s niet kunnen', (
    tester,
  ) async {
    await pump(tester, formulier);
    expect(
      find.text('Sla het document eerst op om foto’s toe te voegen.'),
      findsOneWidget,
    );
    expect(find.text('Foto toevoegen'), findsNothing);
  });

  testWidgets('een toegevoegde foto komt in het antwoord, gezuiverd gemeld', (
    tester,
  ) async {
    final calls = <(String, Set<String>)>[];
    final host = await pump(
      tester,
      formulier,
      images: FormImageSupport(
        add: (fieldId, taken) async {
          calls.add((fieldId, taken));
          return FormImageBatch([stored('images/foto-1.jpg', gps: true)], []);
        },
        probe: (paths) async => {},
        preview: (_) => null,
      ),
    );
    await tester.tap(find.text('Foto toevoegen'));
    await tester.pumpAndSettle();
    expect(calls.single.$1, 'foto');
    expect(calls.single.$2, isEmpty);
    expect(host.currentState!.body, contains('![](images/foto-1.jpg)'));
    expect(
      find.text('Locatiegegevens zijn uit deze foto verwijderd.'),
      findsOneWidget,
    );
    expect(find.text('images/foto-1.jpg'), findsOneWidget);
  });

  testWidgets('een foto zonder positie krijgt geen melding over locatie', (
    tester,
  ) async {
    await pump(
      tester,
      formulier,
      images: FormImageSupport(
        add: (_, _) async => FormImageBatch([stored('images/foto-1.jpg')], []),
        probe: (_) async => {},
        preview: (_) => null,
      ),
    );
    await tester.tap(find.text('Foto toevoegen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Locatiegegevens'), findsNothing);
  });

  testWidgets('de feiten van een toegevoegde foto gaan naar de validator', (
    tester,
  ) async {
    await pump(
      tester,
      formulier,
      images: FormImageSupport(
        // 1600 breed bij een eis van 2000: een waarschuwing, geen "niet gecontroleerd".
        add: (_, _) async =>
            FormImageBatch([stored('images/foto-1.jpg', width: 1600)], []),
        probe: (_) async => {},
        preview: (_) => null,
      ),
    );
    await tester.tap(find.text('Foto toevoegen'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Deze foto is 1600 pixels breed'),
      findsOneWidget,
    );
    expect(find.textContaining('nog niet gecontroleerd'), findsNothing);
  });

  testWidgets(
    'wat de controle niet door kwam wordt gemeld, de rest gaat erin',
    (tester) async {
      final host = await pump(
        tester,
        formulier,
        images: FormImageSupport(
          add: (_, _) async => FormImageBatch(
            [stored('images/foto-1.jpg')],
            [FormImageRefusal.notAPhoto],
          ),
          probe: (_) async => {},
          preview: (_) => null,
        ),
      );
      await tester.tap(find.text('Foto toevoegen'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.textContaining('Deze foto kon niet worden toegevoegd'),
        findsOneWidget,
      );
      expect(host.currentState!.body, contains('images/foto-1.jpg'));
    },
  );

  testWidgets('annuleren verandert niets', (tester) async {
    final host = await pump(
      tester,
      formulier,
      images: FormImageSupport(
        add: (_, _) async => null,
        probe: (_) async => {},
        preview: (_) => null,
      ),
    );
    await tester.tap(find.text('Foto toevoegen'));
    await tester.pumpAndSettle();
    expect(host.currentState!.body, formulier);
  });

  testWidgets('foto\'s die al in het document staan worden gemeten, één keer', (
    tester,
  ) async {
    final asked = <Set<String>>[];
    await pump(
      tester,
      metFoto,
      images: FormImageSupport(
        add: (_, _) async => null,
        probe: (paths) async {
          asked.add({...paths});
          return {
            'images/foto-1.jpg': const FormImageFact(
              displayedWidth: 1200,
              bytes: 5,
              format: 'jpg',
            ),
          };
        },
        preview: (_) => null,
      ),
    );
    await tester.pumpAndSettle();
    expect(asked, [
      {'images/foto-1.jpg'},
    ]);
    // De meting is binnen: een waarschuwing over de breedte in plaats van "niet gecontroleerd".
    expect(
      find.textContaining('Deze foto is 1200 pixels breed'),
      findsOneWidget,
    );
    // Verder typen meet niet opnieuw.
    await tester.enterText(find.byType(TextField).first, 'een beschrijving');
    await tester.pumpAndSettle();
    expect(asked, hasLength(1));
  });

  testWidgets(
    'een foto die er door ongedaan maken weer bijkomt wordt gemeten',
    (tester) async {
      final asked = <Set<String>>[];
      final host = await pump(
        tester,
        formulier,
        images: FormImageSupport(
          add: (_, _) async => null,
          probe: (paths) async {
            asked.add({...paths});
            return {};
          },
          preview: (_) => null,
        ),
      );
      await tester.pumpAndSettle();
      expect(asked, isEmpty, reason: 'er staat nog geen foto in');
      host.currentState!.replace(metFoto);
      await tester.pumpAndSettle();
      expect(asked, [
        {'images/foto-1.jpg'},
      ]);
    },
  );

  testWidgets(
    'een foto waarvan de feiten al bekend zijn wordt niet nog eens gemeten',
    (tester) async {
      var asked = 0;
      final host = await pump(
        tester,
        formulier,
        images: FormImageSupport(
          add: (_, _) async =>
              FormImageBatch([stored('images/foto-1.jpg')], []),
          probe: (paths) async {
            asked++;
            return {};
          },
          preview: (_) => null,
        ),
      );
      await tester.tap(find.text('Foto toevoegen'));
      await tester.pumpAndSettle();
      // Een wijziging van buitenaf (ongedaan maken en weer opnieuw) laadt het
      // formulier opnieuw; de foto is bij het toevoegen al gemeten.
      host.currentState!.replace('$metFoto\nEen slotopmerking.\n');
      await tester.pumpAndSettle();
      expect(asked, 0);
    },
  );

  testWidgets(
    'een foto die niet te meten valt wordt niet bij elke toets opnieuw geprobeerd',
    (tester) async {
      var calls = 0;
      await pump(
        tester,
        metFoto,
        images: FormImageSupport(
          add: (_, _) async => null,
          probe: (paths) async {
            calls++;
            return {};
          },
          preview: (_) => null,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'a');
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'ab');
      await tester.pumpAndSettle();
      expect(calls, 1);
    },
  );

  testWidgets('beschrijving en maker van een foto gaan in het document', (
    tester,
  ) async {
    final host = await pump(
      tester,
      metFoto,
      images: FormImageSupport(
        add: (_, _) async => null,
        probe: (_) async => {},
        preview: (_) => null,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'twee handen');
    await tester.enterText(find.byType(TextField).at(1), 'Sari');
    await tester.pump();
    expect(
      host.currentState!.body,
      contains('![twee handen](images/foto-1.jpg "Sari")'),
    );
  });

  testWidgets('een foto weghalen haalt hem uit het antwoord, niet van schijf', (
    tester,
  ) async {
    final host = await pump(tester, metFoto);
    await tester.tap(find.byTooltip('Foto 1 verwijderen'));
    await tester.pump();
    expect(host.currentState!.body, isNot(contains('images/foto-1.jpg')));
  });
}
