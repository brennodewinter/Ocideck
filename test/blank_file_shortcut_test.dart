import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/models/markdown_kind.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pumpShell(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'app_consent_accepted': true,
    'languageCode': 'nl',
  });
  await tester.binding.setSurfaceSize(const Size(1600, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(AppShell)));
}

Future<void> _newBlank(WidgetTester tester, LogicalKeyboardKey modifier) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

void main() {
  final toDocument = find.text('Wissel naar document');
  final toPresentation = find.text('Wissel naar presentatie');

  testWidgets('Ctrl+Shift+N opent vanaf het openingsscherm een leeg bestand', (
    tester,
  ) async {
    final container = await _pumpShell(tester);
    expect(container.read(tabsProvider).current!.isOpen, isFalse);

    await _newBlank(tester, LogicalKeyboardKey.controlLeft);

    expect(container.read(tabsProvider).tabs, hasLength(1));
    final presentation = container.read(tabsProvider).current!;
    expect(presentation.kind, MarkdownKind.presentation);
    expect(presentation.isDirty, isFalse);
    final slide = presentation.deckNotifier.currentState.deck!.slides.single;
    expect(slide.title, isEmpty);
    expect(slide.subtitle, isEmpty);

    await tester.tap(toDocument);
    await tester.pumpAndSettle();
    final document = container.read(tabsProvider).current!;
    expect(document.kind, MarkdownKind.document);
    expect(document.documentNotifier!.currentState.document!.source, isEmpty);
    expect(container.read(tabsProvider).tabs, hasLength(1));

    await tester.tap(toPresentation);
    await tester.pumpAndSettle();
    expect(
      container.read(tabsProvider).current!.kind,
      MarkdownKind.presentation,
    );
    expect(container.read(tabsProvider).tabs, hasLength(1));
    expect(toDocument, findsOneWidget);
  });

  testWidgets('Ctrl+Shift+N opent een nieuwe tab naast een presentatie', (
    tester,
  ) async {
    final container = await _pumpShell(tester);
    container.read(tabsProvider.notifier).newDeckInCurrentTab('Bestaand');
    await tester.pumpAndSettle();
    final original = container.read(tabsProvider).current!;

    await _newBlank(tester, LogicalKeyboardKey.controlLeft);

    final state = container.read(tabsProvider);
    expect(state.tabs, hasLength(2));
    expect(state.tabs.first, same(original));
    expect(state.current!.kind, MarkdownKind.presentation);
    expect(toDocument, findsOneWidget);
  });

  testWidgets('Cmd+Shift+N maakt naast een document een nieuw leeg document', (
    tester,
  ) async {
    final container = await _pumpShell(tester);
    final tabs = container.read(tabsProvider.notifier);
    await tabs.newDocument(source: '# Bestaande tekst\n');
    await tester.pumpAndSettle();
    final original = container.read(tabsProvider).current!;

    await _newBlank(tester, LogicalKeyboardKey.metaLeft);

    final state = container.read(tabsProvider);
    expect(state.tabs, hasLength(2));
    expect(state.tabs.first, same(original));
    expect(state.current!.kind, MarkdownKind.document);
    expect(toPresentation, findsOneWidget);

    await tester.tap(toPresentation);
    await tester.pumpAndSettle();
    final switched = container.read(tabsProvider);
    expect(switched.tabs, hasLength(2));
    expect(switched.tabs.first, same(original));
    expect(switched.current!.kind, MarkdownKind.presentation);
    expect(switched.clampedIndex, 1);
  });

  testWidgets('getypte documenttekst verhindert wisselen, ook vóór de flush', (
    tester,
  ) async {
    final container = await _pumpShell(tester);
    final tabs = container.read(tabsProvider.notifier);
    await tabs.newDocument();
    await tester.pumpAndSettle();
    final tab = container.read(tabsProvider).current!;
    final document = tab.documentNotifier!;
    document.visualFlush.bind(() => document.edit('Nieuwe tekst'));

    await tester.tap(toPresentation);
    await tester.pumpAndSettle();

    expect(container.read(tabsProvider).current, same(tab));
    expect(document.currentState.document!.source, 'Nieuwe tekst');
    expect(toPresentation, findsNothing);
  });

  testWidgets('inhoud en niet-toegepaste bronwijzigingen verbergen de knop', (
    tester,
  ) async {
    final container = await _pumpShell(tester);
    await _newBlank(tester, LogicalKeyboardKey.controlLeft);
    final tab = container.read(tabsProvider).current!;
    final editor = tab.editorNotifier;
    final source = tab.deckNotifier.generateMarkdown();
    editor.setMode(EditorMode.markdown, initialMarkdown: source);
    editor.updateMarkdown('$source\nEen onopgeslagen wijziging');
    await tester.pumpAndSettle();
    expect(toDocument, findsNothing);

    editor.setMode(EditorMode.visual);
    await tester.pumpAndSettle();
    expect(toDocument, findsOneWidget);

    tab.deckNotifier.addSlide(SlideType.title);
    await tester.pumpAndSettle();
    expect(toDocument, findsNothing);
  });

  testWidgets('een geopend leeg bestand houdt zijn eigen type', (tester) async {
    final container = await _pumpShell(tester);
    await container.read(tabsProvider.notifier).newDocument();
    await tester.pumpAndSettle();
    container
        .read(tabsProvider)
        .current!
        .documentNotifier!
        .loadDocument(MarkdownDocument.parse(''), filePath: '/document.md');
    await tester.pumpAndSettle();
    expect(toPresentation, findsNothing);
  });
}
