// De inzending opslaan als pakket vanaf de invulpagina (FORM_INTAKE.md §5.2, §8):
// wanneer de knop werkt, welk formulier erbij hoort, en wat de invuller te lezen
// krijgt als het niet lukt.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/forms/form_export_support.dart';
import 'package:ocideck/widgets/forms/form_fill_view.dart';
import 'package:ocideck/widgets/forms/form_image_support.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

import 'support/form_photo_fixtures.dart';

const String frontMatter = '---\ntitle: Kookboek\n---\n';

const String leeg = '''<!-- form id=kook version=2 -->
Welkom.

<!-- field id=naam type=text required max-chars=40 -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->
''';

final String gevuld = leeg.replaceFirst(
  '<!-- answer -->\n<!-- /field id=naam -->',
  '<!-- answer -->\nSari\n<!-- /field id=naam -->',
);

/// Alles wat de ondersteuning meldt, en wat de proef erin stopt.
class Spy {
  Spy({this.published, this.picked, this.saveAs = 'kook-abcdef.zip'});

  /// Wat de ondersteuning zich van het formulier herinnert.
  String? published;

  /// Wat de invuller kiest als hem om het formulier wordt gevraagd.
  String? picked;

  /// De naam waaronder het opslaan lukt; `null` is annuleren.
  String? saveAs;
  bool saveThrows = false;
  Map<String, Uint8List> files = {};

  int picks = 0;
  final List<({String name, Uint8List bytes})> saved = [];
  final List<String> remembered = [];

  FormExportSupport get support => FormExportSupport(
    frontMatter: frontMatter,
    clientVersion: '0.6.13',
    readImage: (path) async => files[path],
    pickPublished: () async {
      picks++;
      return picked;
    },
    save: (name, bytes) async {
      if (saveThrows) throw const FormatException('schijf vol');
      saved.add((name: name, bytes: bytes));
      return saveAs;
    },
    recall: (_) => published,
    remember: (_, text) {
      published = text;
      remembered.add(text);
    },
  );
}

class _Host extends StatefulWidget {
  const _Host(this.initial, {required this.spy, this.noExport = false});

  final String initial;
  final Spy spy;
  final bool noExport;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late String body = widget.initial;

  @override
  Widget build(BuildContext context) => FormFillView(
    body: body,
    onChanged: (text, _) => setState(() => body = text),
    export: widget.noExport ? null : widget.spy.support,
  );
}

Future<void> pump(
  WidgetTester tester,
  String text,
  Spy spy, {
  bool noExport = false,
}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('nl'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: _Host(text, spy: spy, noExport: noExport),
      ),
    ),
  );
  await tester.pump();
}

final Finder button = find.text('Inzending opslaan als zip…');

