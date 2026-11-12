import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';
import 'package:ocideck/widgets/shell/document_save_actions.dart';

void main() {
  test('geladen document is schoon en behoudt bron + pad', () {
    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('# Memo\n'), filePath: '/a.md');
    expect(n.currentState.isDirty, isFalse);
    expect(n.currentState.filePath, '/a.md');
    expect(n.currentState.document!.toMarkdown(), '# Memo\n');
  });

  test('edit wijzigt de bron, markeert dirty en zet canUndo', () {
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse('a'));
    n.edit('ab');
    expect(n.currentState.document!.source, 'ab');
    expect(n.currentState.isDirty, isTrue);
    expect(n.canUndo, isTrue);
    expect(n.canRedo, isFalse);
  });

  test('een edit die de bron niet verandert is een no-op', () {
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse('a'));
    n.edit('a');
    expect(n.canUndo, isFalse);
    expect(n.currentState.isDirty, isFalse);
  });

  test('undo herstelt de vorige bron, redo voert opnieuw uit', () {
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse('a'));
    n.edit('ab', coalesceKey: null);
    n.undo();
    expect(n.currentState.document!.source, 'a');
    expect(n.canRedo, isTrue);
    n.redo();
    expect(n.currentState.document!.source, 'ab');
  });

  test('zelfde coalesceKey voegt snelle bewerkingen tot één stap samen', () {
    var now = DateTime.utc(2026);
    final n = DocumentNotifier(now: () => now)
      ..loadDocument(MarkdownDocument.parse(''));
    n.edit('a', coalesceKey: 'typ');
    now = now.add(const Duration(milliseconds: 699));
    n.edit('ab', coalesceKey: 'typ');
    now = now.add(const Duration(milliseconds: 699));
    n.edit('abc', coalesceKey: 'typ');
    // Eén ongedaan-stap terug naar de begintoestand vóór het typen.
    n.undo();
    expect(n.currentState.document!.source, '');
    expect(n.canUndo, isFalse);
  });

  test('een pauze van 700 ms begint een nieuwe ongedaan-stap', () {
    var now = DateTime.utc(2026);
    final n = DocumentNotifier(now: () => now)
      ..loadDocument(MarkdownDocument.parse(''));
    n.edit('a', coalesceKey: 'typ');
    now = now.add(const Duration(milliseconds: 700));
    n.edit('ab', coalesceKey: 'typ');
    n.undo();
    expect(n.currentState.document!.source, 'a');
    n.undo();
    expect(n.currentState.document!.source, '');
    expect(n.canUndo, isFalse);
  });

  test('verschillende coalesceKeys zijn aparte ongedaan-stappen', () {
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse(''));
    n.edit('a', coalesceKey: 'x');
    n.edit('ab', coalesceKey: 'y');
    n.undo();
    expect(n.currentState.document!.source, 'a');
    n.undo();
    expect(n.currentState.document!.source, '');
  });

  test('een nieuwe edit wist de redo-stapel', () {
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse('a'));
    n.edit('ab', coalesceKey: null);
    n.undo();
    expect(n.canRedo, isTrue);
    n.edit('ac', coalesceKey: null);
    expect(n.canRedo, isFalse);
  });

  test('markSaved maakt schoon en onthoudt het pad', () {
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse('a'));
    n.edit('ab');
    n.markSaved(filePath: '/b.md');
    expect(n.currentState.isDirty, isFalse);
    expect(n.currentState.filePath, '/b.md');
  });

  test('setError en clearError', () {
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse('a'));
    n.setError('stuk');
    expect(n.currentState.error, 'stuk');
    n.clearError();
    expect(n.currentState.error, isNull);
  });

  test('undo naar de opgeslagen bron maakt de tab niet vuil (#1672)', () {
    final n = DocumentNotifier()
      ..loadDocument(MarkdownDocument.parse('a'), filePath: '/a.md');
    n.edit('ab');
    expect(n.currentState.isDirty, isTrue);
    n.undo();
    // Bron is weer 'a' == savedSource → niet vuil.
    expect(n.currentState.document!.source, 'a');
    expect(n.currentState.isDirty, isFalse);
  });

  test('undo herstelt visualEdited (#1672)', () {
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse('a'));
    // Eerst een bron-edit (visualEdited: false), dan een visuele edit.
    n.edit('ab', coalesceKey: null);
    n.edit('abc', coalesceKey: null, visualEdit: true);
    expect(n.currentState.visualEdited, isTrue);
    // Undo de visuele edit → visualEdited weer false (de bron-edit was niet
    // visueel).
    n.undo();
    expect(n.currentState.visualEdited, isFalse);
    // Redo de visuele edit → visualEdited weer true.
    n.redo();
    expect(n.currentState.visualEdited, isTrue);
  });

  // Regressie #2720: een opslag die blokkeerde terwijl er verder getypt werd,
  // mocht niet schoon melden — de vervolgschrijfactie zet de nieuwe bron op
  // schijf.
  group('saveDocumentUntilCurrent (#2720)', () {
    test('schrijft opnieuw als de bron tijdens de await veranderde', () async {
      final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse('v1'));
      n.edit('v2');
      final written = <String>[];
      final result = await saveDocumentUntilCurrent(
        notifier: n,
        first: n.currentState.document!,
        write: (doc) async {
          // Tijdens deze "schijfactie" typt de gebruiker verder.
          if (written.isEmpty) n.edit('v3');
          written.add(doc.source);
          return doc;
        },
      );
      expect(result!.source, 'v3');
      expect(written, ['v2', 'v3']);
      // De aanroeper mag pas schoon melden als live == result — hier klopt dat.
      expect(n.currentState.document!.source, result.source);
    });

    test(
      'meldt niet-geschreven bron terug zodat de aanroeper vuil laat',
      () async {
        final n = DocumentNotifier()
          ..loadDocument(MarkdownDocument.parse('v1'));
        n.edit('v2');
        var calls = 0;
        final result = await saveDocumentUntilCurrent(
          notifier: n,
          first: n.currentState.document!,
          maxAttempts: 2,
          write: (doc) async {
            calls++;
            n.edit('v${2 + calls}'); // elke schijfactie wordt ingehaald
            return doc;
          },
        );
        expect(calls, 2);
        // De levende bron is nieuwer dan wat geschreven kon worden: de
        // aanroeper meldt NIET schoon (isDirty blijft, herstelkopie blijft).
        expect(n.currentState.document!.source, isNot(result!.source));
        expect(n.currentState.isDirty, isTrue);
      },
    );
  });
}
