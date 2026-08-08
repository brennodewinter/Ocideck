import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/annotation.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/markdown_kind.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records recovery calls synchronously so the periodic autosave tick can be
/// asserted without touching the filesystem.
class _RecordingRecovery extends RecoveryService {
  _RecordingRecovery() : super(baseDir: Directory.systemTemp);

  final List<RecoverySnapshot> saved = [];
  final List<String> discarded = [];

  @override
  Future<void> save(RecoverySnapshot snapshot) async => saved.add(snapshot);

  @override
  Future<void> discard(String id) async => discarded.add(id);
}

TabsNotifier _tabs(_RecordingRecovery recovery) {
  // Build through a container so the notifier gets a real Ref (used for the
  // import-security alarm); only the recovery service is swapped for the spy.
  final container = ProviderContainer(
    overrides: [recoveryServiceProvider.overrideWithValue(recovery)],
  );
  return container.read(tabsProvider.notifier);
}

Deck _deck() => Deck(
  title: 'D',
  slides: [Slide.create(SlideType.title).copyWith(title: 'D')],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('autosave writes a recovery snapshot for a dirty tab on the tick', () {
    fakeAsync((async) {
      final recovery = _RecordingRecovery();
      final tabs = _tabs(recovery);
      addTearDown(tabs.dispose);

      tabs.state.current!.deckNotifier
        ..loadDeck(_deck())
        ..markDirty();

      // Nothing is written before the 25-second interval elapses.
      async.elapse(const Duration(seconds: 24));
      expect(recovery.saved, isEmpty);

      // The periodic tick fires and snapshots the dirty tab.
      async.elapse(const Duration(seconds: 2));
      expect(recovery.saved, isNotEmpty);
      expect(recovery.saved.last.markdown, contains('D'));
    });
  });

  test('autosave carries the annotation layer into the snapshot', () {
    fakeAsync((async) {
      final recovery = _RecordingRecovery();
      final tabs = _tabs(recovery);
      addTearDown(tabs.dispose);

      final deck = _deck();
      final notifier = tabs.state.current!.deckNotifier..loadDeck(deck);
      // Tekenen is de énige wijziging: het deck wordt er vuil van, dus dit
      // tabblad hoort in de herstelkopie te belanden — mét de streek.
      notifier.setAnnotations({
        deck.slides.first.id: const [
          InkStroke(
            tool: InkTool.pen,
            color: 0xFFEF4444,
            width: 0.004,
            points: [Offset(0.1, 0.2), Offset(0.3, 0.4)],
            id: 's1',
          ),
        ],
      });

      async.elapse(const Duration(seconds: 30));
      expect(recovery.saved, isNotEmpty);
      expect(recovery.saved.last.annotations, isNotNull);

      // En terug: herstellen levert de tekening op, niet alleen de tekst.
      final restored = _tabs(_RecordingRecovery());
      addTearDown(restored.dispose);
      expect(restored.restoreRecovered([recovery.saved.last]), 0);
      final back = restored.state.current!.deckNotifier.currentState.deck!;
      expect(back.annotations.values.expand((s) => s), hasLength(1));
      expect(back.annotations.values.first.single.points, hasLength(2));
    });
  });

  test('een vuil documenttabblad wordt bewaard en hersteld (crash)', () {
    fakeAsync((async) {
      final recovery = _RecordingRecovery();
      final tabs = _tabs(recovery);
      addTearDown(tabs.dispose);

      tabs.newDocument();
      tabs.state.current!.documentNotifier!.edit('# Memo\n\nNiet opgeslagen.');

      // De regressie: documenttabbladen werden overgeslagen bij autosave, dus een
      // crash gooide niet-opgeslagen documenten weg. Nu belanden ze in een eigen
      // momentopname (byte-getrouwe bron, gemarkeerd als document).
      async.elapse(const Duration(seconds: 30));
      expect(recovery.saved, isNotEmpty);
      final snap = recovery.saved.last;
      expect(snap.kind, MarkdownKind.document);
      expect(snap.markdown, '# Memo\n\nNiet opgeslagen.');

      // En terug: herstellen levert een documenttabblad op, byte-getrouw en vuil.
      final restored = _tabs(_RecordingRecovery());
      addTearDown(restored.dispose);
      expect(restored.restoreRecovered([snap]), 0);
      final doc = restored.state.current!.documentNotifier;
      expect(doc, isNotNull);
      expect(doc!.currentState.document!.source, '# Memo\n\nNiet opgeslagen.');
      expect(doc.currentState.isDirty, isTrue);
    });
  });

  test('een schoon documenttabblad wordt niet bewaard', () {
    fakeAsync((async) {
      final recovery = _RecordingRecovery();
      final tabs = _tabs(recovery);
      addTearDown(tabs.dispose);

      tabs.newDocument(); // leeg en schoon (isDirty:false)

      async.elapse(const Duration(seconds: 30));
      expect(recovery.saved, isEmpty);
    });
  });

  test('a clean tab is not autosaved', () {
    fakeAsync((async) {
      final recovery = _RecordingRecovery();
      final tabs = _tabs(recovery);
      addTearDown(tabs.dispose);

      tabs.state.current!.deckNotifier.loadDeck(
        _deck(),
      ); // clean (isDirty:false)

      async.elapse(const Duration(seconds: 30));
      expect(recovery.saved, isEmpty);
    });
  });

  test('autosave preserves unapplied Markdown separately from valid deck', () {
    fakeAsync((async) {
      final recovery = _RecordingRecovery();
      final tabs = _tabs(recovery);
      addTearDown(tabs.dispose);
      final tab = tabs.state.current!;
      tab.deckNotifier.loadDeck(_deck());
      final baseline = tab.deckNotifier.generateMarkdown();
      tab.editorNotifier.setMode(
        EditorMode.markdown,
        initialMarkdown: baseline,
      );
      tab.editorNotifier.updateMarkdown('$baseline\n```onaf');

      async.elapse(const Duration(seconds: 30));

      expect(recovery.saved, hasLength(1));
      final snapshot = recovery.saved.single;
      expect(snapshot.markdown, isNot(contains('```onaf')));
      expect(snapshot.markdownDraft, contains('```onaf'));

      final restored = _tabs(_RecordingRecovery());
      addTearDown(restored.dispose);
      expect(restored.restoreRecovered([snapshot]), 0);
      final restoredEditor =
          restored.state.current!.editorNotifier.currentState;
      expect(restoredEditor.mode, EditorMode.markdown);
      expect(restoredEditor.markdownBuffer, contains('```onaf'));
      expect(restoredEditor.hasMarkdownDraft, isTrue);
    });
  });

  test('disposing the notifier cancels the autosave timer', () {
    fakeAsync((async) {
      final recovery = _RecordingRecovery();
      final tabs = _tabs(recovery);

      tabs.state.current!.deckNotifier
        ..loadDeck(_deck())
        ..markDirty();

      tabs.dispose();
      async.elapse(const Duration(seconds: 60));
      expect(recovery.saved, isEmpty);
    });
  });
}
