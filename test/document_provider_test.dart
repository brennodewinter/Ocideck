import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';

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
    final n = DocumentNotifier()..loadDocument(MarkdownDocument.parse(''));
    n.edit('a', coalesceKey: 'typ');
    n.edit('ab', coalesceKey: 'typ');
    n.edit('abc', coalesceKey: 'typ');
    // Eén ongedaan-stap terug naar de begintoestand vóór het typen.
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
}
