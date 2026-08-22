import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/state/document_provider.dart';

void main() {
  group('conversie presentatie → document: projectPath (#1646)', () {
    test('loadDocument met projectPath onthoudt de map', () {
      final doc = MarkdownDocument.parse('# Titel\n');
      final n = DocumentNotifier()
        ..loadDocument(doc, projectPath: '/project/map');
      expect(n.currentState.projectPath, '/project/map');
      expect(n.currentState.filePath, isNull);
    });

    test('loadDocument zonder projectPath laat het null', () {
      final doc = MarkdownDocument.parse('# Titel\n');
      final n = DocumentNotifier()..loadDocument(doc);
      expect(n.currentState.projectPath, isNull);
    });

    test('projectPath overleeft undo/redo', () {
      final doc = MarkdownDocument.parse('# Titel\n');
      final n = DocumentNotifier()
        ..loadDocument(doc, projectPath: '/project/map');
      n.edit('# Gewijzigd\n');
      n.undo();
      // projectPath is geen onderdeel van de undo-stapel; het blijft staan.
      expect(n.currentState.projectPath, '/project/map');
    });
  });
}
