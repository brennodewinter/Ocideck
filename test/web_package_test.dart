import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/learning_session.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/services/user_notes_codec.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bytes met een geldige PNG-kop — de import valideert op magic bytes, niet
/// op decodeerbaarheid.
final _pngBytes = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  1, 2, 3, 4, 5, 6, 7, 8,
]);

Uint8List _zipOf(Map<String, List<int>> members) {
  final archive = Archive();
  members.forEach(
    (name, bytes) => archive.add(ArchiveFile(name, bytes.length, bytes)),
  );
  return ZipEncoder().encodeBytes(archive);
}

ProviderContainer _container() {
  final tempDir = Directory.systemTemp.createTempSync('ocideck_webpkg_test_');
  addTearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });
  final container = ProviderContainer(
    overrides: [
      recoveryServiceProvider.overrideWithValue(
        RecoveryService(baseDir: tempDir),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });
  tearDown(WebAssetStore.clear);

  group('TabsNotifier._openPackageFromBytes (via openDeckFromBytes)', () {
    test('bindt een leerpakket atomair aan het ontvangende tabblad', () async {
      final container = _container();
      final markdown = container
          .read(markdownServiceProvider)
          .generateDeck(
            Deck(
              title: 'Les',
              slides: [
                Slide.create(
                  SlideType.title,
                ).copyWith(title: 'Les', anchor: 'les'),
              ],
            ),
          );
      final zip = _zipOf({'les.md': utf8.encode(markdown)});
      final session = LearningSessionRef(
        serverUrl: 'https://leren.example',
        accountId: 'account',
        organizationId: 'org',
        enrollmentId: 'enrollment',
        courseVersionId: 'version',
        lessonId: 'lesson',
        packageHash: 'sha256:test',
        startedAt: DateTime.utc(2026, 9, 6),
      );

      final result = await container
          .read(tabsProvider.notifier)
          .openLearningPackage(zip, 'les.ocideck', session);

      expect(result, OpenResult.opened);
      expect(
        container.read(tabsProvider).current?.learningSession,
        same(session),
      );
      expect(
        container
            .read(tabsProvider)
            .current
            ?.deckNotifier
            .currentState
            .filePath,
        isNull,
      );
    });

    test('past de bij publicatie bevroren OciServe-huisstijl toe', () async {
      final container = _container();
      final markdown = container
          .read(markdownServiceProvider)
          .generateDeck(
            Deck(
              title: 'Les',
              slides: [
                Slide.create(
                  SlideType.title,
                ).copyWith(title: 'Les', anchor: 'les'),
              ],
            ),
          );
      final zip = _zipOf({
        'deck.md': utf8.encode(markdown),
        'theme.json': utf8.encode(
          jsonEncode({
            'name': 'Bevroren',
            'revision': 3,
            'definition': {'accentColor': '#123456'},
          }),
        ),
      });
      final session = LearningSessionRef(
        serverUrl: 'https://leren.example',
        accountId: 'account',
        organizationId: 'org',
        enrollmentId: 'enrollment',
        courseVersionId: 'version',
        lessonId: 'lesson',
        packageHash: 'sha256:test',
        startedAt: DateTime.utc(2026, 9, 7),
      );

      expect(
        await container
            .read(tabsProvider.notifier)
            .openLearningPackage(zip, 'les.ocideck', session),
        OpenResult.opened,
      );
      final theme = container
          .read(tabsProvider)
          .current!
          .deckNotifier
          .currentState
          .deck!
          .themeProfile;
      expect(theme.name, 'Bevroren');
      expect(theme.accentColor, '#123456');
    });

    test('weigert een leerpakket met een onleesbaar server-thema', () async {
      final container = _container();
      const source =
          '---\nmarp: true\n---\n<!-- ocideck_slide_anchor: slide-1 -->\n# Les\n';
      final session = LearningSessionRef(
        serverUrl: 'https://leren.example',
        accountId: 'account',
        organizationId: 'org',
        enrollmentId: 'enrollment',
        courseVersionId: 'version',
        lessonId: 'lesson',
        packageHash: 'sha256:test',
        startedAt: DateTime.utc(2026, 9, 7),
      );

      final result = await container
          .read(tabsProvider.notifier)
          .openLearningPackage(
            _zipOf({
              'deck.md': utf8.encode(source),
              'theme.json': utf8.encode('{"definition":false}'),
            }),
            'les.ocideck',
            session,
          );

      expect(result, OpenResult.unreadable);
      expect(container.read(tabsProvider).current?.learningSession, isNull);
    });

    test(
      'begrensd leerpakket laat de ruimere lokale pakketroute intact',
      () async {
        final learningContainer = _container();
        const source =
            '---\nmarp: true\n---\n<!-- ocideck_slide_anchor: slide-1 -->\n# Les\n';
        final zip = _zipOf({
          'deck.md': utf8.encode(source),
          // Nulbytes comprimeren klein, maar moeten tijdens uitpakken wel tegen
          // het 32 MiB-budget van het servercontract lopen.
          'assets/large.bin': Uint8List(33 * 1024 * 1024),
        });
        final session = LearningSessionRef(
          serverUrl: 'https://leren.example',
          accountId: 'account',
          organizationId: 'org',
          enrollmentId: 'enrollment',
          courseVersionId: 'version',
          lessonId: 'lesson',
          packageHash: 'sha256:test',
          startedAt: DateTime.utc(2026, 9, 7),
        );

        expect(
          await learningContainer
              .read(tabsProvider.notifier)
              .openLearningPackage(zip, 'les.ocideck', session),
          OpenResult.unreadable,
        );

        final localContainer = _container();
        expect(
          await localContainer
              .read(tabsProvider.notifier)
              .openDeckFromBytes(zip, 'lokaal.ocideck'),
          OpenResult.opened,
        );
      },
    );

    test('weigert een leerpakket zonder stabiele dia-ankers', () async {
      final container = _container();
      const source = '---\nmarp: true\n---\n# Les\n';
      final session = LearningSessionRef(
        serverUrl: 'https://leren.example',
        accountId: 'account',
        organizationId: 'org',
        enrollmentId: 'enrollment',
        courseVersionId: 'version',
        lessonId: 'lesson',
        packageHash: 'sha256:test',
        startedAt: DateTime.utc(2026, 9, 6),
      );

      final result = await container
          .read(tabsProvider.notifier)
          .openLearningPackage(
            _zipOf({'les.md': utf8.encode(source)}),
            'les.ocideck',
            session,
          );

      expect(result, OpenResult.unreadable);
      expect(container.read(tabsProvider).current?.learningSession, isNull);
    });

    test('behoudt het stabiele anker van een vraagdia', () async {
      final container = _container();
      const source = '''
---
marp: true
---
<!-- ocideck_slide_anchor: slide-15 -->
<!-- _class: question -->
# Even oefenen

```question
{"kind":"trueFalse","prompt":"Klopt dit?","statementIsTrue":true,"answers":[]}
```
''';
      final session = LearningSessionRef(
        serverUrl: 'https://leren.example',
        accountId: 'account',
        organizationId: 'org',
        enrollmentId: 'enrollment',
        courseVersionId: 'version',
        lessonId: 'lesson',
        packageHash: 'sha256:test',
        startedAt: DateTime.utc(2026, 9, 7),
      );

      expect(
        await container
            .read(tabsProvider.notifier)
            .openLearningPackage(
              _zipOf({'deck.md': utf8.encode(source)}),
              'les.ocideck',
              session,
            ),
        OpenResult.opened,
      );
      expect(
        container
            .read(tabsProvider)
            .current!
            .deckNotifier
            .currentState
            .deck!
            .slides
            .single
            .anchor,
        'slide-15',
      );
    });

    test('hervat een leerpakket op het stabiele dia-anker', () async {
      final container = _container();
      final markdown = container
          .read(markdownServiceProvider)
          .generateDeck(
            Deck(
              title: 'Les',
              slides: [
                Slide.create(
                  SlideType.title,
                ).copyWith(title: 'Begin', anchor: 'begin'),
                Slide.create(
                  SlideType.title,
                ).copyWith(title: 'Verder', anchor: 'verder'),
              ],
            ),
          );
      final session = LearningSessionRef(
        serverUrl: 'https://leren.example',
        accountId: 'account',
        organizationId: 'org',
        enrollmentId: 'enrollment',
        courseVersionId: 'version',
        lessonId: 'lesson',
        packageHash: 'sha256:test',
        startedAt: DateTime.utc(2026, 9, 6),
      );

      final result = await container
          .read(tabsProvider.notifier)
          .openLearningPackage(
            _zipOf({'les.md': utf8.encode(markdown)}),
            'les.ocideck',
            session,
            initialAnchor: 'verder',
          );

      expect(result, OpenResult.opened);
      expect(
        container
            .read(tabsProvider)
            .current!
            .editorNotifier
            .currentState
            .selectedIndex,
        1,
      );
    });

    test('weigert een leerpakket met een ontsnappend lid volledig', () async {
      final container = _container();
      const source = '---\nmarp: true\n---\n# Les\n';
      final archive = Archive()
        ..add(ArchiveFile.bytes('les.md', utf8.encode(source)))
        ..add(ArchiveFile.bytes('../verborgen.txt', utf8.encode('nee')));
      final zip = ZipEncoder().encodeBytes(archive);
      final session = LearningSessionRef(
        serverUrl: 'https://leren.example',
        accountId: 'account',
        organizationId: 'org',
        enrollmentId: 'enrollment',
        courseVersionId: 'version',
        lessonId: 'lesson',
        packageHash: 'sha256:test',
        startedAt: DateTime.utc(2026, 9, 6),
      );

      final result = await container
          .read(tabsProvider.notifier)
          .openLearningPackage(zip, 'les.ocideck', session);

      expect(result, isNot(OpenResult.opened));
      expect(container.read(tabsProvider).current?.learningSession, isNull);
    });

    test(
      'opent een pakket in het geheugen: afbeeldingen en notities mee',
      () async {
        final container = _container();
        // Bouw het pakket zoals de app het zelf zou maken: een gegenereerde
        // markdown met een image-slide plus het afbeeldings-lid en een
        // sprekersnotitie-sidecar.
        final md = container.read(markdownServiceProvider);
        final deck = Deck(
          title: 'Pakketdeck',
          slides: [
            Slide.create(SlideType.title).copyWith(title: 'Pakketdeck'),
            Slide.create(
              SlideType.image,
            ).copyWith(title: 'Met beeld', imagePath: 'images/foto.png'),
          ],
        );
        final markdown = md.generateDeck(deck);
        final parsedForNotes = md.parseDeck(markdown)!;
        final notesJson = UserNotesCodec.encode(parsedForNotes.slides, {
          parsedForNotes.slides.first.id: 'Notitie voor de ontvanger',
        })!;

        final zip = _zipOf({
          'Pakketdeck.md': utf8.encode(markdown),
          'images/foto.png': _pngBytes,
          'Pakketdeck.user-notes.json': utf8.encode(notesJson),
        });

        final tabs = container.read(tabsProvider.notifier);
        final result = await tabs.openDeckFromBytes(zip, 'Pakketdeck.ocideck');
        expect(result, OpenResult.opened);

        final opened = container
            .read(tabsProvider)
            .current!
            .deckNotifier
            .currentState
            .deck!;
        // De afbeelding is herschreven naar de in-memory store...
        final imageSlide = opened.slides.firstWhere(
          (s) => s.type == SlideType.image,
        );
        expect(WebAssetStore.isMemPath(imageSlide.imagePath), isTrue);
        expect(WebAssetStore.bytesFor(imageSlide.imagePath), equals(_pngBytes));
        // ...en de sprekersnotitie-sidecar reist mee.
        expect(opened.userNotes.values, contains('Notitie voor de ontvanger'));
        // Geen filePath: opslaan wordt een download.
        expect(
          container
              .read(tabsProvider)
              .current!
              .deckNotifier
              .currentState
              .filePath,
          isNull,
        );
      },
    );

    // Ook een `![…](…)` in de vrije tekst wijst naar een lid van het pakket,
    // en moet dus dezelfde weg naar het geheugen lopen — anders opent het deck
    // met een verwijzing naar een bestand dat alleen ín het archief bestaat.
    test('een afbeelding in de vrije tekst gaat ook mee', () async {
      final container = _container();
      final md = container.read(markdownServiceProvider);
      final deck = Deck(
        title: 'Tekstdeck',
        slides: [
          Slide.create(SlideType.freeMarkdown).copyWith(
            title: 'Verhaal',
            customMarkdown: 'Zie ![alt](images/tekstfoto.png) hierboven.',
          ),
        ],
      );
      final zip = _zipOf({
        'Tekstdeck.md': utf8.encode(md.generateDeck(deck)),
        'images/tekstfoto.png': _pngBytes,
      });

      final tabs = container.read(tabsProvider.notifier);
      expect(
        await tabs.openDeckFromBytes(zip, 'Tekstdeck.ocideck'),
        OpenResult.opened,
      );

      final opened = container
          .read(tabsProvider)
          .current!
          .deckNotifier
          .currentState
          .deck!;
      final markdown = opened.slides.single.customMarkdown;
      expect(markdown, isNot(contains('images/tekstfoto.png')));
      final mem = RegExp(
        r'!\[alt\]\(([^)]+)\)',
      ).firstMatch(markdown)!.group(1)!;
      expect(WebAssetStore.isMemPath(mem), isTrue);
      expect(WebAssetStore.bytesFor(mem), equals(_pngBytes));
    });

    test('een pakket zonder markdown is geen presentatie', () async {
      final container = _container();
      final tabs = container.read(tabsProvider.notifier);
      final zip = _zipOf({'images/foto.png': _pngBytes});
      expect(
        await tabs.openDeckFromBytes(zip, 'leeg.ocideck'),
        OpenResult.notAPresentation,
      );
    });

    test(
      'een pakket met uitvoerbare inhoud wordt geblokkeerd met alarm',
      () async {
        final container = _container();
        final tabs = container.read(tabsProvider.notifier);
        final zip = _zipOf({
          'kwaad.md': utf8.encode(
            '---\nmarp: true\n---\n\n# Hi\n\n<script>steal()</script>\n',
          ),
        });
        expect(
          await tabs.openDeckFromBytes(zip, 'kwaad.ocideck'),
          OpenResult.blocked,
        );
        final alarm = container.read(importSecurityAlarmProvider);
        expect(alarm, isNotNull);
        expect(alarm!.findings, isNotEmpty);
      },
    );

    test('verwijzingen buiten het pakket worden niet gevolgd', () async {
      final container = _container();
      final md = container.read(markdownServiceProvider);
      final deck = Deck(
        title: 'Traversal',
        slides: [
          Slide.create(
            SlideType.image,
          ).copyWith(title: 'Kwaad', imagePath: '../geheim.png'),
        ],
      );
      // De verwijzing wijst mét traversal buiten de pakketwortel; dat er
      // toevallig een lid 'geheim.png' bestaat mag niets uitmaken.
      final zip = _zipOf({
        'Traversal.md': utf8.encode(md.generateDeck(deck)),
        'geheim.png': _pngBytes,
      });
      final tabs = container.read(tabsProvider.notifier);
      final result = await tabs.openDeckFromBytes(zip, 'traversal.ocideck');
      expect(result, OpenResult.opened);
      final opened = container
          .read(tabsProvider)
          .current!
          .deckNotifier
          .currentState
          .deck!;
      final slide = opened.slides.firstWhere((s) => s.type == SlideType.image);
      expect(WebAssetStore.isMemPath(slide.imagePath), isFalse);
      expect(slide.imagePath, '../geheim.png');
    });

    test('gekoppelde grafiekdata reist mee uit data/', () async {
      final container = _container();
      final md = container.read(markdownServiceProvider);
      final deck = Deck(
        title: 'Cijferdeck',
        slides: [
          Slide.create(SlideType.chart).copyWith(
            customMarkdown: const ChartSpec(
              type: ChartType.line,
              title: 'Omzet',
              source: 'data/omzet.csv',
              x: ['Q1', 'Q2'],
              series: [
                ChartSeries(name: '2025', data: [10, 14]),
              ],
            ).toBlock(),
          ),
        ],
      );
      // generateDeck laat alleen de verwijzing staan; de cijfers zitten in het
      // data-lid. Zonder _attachPackageChartData opent dit als een lege plot.
      final zip = _zipOf({
        'Cijferdeck.md': utf8.encode(md.generateDeck(deck)),
        'data/omzet.csv': utf8.encode(',2025\nQ1,10\nQ2,14\n'),
      });
      final tabs = container.read(tabsProvider.notifier);
      final result = await tabs.openDeckFromBytes(zip, 'Cijferdeck.ocideck');
      expect(result, OpenResult.opened);
      final opened = container
          .read(tabsProvider)
          .current!
          .deckNotifier
          .currentState
          .deck!;
      final slide = opened.slides.firstWhere((s) => s.type == SlideType.chart);
      final spec = ChartSpec.parse(slide.customMarkdown);
      expect(spec.hasInlineData, isTrue);
      expect(spec.x, ['Q1', 'Q2']);
      expect(spec.series.single.data, [10, 14]);
      // De verwijzing blijft staan, zodat de koppeling zichtbaar blijft.
      expect(spec.source, 'data/omzet.csv');
    });

    // Nieuwe databestanden zijn JSON (_freeChartDataSource munt altijd .json),
    // dus dit is het pad dat een hedendaags deck aflegt. De CSV-broer hierboven
    // dekte het niet: die las per ongeluk elk lid als CSV.
    test('gekoppelde grafiekdata reist ook als JSON mee', () async {
      final container = _container();
      final md = container.read(markdownServiceProvider);
      final deck = Deck(
        title: 'Cijferdeck',
        slides: [
          Slide.create(SlideType.chart).copyWith(
            customMarkdown: const ChartSpec(
              type: ChartType.line,
              title: 'Omzet',
              source: 'data/omzet.json',
              x: ['Q1', 'Q2'],
              series: [
                ChartSeries(name: '2025', data: [10, 14]),
              ],
            ).toBlock(),
          ),
        ],
      );
      final zip = _zipOf({
        'Cijferdeck.md': utf8.encode(md.generateDeck(deck)),
        'data/omzet.json': utf8.encode(
          '{"x":["Q1","Q2"],"series":[{"name":"2025","data":[10,14]}]}',
        ),
      });
      final tabs = container.read(tabsProvider.notifier);
      final result = await tabs.openDeckFromBytes(zip, 'Cijferdeck.ocideck');
      expect(result, OpenResult.opened);
      final opened = container
          .read(tabsProvider)
          .current!
          .deckNotifier
          .currentState
          .deck!;
      final slide = opened.slides.firstWhere((s) => s.type == SlideType.chart);
      final spec = ChartSpec.parse(slide.customMarkdown);
      expect(spec.hasInlineData, isTrue);
      expect(spec.x, ['Q1', 'Q2']);
      expect(spec.series.single.data, [10, 14]);
      expect(spec.source, 'data/omzet.json');
    });

    test('grafiekdata buiten het pakket wordt niet gevolgd', () async {
      final container = _container();
      final md = container.read(markdownServiceProvider);
      final deck = Deck(
        title: 'Cijfertraversal',
        slides: [
          Slide.create(SlideType.chart).copyWith(
            customMarkdown: const ChartSpec(
              source: '../geheim.csv',
              x: ['Q1'],
              series: [
                ChartSeries(name: '2025', data: [1]),
              ],
            ).toBlock(),
          ),
        ],
      );
      final zip = _zipOf({
        'Cijfertraversal.md': utf8.encode(md.generateDeck(deck)),
        'geheim.csv': utf8.encode(',geheim\nQ1,42\n'),
      });
      final tabs = container.read(tabsProvider.notifier);
      final result = await tabs.openDeckFromBytes(zip, 'ct.ocideck');
      expect(result, OpenResult.opened);
      final opened = container
          .read(tabsProvider)
          .current!
          .deckNotifier
          .currentState
          .deck!;
      final spec = ChartSpec.parse(
        opened.slides
            .firstWhere((s) => s.type == SlideType.chart)
            .customMarkdown,
      );
      expect(spec.hasInlineData, isFalse);
    });

    // Een lege plot is niet te onderscheiden van een grafiek waar nog niets in
    // staat, dus het bytes-pad hoort te melden wat het niet kon invullen.
    test('een niet-ingevulde grafiek levert een melding op', () async {
      final container = _container();
      final md = container.read(markdownServiceProvider);
      final deck = Deck(
        title: 'Cijfertraversal',
        slides: [
          Slide.create(SlideType.chart).copyWith(
            customMarkdown: const ChartSpec(
              type: ChartType.line,
              title: 'Omzet',
              source: 'data/omzet.json',
              x: ['Q1'],
              series: [
                ChartSeries(name: '2025', data: [10]),
              ],
            ).toBlock(),
          ),
        ],
      );
      // Het pakket draagt de verwijzing, maar niet het databestand.
      final zip = _zipOf({
        'Cijfertraversal.md': utf8.encode(md.generateDeck(deck)),
      });
      final tabs = container.read(tabsProvider.notifier);
      expect(
        await tabs.openDeckFromBytes(zip, 'Cijfertraversal.ocideck'),
        OpenResult.opened,
      );
      expect(container.read(chartDataWarningProvider)?.sources, [
        'data/omzet.json',
      ]);
    });
  });
}
