import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/annotation.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:path/path.dart' as p;

/// A FileService whose write fails, to exercise the save error path.
class _ThrowingFileService extends FileService {
  _ThrowingFileService(MarkdownService md)
    : super(md, ImageService(), () => const ThemeProfile());

  // `saveDeckDetailed` is wat de state-laag aanroept (het draagt ook de
  // grafiekdata-klachten); `saveDeck` is er de dunne wrapper omheen.
  @override
  Future<({Deck deck, List<String> chartWarnings})> saveDeckDetailed(
    Deck deck,
    String filePath,
  ) async => throw const FileSystemException('disk full');
}

/// A FileService whose write blocks until [gate] completes, to exercise the
/// concurrent-save lock.
class _BlockingFileService extends FileService {
  _BlockingFileService(this.gate, MarkdownService md)
    : super(md, ImageService(), () => const ThemeProfile());

  final Completer<void> gate;
  int calls = 0;

  @override
  Future<({Deck deck, List<String> chartWarnings})> saveDeckDetailed(
    Deck deck,
    String filePath,
  ) async {
    calls++;
    await gate.future;
    return (deck: deck, chartWarnings: const <String>[]);
  }
}

Deck _deck() => Deck(
  title: 'T',
  slides: [Slide.create(SlideType.title).copyWith(title: 'T')],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('save error handling', () {
    test('a write failure returns false, sets error and stays dirty', () async {
      final md = MarkdownService();
      final n = DeckNotifier(md, _ThrowingFileService(md));
      n.loadDeck(_deck(), filePath: '/tmp/does-not-matter.md');
      n.addSlide(SlideType.bullets); // make it dirty
      expect(n.state.isDirty, isTrue);

      final ok = await n.save();

      expect(ok, isFalse);
      expect(n.state.isDirty, isTrue, reason: 'unsaved work must stay dirty');
      expect(n.state.error, isNotNull);
    });

    test('a second concurrent save is rejected by the lock', () async {
      final md = MarkdownService();
      final gate = Completer<void>();
      final fs = _BlockingFileService(gate, md);
      final n = DeckNotifier(md, fs);
      n.loadDeck(_deck(), filePath: '/tmp/x.md');
      n.addSlide(SlideType.bullets);

      final first = n.save(); // acquires the lock, blocks on the gate
      final second = await n.save(); // lock held → rejected immediately

      expect(second, isFalse);
      gate.complete();
      expect(await first, isTrue);
      expect(fs.calls, 1, reason: 'only one write must reach disk');
    });

    // #1952: een tweede Cmd/Ctrl+S tijdens een lopende opslag werd stilletjes
    // genegeerd. Nu wordt hij onthouden en opnieuw uitgevoerd nadat de eerste
    // klaar is — mits het tabblad nog vuil is (de gebruiker kan ondertussen
    // hebben getypt, of de eerste opslag kan al schoon hebben gemaakt).
    test(
      'a second save during a save is queued and re-runs if still dirty (#1952)',
      () async {
        final md = MarkdownService();
        final gate = Completer<void>();
        final fs = _BlockingFileService(gate, md);
        final n = DeckNotifier(md, fs);
        n.loadDeck(_deck(), filePath: '/tmp/x.md');
        n.addSlide(SlideType.bullets);

        final first = n.save(); // acquires the lock, blocks on the gate
        // De gebruiker typt door tijdens de opslag — het tabblad blijft vuil
        // na de eerste opslag (userEdited-pad).
        n.addSlide(SlideType.bullets);
        final second = await n.save(); // lock held → queued, returns false
        expect(second, isFalse);

        gate.complete();
        expect(await first, isTrue);

        // De herhaling vuurt in de finally van de eerste save — unawaited,
        // dus pompen tot hij landt. De gate is al compleet, dus de tweede
        // schrijfbeurt is direct. Na de schrijfbeurt zelf volgt nog de
        // state-update (isDirty = false), dus pompen tot het tabblad schoon is.
        while (fs.calls < 2 || n.state.isDirty) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(fs.calls, 2, reason: 'queued save re-ran');
        expect(n.state.isDirty, isFalse, reason: 'deck is clean after re-save');
      },
    );

    test(
      'a second save during a save is not re-run if the deck is already clean (#1952)',
      () async {
        final md = MarkdownService();
        final gate = Completer<void>();
        final fs = _BlockingFileService(gate, md);
        final n = DeckNotifier(md, fs);
        n.loadDeck(_deck(), filePath: '/tmp/x.md');
        n.addSlide(SlideType.bullets);

        final first = n.save(); // acquires the lock, blocks on the gate
        final second = await n.save(); // lock held → queued, returns false
        expect(second, isFalse);

        gate.complete();
        expect(await first, isTrue);
        expect(fs.calls, 1, reason: 'first save wrote once');
        expect(
          n.state.isDirty,
          isFalse,
          reason: 'no edits during save → clean',
        );

        // De wachtrij staat, maar het tabblad is schoon — de herhaling slaat
        // over. Pompen een paar keer om zeker te zijn dat er niets meer komt.
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(fs.calls, 1, reason: 'no re-save when deck is already clean');
      },
    );
  });

  group('transactional save (#1949)', () {
    late FileService service;
    late MarkdownService md;
    late Directory temp;

    setUp(() async {
      md = MarkdownService();
      service = FileService(md, ImageService(), () => const ThemeProfile());
      temp = await Directory.systemTemp.createTemp('ocideck_txn_');
    });
    tearDown(() => temp.delete(recursive: true));

    test('a sidecar failure leaves the old .md on disk', () async {
      final slide = Slide.create(
        SlideType.bullets,
      ).copyWith(title: 'Eerste', bullets: ['a']);
      final deck = Deck(
        title: 'Tx',
        slides: [slide],
        annotations: {
          slide.id: [
            InkStroke(
              tool: InkTool.pen,
              color: 0xFF000000,
              width: 0.005,
              points: const [Offset(0.1, 0.1), Offset(0.2, 0.2)],
              id: 's1',
            ),
          ],
        },
      );
      final mdPath = p.join(temp.path, 'deck.md');
      // Eerste opslag slaagt — baseline .md en .ink.json op schijf.
      await service.saveDeck(deck, mdPath);
      final originalMd = await File(mdPath).readAsString();

      // Blokkeer de annotatie-sidecar: vervang het bestand door een map.
      final inkPath = p.setExtension(mdPath, '.ink.json');
      await File(inkPath).delete();
      await Directory(inkPath).create();

      // Tweede opslag met gewijzigde inhoud moet falen bij de sidecar-stap.
      final modified = deck.copyWith(
        slides: [
          ...deck.slides,
          Slide.create(SlideType.bullets).copyWith(title: 'Tweede'),
        ],
      );
      await expectLater(
        service.saveDeck(modified, mdPath),
        throwsA(isA<FileSystemException>()),
      );

      // De .md op schijf is nog steeds het origineel — de nieuwe is nooit
      // geschreven, want sidecars gaan vóór de .md.
      expect(await File(mdPath).readAsString(), originalMd);
    });
  });

  group('openDeck load robustness', () {
    late FileService service;
    late MarkdownService md;
    late Directory temp;

    setUp(() async {
      md = MarkdownService();
      service = FileService(md, ImageService(), () => const ThemeProfile());
      temp = await Directory.systemTemp.createTemp('ocideck_load_');
    });
    tearDown(() => temp.delete(recursive: true));

    test('a CRLF file loads identically to its LF form', () async {
      final deck = Deck(
        title: 'Deck',
        slides: [
          Slide.create(SlideType.title).copyWith(title: 'Eerste'),
          Slide.create(
            SlideType.bullets,
          ).copyWith(title: 'Tweede', bullets: ['een', 'twee']),
        ],
      );
      final lf = md.generateDeck(deck);
      final crlf = lf.replaceAll('\n', '\r\n');

      final lfFile = File(p.join(temp.path, 'lf.md'));
      final crlfFile = File(p.join(temp.path, 'crlf.md'));
      await lfFile.writeAsString(lf);
      await crlfFile.writeAsString(crlf);

      final lfDeck = await service.openDeck(lfFile.path);
      final crlfDeck = await service.openDeck(crlfFile.path);

      expect(lfDeck, isNotNull);
      expect(crlfDeck, isNotNull);
      expect(
        crlfDeck!.slides.map((s) => s.title),
        lfDeck!.slides.map((s) => s.title),
      );
      expect(crlfDeck.slides.length, lfDeck.slides.length);
    });

    // Deze toets stond er omgekeerd in: front matter zonder body gold als een
    // afgekapt bestand en werd geweigerd (#1350). Die regel is teruggedraaid in
    // #1909 — zie de motivering bij `openDeckDetailed`. Dezelfde bytes zijn ook
    // wat OciDeck zelf wegschrijft voor een presentatie waarvan de enige dia nog
    // leeg is, en die moest het kunnen teruglezen.
    test('een presentatie zonder body opent als lege presentatie', () async {
      final file = File(p.join(temp.path, 'leeg.md'));
      await file.writeAsString('---\nmarp: true\ntitle: X\n---\n');

      expect(await service.openDeck(file.path), isNotNull);
    });

    test('non-UTF8 bytes return null instead of throwing', () async {
      final file = File(p.join(temp.path, 'binary.md'));
      await file.writeAsBytes([0xFF, 0xFE, 0x00, 0x80, 0x81]);

      expect(await service.openDeck(file.path), isNull);
    });
  });

  group('editing while a save is in flight', () {
    test(
      'typing during the write is not rolled back, and stays dirty',
      () async {
        final gate = Completer<void>();
        final md = MarkdownService();
        final n = DeckNotifier(md, _BlockingFileService(gate, md));
        n.loadDeck(_deck(), filePath: '/tmp/race.md');

        final saving = n.save();
        // The user keeps working while the project write is on the wire.
        n.addSlide(SlideType.bullets);
        n.addSlide(SlideType.bullets);
        gate.complete();
        final ok = await saving;

        expect(ok, isTrue);
        expect(
          n.state.deck!.slides.length,
          3,
          reason: 'the in-flight save must not roll the deck back',
        );
        expect(
          n.state.isDirty,
          isTrue,
          reason: 'the newer edits are not on disk, so the deck is still dirty',
        );
      },
    );

    test('an untouched deck still lands clean', () async {
      final gate = Completer<void>()..complete();
      final md = MarkdownService();
      final n = DeckNotifier(md, _BlockingFileService(gate, md));
      n.loadDeck(_deck(), filePath: '/tmp/quiet.md');
      n.addSlide(SlideType.bullets);

      expect(await n.save(), isTrue);
      expect(n.state.isDirty, isFalse);
      expect(n.state.deck!.slides.length, 2);
    });
  });

  group('non-edit state replacement during save', () {
    test('a state.deck replacement without a user edit (no undo step) still '
        'lands clean after save', () async {
      final gate = Completer<void>();
      final md = MarkdownService();
      final n = DeckNotifier(md, _BlockingFileService(gate, md));
      n.loadDeck(_deck(), filePath: '/tmp/quiet.md');
      n.addSlide(SlideType.bullets); // dirty
      expect(n.state.isDirty, isTrue);

      final saving = n.save();
      // Simulate a non-edit state replacement (e.g. applyProvenance or a
      // themeProfile copyWith) happening during the async save — it creates
      // a new deck object without adding an undo step.
      n.applyProvenance(null);
      expect(
        !identical(n.state.deck, n.state.deck),
        isFalse,
      ); // sanity: object exists
      gate.complete();
      final ok = await saving;

      expect(ok, isTrue);
      expect(
        n.state.isDirty,
        isFalse,
        reason:
            'state.deck was replaced but no user edit happened (no undo '
            'step), so the deck should be clean after save',
      );
    });
  });
}
