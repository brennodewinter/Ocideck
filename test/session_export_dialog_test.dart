/// Widget-test voor de afloop-dialoog van session-data-edits (#1235).
///
/// Dekt de zichtbare logica in `session_export.dart`: de dialoog toont alleen
/// bij niet-lege sessionOriginals, de titel en knoppen staan er, en "in deck
/// behouden" sluit zonder export. De revert-logica zelf staat in
/// `session_export_revert_test.dart`.
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart' show ThemeProfile;
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ocideck/services/download_delivery.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/widgets/presentation/session_export.dart';

DeckNotifier _notifier() {
  final md = MarkdownService();
  final file = FileService(md, ImageService(), () => const ThemeProfile());
  return DeckNotifier(md, file);
}

Slide _tableSlide(String id, String title) {
  return Slide(
    id: id,
    type: SlideType.table,
    title: title,
    tableEditable: true,
    tableRows: const [
      ['Kop', 'Waarde'],
      ['x', '1'],
    ],
  );
}

/// Zet een deck met twee bewerkte dia's klaar en levert de sessie-originelen.
({DeckNotifier notifier, Map<String, Slide> originals}) _editedSession() {
  final notifier = _notifier();
  notifier.newDeck(
    'T',
    slides: [_tableSlide('a', 'Tabel A'), _tableSlide('b', 'Tabel B')],
  );
  final originals = <String, Slide>{};
  final deck = notifier.currentState.deck!;
  for (var i = 0; i < 2; i++) {
    originals.putIfAbsent(deck.slides[i].id, () => deck.slides[i]);
    notifier.updateSlide(
      i,
      deck.slides[i].copyWith(
        tableRows: const [
          ['Kop', 'Waarde'],
          ['x', '99'],
        ],
      ),
    );
  }
  return (notifier: notifier, originals: originals);
}

Widget _harness(DeckNotifier notifier, Map<String, Slide> originals) =>
    ProviderScope(
      overrides: [deckProvider.overrideWith((ref) => notifier)],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => offerSessionExport(
                context,
                ref,
                deckNotifier: ref.read(deckProvider.notifier),
                sessionOriginals: originals,
              ),
              child: const Text('start'),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('lege sessionOriginals → geen dialoog (vroegtijdig return)', (
    tester,
  ) async {
    final notifier = _notifier();
    notifier.newDeck('T', slides: [_tableSlide('a', 'A')]);

    var offered = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [deckProvider.overrideWith((ref) => notifier)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () async {
                  offered = true;
                  await offerSessionExport(
                    context,
                    ref,
                    deckNotifier: ref.read(deckProvider.notifier),
                    sessionOriginals: const {},
                  );
                },
                child: const Text('start'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pump();
    expect(offered, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('niet-lege sessionOriginals → dialoog toont', (tester) async {
    final notifier = _notifier();
    final a = _tableSlide('a', 'Tabel A');
    notifier.newDeck('T', slides: [a]);

    // Simuleer een session-edit: vang origineel, schrijf door.
    final originals = <String, Slide>{};
    final deck = notifier.currentState.deck!;
    originals.putIfAbsent('a', () => deck.slides[0]);
    notifier.updateSlide(
      0,
      a.copyWith(
        tableRows: const [
          ['Kop', 'Waarde'],
          ['x', '99'],
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [deckProvider.overrideWith((ref) => notifier)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => offerSessionExport(
                  context,
                  ref,
                  deckNotifier: ref.read(deckProvider.notifier),
                  sessionOriginals: originals,
                ),
                child: const Text('start'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pump();
    await tester.pump();

    // Dialoog toont met titel, de dia-titel (in de content-string), en beide
    // knoppen. De titel staat in de content-buffer als deel van een langere
    // tekst, dus find.textContaining i.p.v. find.text.
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Sessie-wijzigingen bewaren?'), findsOneWidget);
    expect(find.textContaining('Tabel A'), findsOneWidget);
    expect(find.text('In deck behouden'), findsOneWidget);
    expect(find.text('Downloaden als losse bestanden'), findsOneWidget);
  });

  testWidgets('"In deck behouden" sluit zonder export', (tester) async {
    final notifier = _notifier();
    final a = _tableSlide('a', 'Tabel A');
    notifier.newDeck('T', slides: [a]);

    final originals = <String, Slide>{};
    final deck = notifier.currentState.deck!;
    originals.putIfAbsent('a', () => deck.slides[0]);
    notifier.updateSlide(
      0,
      a.copyWith(
        tableRows: const [
          ['Kop', 'Waarde'],
          ['x', '99'],
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [deckProvider.overrideWith((ref) => notifier)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => offerSessionExport(
                  context,
                  ref,
                  deckNotifier: ref.read(deckProvider.notifier),
                  sessionOriginals: originals,
                ),
                child: const Text('start'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pump();
    await tester.pump();

    // "In deck behouden" sluit de dialoog; het deck behoudt de edit.
    await tester.tap(find.text('In deck behouden'));
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    final slides = notifier.currentState.deck!.slides;
    expect(slides[0].tableRows[1][1], '99');
  });

  group('web: de hele sessie in één download (#1902)', () {
    final calls = <({String name, Uint8List bytes})>[];
    var accept = true;

    setUp(() {
      calls.clear();
      accept = true;
      debugDeliversByDownload = true;
      debugDownloadSink = (name, bytes, mime) {
        calls.add((name: name, bytes: bytes));
        return accept;
      };
    });

    tearDown(() {
      debugDeliversByDownload = null;
      debugDownloadSink = null;
    });

    testWidgets('twee dia’s vertrekken als één zip, en het deck wordt schoon', (
      tester,
    ) async {
      final session = _editedSession();
      await tester.pumpWidget(_harness(session.notifier, session.originals));
      await tester.tap(find.text('start'));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Downloaden als losse bestanden'));
      await tester.pump();
      await tester.pump();

      // Eén download, niet twee: de tweede zou de browser tegenhouden en dan
      // hield de spreker één dia over zonder dat iemand het merkte.
      expect(calls, hasLength(1));
      expect(calls.single.name, endsWith('-sessie.zip'));
      final zip = ZipDecoder().decodeBytes(calls.single.bytes);
      // sanitizeFilename maakt van de spatie in de dia-titel een underscore.
      expect(zip.files.map((f) => f.name), [
        '01 - Tabel_A.md',
        '02 - Tabel_B.md',
      ]);

      // Gelukt, dus het deck gaat schoon terug naar zijn oorspronkelijke dia's.
      final slides = session.notifier.currentState.deck!.slides;
      expect(slides.map((s) => s.tableRows[1][1]), ['1', '1']);
    });

    testWidgets('een geweigerde download laat het deck staan én zegt het', (
      tester,
    ) async {
      accept = false;
      final session = _editedSession();
      await tester.pumpWidget(_harness(session.notifier, session.originals));
      await tester.tap(find.text('start'));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Downloaden als losse bestanden'));
      await tester.pump();
      await tester.pump();

      // De bewerkingen blijven staan (het veilige uiteinde), maar stil is het
      // niet: anders sluit de spreker af in de veronderstelling dat het bewaard
      // is.
      final slides = session.notifier.currentState.deck!.slides;
      expect(slides.map((s) => s.tableRows[1][1]), ['99', '99']);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('niet opgeslagen'), findsOneWidget);
    });
  });
}
