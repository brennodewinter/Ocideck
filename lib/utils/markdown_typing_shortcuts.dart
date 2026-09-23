import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

/// Zet een getypte Markdown-trigger aan het begin van een regel om in echte
/// Quill-opmaak — zoals GitHub en Notion dat doen. Wie `- [ ] ` typt in de
/// visuele stand krijgt een checklistitem, geen letterlijke brackets.
///
/// De trigger geldt alleen wanneer hij de héle regel vóór de cursor beslaat
/// en de regel nog geen blokopmaak draagt: `> ` midden in een zin is gewone
/// tekst, en in een codeblok of bestaande lijst is `- ` dat ook.
bool applyMarkdownLineShortcut(QuillController controller) {
  final selection = controller.selection;
  if (!selection.isValid || !selection.isCollapsed) return false;
  final caret = selection.baseOffset;
  final node = controller.document.queryChild(caret).node;
  if (node is! Line) return false;
  const blockKeys = {'list', 'blockquote', 'header', 'code-block'};
  if (node.style.attributes.keys.any(blockKeys.contains)) return false;

  final lineStart = node.documentOffset;
  final inLine = caret - lineStart;
  final text = node.toPlainText(); // sluit af met '\n'
  if (inLine <= 0 || inLine > text.length - 1) return false;
  final typed = text.substring(0, inLine);
  // Wat ná de trigger op dezelfde regel staat, blijft de inhoud van het
  // blok — de regelafsluiter staat dus pas `rest` tekens verder.
  final rest = text.substring(inLine, text.length - 1);

  final delta = Delta()
    ..retain(lineStart)
    ..delete(typed.length);
  final attribute = _blockAttributeFor(typed);
  if (attribute != null) {
    delta
      ..retain(rest.length)
      ..retain(1, attribute.toJson());
  } else if (rest.isEmpty && _rulePattern.hasMatch(typed)) {
    // Zelfde type als `horizontalRule` in markdown_quill (`divider`): de
    // embed staat op de plek van de gewiste tekst, voor de eigen
    // regelafsluiter. Met resttekst op de regel is er geen eigen lijn voor
    // de embed — dan is `---` gewone tekst.
    delta.insert(const BlockEmbed('divider', 'hr').toJson());
  } else {
    return false;
  }
  controller.compose(
    delta,
    TextSelection.collapsed(offset: lineStart),
    ChangeSource.local,
  );
  return true;
}

/// Het blokattribuut dat [typed] (inclusief de afsluitende spatie) oplevert,
/// of `null` als er geen bloktrigger staat.
Attribute<Object?>? _blockAttributeFor(String typed) {
  final task = _taskPattern.firstMatch(typed);
  if (task != null) {
    return task.group(1)!.toLowerCase() == 'x'
        ? Attribute.checked
        : Attribute.unchecked;
  }
  if (_bulletPattern.hasMatch(typed)) return Attribute.ul;
  if (_orderedPattern.hasMatch(typed)) return Attribute.ol;
  if (_quotePattern.hasMatch(typed)) return Attribute.blockQuote;
  final heading = _headingPattern.firstMatch(typed);
  if (heading != null) return HeaderAttribute(level: heading.group(1)!.length);
  return null;
}

final _taskPattern = RegExp(r'^[-*+] \[([ xX])\] $');
final _bulletPattern = RegExp(r'^[-*+] $');
final _orderedPattern = RegExp(r'^\d+\. $');
final _quotePattern = RegExp(r'^> $');
final _headingPattern = RegExp(r'^(#{1,6}) $');
final _rulePattern = RegExp(r'^(?:---|\*\*\*|___) $');