Future<void> press(WidgetTester tester) async {
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('zonder ondersteuning is er geen knop', (tester) async {
    await pump(tester, gevuld, Spy(), noExport: true);
    expect(button, findsNothing);
  });

  testWidgets('een leeg formulier wordt onthouden als het gepubliceerde', (
    tester,
  ) async {
    final spy = Spy();
    await pump(tester, leeg, spy);
    expect(spy.remembered, [frontMatter + leeg]);
  });

  testWidgets('een formulier waar al iets in staat wordt niet onthouden', (
    tester,
  ) async {
    final spy = Spy();
    await pump(tester, gevuld, spy);
    expect(spy.remembered, isEmpty);
  });

  testWidgets(
    'met een open fout wijst de knop de fout aan in plaats van op te slaan',
    (tester) async {
      final spy = Spy();
      await pump(tester, leeg, spy);
      expect(find.text('Dit veld is verplicht.'), findsNothing);
      await press(tester);
      expect(spy.saved, isEmpty);
      expect(spy.picks, 0);
      expect(find.textContaining('Dit veld is verplicht'), findsOneWidget);
    },
  );

  testWidgets('met iets open wordt niet eerst om het formulier gevraagd', (
    tester,
  ) async {
    // Een antwoord dat niet mag (te lang), in een document dat al is ingevuld: het
    // formulier is niet onthouden, maar er valt niets op te slaan.
    final teLang = gevuld.replaceFirst('Sari', 'S' * 41);
    final spy = Spy();
    await pump(tester, teLang, spy);
    await press(tester);
    expect(spy.picks, 0);
    expect(spy.saved, isEmpty);
  });

  testWidgets('een ingevuld formulier wordt opgeslagen als een geldig pakket', (
    tester,
  ) async {
    final spy = Spy();
    await pump(tester, leeg, spy);
    await tester.enterText(find.byType(TextField).first, 'Sari');
    await tester.pump();
    await press(tester);
    expect(spy.picks, 0, reason: 'het formulier was onthouden');
    final saved = spy.saved.single;
    expect(saved.name, matches(RegExp(r'^kook-[a-z2-7]{6}\.zip$')));
    final opened = readFormPackage(saved.bytes) as FormPackageOpened;
    expect(opened.submission, frontMatter + gevuld);
    expect(
      opened.manifest.templateSha256,
      formTemplateHash(frontMatter + leeg),
    );
    expect(opened.manifest.clientVersion, '0.6.13');
    expect(
      find.text('Inzending opgeslagen als kook-abcdef.zip.'),
      findsOneWidget,
    );
  });

  testWidgets('zonder onthouden formulier vraagt de pagina om het bestand', (
    tester,
  ) async {
    final spy = Spy(picked: frontMatter + leeg);
    await pump(tester, gevuld, spy);
    await press(tester);
    expect(spy.picks, 1);
    expect(spy.saved, hasLength(1));
    expect(spy.remembered, [
      frontMatter + leeg,
    ], reason: 'de volgende keer niet meer vragen');
  });

  testWidgets(
    'wie het bestand niet kiest, slaat niets op en krijgt geen melding',
    (tester) async {
      final spy = Spy();
      await pump(tester, gevuld, spy);
      await press(tester);
      expect(spy.picks, 1);
      expect(spy.saved, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'een ander formulier dan waar de antwoorden bij horen wordt gemeld',
    (tester) async {
      final spy = Spy(
        picked: frontMatter + leeg.replaceFirst('Welkom.', 'Hallo.'),
      );
      await pump(tester, gevuld, spy);
      await press(tester);
      expect(spy.saved, isEmpty);
      expect(spy.remembered, isEmpty);
      expect(
        find.text(
          'Dit is niet het formulier waar je antwoorden bij horen. Kies het bestand dat je van de organisator kreeg.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'een onthouden formulier dat niet meer klopt wordt opnieuw gevraagd',
    (tester) async {
      final spy = Spy(
        published: frontMatter + leeg.replaceFirst('Welkom.', 'Hallo.'),
        picked: frontMatter + leeg,
      );
      await pump(tester, gevuld, spy);
      await press(tester);
      expect(spy.picks, 1);
      expect(spy.saved, hasLength(1));
    },
  );

  testWidgets('annuleren in het opslagvenster is stil', (tester) async {
    final spy = Spy(published: frontMatter + leeg, saveAs: null);
    await pump(tester, gevuld, spy);
    await press(tester);
    expect(spy.saved, hasLength(1));
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('een opslag die mislukt wordt gemeld, niet verzwegen', (
    tester,
  ) async {
    final spy = Spy(published: frontMatter + leeg)..saveThrows = true;
    await pump(tester, gevuld, spy);
    await press(tester);
    expect(
      find.text('De inzending kon niet worden opgeslagen.'),
      findsOneWidget,
    );
    expect(find.textContaining('Inzending opgeslagen als'), findsNothing);
    expect(button, findsOneWidget, reason: 'opnieuw proberen kan');
  });

  testWidgets('terwijl het opslaan loopt is de knop uit, en daarna weer aan', (
    tester,
  ) async {
    final release = Completer<String?>();
    final spy = Spy(published: frontMatter + leeg);
    final support = FormExportSupport(
      frontMatter: frontMatter,
      readImage: (_) async => null,
      pickPublished: () async => null,
      save: (name, bytes) {
        spy.saved.add((name: name, bytes: bytes));
        return release.future;
      },
      recall: (_) => spy.published,
      remember: (_, text) => spy.published = text,
    );
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('nl'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FormFillView(
            body: gevuld,
            onChanged: (_, _) {},
            export: support,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    await tester.pump();
    expect(spy.saved, hasLength(1));
    final busy = tester.widget<ButtonStyleButton>(
      find.ancestor(of: button, matching: find.bySubtype<ButtonStyleButton>()),
    );
    expect(busy.onPressed, isNull);
    release.complete('kook.zip');
    await tester.pumpAndSettle();
    final idle = tester.widget<ButtonStyleButton>(
      find.ancestor(of: button, matching: find.bySubtype<ButtonStyleButton>()),
    );
    expect(idle.onPressed, isNotNull);
  });

  testWidgets('met iets open gaat de pagina terug naar de lijst bovenaan', (
    tester,
  ) async {
    final many = StringBuffer('<!-- form id=kook version=2 -->\n');
    for (var i = 0; i < 12; i++) {
      many.write(
        '<!-- field id=v$i type=text required -->\n**Vraag $i**\n<!-- answer -->\n<!-- /field id=v$i -->\n',
      );
    }
    await pump(tester, many.toString(), Spy());
    tester.view.physicalSize = const Size(900, 500);
    await tester.pumpAndSettle();
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(scrollable.position.pixels, greaterThan(100));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, 0);
  });

  group('met foto’s', () {
    const metFoto = '''<!-- form id=kook version=2 -->
<!-- field id=foto type=image count=1..3 -->
**Foto's**
<!-- answer -->
![](images/foto-1.jpg)
<!-- /field id=foto -->
''';

    Future<void> pumpPhotos(
      WidgetTester tester,
      Spy spy, {
      String body = metFoto,
    }) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('nl'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: FormFillView(
              body: body,
              onChanged: (_, _) {},
              export: spy.support,
              images: FormImageSupport(
                add: (_, _) async => null,
                probe: (paths) async => {
                  for (final path in paths)
                    path: const FormImageFact(
                      displayedWidth: 3000,
                      bytes: 1000,
                      format: 'jpg',
                    ),
                },
                preview: (_) => null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('een foto die er niet meer is, wordt bij naam genoemd', (
      tester,
    ) async {
      final spy = Spy(published: frontMatter + metFoto);
      await pumpPhotos(tester, spy);
      await press(tester);
      expect(spy.saved, isEmpty);
      expect(
        find.text(
          'Een foto kon niet worden gelezen: images/foto-1.jpg. Voeg hem opnieuw toe.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('te veel foto’s voor een pakket worden gemeld', (tester) async {
      final paths = [for (var i = 1; i <= 63; i++) 'images/foto-$i.jpg'];
      final many =
          '''<!-- form id=kook version=2 -->
<!-- field id=foto type=image count=1..70 -->
**Foto's**
<!-- answer -->
${paths.map((path) => '![]($path)').join('\n')}
<!-- /field id=foto -->
''';
      final photo = jpegPhoto();
      final spy = Spy(published: frontMatter + many)
        ..files = {for (final path in paths) path: photo};
      await pumpPhotos(tester, spy, body: many);
      await press(tester);
      expect(spy.saved, isEmpty);
      expect(
        find.text(
          'De inzending past niet in een pakket: te veel foto’s, of een foto die te groot is.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('een foto gaat gezuiverd mee in het pakket', (tester) async {
      final onDisk = jpegPhoto(gps: true);
      final spy = Spy(published: frontMatter + metFoto)
        ..files = {'images/foto-1.jpg': onDisk};
      await pumpPhotos(tester, spy);
      await press(tester);
      final opened =
          readFormPackage(spy.saved.single.bytes) as FormPackageOpened;
      expect(opened.images.keys, ['images/foto-1.jpg']);
      expect(
        cleanImage(opened.images['images/foto-1.jpg']!)!.removed.gps,
        isFalse,
      );
    });
  });
}
